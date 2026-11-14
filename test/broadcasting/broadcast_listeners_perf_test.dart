import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';
import 'package:magic_socket/testing.dart';

/// What this pins: a [BroadcastListeners] fan-out emits one
/// [BroadcastReceived] through core's [MagicPerfHooks] and runs every handler
/// under the root [MagicNotifyCause.broadcast], so a [ControllerNotified]
/// fired from a handler names the broadcast, while a [Debouncer] armed in one
/// reports its own tick.
class _StateController extends MagicController with MagicStateMixin<String> {
  _StateController() {
    onInit();
  }

  /// A reload in the shape a real controller writes: the state moves only
  /// after the awaited read.
  Future<void> reload() async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    setSuccess('reloaded');
  }
}

void main() {
  late List<MagicPerfEvent> events;
  late FakeBroadcastManager echo;

  setUp(() async {
    MagicApp.reset();
    Magic.flush();
    events = <MagicPerfEvent>[];
    MagicPerfHooks.sink = events.add;
    echo = Echo.fake();
    Log.fake();
    BroadcastListeners.channel('team', () => 'teams.1');
    await BroadcastListeners.sync();
  });

  tearDown(() {
    MagicPerfHooks.sink = null;
    BroadcastListeners.reset();
    Echo.unfake();
    Log.unfake();
  });

  Iterable<MagicNotifyCause> causesFor(MagicController controller) {
    return events
        .whereType<ControllerNotified>()
        .where((ControllerNotified e) => identical(e.controller, controller))
        .map((ControllerNotified e) => e.cause);
  }

  void dispatchCheckRecorded() {
    echo.dispatch('private-teams.1', 'check.recorded', const <String, dynamic>{
      'id': '1',
    });
  }

  test('a broadcast dispatch reports broadcast', () {
    final _StateController controller = _StateController();
    BroadcastListeners.add(
      'team',
      'check.recorded',
      (BroadcastEvent _) => controller.refreshUI(),
    );

    dispatchCheckRecorded();

    expect(
      events.whereType<BroadcastReceived>().single.event,
      'check.recorded',
    );
    expect(causesFor(controller), <MagicNotifyCause>[
      MagicNotifyCause.broadcast,
    ]);
  });

  test(
    'a Debouncer armed by a broadcast handler reports timerTick for the '
    'reload it later fires: a root site replaces the inherited cause',
    () async {
      final _StateController controller = _StateController();
      final Debouncer debouncer = Debouncer();
      BroadcastListeners.add(
        'team',
        'check.recorded',
        // Still running when the Debouncer fires, so the broadcast scope the
        // timer was armed in is open: only a root site that replaces it
        // reports timerTick.
        (BroadcastEvent _) async {
          debouncer.run(
            'reload',
            const Duration(milliseconds: 10),
            controller.reload,
          );
          await Future<void>.delayed(const Duration(milliseconds: 40));
        },
      );

      dispatchCheckRecorded();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(causesFor(controller), <MagicNotifyCause>[
        MagicNotifyCause.timerTick,
      ]);
    },
  );

  test(
    'an async broadcast handler reports broadcast after its await',
    () async {
      final _StateController controller = _StateController();
      BroadcastListeners.add(
        'team',
        'check.recorded',
        (BroadcastEvent _) => controller.reload(),
      );

      dispatchCheckRecorded();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(causesFor(controller), <MagicNotifyCause>[
        MagicNotifyCause.broadcast,
      ]);
    },
  );
}
