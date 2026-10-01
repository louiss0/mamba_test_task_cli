import 'dart:io';

import 'package:mamba/mamba.dart';
import 'package:nocterm/nocterm.dart';

import 'path_command.dart';
import 'ui.dart';

final class Tui extends Command {
  @override
  String get name => 'tui';
  @override
  String get shortDescription =>
      'Open the interactive task manager (keyboard help: ?).';
  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) async {
    if (!stdin.hasTerminal || !stdout.hasTerminal) {
      throw MambaException(
        'The TUI needs an interactive terminal. Use lists/tasks commands for scripts.',
      );
    }
    return withService(inputs, (service) async {
      await runApp(TaskApp(service), enableHotReload: false);
      return null;
    });
  }
}
