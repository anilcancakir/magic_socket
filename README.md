<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/magic_socket/master/.github/logo.png" width="120" alt="Magic Socket logo" />
</p>

<h1 align="center">Magic Socket</h1>

<p align="center">
  <strong>Real-time broadcasting for Magic apps, with a Laravel Echo style API.</strong><br/>
  The <code>Echo</code> facade subscribes to public, private and presence channels over a Reverb (Pusher protocol) websocket, reconnects on its own and ships a <code>null</code> driver and <code>Echo.fake</code> so the same code runs and tests without a server.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic_socket"><img src="https://img.shields.io/pub/v/magic_socket.svg" alt="pub package"></a>
  <a href="https://github.com/anilcancakir/magic_socket/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/magic_socket/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/anilcancakir/magic_socket"><img src="https://codecov.io/gh/anilcancakir/magic_socket/graph/badge.svg" alt="codecov"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/magic_socket/score"><img src="https://img.shields.io/pub/points/magic_socket" alt="pub points"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/magic/docs/socket">Documentation</a> ·
  <a href="https://pub.dev/packages/magic_socket">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/magic_socket/issues">Issues</a>
</p>

## At a glance

| Fact | Value |
|---|---|
| Package | [`magic_socket`](https://pub.dev/packages/magic_socket) |
| Install | `flutter pub add magic_socket`, then `dart run magic:dowel plugin:install magic_socket` |
| Import | `package:magic_socket/magic_socket.dart`; tests add `package:magic_socket/testing.dart` |
| Entry points | `Echo` (facade), `BroadcastServiceProvider` (wiring), `broadcastingConfig` (env-reading config factory), `ListensToBroadcasts` (controller mixin), `BroadcastListeners`, `AuthChannelSubscription` |
| Platforms | Android, iOS, web, macOS, Windows and Linux |
| Requires | Dart >=3.13, Flutter >=3.47, `magic` ^1.0.0, a Laravel Reverb or other Pusher-protocol server for the `reverb` connection |
| Dependencies | `magic`, `web_socket_channel`; dowel runs the installer |
| License | MIT |

## Install

```bash
flutter pub add magic_socket
dart run magic:dowel plugin:install magic_socket
```

The installer adds `BroadcastServiceProvider` to the `providers` list of `lib/config/app.dart` and `() => broadcastingConfig` to the `configFactories` of `lib/main.dart`. No config file is published: every value comes from `.env`.

```dotenv
BROADCAST_CONNECTION=reverb
REVERB_HOST=localhost
REVERB_PORT=8080
REVERB_SCHEME=ws
REVERB_APP_KEY=
```

`BROADCAST_CONNECTION` defaults to `null`, which keeps the socket off. A blank `REVERB_HOST` or `REVERB_SCHEME` falls back to `localhost` or `ws`; a blank `REVERB_APP_KEY` is logged once as a configuration error and the driver does not connect or retry.

## Echo

Subscribe to a channel and react to its events.

```dart
import 'package:magic_socket/magic_socket.dart';

void main() {
  // 'OrderShipped' must equal the frame's event name: the broadcastAs() of the Laravel event.
  Echo.channel('orders').listen('OrderShipped', (event) {
    print('Order ${event.data['id']} has shipped');
  });

  Echo.private('user.1').listen('ProfileUpdated', (event) => print(event.data));

  final room = Echo.join('room.1');
  room.onJoin.listen((member) => print('${member['name']} joined'));

  Echo.leave('orders');
}
```

| Member | Returns | Meaning |
|--------|---------|---------|
| `Echo.channel(name)` | `BroadcastChannel` | A public channel. |
| `Echo.private(name)` | `BroadcastChannel` | A private channel; the driver authorises it over `POST /broadcasting/auth`. |
| `Echo.join(name)` | `BroadcastPresenceChannel` | A presence channel with `members`, `onJoin` and `onLeave`. |
| `Echo.listen(channel, event, callback)` | `BroadcastChannel` | Shorthand for a public channel. |
| `Echo.leave(name)` | `void` | Unsubscribes `name` and its `private-` and `presence-` forms, as Laravel Echo does, so `leave('chat.1')` also drops a public `chat.1`. |
| `Echo.connect()`, `Echo.disconnect()` | `Future<void>` | Opens or closes the socket; `connect` is idempotent. |
| `Echo.socketId` | `String?` | The server-assigned id, `null` while disconnected. |
| `Echo.connectionState`, `Echo.onReconnect` | `Stream` | Lifecycle transitions and reconnect handshakes. |
| `Echo.addInterceptor(interceptor)` | `void` | Hooks the driver message pipeline. |
| `Echo.fake()`, `Echo.unfake()` | `FakeBroadcastManager`, `void` | Swap in the in-memory fake for tests. |

### Differences from Laravel Echo

The API is Echo shaped, not a port, and one difference decides whether a handler runs: `listen` compares the name you pass with the event name in the frame, exactly. Echo JS prepends the event's namespace for you; this driver does not. A Laravel event without `broadcastAs()` goes out under its full class name (`App\Events\OrderShipped`), so a handler registered for `'OrderShipped'` never runs. Name the event on the server, or pass the full class name to `listen`:

```php
use Illuminate\Broadcasting\Channel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;

class OrderShipped implements ShouldBroadcast
{
    public function broadcastOn(): Channel
    {
        return new Channel('orders');
    }

    public function broadcastAs(): string
    {
        return 'OrderShipped';
    }
}
```

Echo's leading-dot form (`.OrderShipped`) is not needed and not recognised: pass the name as the frame carries it.

Every handler gets a `BroadcastEvent` (`event`, `channel`, `data`, `receivedAt`). A second `listen` for the same event on one channel replaces the first; the server can also repeat a frame, so write idempotent handlers.

## Drivers

| Connection | Driver | Use |
|------------|--------|-----|
| `reverb` | `ReverbBroadcastDriver` | Laravel Reverb, Soketi or any Pusher-protocol server. Reconnects with exponential backoff and jitter, pings on silence, and resubscribes every channel on each handshake. |
| `null` | `NullBroadcastDriver` | The default. Every call succeeds and nothing is delivered. |

Custom drivers register with `BroadcastManager.extend`. `BroadcastServiceProvider.boot()` starts the connection without waiting, so a server that is down never blocks the app launch; await `Echo.connect()` when you need the socket.

## Excluding the sender

`SocketIdInterceptor` adds `X-Socket-ID` to every `Http` request while a socket is connected, so Laravel's `broadcast($event)->toOthers()` skips the device that made the request. The provider registers it when the connection is not `null` and a network driver is bound, so add `NetworkServiceProvider` to the `providers` list.

## Controllers

`ListensToBroadcasts` lets several controllers share one private channel. It replaces the `--broadcasts` flag of the removed `make:controller` option: write the mixin by hand.

```dart
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

class MonitorController extends MagicController with ListensToBroadcasts {
  @override
  Map<String, void Function(BroadcastEvent)> get listeners => {
    'team:check.recorded': (event) => print(event.data),
  };
}
```

Declare the `team` alias once with `BroadcastListeners.channel('team', () => 'teams.1')` and call `BroadcastListeners.sync()` when the name changes. Core keeps the `BroadcastReceived` perf event that this registry emits.

## Testing

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';
import 'package:magic_socket/testing.dart';

void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();
  });

  tearDown(() => Echo.unfake());

  test('a handler receives a dispatched frame', () {
    final FakeBroadcastManager fake = Echo.fake();
    final received = <BroadcastEvent>[];

    Echo.private('user.1').listen('ProfileUpdated', received.add);
    fake.dispatch('private-user.1', 'ProfileUpdated', {'name': 'Ada'});

    fake.assertListening('private-user.1', 'ProfileUpdated');
    expect(received.single.data['name'], 'Ada');
  });
}
```

`assertConnected`, `assertDisconnected`, `assertSubscribed`, `assertNotSubscribed`, `assertListening`, `assertNotListening`, `assertInterceptorAdded` and `reset` are the assertions; `dispatch` delivers a decoded payload to the registered handler.

## For AI coding agents

Rules for an agent writing code against this package. Each one is a mistake that costs a user a crash or a silent no-op.

| Do | Because |
|----|---------|
| Import `package:magic_socket/magic_socket.dart`, and `package:magic_socket/testing.dart` in tests only | Everything under `src/` is private; the fakes stay out of the runtime barrel. |
| Register `BroadcastServiceProvider` in `providers` and `() => broadcastingConfig` in `configFactories` | Neither is automatic; without them `Echo` has no `broadcasting` binding. |
| Use `configFactories`, not `configs`, for `broadcastingConfig` | It calls `env()`, which must run after `.env` loads. |
| Pass channel names without `private-` or `presence-` | The driver adds the prefix; `fake.assertSubscribed` sees the prefixed name. |
| Use `Echo.private`, not `Echo.listen`, for a private channel | `Echo.listen` is shorthand for a public channel. |
| Pass `listen` the event name the frame carries: the server's `broadcastAs()`, or the full class name when it has none | The driver compares names exactly and resolves no namespace as Echo JS does, so `'OrderShipped'` never matches `App\Events\OrderShipped`. |
| Make handlers idempotent | The server can repeat a frame, and a second `listen` replaces the first. |
| Refetch on `onSubscriptionChanged` turning `true`, not on `Echo.onReconnect` | `onReconnect` fires before the server confirms the channel. |
| Add `NetworkServiceProvider` when you rely on `toOthers()` | The `X-Socket-ID` interceptor needs a network driver. |
| In tests, call `MagicApp.reset()` and `Magic.flush()` in `setUp` and `BroadcastListeners.reset()`, `BroadcastManager.resetDrivers()` in `tearDown` | The listener registry and custom drivers are statics that `Magic.flush()` does not clear; the fake lives in the container, which `Magic.flush()` empties. |

## Dependencies

`magic` for the container, `Http`, `Log` and the service provider base class; `web_socket_channel` for the websocket; dowel to run the installer through `dart run magic:dowel`.

## Links

- [Documentation](https://anilcancakir.com/magic/docs/socket/getting-started/installation): installation, channels, configuration, listeners, connection, extending and testing
- [API reference](https://pub.dev/documentation/magic_socket/latest/)
- [llms.txt](llms.txt) and the [agent skill](skills/magic-socket/SKILL.md) for AI coding agents: `npx skills add anilcancakir/magic_socket`
- [Changelog](CHANGELOG.md)
- [Report an issue](https://github.com/anilcancakir/magic_socket/issues)
- [Security policy](SECURITY.md)

## License

MIT, see [LICENSE](LICENSE). Built by [Anılcan Çakır](https://anilcancakir.com).
