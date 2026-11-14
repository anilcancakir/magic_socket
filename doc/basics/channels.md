# Channels

Subscribe to public, private and presence channels through the `Echo` facade and react to the events they deliver.

- [Basic Usage](#basic-usage)
- [Quick Reference](#quick-reference)
- [Public Channels](#public-channels)
- [Private Channels](#private-channels)
- [Presence Channels](#presence-channels)
- [The BroadcastEvent Envelope](#the-broadcastevent-envelope)
- [Subscription State](#subscription-state)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="basic-usage"></a>
## Basic Usage

```dart
import 'package:magic_socket/magic_socket.dart';

void main() {
  Echo.channel('orders').listen('OrderShipped', (event) {
    print('Order ${event.data['id']} has shipped');
  });

  Echo.leave('orders');
}
```

`Echo` is a static facade over the `BroadcastManager` bound at `broadcasting`. It mirrors the Laravel Echo client: `channel`, `private`, `join`, `listen` and `leave`. With the `null` driver the calls succeed and no event ever arrives, so the same code runs in development without a server.

<a name="quick-reference"></a>
## Quick Reference

| Member | Returns | Meaning |
|:-------|:--------|:--------|
| `Echo.channel(name)` | `BroadcastChannel` | A public channel; no auth. |
| `Echo.private(name)` | `BroadcastChannel` | A private channel; the driver adds `private-` and authorises over HTTP. |
| `Echo.join(name)` | `BroadcastPresenceChannel` | A presence channel; the driver adds `presence-` and tracks members. |
| `Echo.listen(channel, event, callback)` | `BroadcastChannel` | Shorthand for `Echo.channel(channel).listen(event, callback)`. |
| `Echo.leave(name)` | `void` | Unsubscribes; no effect when not subscribed. |
| `Echo.connect()`, `Echo.disconnect()` | `Future<void>` | Opens or closes the socket, see [Connection](../guides/connection.md). |
| `channel.listen(event, callback)` | `BroadcastChannel` | Registers a handler and returns the channel for chaining. |
| `channel.stopListening(event)` | `void` | Removes the handler for that event. |
| `channel.events` | `Stream<BroadcastEvent>` | Every event on the channel, whether or not a handler is registered. |

<a name="public-channels"></a>
## Public Channels

Any connected client may subscribe to a public channel.

```dart
import 'package:magic_socket/magic_socket.dart';

void main() {
  void onShipped(BroadcastEvent event) => print(event.data);
  void onCancelled(BroadcastEvent event) => print(event.data);

  Echo.channel('orders')
      .listen('OrderShipped', onShipped)
      .listen('OrderCancelled', onCancelled);

  Echo.channel('orders').stopListening('OrderShipped');
}
```

A second `listen` for the same event on the same channel replaces the first handler. To fan one event out to several handlers, use [BroadcastListeners](./listeners.md).

<a name="private-channels"></a>
## Private Channels

A private channel performs an HTTP handshake before it subscribes: the driver posts `socket_id` and `channel_name` to the `auth_endpoint` (`/broadcasting/auth` by default) through `Http`, and expects `{"auth": "..."}` back.

```dart
import 'package:magic_socket/magic_socket.dart';

void main() {
  Echo.private('user.1').listen('ProfileUpdated', (event) {
    print('Profile updated: ${event.data}');
  });
}
```

The server decides who may join, in Laravel's `routes/channels.php`:

```php
Broadcast::channel('user.{id}', function ($user, $id) {
    return (int) $user->id === (int) $id;
});
```

The request goes through your `Http` stack, so the user's bearer token reaches the auth route like any other call. A refusal (401, 403) is logged and not retried; a missing response or a 5xx is retried with the reconnect backoff, see [Connection](../guides/connection.md#auth-failures).

<a name="presence-channels"></a>
## Presence Channels

A presence channel is a private channel that also tracks who is in it.

```dart
import 'package:magic_socket/magic_socket.dart';

void main() {
  final room = Echo.join('room.1');

  print('Online: ${room.members.length}');

  room.onJoin.listen((member) => print('${member['name']} joined'));
  room.onLeave.listen((member) => print('${member['name']} left'));
  room.listen('MessagePosted', (event) => print(event.data['body']));
}
```

| Member | Type | Meaning |
|:-------|:-----|:--------|
| `members` | `List<Map<String, dynamic>>` | The current members, an immutable snapshot. |
| `onJoin` | `Stream<Map<String, dynamic>>` | Emits the member payload on each join. |
| `onLeave` | `Stream<Map<String, dynamic>>` | Emits the member payload on each leave. |

<a name="the-broadcastevent-envelope"></a>
## The BroadcastEvent Envelope

Every handler receives a `BroadcastEvent`.

| Property | Type | Meaning |
|:---------|:-----|:--------|
| `event` | `String` | The event name, for example `App\Events\OrderShipped`. |
| `channel` | `String` | The channel the event arrived on, with its `private-` or `presence-` prefix. |
| `data` | `Map<String, dynamic>` | The decoded JSON payload. |
| `receivedAt` | `DateTime` | The local time of receipt. |

Every frame the server sends reaches your handler, including one whose payload repeats an earlier frame. The server can also deliver an event twice when a queued broadcast job is retried. Write handlers so a second delivery is harmless: refetch, or upsert by an id in the payload, rather than counting or showing a toast per frame.

<a name="subscription-state"></a>
## Subscription State

A connected driver does not mean a subscribed channel: a private channel still waits on its auth call, and a refusal leaves it unsubscribed. Each channel reports the server's confirmation itself.

```dart
import 'package:magic_socket/magic_socket.dart';

void main() {
  final channel = Echo.private('team.1');

  print(channel.isSubscribed); // true once the server sent subscription_succeeded

  channel.onSubscriptionChanged.listen((subscribed) {
    print(subscribed ? 'stop polling' : 'start polling');
  });
}
```

`onSubscriptionChanged` emits only on a change and never replays, so read `isSubscribed` when you attach. Channels of the null driver are never subscribed.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Using `Echo.listen` for a private channel | It is shorthand for a public channel; call `Echo.private(name).listen(...)`. |
| Registering two handlers for one event on one channel | The second replaces the first. Use `BroadcastListeners` to share the event. |
| Treating `onReconnect` as "the channel is back" | It fires after the subscribe was sent, not confirmed. Refetch on `onSubscriptionChanged` turning `true`. |
| Counting frames as unique events | The server can repeat a frame; make the handler idempotent. |
| Calling `Echo` before `Magic.init` | The `broadcasting` binding does not exist yet; await `Magic.init` in `main`. |
| Expecting events from the `null` driver | It drops everything; set `BROADCAST_CONNECTION=reverb`. |

<a name="related-documentation"></a>
## Related Documentation

- [Configuration](./configuration.md): connections, environment keys and the socket id header.
- [Listeners](./listeners.md): sharing a channel between controllers.
- [Connection](../guides/connection.md): lifecycle, reconnects and auth failures.
- [Testing](../guides/testing.md): faking channels and delivering events in a test.
