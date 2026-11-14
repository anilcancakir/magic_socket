import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

const Color _ink = Color(0xFF111827);
const Color _accent = Color(0xFF4F46E5);
const TextStyle _text = TextStyle(color: _ink, fontSize: 16);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    // `broadcastingConfig` reads BROADCAST_CONNECTION from .env and falls back
    // to the null driver, so the example needs no server.
    configFactories: [() => broadcastingConfig],
    configs: [
      {
        'app': {
          'providers': [(app) => BroadcastServiceProvider(app)],
        },
      },
    ],
  );

  runApp(const ExampleApp());
}

/// One channel subscription and a button that stands in for the server.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'magic_socket example',
      color: _accent,
      textStyle: _text,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        );
      },
      home: const OrdersPage(),
    );
  }
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final List<String> _received = <String>[];
  int _orderId = 0;

  @override
  void initState() {
    super.initState();

    // The null driver accepts the subscription and never delivers a frame.
    // With BROADCAST_CONNECTION=reverb the same line receives real events.
    Echo.channel('orders').listen('OrderShipped', _onShipped);
  }

  @override
  void dispose() {
    Echo.leave('orders');
    super.dispose();
  }

  void _onShipped(BroadcastEvent event) {
    if (!mounted) return;

    setState(() {
      _received.insert(0, '${event.event} on ${event.channel}: ${event.data}');
    });
  }

  /// Hands the listener the envelope the Reverb driver would build from a
  /// frame, because the null driver never emits one.
  void _simulate() {
    _onShipped(
      BroadcastEvent(
        event: 'OrderShipped',
        channel: 'orders',
        data: <String, dynamic>{'id': ++_orderId},
        receivedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Driver: ${Echo.connection.runtimeType}, '
              'socket id: ${Echo.socketId ?? 'none'}',
              style: _text,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Button(label: 'Simulate OrderShipped', onTap: _simulate),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _received.isEmpty ? 'No events yet.' : _received.join('\n'),
              style: _text,
            ),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: _accent,
        child: Text(label, style: const TextStyle(color: Color(0xFFFFFFFF))),
      ),
    );
  }
}
