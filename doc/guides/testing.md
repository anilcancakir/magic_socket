# Testing

Test code that subscribes to channels with `Echo.fake`, assert subscriptions and handlers, and deliver events with no server and no mocking library.

- [Echo.fake](#echo-fake)
- [Assertions](#assertions)
- [Delivering Events](#delivering-events)
- [Subscription State](#subscription-state)
- [Resetting Static State](#resetting-static-state)
- [Related Documentation](#related-documentation)

<a name="echo-fake"></a>
## Echo.fake

`Echo.fake()` binds a `FakeBroadcastManager` in place of the real manager. All channel operations go through an in-memory driver and no websocket opens. It returns the fake so the test can assert on it. The fakes live in a separate barrel:

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

  tearDown(() {
    Echo.unfake();
  });

  test('subscribes to the orders channel', () async {
    final FakeBroadcastManager fake = Echo.fake();

    Echo.channel('orders').listen('OrderShipped', (event) {});

    fake.assertSubscribed('orders');
    fake.assertDisconnected();

    await Echo.connect();
    fake.assertConnected();
  });
}
```

`channel()` records the subscription, but the fake stays disconnected until `Echo.connect()` is awaited.

<a name="assertions"></a>
## Assertions

Every assertion throws an `AssertionError` with a descriptive message.

| Method | Passes when |
|:-------|:------------|
| `assertConnected()`, `assertDisconnected()` | The fake driver is, or is not, connected. |
| `assertSubscribed(channel)`, `assertNotSubscribed(channel)` | The name is, or is not, in the subscribed list. Private and presence names carry their prefix: `private-user.1`. |
| `assertListening(channel, event)`, `assertNotListening(channel, event)` | A handler is, or is not, registered for the event on the channel. |
| `assertInterceptorAdded()` | At least one interceptor was added. |
| `reset()` | Disconnects and clears all recorded state, interceptors included; confirmed channels emit `false`, then every channel's `onSubscriptionChanged` ends. |

Subscribing and listening are separate steps, and only `assertListening` covers the second. `assertSubscribed` passes for an app that holds a live channel and registers no handler at all, so a deleted `listen()` line is invisible to it. Assert the line your realtime feature depends on.

The fake forgets a channel the way the Reverb driver does. `Echo.disconnect()` forgets every channel, and `Echo.leave(name)` forgets `name` and its `private-` and `presence-` forms: each one leaves `subscribedChannels`, loses its handlers, emits `false` if it was confirmed, and its `onSubscriptionChanged` stream ends. After either call `assertSubscribed`, `assertListening` and `dispatch` fail for those channels until the code subscribes them again, and a subscription that registers its channel again after a disconnect (an `AuthChannelSubscription` on its next `sync()`) adds a new entry to `subscribedChannels`. A handle kept from before the leave or disconnect stays detached: it reports `isSubscribed` as `false`, and its `listen` and `stopListening` do not reach the channel subscribed again under the same name.

`fake.driver` exposes the recorded state for low-level checks:

```dart
import 'package:magic_socket/magic_socket.dart';

void main() {
  final fake = Echo.fake();

  Echo.channel('orders');
  Echo.private('user.1');

  print(fake.driver.subscribedChannels); // [orders, private-user.1]
  print(fake.driver.isConnected); // false
  print(fake.driver.listeners); // registered event names per channel
}
```

<a name="delivering-events"></a>
## Delivering Events

`fake.dispatch(channel, event, data)` runs the registered handler with a decoded payload, as the driver would on an incoming frame. It throws an `AssertionError` when nothing is listening, because dispatching into silence is the failure it exists to reveal.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_socket/magic_socket.dart';

void main() {
  test('a handler receives a dispatched frame', () {
    final fake = Echo.fake();
    final received = <BroadcastEvent>[];

    Echo.private('user.1').listen('ProfileUpdated', received.add);

    fake.dispatch('private-user.1', 'ProfileUpdated', {'name': 'Ada'});

    expect(received.single.data['name'], 'Ada');
  });
}
```

A second `listen` for one event replaces the first, matching `ReverbBroadcastDriver`, so a double registration shows up in a test the way it does in production.

A controller that uses `ListensToBroadcasts` is tested the same way: declare the alias, sync, then dispatch to the channel the alias resolves to.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

class TeamController extends MagicController with ListensToBroadcasts {
  final List<BroadcastEvent> received = [];

  @override
  Map<String, void Function(BroadcastEvent)> get listeners => {
    'team:check.recorded': received.add,
  };
}

void main() {
  test('the controller receives the event', () async {
    final fake = Echo.fake();
    BroadcastListeners.channel('team', () => 'teams.1');
    await BroadcastListeners.sync();

    final controller = TeamController()..onInit();
    fake.dispatch('private-teams.1', 'check.recorded', {'id': '1'});

    expect(controller.received, hasLength(1));
  });
}
```

<a name="subscription-state"></a>
## Subscription State

Every fake channel starts with `isSubscribed` false. `fake.driver.setSubscribed(name, value)` stands in for the server's confirmation (`true`) or a dropped socket (`false`). It takes the fully-qualified name and emits on the channel's `onSubscriptionChanged` when the value changes.

```dart
import 'package:magic_socket/magic_socket.dart';

void main() {
  final fake = Echo.fake();

  fake.driver.setSubscribed('private-user.1', true);

  print(Echo.private('user.1').isSubscribed); // true
}
```

<a name="resetting-static-state"></a>
## Resetting Static State

`Magic.flush()` and `MagicApp.reset()` clear the container, not the statics this package keeps. Reset them yourself.

| State | Reset in `tearDown` |
|:------|:--------------------|
| The fake binding | `Echo.unfake()` |
| Declared aliases and handlers | `BroadcastListeners.reset()` |
| Custom drivers | `BroadcastManager.resetDrivers()` |
| Perf sink, if you set one | `MagicPerfHooks.sink = null` |

Call `MagicApp.reset()` and `Magic.flush()` in every `setUp`.

<a name="related-documentation"></a>
## Related Documentation

- [Channels](../basics/channels.md): the calls under test.
- [Listeners](../basics/listeners.md): `BroadcastListeners` and the mixin.
- [Extending](./extending.md): custom drivers and interceptors.
