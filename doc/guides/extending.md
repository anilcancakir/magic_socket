# Extending

Hook into the driver message pipeline with a `BroadcastInterceptor` and register a custom driver with `BroadcastManager.extend`.

- [Interceptors](#interceptors)
- [Registering an Interceptor](#registering-an-interceptor)
- [Custom Drivers](#custom-drivers)
- [Registering a Driver](#registering-a-driver)
- [Related Documentation](#related-documentation)

<a name="interceptors"></a>
## Interceptors

A `BroadcastInterceptor` sits in the driver pipeline, the same idea as `MagicNetworkInterceptor` for `Http`. Every hook has a pass-through default, so override only what you need.

| Hook | Receives | Returns | Meaning |
|:-----|:---------|:--------|:--------|
| `onSend(message)` | `Map<String, dynamic>` | `Map<String, dynamic>` | Before an outbound frame; return an empty map to suppress it. |
| `onReceive(event)` | `BroadcastEvent` | `BroadcastEvent` | On an inbound event; return a modified event to pass it on. |
| `onError(error)` | `dynamic` | `dynamic` | On a driver error, including a malformed frame; the next interceptor gets what this one returns. A `BroadcastEvent` returned by the last one is delivered to the listeners of the channel it names, without `onReceive`. |

```dart
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

class LoggingBroadcastInterceptor extends BroadcastInterceptor {
  @override
  BroadcastEvent onReceive(BroadcastEvent event) {
    Log.debug('Broadcast received: ${event.event} on ${event.channel}');

    return event;
  }

  @override
  dynamic onError(dynamic error) {
    Log.error('Broadcast error: $error');

    return error;
  }
}
```

<a name="registering-an-interceptor"></a>
## Registering an Interceptor

Add it in a provider's `boot()`, after `BroadcastServiceProvider` is listed.

```dart
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

class AppBroadcastProvider extends ServiceProvider {
  AppBroadcastProvider(super.app);

  @override
  void register() {}

  @override
  Future<void> boot() async {
    Echo.addInterceptor(LoggingBroadcastInterceptor());
  }
}

class LoggingBroadcastInterceptor extends BroadcastInterceptor {}
```

`Echo.addInterceptor` adds to the default connection and runs interceptors in the order they were added.

<a name="custom-drivers"></a>
## Custom Drivers

Implement `BroadcastDriver` to talk to another transport. The contract has `connect`, `disconnect`, `socketId`, `isConnected`, `connectionState`, `onReconnect`, `channel`, `private`, `join`, `leave` and `addInterceptor`. A channel implements `BroadcastChannel` (`name`, `events`, `isSubscribed`, `onSubscriptionChanged`, `listen`, `stopListening`), and a presence channel adds `members`, `onJoin` and `onLeave`.

Two parts of the contract are obligations, since `AuthChannelSubscription` and `BroadcastListeners` rely on them:

| Obligation | Why |
|:-----------|:----|
| `leave(name)` drops `name` and its `private-` and `presence-` forms. | `Echo.leave('chat.1')` must leave the channel `Echo.private('chat.1')` or `Echo.join('chat.1')` opened, as Laravel Echo does. |
| `channel(name)`, `private(name)` and `join(name)` return the instance they already hold for a registered name, and a new one only after a leave or a disconnect. | A subscription calls `private(name)` on every `sync()` and compares identity with the channel it holds: the same instance means the channel is live, another means it was left or disconnected, so the subscription registers it again. |
| A channel's `onSubscriptionChanged` ends when the driver disposes it (a leave or a disconnect). | Listeners attached to a disposed channel learn that it receives nothing any more. |

`NullBroadcastDriver` subscribes nothing and mints a new channel on every call, so a subscription on it registers again on every `sync()`; that does nothing, because its channels are never confirmed. A driver built on it that sends a real subscribe from `private()` must override `private()` and `join()` to hold one channel per name, or it subscribes again on every `sync()` and a confirmed channel fires `onReconnect` each time.

<a name="registering-a-driver"></a>
## Registering a Driver

```dart
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

class PusherBroadcastDriver extends NullBroadcastDriver {
  PusherBroadcastDriver(this.config);

  final Map<String, dynamic> config;
}

class AppServiceProvider extends ServiceProvider {
  AppServiceProvider(super.app);

  @override
  void register() {}

  @override
  Future<void> boot() async {
    BroadcastManager.extend('pusher', PusherBroadcastDriver.new);
  }
}
```

Then name the driver in the config and select it with `BROADCAST_CONNECTION=pusher`:

```dart
Map<String, dynamic> get pusherConfig => {
  'broadcasting': {
    'default': 'pusher',
    'connections': {
      'pusher': {'driver': 'pusher', 'app_key': 'my-key'},
    },
  },
};
```

The factory receives the connection's config map. Register the driver before the provider that reads the default connection resolves it, and call `BroadcastManager.resetDrivers()` in a test's `tearDown`, since the registry is static.

<a name="related-documentation"></a>
## Related Documentation

- [Configuration](../basics/configuration.md): connections and the `driver` key.
- [Connection](./connection.md): the reconnect and auth behaviour a custom driver replaces.
- [Testing](./testing.md): resetting static state.
