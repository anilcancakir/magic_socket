import '../broadcast_event.dart';

/// The Broadcast Interceptor contract.
///
/// Provides hooks for inspecting and mutating messages at the driver level,
/// mirroring the [MagicNetworkInterceptor] pattern. All methods have
/// pass-through default implementations so subclasses only override what they
/// need.
///
/// ```dart
/// class LoggingBroadcastInterceptor extends BroadcastInterceptor {
///   @override
///   BroadcastEvent onReceive(BroadcastEvent event) {
///     print('Received ${event.event} on ${event.channel}');
///     return event;
///   }
/// }
/// ```
///
/// Register interceptors via [BroadcastDriver.addInterceptor].
abstract class BroadcastInterceptor {
  /// Called before an outbound message is sent to the server.
  ///
  /// [message] is the raw payload map. Return the (optionally modified) map
  /// to allow the message to proceed, or an empty map to suppress it: the
  /// frame is not sent and the interceptors after this one are not called.
  /// Suppressing a `pusher:pong` lets the server time the socket out.
  Map<String, dynamic> onSend(Map<String, dynamic> message) => message;

  /// Called when a [BroadcastEvent] is received from the server.
  ///
  /// Return the (optionally modified) event to pass it downstream to channel
  /// listeners.
  BroadcastEvent onReceive(BroadcastEvent event) => event;

  /// Called when the driver encounters an error.
  ///
  /// Return the original [error] to propagate it, or return a replacement
  /// value to recover (e.g. a fallback [BroadcastEvent]). The next
  /// interceptor receives whatever this one returns. When the last one
  /// returns a [BroadcastEvent], the driver delivers it to the listeners of
  /// the channel it names, without passing it through [onReceive]. The
  /// driver's own handling of the failure (a reconnect, an auth retry, a log
  /// entry) runs whatever is returned.
  dynamic onError(dynamic error) => error;
}
