import 'dart:async';

import '../broadcasting/broadcast_connection_state.dart';
import '../broadcasting/broadcast_event.dart';
import '../broadcasting/broadcast_manager.dart';
import '../broadcasting/contracts/broadcast_channel.dart';
import '../broadcasting/contracts/broadcast_driver.dart';
import '../broadcasting/contracts/broadcast_interceptor.dart';
import '../broadcasting/contracts/broadcast_presence_channel.dart';

/// A fake [BroadcastManager] for testing.
///
/// Routes all broadcasting operations through an in-memory fake driver instead
/// of a real WebSocket connection. Provides assertion helpers for verifying
/// expected broadcasting activity.
///
/// ```dart
/// final fake = Echo.fake();
///
/// await Echo.connect();
/// Echo.channel('orders');
///
/// fake.assertConnected();
/// fake.assertSubscribed('orders');
/// ```
class FakeBroadcastManager extends BroadcastManager {
  final FakeBroadcastDriver _driver = FakeBroadcastDriver();

  /// The underlying fake driver, exposed for direct inspection in tests.
  FakeBroadcastDriver get driver => _driver;

  @override
  BroadcastDriver connection([String? name]) => _driver;

  // ---------------------------------------------------------------------------
  // Assertions
  // ---------------------------------------------------------------------------

  /// Assert that the fake driver is currently connected.
  ///
  /// Throws [AssertionError] if the driver is not connected.
  void assertConnected() {
    if (!_driver._connected) {
      throw AssertionError(
        'Expected the broadcast driver to be connected but it was disconnected.',
      );
    }
  }

  /// Assert that the fake driver is currently disconnected.
  ///
  /// Throws [AssertionError] if the driver is connected.
  void assertDisconnected() {
    if (_driver._connected) {
      throw AssertionError(
        'Expected the broadcast driver to be disconnected but it was connected.',
      );
    }
  }

  /// Assert that [channel] is currently in the subscribed channels list.
  ///
  /// Throws [AssertionError] if [channel] was not subscribed.
  void assertSubscribed(String channel) {
    if (!_driver._subscribedChannels.contains(channel)) {
      throw AssertionError(
        'Expected channel "$channel" to be subscribed but it was not found. '
        'Subscribed channels: ${_driver._subscribedChannels}',
      );
    }
  }

  /// Assert that [channel] is NOT in the subscribed channels list.
  ///
  /// Throws [AssertionError] if [channel] is currently subscribed.
  void assertNotSubscribed(String channel) {
    if (_driver._subscribedChannels.contains(channel)) {
      throw AssertionError(
        'Expected channel "$channel" to not be subscribed but it was found.',
      );
    }
  }

  /// Assert that a handler for [event] is registered on [channel].
  ///
  /// Subscribing to a channel and listening for an event are separate steps, and
  /// [assertSubscribed] only covers the first: an application can hold a live
  /// channel and register no handler at all. This is the assertion that fails
  /// when a `listen()` line is deleted.
  ///
  /// Throws [AssertionError] if no handler is registered.
  void assertListening(String channel, String event) {
    final Map<String, void Function(BroadcastEvent)>? handlers =
        _driver._listeners[channel];

    if (handlers == null || !handlers.containsKey(event)) {
      throw AssertionError(
        'Expected a handler for "$event" on channel "$channel" but none was '
        'registered. Registered: ${_driver.listeners}',
      );
    }
  }

  /// Assert that NO handler for [event] is registered on [channel].
  ///
  /// Throws [AssertionError] if a handler is registered.
  void assertNotListening(String channel, String event) {
    if (_driver._listeners[channel]?.containsKey(event) ?? false) {
      throw AssertionError(
        'Expected no handler for "$event" on channel "$channel" but one was '
        'registered.',
      );
    }
  }

  /// Deliver [data] to the handler registered for [event] on [channel], exactly
  /// as the driver would on an incoming frame.
  ///
  /// This is what turns "a handler exists" into "a handler runs on a frame".
  /// [data] is handed over already decoded, matching [BroadcastEvent.data] on the
  /// real driver, which performs the Pusher double-JSON-decode before a handler
  /// ever sees it.
  ///
  /// Throws [AssertionError] if no handler is registered, because dispatching
  /// into silence is the failure this method exists to make visible.
  void dispatch(String channel, String event, Map<String, dynamic> data) {
    assertListening(channel, event);

    _driver._listeners[channel]![event]!(
      BroadcastEvent(
        event: event,
        channel: channel,
        data: data,
        receivedAt: DateTime.now(),
      ),
    );
  }

  /// Assert that at least one interceptor has been added to the driver.
  ///
  /// Throws [AssertionError] if no interceptors have been added.
  void assertInterceptorAdded() {
    if (_driver._addedInterceptors.isEmpty) {
      throw AssertionError(
        'Expected at least one interceptor to have been added but none were recorded.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------

  /// Clear all recorded state on the fake driver.
  void reset() => _driver._reset();
}

// ---------------------------------------------------------------------------
// Fake driver: records operations, no real connection
// ---------------------------------------------------------------------------

/// An in-memory [BroadcastDriver] that records all operations for assertions.
///
/// Accessed via [FakeBroadcastManager.driver] in tests.
class FakeBroadcastDriver implements BroadcastDriver {
  bool _connected = false;
  final List<String> _subscribedChannels = [];
  final List<BroadcastInterceptor> _addedInterceptors = [];

  /// Whether the driver is currently connected.
  @override
  bool get isConnected => _connected;

  /// The list of channel names currently recorded as subscribed.
  List<String> get subscribedChannels => List.unmodifiable(_subscribedChannels);

  /// The list of interceptors that have been added.
  List<BroadcastInterceptor> get addedInterceptors =>
      List.unmodifiable(_addedInterceptors);

  @override
  Future<void> connect() async => _connected = true;

  /// Disconnects and forgets every channel, as the real driver does: each
  /// handler is dropped, each channel leaves [subscribedChannels], a
  /// confirmed channel reports `false` on its
  /// [BroadcastChannel.onSubscriptionChanged], and that stream then ends.
  @override
  Future<void> disconnect() async {
    _connected = false;
    _forgetAll();
  }

  @override
  String? get socketId => _connected ? 'fake-socket-id' : null;

  @override
  Stream<BroadcastConnectionState> get connectionState => const Stream.empty();

  @override
  Stream<void> get onReconnect => const Stream.empty();

  /// The handle held for each registered fully-qualified channel name, so a
  /// second call for that name answers the same one, as the real driver
  /// does. A leave or a disconnect removes it.
  final Map<String, _FakeBroadcastChannel> _handles = {};

  @override
  BroadcastChannel channel(String name) =>
      _handles[name] ?? _hold(_FakeBroadcastChannel(name, this));

  @override
  BroadcastChannel private(String name) {
    final String prefixed = 'private-$name';

    return _handles[prefixed] ?? _hold(_FakeBroadcastChannel(prefixed, this));
  }

  @override
  BroadcastPresenceChannel join(String name) {
    final String prefixed = 'presence-$name';
    final _FakeBroadcastChannel? held = _handles[prefixed];
    if (held is _FakeBroadcastPresenceChannel) return held;

    return _hold<_FakeBroadcastPresenceChannel>(
      _FakeBroadcastPresenceChannel(prefixed, this),
    );
  }

  /// Records the subscription of [channel] and holds it under its name.
  T _hold<T extends _FakeBroadcastChannel>(T channel) {
    _subscribedChannels.add(channel.name);
    _handles[channel.name] = channel;

    return channel;
  }

  /// Event handlers registered through [BroadcastChannel.listen], keyed by
  /// channel name and then by event name.
  ///
  /// The driver owns this rather than the channel, so [FakeBroadcastManager]
  /// asserts and dispatches against one place, and a leave or a disconnect
  /// forgets a channel's handlers in the same step that drops its handle.
  final Map<String, Map<String, void Function(BroadcastEvent)>> _listeners = {};

  /// Registered event names per channel, for low-level inspection.
  Map<String, List<String>> get listeners => Map.unmodifiable({
    for (final MapEntry<String, Map<String, void Function(BroadcastEvent)>> e
        in _listeners.entries)
      e.key: List<String>.unmodifiable(e.value.keys),
  });

  void _register(
    String channel,
    String event,
    void Function(BroadcastEvent) callback,
  ) {
    // Last registration wins, matching ReverbBroadcastDriver, which cancels the
    // previous subscription before storing the new one. A fake that appended
    // instead would hide a double-registration bug rather than reproduce it.
    (_listeners[channel] ??= {})[event] = callback;
  }

  void _unregister(String channel, String event) =>
      _listeners[channel]?.remove(event);

  /// Server confirmations per fully-qualified channel name, read by
  /// [BroadcastChannel.isSubscribed]. Owned here for the same reason as
  /// [_listeners]: the channel objects are minted per call.
  final Map<String, bool> _confirmed = {};

  /// The [BroadcastChannel.onSubscriptionChanged] source per fully-qualified
  /// channel name, shared by every channel object minted for that name until
  /// a leave or a disconnect closes it, the way the real driver closes a
  /// channel's stream when it disposes the channel.
  final Map<String, StreamController<bool>> _confirmationStreams = {};

  /// The open confirmation source for [channel], created on first use.
  StreamController<bool> _confirmationsFor(String channel) =>
      _confirmationStreams[channel] ??= StreamController<bool>.broadcast();

  /// Sets what [BroadcastChannel.isSubscribed] answers for [channel], the
  /// fully-qualified name (`private-orders`, not `orders`), and emits on its
  /// [BroadcastChannel.onSubscriptionChanged] when the value changes.
  ///
  /// Stands in for the server's `subscription_succeeded` (`true`) and a
  /// dropped socket (`false`). Every channel starts unconfirmed.
  void setSubscribed(String channel, bool subscribed) {
    if ((_confirmed[channel] ?? false) == subscribed) return;

    _confirmed[channel] = subscribed;
    _confirmationStreams[channel]?.add(subscribed);
  }

  /// Leaves every channel recorded under [name]: the channel itself and its
  /// `private-` and `presence-` forms, as the real driver does. Each one's
  /// handlers are dropped, a confirmed one reports `false`, and its
  /// subscription stream ends.
  @override
  void leave(String name) {
    for (final candidate in <String>[name, 'private-$name', 'presence-$name']) {
      _forget(candidate);
    }
  }

  @override
  void addInterceptor(BroadcastInterceptor interceptor) =>
      _addedInterceptors.add(interceptor);

  /// Drops everything recorded for the fully-qualified [channel].
  void _forget(String channel) {
    _subscribedChannels.removeWhere((recorded) => recorded == channel);
    _listeners.remove(channel);
    // Report a confirmed channel as dropped before its stream ends, so a
    // listener attached earlier does not keep a stale `true`.
    setSubscribed(channel, false);
    _confirmed.remove(channel);
    _confirmationStreams.remove(channel)?.close();
    _handles.remove(channel);
  }

  /// Forgets every channel the driver has recorded in any form.
  void _forgetAll() {
    final channels = <String>{
      ..._subscribedChannels,
      ..._listeners.keys,
      ..._confirmed.keys,
      ..._confirmationStreams.keys,
    };
    for (final channel in channels) {
      _forget(channel);
    }
  }

  void _reset() {
    _connected = false;
    _addedInterceptors.clear();
    _forgetAll();
  }
}

// ---------------------------------------------------------------------------
// Internal fake channel: stub with empty events stream
// ---------------------------------------------------------------------------

class _FakeBroadcastChannel implements BroadcastChannel {
  _FakeBroadcastChannel(this._name, this._driver)
    : _confirmations = _driver._confirmationsFor(_name);

  final String _name;
  final FakeBroadcastDriver _driver;

  /// The confirmation source open when this channel was minted. A leave or
  /// a disconnect closes it, which ends [onSubscriptionChanged] for this
  /// object even after the name is subscribed again.
  final StreamController<bool> _confirmations;

  /// Whether a leave or a disconnect disposed this handle. A disposed handle
  /// is detached from the name: a channel subscribed again under it gets a
  /// new handle, and this one neither reports that channel's state nor
  /// touches its handlers, as a disposed Reverb channel does.
  bool get _disposed => _confirmations.isClosed;

  @override
  String get name => _name;

  @override
  Stream<BroadcastEvent> get events => const Stream.empty();

  @override
  bool get isSubscribed => !_disposed && (_driver._confirmed[_name] ?? false);

  @override
  Stream<bool> get onSubscriptionChanged => _confirmations.stream;

  @override
  BroadcastChannel listen(
    String event,
    void Function(BroadcastEvent) callback,
  ) {
    // Recorded rather than discarded, and the difference is what a consumer's
    // test can prove. This used to return `this` and drop both arguments, so a
    // subscription line could be deleted from an application and its whole suite
    // stayed green: the one line every broadcast depends on was the one line
    // nothing covered.
    if (!_disposed) {
      _driver._register(_name, event, callback);
    }

    return this;
  }

  @override
  void stopListening(String event) {
    if (_disposed) return;

    _driver._unregister(_name, event);
  }
}

// ---------------------------------------------------------------------------
// Internal fake presence channel: empty members and streams
// ---------------------------------------------------------------------------

class _FakeBroadcastPresenceChannel extends _FakeBroadcastChannel
    implements BroadcastPresenceChannel {
  _FakeBroadcastPresenceChannel(super.name, super.driver);

  @override
  List<Map<String, dynamic>> get members => const [];

  @override
  Stream<Map<String, dynamic>> get onJoin => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get onLeave => const Stream.empty();
}
