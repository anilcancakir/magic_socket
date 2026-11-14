# magic_socket example

A Magic app that subscribes to the `orders` channel through the null driver, so it runs with no server. `Simulate OrderShipped` hands the listener the `BroadcastEvent` a real driver would deliver and the event appears in the list; the header shows the active driver and the socket id (`none` for the null driver).

```bash
cd example
flutter create --platforms=web .
flutter run -d chrome
```

`flutter create` adds the platform folder once; it leaves `lib/` and `pubspec.yaml` as they are.

To receive real events, add a `.env` file with `BROADCAST_CONNECTION=reverb` and the `REVERB_*` keys from the package README, and start a Laravel Reverb server. The `Echo.channel('orders').listen(...)` line in `lib/main.dart` stays the same.
