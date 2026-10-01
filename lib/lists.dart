import 'package:mamba/mamba.dart';

import 'application/open_task_book.dart';
import 'cli/guard_command.dart';
import 'cli/command_rules.dart';
import 'persistence/json_task_repository.dart';


/// Owns the commands that manage task lists.
final class ListsCommand extends GroupCommand {
  new({TaskRepository? repository}) : super(_childrenOf(repository));

  @override
  String get name => 'lists';

  @override
  String get shortDescription => 'Create, rename, and remove task lists.';

  static List<Command> _childrenOf(TaskRepository? repository) {
    final book = resolveRepository(repository);
    return [
      ListsLs(book),
      ListsCreate(book),
      ListsRename(book),
      ListsRm(book),
    ];
  }
}

/// Prints every list with its task counts.
final class ListsLs extends Command {
  new(this.repository);

  final TaskRepository repository;

  @override
  String get name => 'ls';

  @override
  String get shortDescription => 'Show every task list.';

  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      guardCommand(() async {
        final book = await openTaskBook(repository: repository);
        final lists = book.lists;        if (lists.isEmpty) {
          return 'No lists yet.\n'
              'Create one with: task_list lists create <name>';
        }

        final nameWidth = lists.fold<int>(
          'NAME'.length,
          (longest, list) =>
              list.name.length > longest ? list.name.length : longest,
        );
        final buffer = StringBuffer()..writeln(
            '${'NAME'.padRight(nameWidth)}  TASKS  OPEN  DONE');
        for (final list in lists) {
          buffer.writeln(
            '${list.name.padRight(nameWidth)}  '
            '${list.tasks.length.toString().padLeft(5)}  '
            '${list.openCount.toString().padLeft(4)}  '
            '${list.completedCount.toString().padLeft(4)}',
          );
        }
        return buffer.toString().trimRight();
      });
}

/// Creates a list.
final class ListsCreate extends Command {
  new(this.repository) : super(mandatoryPositionals: [listName]);

  final TaskRepository repository;

  static final NormalPositional listName = NormalPositional(
    'name',
    description: 'Name for the new list.',
    regExp: freeText,
  );

  @override
  String get name => 'create';

  @override
  String get shortDescription => 'Create a task list.';

  @override
  String get longDescription =>
      'Creates a task list. Names are unique, ignoring case and surrounding '
      'spaces.';

  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      guardCommand(() async {
        final book = await openTaskBook(repository: repository);
        final list = await book.createList(inputs.valueOf(listName));
        return 'Created list "${list.name}".';
      });
}

/// Renames a list.
final class ListsRename extends Command {
  new(this.repository)
      : super(mandatoryPositionals: [listName, replacementName]);

  final TaskRepository repository;

  static final NormalPositional listName = NormalPositional(
    'list',
    description: 'Name of the list to rename.',
    regExp: freeText,
  );

  static final NormalPositional replacementName = NormalPositional(
    'new-name',
    description: 'The replacement name.',
    regExp: freeText,
  );

  @override
  String get name => 'rename';

  @override
  String get shortDescription => 'Rename a task list.';

  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      guardCommand(() async {
        final book = await openTaskBook(repository: repository);
        final previous = book.requireListByName(inputs.valueOf(listName));
        final renamed = await book.renameList(
          previous.id,
          inputs.valueOf(replacementName),
        );
        return 'Renamed "${previous.name}" to "${renamed.name}".';
      });
}

/// Removes a list and, with it, every task inside.
final class ListsRm extends Command {
  new(this.repository)
      : super(mandatoryPositionals: [listName], flags: [force]);

  final TaskRepository repository;

  static final NormalPositional listName = NormalPositional(
    'list',
    description: 'Name of the list to remove.',
    regExp: freeText,
  );

  static final BooleanFlag force = BooleanFlag(
    'force',
    short: 'f',
    description: 'Confirm removal of a list that still holds tasks.',
  );

  @override
  String get name => 'rm';

  @override
  String get shortDescription => 'Remove a task list and its tasks.';

  @override
  String get longDescription =>
      'Removes a list together with every task in it. A list that still holds '
      'tasks is only removed when --force is given, so a mistyped name cannot '
      'discard work by accident.';

  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      guardCommand(() async {
        final book = await openTaskBook(repository: repository);
        final list = book.requireListByName(inputs.valueOf(listName));
        final taskCount = list.tasks.length;
        if (taskCount > 0 && !inputs.valueOf(force)) {
          throw MambaException(
            'List "${list.name}" still holds $taskCount '
            '${taskCount == 1 ? 'task' : 'tasks'}. Re-run with --force to '
            'remove the list and its tasks.',
            exitCode: exitRejected,
          );
        }
        await book.deleteList(list.id);
        return taskCount == 0
            ? 'Removed list "${list.name}".'
            : 'Removed list "${list.name}" and $taskCount '
                '${taskCount == 1 ? 'task' : 'tasks'}.';
      });
}
