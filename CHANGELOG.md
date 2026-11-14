# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.0.1] - 2026-11-14

### Added

- **First release.** Real-time broadcasting for Magic apps, moved out of `magic` core 0.1.0.
- `Echo` facade: public, private and presence channels over a Laravel Reverb (Pusher protocol) websocket, automatic reconnection, connection state and reconnect streams, and message interceptors.
- A `null` driver and `Echo.fake` (with `package:magic_socket/testing.dart`) so the same code runs and tests without a server.
- `BroadcastServiceProvider`, the `broadcastingConfig` config factory, the `ListensToBroadcasts` controller mixin, `BroadcastListeners` and `AuthChannelSubscription`.
- `SocketIdInterceptor`, which adds `X-Socket-ID` to `Http` requests so Laravel's `toOthers()` skips the sending device.
- A `dowel` plugin provider (`MagicSocketDowelProvider`) that `dart run magic:dowel plugin:install magic_socket` registers.
- Built on `web_socket_channel` ^3.0.3 and `dowel` ^0.0.21. Requires Dart 3.13, Flutter 3.47 and `magic` ^0.1.0.
