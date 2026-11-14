/// Real-time broadcasting for Magic apps.
///
/// The `Echo` facade fronts a [BroadcastManager] that resolves the configured
/// connection: [ReverbBroadcastDriver] for Laravel Reverb, or
/// [NullBroadcastDriver]. [BroadcastServiceProvider] binds the manager, starts
/// the default connection at boot and adds the `X-Socket-ID` header to `Http`
/// requests; `broadcastingConfig` is the config factory it reads.
library;

export 'config/broadcasting.dart';
export 'src/broadcasting/auth_channel_subscription.dart';
export 'src/broadcasting/broadcast_connection_state.dart';
export 'src/broadcasting/broadcast_event.dart';
export 'src/broadcasting/broadcast_listeners.dart';
export 'src/broadcasting/broadcast_manager.dart';
export 'src/broadcasting/broadcast_service_provider.dart';
export 'src/broadcasting/contracts/broadcast_channel.dart';
export 'src/broadcasting/contracts/broadcast_driver.dart';
export 'src/broadcasting/contracts/broadcast_interceptor.dart';
export 'src/broadcasting/contracts/broadcast_presence_channel.dart';
export 'src/broadcasting/drivers/null_broadcast_driver.dart';
export 'src/broadcasting/drivers/reverb_broadcast_driver.dart';
export 'src/broadcasting/listens_to_broadcasts.dart';
export 'src/broadcasting/socket_id_interceptor.dart';
export 'src/facades/echo.dart';
