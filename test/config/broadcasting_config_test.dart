import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

Map<String, dynamic> _reverb() {
  final broadcasting = broadcastingConfig['broadcasting'] as Map;
  final connections = broadcasting['connections'] as Map;

  return connections['reverb'] as Map<String, dynamic>;
}

Future<void> _loadEnv(Map<String, String> values) async {
  Env.reset();
  await Env.load(mergeWith: values);
}

void main() {
  tearDown(Env.reset);

  group('broadcastingConfig: Reverb env values', () {
    test('an absent host and scheme take their fallbacks', () async {
      await _loadEnv({});

      expect(_reverb()['host'], 'localhost');
      expect(_reverb()['scheme'], 'ws');
    });

    test('a present but empty host and scheme take their fallbacks', () async {
      await _loadEnv({'REVERB_HOST': '', 'REVERB_SCHEME': ''});

      expect(_reverb()['host'], 'localhost');
      expect(_reverb()['scheme'], 'ws');
    });

    test('a whitespace-only host and scheme take their fallbacks', () async {
      await _loadEnv({'REVERB_HOST': '   ', 'REVERB_SCHEME': '  '});

      expect(_reverb()['host'], 'localhost');
      expect(_reverb()['scheme'], 'ws');
    });

    test('a quote-only host and scheme take their fallbacks', () async {
      await _loadEnv({'REVERB_HOST': '""', 'REVERB_SCHEME': "''"});

      expect(_reverb()['host'], 'localhost');
      expect(_reverb()['scheme'], 'ws');
    });

    test('a set host and scheme win over the fallbacks', () async {
      await _loadEnv({'REVERB_HOST': 'ws.example.com', 'REVERB_SCHEME': 'wss'});

      expect(_reverb()['host'], 'ws.example.com');
      expect(_reverb()['scheme'], 'wss');
    });

    test('a blank app key stays blank for the driver to report', () async {
      await _loadEnv({'REVERB_APP_KEY': ''});

      expect(_reverb()['app_key'], '');
    });

    test('a set app key is read as is', () async {
      await _loadEnv({'REVERB_APP_KEY': 'abc123'});

      expect(_reverb()['app_key'], 'abc123');
    });

    test('a blank port keeps the default port', () async {
      await _loadEnv({'REVERB_PORT': ''});

      expect(_reverb()['port'], 8080);
    });
  });
}
