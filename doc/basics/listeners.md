# Listeners

Share one private channel between controllers with `BroadcastListeners` and the `ListensToBroadcasts` mixin, and keep an auth-scoped channel in sync with `AuthChannelSubscription`.

- [Basic Usage](#basic-usage)
- [Quick Reference](#quick-reference)
- [Declaring an Alias](#declaring-an-alias)
- [The ListensToBroadcasts Mixin](#the-listenstobroadcasts-mixin)
- [Syncing on Auth Changes](#syncing-on-auth-changes)
- [AuthChannelSubscription](#authchannelsubscription)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="basic-usage"></a>
## Basic Usage

```dart
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

class MonitorController extends MagicController with ListensToBroadcasts {
  @override
  Map<String, void Function(BroadcastEvent)> get listeners => {
    'team:check.recorded': (event) => print(event.data['monitor_id']),
  };
}

Future<void> boot(String? Function() teamChannel) async {
  BroadcastListeners.channel('team', teamChannel);
  await BroadcastListeners.sync();
}
```

A controller that mixes in `ListensToBroadcasts` declares the events it wants as `'<alias>:<event>'`. The alias names a channel you declared once with `BroadcastListeners.channel`. This is the Magic replacement for the `--broadcasts` flag that `make:controller` used to have: write the mixin by hand, there is no generator.

<a name="quick-reference"></a>
## Quick Reference

| Member | Meaning |
|:-------|:--------|
| `BroadcastListeners.channel(alias, name, {onReconnect})` | Declares which private channel `alias` resolves to; `name` returns `null` for "no channel right now". |
| `BroadcastListeners.sync()` | Re-reads every alias name, leaves and joins channels, and disconnects when no alias is live. |
| `BroadcastListeners.add(alias, event, handler)` | Registers a handler and returns a `BroadcastListenerToken`. Throws `StateError` for an undeclared alias. |
| `BroadcastListeners.remove(token)` | Unregisters exactly that handler. |
| `ListensToBroadcasts.listeners` | The `'<alias>:<event>'` map a controller declares. |
| `ListensToBroadcasts.startListening()` | Registers `listeners`; idempotent. Called from `onInit`. |

<a name="declaring-an-alias"></a>
## Declaring an Alias

Left to `Echo`, a second controller's `Echo.private(name).listen(event, ...)` replaces the first controller's handler for that event, and either controller closing would tear the channel down under the other. `BroadcastListeners` is the process-wide registry that fixes both: one subscription per alias, with every handler fanned out from one stable callback in registration order.

```dart
import 'package:magic_socket/magic_socket.dart';

Future<void> declare(int? teamId, Future<void> Function() refetchAll) async {
  BroadcastListeners.channel(
    'team',
    () => teamId == null ? null : 'teams.$teamId',
    onReconnect: refetchAll,
  );

  await BroadcastListeners.sync();
}
```

Declare aliases once, typically in a provider's `boot()`. Calling `channel` again for the same alias replaces its name resolver and `onReconnect` in place. The channel is always a private one (`Echo.private`), so the server must authorise it.

A handler that throws is logged with `Log.error` and the next handler still runs.

<a name="the-listenstobroadcasts-mixin"></a>
## The ListensToBroadcasts Mixin

```dart
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

class MonitorController extends MagicController with ListensToBroadcasts {
  @override
  Map<String, void Function(BroadcastEvent)> get listeners => {
    'team:check.recorded': _onCheck,
    'team:monitor.paused': _onPaused,
  };

  void _onCheck(BroadcastEvent event) => print(event.data);
  void _onPaused(BroadcastEvent event) => print(event.data);
}
```

| Lifecycle | What the mixin does |
|:----------|:--------------------|
| `onInit` | Calls `startListening()` after `super.onInit()`. Magic runs it once, the first time a controller backs a view. |
| `startListening()` | Registers every entry; a key without a colon throws `ArgumentError`. A second call does nothing. |
| `onClose` | Removes every token this controller registered and leaves other controllers on the same alias untouched. |

A controller read only through `.instance` and never mounted in a view never gets `onInit`, so call `startListening()` from its own constructor.

<a name="syncing-on-auth-changes"></a>
## Syncing on Auth Changes

`BroadcastListeners.sync()` is what moves the subscription when the answer of a name resolver changes, so wire it to whatever changes that answer, usually the auth state.

```dart
import 'package:flutter/foundation.dart';
import 'package:magic_socket/magic_socket.dart';

void wire(ChangeNotifier authState) {
  authState.addListener(BroadcastListeners.sync);

  BroadcastListeners.sync(); // the listener only fires on a change
}
```

The aliases share the default `Echo` connection. A `null` name on one alias leaves only that alias's channel. `sync()` disconnects once no alias resolves a channel any more, so a user leaving their last team does not silence an alias that still names them.

<a name="authchannelsubscription"></a>
## AuthChannelSubscription

`AuthChannelSubscription` is the single-channel building block under `BroadcastListeners`. Use it directly when one controller owns one auth-scoped channel and nothing else shares it.

```dart
import 'package:magic_socket/magic_socket.dart';

void watchTeam(int? teamId) {
  final subscription = AuthChannelSubscription(
    channelName: () => teamId == null ? null : 'teams.$teamId',
    listeners: {
      'incident.opened': (event) => print(event.data),
    },
    onReconnect: () => print('refetch what the socket missed'),
  );

  subscription.sync();
}
```

| Behaviour | Detail |
|:----------|:-------|
| `sync()` | Serialised: a call during another defers and runs once more afterwards, so two subscriptions never coexist across an await. |
| Name unchanged | If the connection is down, `sync()` calls `Echo.connect()`. After a mere socket drop the driver still holds the channel and subscribes it on its next handshake, so it is not registered again. After an `Echo.disconnect()` made elsewhere the driver has forgotten it, so `sync()` registers it again with every entry of `listeners`. |
| Name changed | Leaves the old channel, connects when needed, subscribes the new one and wires every entry of `listeners`. |
| `onReconnect` | Fires each time the server confirms the channel again after a drop or a disconnect, not when the socket returns, and at once when a `sync()` finds the channel already confirmed again by another consumer. Reverb does not replay, so refetch here. |
| `null` name | Leaves the channel and, with `disconnectOnTeardown: true` (the default), calls `Echo.disconnect()`, which drops every channel on the connection. |
| `dispose()` | Cancels the reconnect listening only; the channel stays live until a later `sync()` resolves `null`. |

`BroadcastListeners` builds each alias with `disconnectOnTeardown: false` so one alias leaving does not drop the others.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| An alias key without a colon, `'check.recorded'` | Write `'team:check.recorded'`; the first colon splits alias from event. |
| `BroadcastListeners.add` before `channel` | It throws `StateError`; declare the alias first. |
| Never calling `sync()` | No channel is subscribed; call it at startup and on every auth change. |
| Two standalone `AuthChannelSubscription`s on one connection | One `null` name disconnects both, and the other one receives nothing until its next `sync()` registers its channel again; use `BroadcastListeners` or pass `disconnectOnTeardown: false`. |
| A controller only used through `.instance` | `onInit` never runs; call `startListening()` in its constructor. |
| Leaving aliases declared between tests | `BroadcastListeners` is static state that `Magic.flush()` does not clear; call `BroadcastListeners.reset()` in `tearDown`. |

<a name="related-documentation"></a>
## Related Documentation

- [Channels](./channels.md): `Echo.private` and the event envelope.
- [Connection](../guides/connection.md): what `Echo.connect()` and `Echo.disconnect()` do.
- [Testing](../guides/testing.md): `fake.dispatch` against a listener.
