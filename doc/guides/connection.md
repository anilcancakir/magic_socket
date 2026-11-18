# Connection

How the Reverb driver connects, reconnects, authorises channels and detects a dead socket, and which settings change that.

- [Lifecycle](#lifecycle)
- [Connection State](#connection-state)
- [Resubscription](#resubscription)
- [Auth Failures](#auth-failures)
- [Reconnect Backoff](#reconnect-backoff)
- [Close Codes](#close-codes)
- [Configuration Errors](#configuration-errors)
- [Activity Monitor](#activity-monitor)
- [Connection Timeout](#connection-timeout)
- [Perf Events](#perf-events)
- [Related Documentation](#related-documentation)

<a name="lifecycle"></a>
## Lifecycle

`BroadcastServiceProvider.boot()` starts the default connection and does not wait for it, so a server that is down never fails the app launch. The failure is logged as a warning and the driver keeps retrying, unless it is a configuration error (see [Configuration Errors](#configuration-errors)). Code that needs the socket awaits `Echo.connect()`, which is idempotent: it returns at once when connected, joins an attempt already in flight, and when a retry is armed it cancels the timer and reconnects now. It never opens a second socket.

```dart
import 'package:magic_socket/magic_socket.dart';

Future<void> main() async {
  await Echo.connect();
  print(Echo.socketId);

  await Echo.disconnect();
}
```

<a name="connection-state"></a>
## Connection State

`Echo.connectionState` is a broadcast stream of `BroadcastConnectionState`.

| State | Meaning |
|:------|:--------|
| `connecting` | Establishing the connection. |
| `connected` | Active and healthy. |
| `disconnected` | Not connected and not retrying: a fatal close code, `reconnect` off, or a configuration error. |
| `reconnecting` | Lost the connection and re-establishing it. |

```dart
import 'package:magic_socket/magic_socket.dart';

void main() {
  Echo.connectionState.listen((state) {
    switch (state) {
      case BroadcastConnectionState.connected:
        print('online');
      case BroadcastConnectionState.reconnecting:
        print('reconnecting');
      case BroadcastConnectionState.disconnected:
        print('offline');
      case BroadcastConnectionState.connecting:
        break;
    }
  });
}
```

<a name="resubscription"></a>
## Resubscription

Every handshake subscribes every channel the app holds, public, private and presence, with the new socket id, as pusher-js does. That covers a timer retry, an explicit `Echo.connect()` after a drop and the first connect. A channel created while the socket is down is subscribed once, by the next handshake. Private and presence channels authorise again, because the signature covers the socket id.

`Echo.onReconnect` emits after each reconnect handshake, once every channel was sent its subscribe, and never for the first connection. It does not mean the server confirmed anything. Refetch on the channel's own confirmation instead:

```dart
import 'package:magic_socket/magic_socket.dart';

void main() {
  Echo.private('teams.1').onSubscriptionChanged.where((subscribed) => subscribed).listen((_) {
    print('events flow again; fetch what was missed');
  });
}
```

<a name="auth-failures"></a>
## Auth Failures

The default auth call throws a `BroadcastAuthException` when the `auth_endpoint` answers outside 2xx.

| Property | Meaning |
|:---------|:--------|
| `channelName` | The fully-qualified channel the call was for. |
| `statusCode` | The HTTP status, or `0` when no response arrived. |
| `isRetryable` | `true` for status `0` and any 5xx. |

A retryable failure is retried with the reconnect backoff while the socket lasts and logged as a warning. A 401 or 403 is logged as an error and not retried, because retrying cannot change the answer. Every failure goes through the interceptor `onError` chain, and one channel's failure does not block the rest. An answer that arrives after the socket changed, or after the channel was left, is dropped.

<a name="reconnect-backoff"></a>
## Reconnect Backoff

```
base  = min(500 ms * 2^attempt, max_reconnect_delay)
delay = base + random(0 .. base * 0.3)
```

The base starts at 500 ms and doubles per attempt up to `max_reconnect_delay` (30 000 ms by default). The jitter, up to 30% of the base, keeps clients from reconnecting in the same instant after a server restart. Set `reconnect` to `false` to disable automatic reconnects; a later `Echo.connect()` still opens a fresh socket.

<a name="close-codes"></a>
## Close Codes

The websocket close code decides the strategy, following the Pusher protocol.

| Close code | Action |
|:-----------|:-------|
| 4000 to 4099 | Fatal: no reconnect, the state goes to `disconnected`. |
| 4100 to 4199 | Reconnect with backoff. |
| 4200 to 4299 | Reconnect at once, no backoff. |
| Any other, or none | Reconnect with backoff. |

A close without a code is the common case: a restarting Reverb drops connections without a close frame. A `pusher:error` frame on an open socket never reconnects; it only reaches the interceptor `onError` chain, because Reverb sends one for any server-side exception and keeps the socket open.

<a name="configuration-errors"></a>
## Configuration Errors

A blank scheme, host or app key cannot heal by retrying, so the driver checks them before it opens anything. On a miss it logs one error naming each blank variable (`REVERB_SCHEME`, `REVERB_HOST`, `REVERB_APP_KEY`), opens no socket, arms no retry, reports `disconnected` and rejects `Echo.connect()` with a `StateError`. A scheme or host that does not parse (for example an unclosed `[` in the host), a scheme other than `ws` or `wss`, and a URL without a host end the same way and name `REVERB_SCHEME` and `REVERB_HOST`. A host such as `example.com/path` still parses, so it is not caught: the driver connects to `example.com` and the server answers. The error is logged once per driver, however many times `Echo.connect()` is called; fix `.env` (or the connection config that overrides it) and restart the app. `broadcastingConfig` already turns a blank `REVERB_HOST` into `localhost` and a blank `REVERB_SCHEME` into `ws`, so in practice a blank `REVERB_APP_KEY` is the case you meet.

<a name="activity-monitor"></a>
## Activity Monitor

The driver detects silent connection loss, such as a crashed server or a network partition, without a close frame.

1. After the handshake it reads `activity_timeout` from the server payload, falling back to the config key (120 seconds).
2. If no message arrives within that time, it sends `pusher:ping`.
3. If no `pusher:pong` arrives within 30 seconds, the connection is declared dead and dropped as a close without a code: the state becomes `reconnecting`, every channel reports unsubscribed and the backoff starts.
4. Any inbound message resets the timer, not only a pong.

The driver also answers a server `pusher:ping` with `pusher:pong` by itself.

<a name="connection-timeout"></a>
## Connection Timeout

`connection_timeout` (15 seconds by default) is how long the driver waits for `pusher:connection_established` after the websocket upgrades. On expiry the socket is closed, a reconnect is scheduled (subject to `reconnect`) and `Echo.connect()` throws a `TimeoutException`, so a caller can show an error state.

<a name="perf-events"></a>
## Perf Events

`BroadcastListeners` reports each received message to core's perf seam. When `MagicPerfHooks.sink` is set, every fanned-out event emits a `BroadcastReceived(event)` and its handlers run under the `MagicNotifyCause.broadcast` root cause, so a diagnostic tool can attribute rebuilds to a realtime message. Both types live in `package:magic/magic.dart`; with no sink installed the check is a single null test and nothing is allocated.

<a name="related-documentation"></a>
## Related Documentation

- [Configuration](../basics/configuration.md): the keys named here.
- [Channels](../basics/channels.md): subscription state per channel.
- [Listeners](../basics/listeners.md): `AuthChannelSubscription` and `onReconnect`.
- [Extending](./extending.md): interceptors see every error.
