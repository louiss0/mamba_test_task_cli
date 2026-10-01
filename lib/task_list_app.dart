import 'package:mamba/mamba.dart';

import 'lists.dart';
import 'persistence/json_task_repository.dart';
import 'tasks.dart';
import 'tui.dart';

/// The application version, as Semantic Versioning.
const String applicationVersion = '1.0.0';

/// Builds the executor for the `task_list` application.
///
/// Both executables share this one command tree, so the CLI and the TUI always
/// offer the same operations. Passing [repository] redirects every command at
/// a different book, which is how the tests work in a temporary directory
/// instead of the user's real data.
Executor createTaskListExecutor({TaskRepository? repository}) => Executor(
      'task_list',
      'Manage persistent task lists from the command line or an interactive '
          'terminal interface.',
      applicationVersion,
      [
        ListsCommand(repository: repository),
        TasksCommand(repository: repository),
        TuiCommand(repository: repository),
        // Mamba derives the script from the same registry the parser reads, so
        // completions can never describe a command that no longer exists.
        CompletionCommand.preset(createFile: null),
      ],
      longDescription:
          'Tasks live in named lists that persist as plain JSON in the '
          "platform's user data directory. Run without arguments to open the "
          'interactive interface.',
      defaultCommandPath: [TuiCommand.commandName],
    );
