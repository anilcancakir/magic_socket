# Installation

Add `magic_socket` to a Magic app, register its provider and config, and check that `Echo` resolves a driver.

- [Install](#install)
- [Requirements](#requirements)
- [Register by Hand](#register-by-hand)
- [Environment](#environment)
- [Verify](#verify)
- [Related Documentation](#related-documentation)

<a name="install"></a>
## Install

```bash
flutter pub add magic_socket
dart run magic:dowel plugin:install magic_socket
```

The installer reads the package's `install.yaml` and makes two edits: it adds `BroadcastServiceProvider` to the `providers` list of `lib/config/app.dart`, and it adds `() => broadcastingConfig` to the `configFactories` of `lib/main.dart`. It publishes no config file, because `broadcastingConfig` reads every value from `.env` and is imported from the package.

The barrel, `package:magic_socket/magic_socket.dart`, is the only runtime import; everything under `src/` is private. Test doubles live in a second barrel, `package:magic_socket/testing.dart`, see [Testing](../guides/testing.md).

<a name="requirements"></a>
## Requirements

| Requirement | Value |
|:------------|:------|
| Dart | `>=3.13.0` |
| Flutter | `>=3.47.0` |
| Magic | `^1.0.0`, installed and bootstrapped (`lib/config/app.dart` exists) |
| Server | Laravel Reverb or any Pusher-protocol server; none for the `null` driver |
| Dependencies | `web_socket_channel`, pulled in automatically |

<a name="register-by-hand"></a>
## Register by Hand

`plugin:install` does this for you. To do it yourself, register the provider and the config factory in `Magic.init`:

```dart
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

Future<void> main() async {
  await Magic.init(
    configFactories: [
      () => broadcastingConfig,
    ],
    configs: [
      {
        'app': {
          'providers': [
            (app) => BroadcastServiceProvider(app),
          ],
        },
      },
    ],
  );
}
```

Use `configFactories`, not `configs`, for `broadcastingConfig`: it is a getter that calls `env()`, and a factory runs after `.env` is loaded. The provider is not auto-registered, so without it `Echo` finds no `broadcasting` binding.

<a name="environment"></a>
## Environment

```dotenv
BROADCAST_CONNECTION=reverb
REVERB_HOST=localhost
REVERB_PORT=8080
REVERB_SCHEME=ws
REVERB_APP_KEY=
```

`BROADCAST_CONNECTION` defaults to `null`, which keeps the socket off. Every key and its default is listed in [Configuration](../basics/configuration.md).

Private and presence channels authorise through `POST /broadcasting/auth` on your API through `Http`, and Laravel's `toOthers()` needs the `X-Socket-ID` header, so add `NetworkServiceProvider` to the `providers` list if the app does not have it yet.

<a name="verify"></a>
## Verify

```dart
import 'package:magic_socket/magic_socket.dart';

Future<void> main() async {
  // Magic.init(...) has run with the provider and config above.
  print(Echo.connection.runtimeType); // NullBroadcastDriver until BROADCAST_CONNECTION=reverb
  print(Echo.socketId); // null until a real connection is up

  Echo.channel('orders').listen('OrderShipped', (event) => print(event.data));
}
```

With `BROADCAST_CONNECTION=reverb` and a server running, the first line prints `ReverbBroadcastDriver` and `Echo.socketId` is a string once the handshake completes.

<a name="related-documentation"></a>
## Related Documentation

- [Channels](../basics/channels.md): public, private and presence channels and the `BroadcastEvent` envelope.
- [Configuration](../basics/configuration.md): connections, environment keys and the socket id header.
- [Listeners](../basics/listeners.md): sharing one subscription between controllers.
- [Testing](../guides/testing.md): `Echo.fake` and the assertion helpers.
