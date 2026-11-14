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
| `onError(error)` | `dynamic` | `dynamic` | On a driver error; return a replacement to recover. |

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
