# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed

- **The README shows the plugin's own logo instead of the Magic logo.** `.github/logo.png`, a 512 pixel PNG of the mark the docs site serves, replaces `.github/magic-logo.svg`. (`README.md`, `.github/`)

## [1.0.2] - 2026-11-18

### Fixed

- A blank `REVERB_SCHEME` made `Uri.parse` throw before any retry was armed, which left the Reverb driver in `connecting` for good; a blank `REVERB_APP_KEY` built `/app/?protocol=7`, which the server rejected, and the driver retried it for ever with a `Reconnect failed` log that named nothing; a blank `REVERB_HOST` built `ws://:8080/...` and entered the same retry loop.
- `lib/config/broadcasting.dart` reads `REVERB_HOST` and `REVERB_SCHEME` with `Env.filled`, so a blank value takes the fallback (`localhost`, `ws`) as an absent one does.
- `ReverbBroadcastDriver` checks the scheme, host and app key before it connects. A blank one, a URL that does not parse, a scheme other than `ws` or `wss` and a URL without a host are logged once per driver as an error naming `REVERB_SCHEME`, `REVERB_HOST` or `REVERB_APP_KEY`; no socket is opened, no retry is armed, the state is `disconnected` and `connect()` throws a `StateError`. A channel factory that throws synchronously takes the retry path.
- The boot warning and the `AuthChannelSubscription` connect warning no longer claim the driver retries when the failure is a configuration error, or when `reconnect` is off. The reconnect path skips its generic `Reconnect failed` line for a configuration error, which was named already.

## [1.0.1] - 2026-11-15

### Changed

- The package page is `https://anilcancakir.com/magic/socket` and the documentation links sit under `https://anilcancakir.com/magic/docs/socket`.
- An `AuthChannelSubscription` compares the channel it holds with the one `private(name)` returns by identity, so a custom `BroadcastDriver` must return the instance it already holds for a registered name; a driver that mints a new channel on every call makes each `sync` register the channel again and fire `onReconnect` once the new channel is confirmed. The custom driver guide lists this obligation.

### Fixed

- `Echo.leave('chat.1')` now leaves the channel `Echo.private('chat.1')` or `Echo.join('chat.1')` opened, as Laravel Echo does; it used to keep the server subscription and its listeners alive. It drops all three forms of the name, so it also leaves a public `chat.1`. The prefixed name still works, and `Echo.fake` behaves the same.
- An `AuthChannelSubscription` (and so `ListensToBroadcasts` and `BroadcastListeners`) receives events again after an `Echo.disconnect()` made elsewhere: its next `sync` registers the channel again and fires `onReconnect` once it is confirmed, or at once when another consumer already had it confirmed again.
- `Echo.fake`'s `disconnect`, `leave` and `reset` now forget the handlers and recorded subscriptions of the channels they drop and end those channels' `onSubscriptionChanged` streams, as the real driver does. A test that calls `assertSubscribed`, `assertListening` or `dispatch` after `Echo.disconnect()` or `Echo.leave(x)` now fails, and a subscription registers its channel again after a disconnect, so it appears in `subscribedChannels` again. A repeated `channel`, `private` or `join` for a name the fake still holds now returns the same handle and records no second entry in `subscribedChannels`, as the real driver does.
- A websocket error on the Reverb driver reaches each interceptor's `onError` once; it used to run twice for one error.
- A `BroadcastInterceptor` whose `onSend` returns an empty map now suppresses the frame, and a `BroadcastEvent` returned from `onError` now reaches the listeners of its channel, as the contract promised.
- A websocket frame that is not JSON, or a handshake with a missing or non-string field, no longer escapes as an uncaught error: it is logged as a warning, passed to the interceptors' `onError`, and the connection keeps delivering events. An error thrown by an interceptor's `onReceive`, `onSend` or `onError` still reaches the app's zone, and `onError` runs once per error.
- The documentation now says that `listen` compares its event name with the frame's event name exactly and resolves no namespace, unlike Echo JS. A Laravel event without `broadcastAs()` arrives as its full class name, so the samples now assume a `broadcastAs()` and the README and the Channels page show it and list the difference from Laravel Echo.
- The documentation no longer claims that `Echo.fake` survives `Magic.flush()`: the fake lives in the container and the flush drops it; only the `BroadcastListeners` registry, the custom drivers and a `MagicPerfHooks.sink` a test sets are statics to reset.
- The custom driver guide counts three obligations of the driver contract, not two.

## [1.0.0] - 2026-11-14

### Added

- **First release.** Real-time broadcasting for Magic apps, moved out of `magic` core 1.0.0.
- `Echo` facade: public, private and presence channels over a Laravel Reverb (Pusher protocol) websocket, automatic reconnection, connection state and reconnect streams, and message interceptors.
- A `null` driver and `Echo.fake` (with `package:magic_socket/testing.dart`) so the same code runs and tests without a server.
- `BroadcastServiceProvider`, the `broadcastingConfig` config factory, the `ListensToBroadcasts` controller mixin, `BroadcastListeners` and `AuthChannelSubscription`.
- `SocketIdInterceptor`, which adds `X-Socket-ID` to `Http` requests so Laravel's `toOthers()` skips the sending device.
- A `dowel` plugin provider (`MagicSocketDowelProvider`) that `dart run magic:dowel plugin:install magic_socket` registers.
- Built on `web_socket_channel` ^3.0.3 and `dowel` ^1.0.0. Requires Dart 3.13, Flutter 3.47 and `magic` ^1.0.0.
