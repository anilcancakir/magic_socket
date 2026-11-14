# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed

- `Echo.leave('chat.1')` now leaves the channel `Echo.private('chat.1')` or `Echo.join('chat.1')` opened, as Laravel Echo does; it used to keep the server subscription and its listeners alive. The prefixed name still works, and `Echo.fake` behaves the same.
- An `AuthChannelSubscription` (and so `ListensToBroadcasts` and `BroadcastListeners`) receives events again after an `Echo.disconnect()` made elsewhere: its next `sync` registers the channel again and fires `onReconnect` once it is confirmed. `Echo.fake`'s `disconnect` now forgets every channel and handler, as the real driver does.
- A `BroadcastInterceptor` whose `onSend` returns an empty map now suppresses the frame, and a `BroadcastEvent` returned from `onError` now reaches the listeners of its channel, as the contract promised.
- A websocket frame that is not JSON, or a handshake with a missing or non-string `socket_id`, no longer escapes as an uncaught error: it reaches the interceptors' `onError` and the connection keeps delivering events.

## [1.0.0] - 2026-11-14

### Added

- **First release.** Real-time broadcasting for Magic apps, moved out of `magic` core 1.0.0.
- `Echo` facade: public, private and presence channels over a Laravel Reverb (Pusher protocol) websocket, automatic reconnection, connection state and reconnect streams, and message interceptors.
- A `null` driver and `Echo.fake` (with `package:magic_socket/testing.dart`) so the same code runs and tests without a server.
- `BroadcastServiceProvider`, the `broadcastingConfig` config factory, the `ListensToBroadcasts` controller mixin, `BroadcastListeners` and `AuthChannelSubscription`.
- `SocketIdInterceptor`, which adds `X-Socket-ID` to `Http` requests so Laravel's `toOthers()` skips the sending device.
- A `dowel` plugin provider (`MagicSocketDowelProvider`) that `dart run magic:dowel plugin:install magic_socket` registers.
- Built on `web_socket_channel` ^3.0.3 and `dowel` ^1.0.0. Requires Dart 3.13, Flutter 3.47 and `magic` ^1.0.0.
