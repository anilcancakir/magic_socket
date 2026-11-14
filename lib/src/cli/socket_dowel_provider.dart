import 'package:dowel/dowel.dart';

/// The dowel provider for Magic Socket.
///
/// Contributes no commands. It exists because dowel `plugin:install` resolves
/// a plugin through `package:magic_socket/cli.dart` and registers the class
/// named `<PascalCase package>DowelProvider` from it.
class MagicSocketDowelProvider extends DowelServiceProvider {
  @override
  String get providerName => 'magic_socket';

  @override
  List<DowelCommand> commands() => <DowelCommand>[];
}
