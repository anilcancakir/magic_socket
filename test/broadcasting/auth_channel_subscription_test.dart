import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';
import 'package:magic_socket/testing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// A [FakeBroadcastDriver] with controllable `onReconnect` and
/// `connectionState` streams, plus a `connect()` counter.
///
/// The shipped [FakeBroadcastDriver] cannot emit a synthetic reconnect or
/// connection-state signal: both streams are `Stream.empty()`. It also cannot
/// distinguish one `connect()` call from two, since `connect()` just flips a
/// bool; counting them is what shows when the subscription asks the driver
/// to connect and when it reuses the live connection.
class _CountingBroadcastDriver extends FakeBroadcastDriver {
  int connectCount = 0;

  /// How many times a private channel was registered through [private].
  int privateCount = 0;

  /// When set, the next [connect] emits `connecting` on [connectionState]
  /// and then throws, instead of succeeding. Simulates the real Reverb
  /// driver's `connect()` failing after its own `connecting` announcement
  /// (e.g. the server unreachable at boot).
  bool failNextConnect = false;

  /// Set by [drop] until the next [connect].
  bool _dropped = false;

  final StreamController<void> _reconnectController =
      StreamController<void>.broadcast();
  final StreamController<BroadcastConnectionState> _connectionStateController =
      StreamController<BroadcastConnectionState>.broadcast();

  @override
  bool get isConnected => !_dropped && super.isConnected;

  @override
  Future<void> connect() async {
    connectCount++;
    if (failNextConnect) {
      failNextConnect = false;
      _connectionStateController.add(BroadcastConnectionState.connecting);
      throw StateError('connect failed');
    }
    _dropped = false;
    return super.connect();
  }

  @override
  BroadcastChannel private(String name) {
    privateCount++;
    return super.private(name);
  }

  /// Loses the socket the way a network drop does: the driver reports itself
  /// disconnected but keeps every channel, which the Reverb driver subscribes
  /// again on its next handshake. Unlike [disconnect], nothing is forgotten.
  void drop() => _dropped = true;

  @override
  Stream<void> get onReconnect => _reconnectController.stream;

  @override
  Stream<BroadcastConnectionState> get connectionState =>
      _connectionStateController.stream;

  /// Emits a synthetic `Echo.onReconnect` signal.
  void emitReconnect() => _reconnectController.add(null);

  /// Emits a synthetic `connectionState` transition.
  void emitConnectionState(BroadcastConnectionState state) =>
      _connectionStateController.add(state);
}

/// A [FakeBroadcastManager] handing out a [_CountingBroadcastDriver].
///
/// Overrides `connection()` rather than replacing the parent's driver, which
/// is private and final, so the inherited assertion helpers (`assertSubscribed`
/// etc.) still speak for the parent's unused driver. Read state off [spy]
/// directly in tests that use this manager.
class _CountingBroadcastManager extends FakeBroadcastManager {
  final _CountingBroadcastDriver spy = _CountingBroadcastDriver();

  @override
  BroadcastDriver connection([String? name]) => spy;
}

/// A [BroadcastManager] handing out one given driver.
class _DriverManager extends BroadcastManager {
  _DriverManager(this.driver);

  final BroadcastDriver driver;

  @override
  BroadcastDriver connection([String? name]) => driver;
}

/// A Reverb socket that completes the Pusher handshake with [socketId] on
/// the next event-loop turn and records every frame the driver sends.
class _ScriptedSocket implements WebSocketChannel {
  _ScriptedSocket(String socketId) {
    Future<void>.delayed(Duration.zero, () {
      _incoming.add(
        jsonEncode(<String, dynamic>{
          'event': 'pusher:connection_established',
          'data': jsonEncode(<String, dynamic>{'socket_id': socketId}),
        }),
      );
    });
  }

  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  final _RecordingSink _sink = _RecordingSink();

  /// The channel names the driver sent a `pusher:subscribe` for.
  List<String> get subscribedChannels => _sink.frames
      .where((Map<String, dynamic> f) => f['event'] == 'pusher:subscribe')
      .map(
        (Map<String, dynamic> f) =>
            (f['data'] as Map<String, dynamic>)['channel'] as String,
      )
      .toList();

  /// Sends the server's confirmation of [channel].
  void confirm(String channel) => _incoming.add(
    jsonEncode(<String, dynamic>{
      'event': 'pusher_internal:subscription_succeeded',
      'channel': channel,
      'data': '{}',
    }),
  );

  /// Sends an application [event] on [channel] carrying [data].
  void deliver(String channel, String event, String data) => _incoming.add(
    jsonEncode(<String, dynamic>{
      'event': event,
      'channel': channel,
      'data': data,
    }),
  );

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [WebSocketSink] that records the decoded frames written to it.
class _RecordingSink implements WebSocketSink {
  final List<Map<String, dynamic>> frames = <Map<String, dynamic>>[];

  @override
  void add(dynamic data) =>
      frames.add(jsonDecode(data as String) as Map<String, dynamic>);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.drain<void>();

  @override
  Future<void> close([int? closeCode, String? closeReason]) =>
      Future<void>.value();

  @override
  Future<void> get done => Future<void>.value();
}

/// Binds a [ReverbBroadcastDriver] with `reconnect: false` as the default
/// `Echo` connection. Every socket it opens is a [_ScriptedSocket] appended to
/// [sockets] with socket id `socket-<index>`, and every auth call is signed.
ReverbBroadcastDriver _bindReverbDriver(List<_ScriptedSocket> sockets) {
  final ReverbBroadcastDriver driver = ReverbBroadcastDriver(
    <String, dynamic>{
      'host': 'localhost',
      'port': 8080,
      'scheme': 'ws',
      'app_key': 'test-app-key',
      'reconnect': false,
    },
    channelFactory: (Uri uri) {
      final _ScriptedSocket socket = _ScriptedSocket(
        'socket-${sockets.length + 1}',
      );
      sockets.add(socket);
      return socket;
    },
    authFactory: (String endpoint, Map<String, dynamic> data) async =>
        <String, dynamic>{'auth': 'sig-${data['socket_id']}'},
  );
  Magic.app.setInstance('broadcasting', _DriverManager(driver));
  return driver;
}

void main() {
  late FakeBroadcastManager echo;

  setUp(() {
    MagicApp.reset();
    Magic.flush();
    // Bind LogManager so the documented degradation path (a caught `sync`
    // failure logs rather than throwing) resolves the `log` service.
    Magic.singleton('log', () => LogManager());
    echo = Echo.fake();
  });

  tearDown(() {
    Echo.unfake();
    MagicApp.reset();
    Magic.flush();
  });

  /// Lets a stream event queued on a [StreamController] reach its listener
  /// before assertions run.
  Future<void> flushMicrotasks() => Future<void>.delayed(Duration.zero);

  test(
    'the first sync subscribes and a dispatched event reaches its listener',
    () async {
      final List<BroadcastEvent> received = <BroadcastEvent>[];
      final AuthChannelSubscription subscription = AuthChannelSubscription(
        channelName: () => 'teams.1',
        listeners: <String, void Function(BroadcastEvent)>{
          'incident.opened': received.add,
        },
      );

      await subscription.sync();

      echo.assertConnected();
      echo.assertSubscribed('private-teams.1');
      echo.assertListening('private-teams.1', 'incident.opened');

      echo.dispatch(
        'private-teams.1',
        'incident.opened',
        const <String, dynamic>{'id': 'i1'},
      );

      expect(received, hasLength(1));
      expect(received.single.data['id'], 'i1');
    },
  );

  test(
    'a name change leaves the old channel and subscribes to the new one with '
    'exactly one connect',
    () async {
      final _CountingBroadcastManager counting = _CountingBroadcastManager();
      Magic.app.setInstance('broadcasting', counting);

      String channelName = 'teams.1';
      final AuthChannelSubscription subscription = AuthChannelSubscription(
        channelName: () => channelName,
        listeners: <String, void Function(BroadcastEvent)>{},
      );

      await subscription.sync();
      expect(
        counting.spy.connectCount,
        1,
        reason: 'the first sync must connect',
      );
      expect(counting.spy.subscribedChannels, contains('private-teams.1'));

      channelName = 'teams.2';
      await subscription.sync();

      expect(
        counting.spy.connectCount,
        1,
        reason: 'an already-open socket is reused',
      );
      expect(counting.spy.subscribedChannels, contains('private-teams.2'));
      expect(
        counting.spy.subscribedChannels,
        isNot(contains('private-teams.1')),
      );
    },
  );

  test('an unchanged name asks the driver to connect while the socket is '
      'down and holds the channel exactly once', () async {
    final _CountingBroadcastManager counting = _CountingBroadcastManager();
    Magic.app.setInstance('broadcasting', counting);

    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{},
    );

    await subscription.sync();
    await counting.spy.disconnect();
    await subscription.sync();

    expect(
      counting.spy.connectCount,
      2,
      reason:
          'a driver with reconnect disabled never retries on its own, and '
          'connect() is idempotent on one that does',
    );
    expect(
      counting.spy.subscribedChannels
          .where((String c) => c == 'private-teams.1')
          .length,
      1,
    );
  });

  test('an unchanged name after a mere socket drop asks the driver to '
      'connect without registering the channel again', () async {
    final _CountingBroadcastManager counting = _CountingBroadcastManager();
    Magic.app.setInstance('broadcasting', counting);

    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{},
    );

    await subscription.sync();
    counting.spy.drop();
    await subscription.sync();

    expect(counting.spy.connectCount, 2);
    expect(
      counting.spy.privateCount,
      1,
      reason:
          'the driver still holds the channel and subscribes it on its '
          'next handshake',
    );
  });

  test('an Echo.leave() followed by a sync with no await between registers '
      'the channel again', () async {
    final List<BroadcastEvent> received = <BroadcastEvent>[];
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{
        'incident.opened': received.add,
      },
    );
    await subscription.sync();

    Echo.leave('teams.1');
    await subscription.sync();

    echo.assertSubscribed('private-teams.1');
    echo.dispatch('private-teams.1', 'incident.opened', const <String, dynamic>{
      'id': 'i4',
    });
    expect(received.single.data['id'], 'i4');
  });

  test('on the Reverb driver, an Echo.leave() followed by a sync with no '
      'await between subscribes the channel again', () async {
    final List<_ScriptedSocket> sockets = <_ScriptedSocket>[];
    final ReverbBroadcastDriver driver = _bindReverbDriver(sockets);
    final List<BroadcastEvent> received = <BroadcastEvent>[];
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{
        'incident.opened': received.add,
      },
    );
    await subscription.sync();
    await flushMicrotasks();
    sockets.single.confirm('private-teams.1');
    await flushMicrotasks();

    Echo.leave('teams.1');
    await subscription.sync();
    await flushMicrotasks();

    expect(
      sockets.single.subscribedChannels.where(
        (String c) => c == 'private-teams.1',
      ),
      hasLength(2),
    );
    sockets.single.confirm('private-teams.1');
    sockets.single.deliver('private-teams.1', 'incident.opened', '{"id":"i5"}');
    await flushMicrotasks();
    expect(received.single.data['id'], 'i5');

    await driver.disconnect();
  });

  test('an external Echo.disconnect() then a sync registers the channel '
      'again and a dispatched event reaches its listener', () async {
    final List<BroadcastEvent> received = <BroadcastEvent>[];
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{
        'incident.opened': received.add,
      },
    );
    await subscription.sync();

    await Echo.disconnect();
    await subscription.sync();

    echo.assertConnected();
    echo.assertSubscribed('private-teams.1');
    echo.dispatch('private-teams.1', 'incident.opened', const <String, dynamic>{
      'id': 'i2',
    });
    expect(received.single.data['id'], 'i2');
  });

  test('a channel registered again after an external Echo.disconnect() '
      'refetches on its first confirmation', () async {
    int reconnectCount = 0;
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{},
      onReconnect: () => reconnectCount++,
    );
    await subscription.sync();
    echo.driver.setSubscribed('private-teams.1', true);
    await flushMicrotasks();

    await Echo.disconnect();
    await subscription.sync();
    echo.driver.setSubscribed('private-teams.1', true);
    await flushMicrotasks();

    expect(
      reconnectCount,
      1,
      reason: 'events published while the socket was gone are lost',
    );
  });

  test('on the Reverb driver, an external Echo.disconnect() then a sync '
      'receives server events again and fires onReconnect', () async {
    final List<_ScriptedSocket> sockets = <_ScriptedSocket>[];
    final ReverbBroadcastDriver driver = _bindReverbDriver(sockets);

    final List<BroadcastEvent> received = <BroadcastEvent>[];
    int reconnectCount = 0;
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{
        'incident.opened': received.add,
      },
      onReconnect: () => reconnectCount++,
    );
    await subscription.sync();
    await flushMicrotasks();
    sockets.first.confirm('private-teams.1');
    await flushMicrotasks();

    await Echo.disconnect();
    await subscription.sync();
    await flushMicrotasks();

    expect(sockets, hasLength(2));
    expect(sockets.last.subscribedChannels, contains('private-teams.1'));

    sockets.last.confirm('private-teams.1');
    sockets.last.deliver('private-teams.1', 'incident.opened', '{"id":"i3"}');
    await flushMicrotasks();

    expect(received.single.data['id'], 'i3');
    expect(reconnectCount, 1);

    await driver.disconnect();
  });

  test(
    'on the Reverb driver, a sync after an external Echo.disconnect() '
    'that finds the channel already confirmed again fires onReconnect',
    () async {
      final List<_ScriptedSocket> sockets = <_ScriptedSocket>[];
      final ReverbBroadcastDriver driver = _bindReverbDriver(sockets);

      int reconnectCount = 0;
      final AuthChannelSubscription subscription = AuthChannelSubscription(
        channelName: () => 'teams.1',
        listeners: <String, void Function(BroadcastEvent)>{},
        onReconnect: () => reconnectCount++,
      );
      await subscription.sync();
      await flushMicrotasks();
      sockets.first.confirm('private-teams.1');
      await flushMicrotasks();

      // Another consumer registers the channel again and the server confirms
      // it before this subscription's next sync, so its confirmation stream
      // has nothing left to replay.
      await Echo.disconnect();
      Echo.private('teams.1');
      await Echo.connect();
      await flushMicrotasks();
      sockets.last.confirm('private-teams.1');
      await flushMicrotasks();
      expect(Echo.private('teams.1').isSubscribed, isTrue);

      await subscription.sync();
      await flushMicrotasks();

      expect(
        reconnectCount,
        1,
        reason: 'events published while the socket was gone are lost',
      );

      await driver.disconnect();
    },
  );

  test(
    'a failed connect is retried by the next sync for the same name',
    () async {
      final _CountingBroadcastManager counting = _CountingBroadcastManager();
      Magic.app.setInstance('broadcasting', counting);
      counting.spy.failNextConnect = true;

      final AuthChannelSubscription subscription = AuthChannelSubscription(
        channelName: () => 'teams.1',
        listeners: <String, void Function(BroadcastEvent)>{},
      );

      await subscription.sync();
      expect(counting.spy.isConnected, isFalse);

      await subscription.sync();

      expect(counting.spy.connectCount, 2);
      expect(counting.spy.isConnected, isTrue);
    },
  );

  test('a name change while the socket is down asks the driver to connect, '
      'whatever state it last reported, and subscribes', () async {
    final _CountingBroadcastManager counting = _CountingBroadcastManager();
    Magic.app.setInstance('broadcasting', counting);

    String channelName = 'teams.1';
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => channelName,
      listeners: <String, void Function(BroadcastEvent)>{},
    );

    await subscription.sync();
    expect(counting.spy.connectCount, 1);

    // The driver dropped its socket and reports a pending reconnect. The
    // subscription no longer second-guesses that: the driver's connect()
    // is idempotent and supersedes its own armed retry.
    counting.spy.emitConnectionState(BroadcastConnectionState.reconnecting);
    await flushMicrotasks();
    await counting.spy.disconnect();

    channelName = 'teams.2';
    await subscription.sync();

    expect(counting.spy.connectCount, 2);
    expect(counting.spy.subscribedChannels, contains('private-teams.2'));
  });

  test('a failed own connect still registers the channel with its listeners, '
      'the driver subscribes it on its next handshake', () async {
    final _CountingBroadcastManager counting = _CountingBroadcastManager();
    Magic.app.setInstance('broadcasting', counting);
    counting.spy.failNextConnect = true;

    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{
        'incident.opened': (BroadcastEvent event) {},
      },
    );

    await subscription.sync();

    expect(
      counting.spy.connectCount,
      1,
      reason: 'the first sync attempts to connect',
    );
    expect(
      counting.spy.subscribedChannels,
      contains('private-teams.1'),
      reason: 'a failed connect must not leave the channel unregistered',
    );
    expect(
      counting.spy.listeners['private-teams.1'],
      contains('incident.opened'),
      reason: 'the listeners are attached before the driver ever connects',
    );

    await subscription.sync();

    expect(
      counting.spy.subscribedChannels
          .where((String c) => c == 'private-teams.1')
          .length,
      1,
      reason: 'the marker is set, so an unchanged name is not registered again',
    );
  });

  test('a failed own connect refetches on the first confirmation, which '
      'closes the gap since the screen loaded', () async {
    final _CountingBroadcastManager counting = _CountingBroadcastManager();
    Magic.app.setInstance('broadcasting', counting);
    counting.spy.failNextConnect = true;

    int reconnectCount = 0;
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{},
      onReconnect: () => reconnectCount++,
    );
    await subscription.sync();

    counting.spy.setSubscribed('private-teams.1', true);
    await flushMicrotasks();

    expect(reconnectCount, 1);
  });

  test('overlapping syncs serialize and settle on the latest name', () async {
    String channelName = 'teams.1';
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => channelName,
      listeners: <String, void Function(BroadcastEvent)>{},
    );

    // Start the first sync (teams.1) without awaiting; it suspends at
    // `await Echo.connect()`.
    final Future<void> first = subscription.sync();
    // The name changes before the first sync completes. Without the latch
    // this would run concurrently and could leave both channels subscribed.
    channelName = 'teams.2';
    final Future<void> second = subscription.sync();

    await Future.wait(<Future<void>>[first, second]);

    echo.assertSubscribed('private-teams.2');
    echo.assertNotSubscribed('private-teams.1');
    expect(
      echo.driver.subscribedChannels
          .where((String c) => c == 'private-teams.2')
          .length,
      1,
      reason: 'the deferred re-run must not double-subscribe the settled name',
    );
  });

  test('a null channel name leaves the channel and disconnects', () async {
    String? channelName = 'teams.1';
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => channelName,
      listeners: <String, void Function(BroadcastEvent)>{},
    );

    await subscription.sync();
    echo.assertConnected();

    channelName = null;
    await subscription.sync();

    echo.assertDisconnected();
    echo.assertNotSubscribed('private-teams.1');
  });

  test('a null channel name before any subscribe is a safe no-op', () async {
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => null,
      listeners: <String, void Function(BroadcastEvent)>{},
    );

    await subscription.sync();

    echo.assertDisconnected();
  });

  test('a confirmation after a drop fires onReconnect once, the first '
      'confirmation on a live socket does not', () async {
    final _CountingBroadcastManager counting = _CountingBroadcastManager();
    Magic.app.setInstance('broadcasting', counting);

    int reconnectCount = 0;
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{},
      onReconnect: () => reconnectCount++,
    );
    await subscription.sync();

    counting.spy.setSubscribed('private-teams.1', true);
    await flushMicrotasks();
    expect(reconnectCount, 0);

    counting.spy.setSubscribed('private-teams.1', false);
    counting.spy.setSubscribed('private-teams.1', true);
    await flushMicrotasks();

    expect(reconnectCount, 1);
  });

  test('a reconnect announced before the channel is confirmed again does '
      'not refetch until the confirmation', () async {
    final _CountingBroadcastManager counting = _CountingBroadcastManager();
    Magic.app.setInstance('broadcasting', counting);

    int reconnectCount = 0;
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{},
      onReconnect: () => reconnectCount++,
    );
    await subscription.sync();
    counting.spy.setSubscribed('private-teams.1', true);
    await flushMicrotasks();

    // The socket is back but the channel's auth is still being retried:
    // events published now are not delivered, so a refetch would miss them.
    counting.spy.setSubscribed('private-teams.1', false);
    counting.spy.emitConnectionState(BroadcastConnectionState.connected);
    counting.spy.emitReconnect();
    await flushMicrotasks();
    expect(reconnectCount, 0);

    counting.spy.setSubscribed('private-teams.1', true);
    await flushMicrotasks();

    expect(reconnectCount, 1);
  });

  test('a resync requested while a pass is throwing still runs and settles on '
      'the latest name', () async {
    // `channelName` throws on its very first call, the way a caller's
    // getter might while its own state is mid-update. A second `sync`
    // arrives before that failing pass is caught, so it only sets the
    // resync flag; the fix is that the flag is still honored after the
    // catch, not just after a clean pass.
    int calls = 0;
    String channelName = 'teams.1';
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () {
        calls++;
        if (calls == 1) {
          throw StateError('channel name unavailable');
        }
        return channelName;
      },
      listeners: <String, void Function(BroadcastEvent)>{},
    );

    final Future<void> first = subscription.sync();
    channelName = 'teams.2';
    final Future<void> second = subscription.sync();

    await Future.wait(<Future<void>>[first, second]);

    echo.assertSubscribed('private-teams.2');
  });

  test('dispose is idempotent', () async {
    final AuthChannelSubscription subscription = AuthChannelSubscription(
      channelName: () => 'teams.1',
      listeners: <String, void Function(BroadcastEvent)>{},
    );
    await subscription.sync();

    subscription.dispose();
    subscription.dispose();
  });
}
