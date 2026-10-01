import 'dart:io';

import 'dart:async';

import 'package:mamba/mamba.dart';
import 'package:nocterm/nocterm.dart';

import 'application/open_task_book.dart';
import 'cli/guard_command.dart';
import 'cli/command_rules.dart';
import 'persistence/json_task_repository.dart';
import 'presentation/theme.dart';
import 'tui/task_list_app.dart';
import 'tui/task_screen.dart';

/// Opens the interactive interface.
final class TuiCommand extends Command {
  new({TaskRepository? repository})
      : repository = resolveRepository(repository),
        super(options: [theme]);

  /// The command token, reused as the executor's default command path.
  static const String commandName = 'tui';

  /// Where the book is read from. Defaults to the platform data directory.
  final TaskRepository repository;

  static final DefaultedOption<AppTheme> theme = ChoiceOption.withDefault(
    'theme',
    choices: AppTheme.values,
    defaultValue: AppTheme.auto,
    description: 'Colour scheme for the interactive interface.',
  );

  @override
  String get name => commandName;

  @override
  String get shortDescription => 'Open the interactive task manager.';

  @override
  String get longDescription =>
      'Opens a full-screen interface for managing lists and tasks. This is the '
      'default when the application is run with no arguments.';

  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      guardCommand(() async {
        if (!stdout.hasTerminal) {
          throw MambaException(
            'The interactive interface needs a terminal. Use the "lists" and '
            '"tasks" commands for non-interactive use.',
            exitCode: exitRejected,
          );
        }

        final book = await openTaskBook(repository: repository);
        final selected = inputs.valueOf(theme);

        await runApp(
          TuiTheme(
            data: resolveTheme(selected),
            child: TaskListApp(
              book: book,
              screen: TaskScreen(book),
            ),
          ),
        );
        return null;
      });
}
