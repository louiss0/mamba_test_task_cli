import 'package:mamba/mamba.dart';

import 'application/open_task_book.dart';
import 'cli/guard_command.dart';
import 'cli/command_rules.dart';
import 'domain/completion_filter.dart';
import 'domain/task.dart';
import 'domain/task_filter.dart';
import 'domain/task_list.dart';
import 'domain/validation.dart';
import 'persistence/json_task_repository.dart';
import 'presentation/table.dart';
import 'presentation/timestamps.dart';

/// Owns the commands that manage tasks inside a list.
final class TasksCommand extends GroupCommand {
  new({TaskRepository? repository}) : super(_childrenOf(repository));

  @override
  String get name => 'tasks';

  @override
  String get shortDescription => 'Add, edit, complete, and remove tasks.';

  static List<Command> _childrenOf(TaskRepository? repository) {
    final book = resolveRepository(repository);
    return [
      TasksLs(book),
      TasksAdd(book),
      TasksEdit(book),
      TasksDone(book),
      TasksUndone(book),
      TasksRm(book),
    ];
  }
}

/// Prints the tasks of one list, optionally narrowed to one completion state.
final class TasksLs extends Command {
  new(this.repository)
      : super(
          mandatoryPositionals: [listName],
          options: [filter],
        );

  final TaskRepository repository;

  static final NormalPositional listName = NormalPositional(
    'list',
    description: 'Name of the list to read.',
    regExp: freeText,
  );

  static final DefaultedOption<CompletionFilter> filter =
      ChoiceOption.withDefault(
    'filter',
    choices: CompletionFilter.values,
    defaultValue: CompletionFilter.all,
    short: 'f',
    description: 'Which completion states to include.',
  );

  @override
  String get name => 'ls';

  @override
  String get shortDescription => 'Show the tasks in a list.';

  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      guardCommand(() async {
        final book = await openTaskBook(repository: repository);
        final list = book.requireListByName(inputs.valueOf(listName));
        final completion = inputs.valueOf(filter);
        final tasks = book.queryTasks(
          list.id,
          TaskFilter.byCompletion(completion),
        );
        if (tasks.isEmpty) {
          return _emptyMessage(list, completion);
        }

        return renderTable(
          headings: const ['REF', 'STATUS', 'CREATED', 'TITLE'],
          rows: [
            for (final task in tasks)
              [
                task.reference,
                task.completed ? 'done' : 'open',
                formatTimestamp(task.createdAt),
                task.title,
              ],
          ],
        );
      });

  String _emptyMessage(TaskList list, CompletionFilter completion) {
    if (list.tasks.isEmpty) {
      return 'List "${list.name}" has no tasks.\n'
          'Add one with: task_list tasks add ${list.name} <title>';
    }
    return switch (completion) {
      CompletionFilter.all => 'List "${list.name}" has no tasks.',
      CompletionFilter.incomplete => 'List "${list.name}" has no incomplete '
          'tasks.\nRun with --filter completed to see the finished ones.',
      CompletionFilter.completed => 'List "${list.name}" has no completed '
          'tasks.\nRun with --filter incomplete to see what is left.',
    };
  }
}

/// Adds a task to a list.
final class TasksAdd extends Command {
  new(this.repository)
      : super(
          mandatoryPositionals: [listName, firstWord],
          variadic: rest,
        );

  final TaskRepository repository;

  static final NormalPositional listName = NormalPositional(
    'list',
    description: 'Name of the list to add to.',
    regExp: freeText,
  );

  static final NormalPositional firstWord = NormalPositional(
    'title',
    description: 'The task title. Quote it to include spaces.',
    regExp: freeText,
  );

  static final NormalVariadic rest = NormalVariadic(
    description: 'Words after -- , for a title that starts with a dash.',
    regExp: freeText,
  );

  @override
  String get name => 'add';

  @override
  String get shortDescription => 'Add a task to a list.';

  @override
  String get longDescription =>
      'Adds an incomplete task. Quote the title so spaces are kept: '
      'task_list tasks add Work "Buy milk". A title that begins with a dash '
      'goes after a -- separator.';

  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      guardCommand(() async {
        final book = await openTaskBook(repository: repository);
        final list = book.requireListByName(inputs.valueOf(listName));
        final task = await book.addTask(
          list.id,
          joinTitle(inputs.valueOf(firstWord), args),
        );
        return 'Added "${task.title}" to "${list.name}" '
            '[ref ${task.reference}].';
      });
}

/// Changes the title of a task.
final class TasksEdit extends Command {
  new(this.repository)
      : super(
          mandatoryPositionals: [listName, reference, firstWord],
          variadic: rest,
        );

  final TaskRepository repository;

  static final NormalPositional listName = NormalPositional(
    'list',
    description: 'Name of the list holding the task.',
    regExp: freeText,
  );

  static final NormalPositional reference = NormalPositional(
    'ref',
    description: 'Task reference shown by "tasks ls".',
  );

  static final NormalPositional firstWord = NormalPositional(
    'title',
    description: 'The replacement title.',
    regExp: freeText,
  );

  static final NormalVariadic rest = NormalVariadic(
    description: 'Words after -- , for a title that starts with a dash.',
    regExp: freeText,
  );

  @override
  String get name => 'edit';

  @override
  String get shortDescription => 'Change a task title.';

  @override
  String get longDescription =>
      'Changes the title of the task named by its reference. Quote the new '
      'title so spaces are kept: task_list tasks edit Work <ref> "New title".';

  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      guardCommand(() async {
        final book = await openTaskBook(repository: repository);
        final list = book.requireListByName(inputs.valueOf(listName));
        final task = resolveTask(list, inputs.valueOf(reference));
        final updated = await book.editTask(
          list.id,
          task.id,
          joinTitle(inputs.valueOf(firstWord), args),
        );
        return 'Renamed task ${updated.reference} to "${updated.title}".';
      });
}

/// Marks a task complete.
final class TasksDone extends Command {
  new(this.repository) : super(mandatoryPositionals: [listName, reference]);

  final TaskRepository repository;

  static final NormalPositional listName = NormalPositional(
    'list',
    description: 'Name of the list holding the task.',
    regExp: freeText,
  );

  static final NormalPositional reference = NormalPositional(
    'ref',
    description: 'Task reference shown by "tasks ls".',
  );

  @override
  String get name => 'done';

  @override
  String get shortDescription => 'Mark a task complete.';

  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      guardCommand(() async {
        final book = await openTaskBook(repository: repository);
        final list = book.requireListByName(inputs.valueOf(listName));
        final task = resolveTask(list, inputs.valueOf(reference));
        final updated = await book.setTaskCompleted(list.id, task.id, true);
        return 'Marked "${updated.title}" complete.';
      });
}

/// Marks a completed task incomplete again.
final class TasksUndone extends Command {
  new(this.repository) : super(mandatoryPositionals: [listName, reference]);

  final TaskRepository repository;

  static final NormalPositional listName = NormalPositional(
    'list',
    description: 'Name of the list holding the task.',
    regExp: freeText,
  );

  static final NormalPositional reference = NormalPositional(
    'ref',
    description: 'Task reference shown by "tasks ls".',
  );

  @override
  String get name => 'undone';

  @override
  String get shortDescription => 'Reopen a completed task.';

  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      guardCommand(() async {
        final book = await openTaskBook(repository: repository);
        final list = book.requireListByName(inputs.valueOf(listName));
        final task = resolveTask(list, inputs.valueOf(reference));
        final updated = await book.setTaskCompleted(list.id, task.id, false);
        return 'Marked "${updated.title}" incomplete.';
      });
}

/// Deletes a task.
final class TasksRm extends Command {
  new(this.repository) : super(mandatoryPositionals: [listName, reference]);

  final TaskRepository repository;

  static final NormalPositional listName = NormalPositional(
    'list',
    description: 'Name of the list holding the task.',
    regExp: freeText,
  );

  static final NormalPositional reference = NormalPositional(
    'ref',
    description: 'Task reference shown by "tasks ls".',
  );

  @override
  String get name => 'rm';

  @override
  String get shortDescription => 'Delete a task.';

  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      guardCommand(() async {
        final book = await openTaskBook(repository: repository);
        final list = book.requireListByName(inputs.valueOf(listName));
        final task = resolveTask(list, inputs.valueOf(reference));
        await book.deleteTask(list.id, task.id);
        return 'Deleted task ${task.reference} "${task.title}".';
      });
}

/// Resolves a CLI reference to exactly one task in [list].
///
/// A reference is any unambiguous leading part of a task identifier. An
/// ambiguous one is rejected instead of guessed, because completing the wrong
/// task is worse than refusing.
Task resolveTask(TaskList list, String reference) {
  final task = list.taskByReference(reference);
  if (task != null) return task;

  final matches = list.countReferenceMatches(reference);
  if (matches > 1) {
    throw ValidationException(
      '"$reference" matches $matches tasks in "${list.name}". '
      'Use more of the reference shown by "task_list tasks ls ${list.name}".',
    );
  }
  throw NotFoundException(
    'List "${list.name}" has no task with reference "$reference". '
    'Run "task_list tasks ls ${list.name}" to see the references.',
  );
}

/// Joins the title positional with any words that followed a `--` separator.
///
/// A title is normally one quoted argument. The separator exists for a title
/// that begins with a dash and would otherwise be read as a flag.
String joinTitle(String firstWord, List<String> rest) =>
    rest.isEmpty ? firstWord : '$firstWord ${rest.join(' ')}';
