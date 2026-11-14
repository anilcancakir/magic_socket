import 'package:magic/magic.dart';

/// Broadcasting configuration, registered as a `configFactories` entry so the
/// `env` reads run after `.env` is loaded.
///
/// ## Connections
///
/// - `reverb`: Laravel Reverb WebSocket server
/// - `null`: no-op driver; drops every broadcast event silently (the default)
///
/// ## Reverb options
///
/// - `host` / `port` / `scheme`: WebSocket endpoint coordinates
/// - `app_key`: Reverb application key (matches the server config)
/// - `auth_endpoint`: HTTP endpoint for private and presence channel auth
/// - `reconnect`: reconnect on an unexpected disconnect
/// - `max_reconnect_delay`: maximum back-off delay in milliseconds
/// - `activity_timeout`: seconds of inactivity before a ping is sent
/// - `connection_timeout`: seconds to wait for the connection to establish
Map<String, dynamic> get broadcastingConfig => {
  'broadcasting': {
    'default': env('BROADCAST_CONNECTION', 'null'),
    'connections': {
      'reverb': {
        'driver': 'reverb',
        'host': env('REVERB_HOST', 'localhost'),
        'port': int.tryParse(env('REVERB_PORT', '8080')) ?? 8080,
        'scheme': env('REVERB_SCHEME', 'ws'),
        'app_key': env('REVERB_APP_KEY', ''),
        'auth_endpoint': '/broadcasting/auth',
        'reconnect': true,
        'max_reconnect_delay': 30000,
        'activity_timeout': 120,
        'connection_timeout': 15,
      },
      'null': {'driver': 'null'},
    },
  },
};
