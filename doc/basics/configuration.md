# Configuration

Pick the broadcast connection with `.env`, tune the Reverb driver and understand the `X-Socket-ID` header the provider adds.

- [Basic Usage](#basic-usage)
- [Quick Reference](#quick-reference)
- [Connections](#connections)
- [Environment Keys](#environment-keys)
- [Reverb Options](#reverb-options)
- [The Provider](#the-provider)
- [Excluding the Sender](#excluding-the-sender)
- [The Null Driver](#the-null-driver)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="basic-usage"></a>
## Basic Usage

```dotenv
BROADCAST_CONNECTION=reverb
REVERB_HOST=api.example.com
REVERB_PORT=443
REVERB_SCHEME=wss
REVERB_APP_KEY=my-app-key
```

`broadcastingConfig`, exported from the package barrel, reads these keys and builds the `broadcasting` config. Nothing is copied into your app: the installer registers `() => broadcastingConfig` in `configFactories` and you change behaviour through `.env`.

<a name="quick-reference"></a>
## Quick Reference

| Key | Type | Default | Meaning |
|:----|:-----|:--------|:--------|
| `broadcasting.default` | `String` | `null` | The connection `Echo` uses, from `BROADCAST_CONNECTION`. |
| `broadcasting.connections.reverb` | `Map` | see below | The Reverb (Pusher protocol) websocket driver. |
| `broadcasting.connections.null` | `Map` | `{driver: null}` | The no-op driver. |

<a name="connections"></a>
## Connections

| Connection | Driver | Use |
|:-----------|:-------|:----|
| `reverb` | `ReverbBroadcastDriver` | Laravel Reverb, Soketi or any Pusher-protocol server, over a pure Dart websocket. |
| `null` | `NullBroadcastDriver` | Local development and tests; every operation succeeds and nothing is delivered. |

A connection with an unknown `driver` name falls back to the null driver. Register your own name with `BroadcastManager.extend`, see [Extending](../guides/extending.md).

<a name="environment-keys"></a>
## Environment Keys

| Key | Default | Feeds |
|:----|:--------|:------|
| `BROADCAST_CONNECTION` | `null` | `broadcasting.default` |
| `REVERB_HOST` | `localhost` | `host`; a blank value falls back to `localhost` |
| `REVERB_PORT` | `8080` | `port`; a non-numeric value falls back to `8080` |
| `REVERB_SCHEME` | `ws` | `scheme`; use `wss` behind TLS; a blank value falls back to `ws` |
| `REVERB_APP_KEY` | empty | `app_key`; required, a blank value is a configuration error, see [The Provider](#the-provider) |

<a name="reverb-options"></a>
## Reverb Options

| Key | Type | Default | Meaning |
|:----|:-----|:--------|:--------|
| `host`, `port`, `scheme` | `String`, `int`, `String` | from `.env` | The websocket endpoint. |
| `app_key` | `String` | from `.env` | The application key; must match the server. |
| `auth_endpoint` | `String` | `/broadcasting/auth` | The HTTP route for private and presence auth. |
| `reconnect` | `bool` | `true` | Reconnect after an unexpected disconnect. |
| `max_reconnect_delay` | `int` | `30000` | Cap of the reconnect backoff, in milliseconds. |
| `activity_timeout` | `int` | `120` | Seconds of silence before the driver pings; the server value wins after the handshake. |
| `connection_timeout` | `int` | `15` | Seconds to wait for `pusher:connection_established`. |

The last five keys are not read from `.env`. To change one, wrap the factory and override it:

```dart
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

Map<String, dynamic> myBroadcastingConfig() {
  final config = broadcastingConfig;
  final reverb = (config['broadcasting'] as Map)['connections']['reverb'] as Map;

  reverb['max_reconnect_delay'] = 10000;

  return config;
}

Future<void> main() async {
  await Magic.init(configFactories: [myBroadcastingConfig]);
}
```

Register `myBroadcastingConfig` in `configFactories` instead of `() => broadcastingConfig`.

<a name="the-provider"></a>
## The Provider

`BroadcastServiceProvider` is not auto-registered.

| Phase | What it does |
|:------|:-------------|
| `register()` | Binds the `BroadcastManager` singleton at `broadcasting`. |
| `boot()` | Skips everything when `broadcasting.default` is `null`. Otherwise adds `SocketIdInterceptor` to the network driver (when one is bound) and starts connecting without waiting. |

Boot does not wait for the socket. A server that is down or slow never holds or fails the app launch: the failure is logged with `Log.warning` and, while `reconnect` is on, the driver keeps retrying. A blank app key (or a blank host or scheme in a custom connection config) is a configuration error instead: the driver logs one error naming the variable (`REVERB_SCHEME`, `REVERB_HOST` or `REVERB_APP_KEY`), opens no socket, reports `disconnected` and does not retry, so fix `.env` (or the connection config that overrides it) and restart the app. Code that needs the socket awaits `Echo.connect()`, which joins the attempt already in flight and throws a `StateError` for a configuration error.

<a name="excluding-the-sender"></a>
## Excluding the Sender

Laravel's `broadcast($event)->toOthers()` skips the socket that made the request, but only when the request carries an `X-Socket-ID` header. `SocketIdInterceptor` sets it from `Echo.socketId` on every outgoing `Http` request, so the device that made a change does not receive its own event back.

| Situation | Header |
|:----------|:-------|
| Socket connected | `X-Socket-ID: <id>` |
| Socket down | Not sent; the header is never empty. |
| `null` driver | Not sent; the interceptor is not registered. |
| No network driver bound | The interceptor is skipped; add `NetworkServiceProvider` to the `providers` list. |

<a name="the-null-driver"></a>
## The Null Driver

`NullBroadcastDriver` is the default. `connect` and `disconnect` resolve at once, `socketId` is `null`, `isConnected` is `false`, and channels accept `listen` and never emit. Code written against `Echo` therefore compiles and runs with no server. To exercise handlers without one, use [Echo.fake](../guides/testing.md).

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Putting `broadcastingConfig` in `configs` | It reads `.env`; register it in `configFactories` so it runs after `.env` loads. |
| Forgetting `REVERB_APP_KEY` | A blank key is logged once as an error naming `REVERB_APP_KEY` and the driver does not connect or retry; set it, equal to the server's `REVERB_APP_KEY`, and restart. |
| Using `ws` against a TLS endpoint | Set `REVERB_SCHEME=wss`. |
| Expecting `Echo.socketId` right after `Magic.init` | Boot does not wait; await `Echo.connect()` first. |
| `toOthers()` has no effect | The request had no `X-Socket-ID`: connection `null`, socket down, or no `NetworkServiceProvider`. |
| Setting `BROADCAST_CONNECTION=pusher` with no driver | An unknown name resolves to the null driver; register it with `BroadcastManager.extend`. |

<a name="related-documentation"></a>
## Related Documentation

- [Installation](../getting-started/installation.md): registering the provider and the config factory.
- [Channels](./channels.md): subscribing and listening.
- [Connection](../guides/connection.md): timeouts, backoff and close codes.
- [Extending](../guides/extending.md): interceptors and custom drivers.
