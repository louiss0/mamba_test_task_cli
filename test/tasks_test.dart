import 'package:mamba/mamba.dart';
import 'package:task_list_cli/application/task_book.dart';
import 'package:task_list_cli/domain/id_source.dart';
import 'package:task_list_cli/domain/task.dart';
import 'package:task_list_cli/domain/task_list.dart';
import 'package:task_list_cli/persistence/in_memory_task_repository.dart';
import 'package:task_list_cli/tasks.dart';
import 'package:test/test.dart';

import 'support/test_workspace.dart';

void main() {
  late InMemoryTaskRepository repository;
  late IdSource ids;

  setUp(() {
    repository = InMemoryTaskRepository();
    ids = deterministicIds();
  });

  MambaExecutor<MambaExecutionResult> cli() => Executor(
        'task_list',
        'Manage tasks in a list.',
        '1.0.0',
        [TasksCommand(repository: repository)],
      ).fake();

  Future<MambaExecutionResult> run(List<String> tokens) => cli().execute(tokens);

  /// Returns the output of a successful run.
  Future<String> outputOf(List<String> tokens) async {
    final result = await run(tokens);
    expect(result, isA<MambaSuccessResult>(), reason: 'expected $tokens to work');
    return (result as MambaSuccessResult).output!;
  }

  /// Creates a list holding [titles] and returns it as it is on disk.
  Future<TaskList> seed(String name, {List<String> titles = const []}) async {
    final book = TaskBook(repository, ids: ids);
    await book.load();
    final list = await book.createList(name);
    for (final title in titles) {
      await book.addTask(list.id, title);
    }
    return book.requireList(list.id);
  }

  /// Returns a freshly loaded view of the saved book.
  Future<TaskBook> reload() async {
    final book = TaskBook(repository, ids: ids);
    await book.load();
    return book;
  }

  /// The reference the CLI shows for the task at [index] of [list].
  Future<String> referenceOf(TaskList list, int index) async {
    final shown = await outputOf(['tasks', 'ls', list.name]);
    return shown
        .split('\n')
        .skip(1)
        .map((line) => line.split(RegExp(r'\s+')).first)
        .toList()[index];
  }

  Matcher fails({
    required int exitCode,
    required Object message,
    required MambaExecutionPhase phase,
    required List<String> commandPath,
  }) =>
      isA<MambaFailureResult>()
          .having((value) => value.exitCode, 'exit code', exitCode)
          .having((value) => value.message, 'message', message)
          .having((value) => value.output, 'output', isNull)
          .having((value) => value.errors, 'errors', hasLength(1))
          .having((value) => value.errors.single.phase, 'phase', phase)
          .having(
            (value) => value.errors.single.commandPath,
            'command path',
            commandPath,
          );

  group('tasks', () {
    test('shows its child commands', () async {
      final result = await run(['tasks', '--help']);

      expect(
        (result as MambaSuccessResult).output,
        allOf(contains('add'), contains('done'), contains('undone')),
      );
    });
  });

  group('ls', () {
    test('explains what to do when the list has no tasks', () async {
      await seed('Work');

      final result = await run(['tasks', 'ls', 'Work']);

      expect(
        result,
        isA<MambaSuccessResult>().having(
          (value) => value.output,
          'output',
          allOf(
            contains('has no tasks'),
            contains('task_list tasks add Work'),
          ),
        ),
      );
    });

    test('shows a reference, state, creation time, and title', () async {
      await seed('Work', titles: ['Buy milk']);

      final result = await run(['tasks', 'ls', 'Work']);

      expect(
        (result as MambaSuccessResult).output,
        allOf(
          contains('REF'),
          contains('STATUS'),
          contains('CREATED'),
          contains('TITLE'),
          contains('open'),
          contains('Buy milk'),
          contains(RegExp(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}')),
        ),
      );
    });

    test('shows every task by default', () async {
      final list = await seed('Work', titles: ['One', 'Two']);
      final book = await reload();
      await book.setTaskCompleted(list.id, list.tasks.first.id, true);

      final shown = await outputOf(['tasks', 'ls', 'Work']);

      expect(shown, contains('One'));
      expect(shown, contains('Two'));
    });

    test('narrows to incomplete tasks', () async {
      final list = await seed('Work', titles: ['One', 'Two']);
      final book = await reload();
      await book.setTaskCompleted(list.id, list.tasks.first.id, true);

      final shown =
          await outputOf(['tasks', 'ls', 'Work', '--filter', 'incomplete']);

      expect(shown, isNot(contains('One')));
      expect(shown, contains('Two'));
    });

    test('narrows to completed tasks', () async {
      final list = await seed('Work', titles: ['One', 'Two']);
      final book = await reload();
      await book.setTaskCompleted(list.id, list.tasks.first.id, true);

      final shown =
          await outputOf(['tasks', 'ls', 'Work', '--filter', 'completed']);

      expect(shown, contains('One'));
      expect(shown, isNot(contains('Two')));
    });

    test('explains an empty completed view', () async {
      await seed('Work', titles: ['One']);

      final result = await run(['tasks', 'ls', 'Work', '-f', 'completed']);

      expect(
        (result as MambaSuccessResult).output,
        allOf(
          contains('no completed tasks'),
          contains('--filter incomplete'),
        ),
      );
    });

    test('rejects an unknown filter', () async {
      await seed('Work', titles: ['One']);

      final result = await run(['tasks', 'ls', 'Work', '--filter', 'maybe']);

      expect(result, isA<MambaFailureResult>());
    });

    test('reports an unknown list', () async {
      final result = await run(['tasks', 'ls', 'Nope']);

      expect(
        result,
        fails(
          exitCode: 3,
          message: contains('No list named "Nope"'),
          phase: MambaExecutionPhase.run,
          commandPath: ['task_list', 'tasks', 'ls'],
        ),
      );
    });
  });

  group('add', () {
    test('adds a task and reports its reference', () async {
      await seed('Work');

      final result = await run(['tasks', 'add', 'Work', 'Buy milk']);

      final output = (result as MambaSuccessResult).output!;
      expect(output, startsWith('Added "Buy milk" to "Work"'));
      expect(output, contains('ref '));
    });

    test('accepts a quoted title with spaces', () async {
      await seed('Work');

      await run(['tasks', 'add', 'Work', 'Buy milk and bread']);

      expect(await outputOf(['tasks', 'ls', 'Work']), contains('Buy milk and bread'));
    });

    test('accepts a title written as several words after a separator', () async {
      await seed('Work');

      // A leading dash would otherwise be read as a flag, so the words follow
      // an explicit separator.
      await run(['tasks', 'add', 'Work', '-', '--', 'review', 'drafts']);

      expect(await outputOf(['tasks', 'ls', 'Work']), contains('- review drafts'));
    });

    test('rejects an empty title', () async {
      await seed('Work');

      final result = await run(['tasks', 'add', 'Work', '   ']);

      expect(
        result,
        fails(
          exitCode: 4,
          message: 'A task title cannot be empty.',
          phase: MambaExecutionPhase.run,
          commandPath: ['task_list', 'tasks', 'add'],
        ),
      );
    });

    test('reports an unknown list', () async {
      final result = await run(['tasks', 'add', 'Nope', 'Buy milk']);

      expect(
        result,
        fails(
          exitCode: 3,
          message: contains('No list named "Nope"'),
          phase: MambaExecutionPhase.run,
          commandPath: ['task_list', 'tasks', 'add'],
        ),
      );
    });
  });

  group('edit', () {
    test('changes the title of the named task', () async {
      final list = await seed('Work', titles: ['Old title']);
      final reference = await referenceOf(list, 0);

      final result = await run([
        'tasks',
        'edit',
        'Work',
        reference,
        'New title',
      ]);

      expect(
        (result as MambaSuccessResult).output,
        'Renamed task $reference to "New title".',
      );
      expect(await outputOf(['tasks', 'ls', 'Work']), contains('New title'));
    });

    test('leaves the other tasks alone', () async {
      final list = await seed('Work', titles: ['First', 'Second']);
      final reference = await referenceOf(list, 0);

      await run(['tasks', 'edit', 'Work', reference, 'Changed']);

      final shown = await outputOf(['tasks', 'ls', 'Work']);
      expect(shown, contains('Changed'));
      expect(shown, contains('Second'));
    });

    test('reports an unknown reference', () async {
      await seed('Work', titles: ['One']);

      final result = await run(['tasks', 'edit', 'Work', 'nosuchref', 'Changed']);

      expect(
        result,
        fails(
          exitCode: 3,
          message: contains('no task with reference "nosuchref"'),
          phase: MambaExecutionPhase.run,
          commandPath: ['task_list', 'tasks', 'edit'],
        ),
      );
    });
  });

  group('done', () {
    test('marks a task complete without removing it', () async {
      final list = await seed('Work', titles: ['One']);
      final reference = await referenceOf(list, 0);

      final result = await run(['tasks', 'done', 'Work', reference]);

      expect((result as MambaSuccessResult).output, 'Marked "One" complete.');
      expect(await outputOf(['tasks', 'ls', 'Work']), contains('One'));
      expect(await outputOf(['tasks', 'ls', 'Work']), contains('done'));
    });

    test('is not undone by completing twice', () async {
      final list = await seed('Work', titles: ['One']);
      final reference = await referenceOf(list, 0);

      await run(['tasks', 'done', 'Work', reference]);
      await run(['tasks', 'done', 'Work', reference]);

      expect(await outputOf(['tasks', 'ls', 'Work']), contains('done'));
    });

    test('reports an unknown reference', () async {
      await seed('Work', titles: ['One']);

      final result = await run(['tasks', 'done', 'Work', 'nosuchref']);

      expect(
        result,
        fails(
          exitCode: 3,
          message: contains('no task with reference "nosuchref"'),
          phase: MambaExecutionPhase.run,
          commandPath: ['task_list', 'tasks', 'done'],
        ),
      );
    });
  });

  group('undone', () {
    test('reopens a completed task', () async {
      final list = await seed('Work', titles: ['One']);
      final reference = await referenceOf(list, 0);
      await run(['tasks', 'done', 'Work', reference]);

      final result = await run(['tasks', 'undone', 'Work', reference]);

      expect(
        (result as MambaSuccessResult).output,
        'Marked "One" incomplete.',
      );
      expect(await outputOf(['tasks', 'ls', 'Work']), contains('open'));
    });
  });

  group('rm', () {
    test('deletes the named task and leaves the rest', () async {
      final list = await seed('Work', titles: ['One', 'Two']);
      final reference = await referenceOf(list, 0);

      final result = await run(['tasks', 'rm', 'Work', reference, '--force']);

      expect(
        (result as MambaSuccessResult).output,
        allOf(contains('Deleted task $reference'), contains('"One"')),
      );
      final shown = await outputOf(['tasks', 'ls', 'Work']);
      expect(shown, isNot(contains('One')));
      expect(shown, contains('Two'));
    });

    test('accepts the short force flag', () async {
      final list = await seed('Work', titles: ['One']);
      final reference = await referenceOf(list, 0);

      final result = await run(['tasks', 'rm', 'Work', reference, '-f']);

      expect(result, isA<MambaSuccessResult>());
      expect((await outputOf(['tasks', 'ls', 'Work'])), isNot(contains('One')));
    });

    test('refuses to delete without confirmation and keeps the task', () async {
      // A removal cannot be undone, so a mistyped reference must not discard
      // work without a second deliberate act.
      final list = await seed('Work', titles: ['One']);

      final result = await run(['tasks', 'rm', 'Work', await referenceOf(list, 0)]);

      expect(
        result,
        fails(
          exitCode: 4,
          message: allOf(
            contains('will be deleted for good'),
            contains('--force'),
          ),
          phase: MambaExecutionPhase.run,
          commandPath: ['task_list', 'tasks', 'rm'],
        ),
      );
      expect(
        await outputOf(['tasks', 'ls', 'Work']),
        contains('One'),
        reason: 'an unconfirmed removal must not change anything',
      );
    });

    test('reports an unknown reference', () async {
      await seed('Work', titles: ['One']);

      final result = await run([
        'tasks',
        'rm',
        'Work',
        'nosuchref',
        '--force',
      ]);

      expect(
        result,
        fails(
          exitCode: 3,
          message: contains('no task with reference "nosuchref"'),
          phase: MambaExecutionPhase.run,
          commandPath: ['task_list', 'tasks', 'rm'],
        ),
      );
    });

    test('reports an unknown reference before asking for confirmation',
        () async {
      await seed('Work', titles: ['One']);

      final result = await run(['tasks', 'rm', 'Work', 'nosuchref']);

      expect(
        result,
        fails(
          exitCode: 3,
          message: contains('no task with reference "nosuchref"'),
          phase: MambaExecutionPhase.run,
          commandPath: ['task_list', 'tasks', 'rm'],
        ),
      );
    });
  });

  group('task references', () {
    test('stay valid after another task is deleted', () async {
      final list = await seed('Work', titles: ['One', 'Two', 'Three']);
      final removed = await referenceOf(list, 0);
      final reference = await referenceOf(list, 2);

      await run(['tasks', 'rm', 'Work', removed, '--force']);
      expect(
        await outputOf(['tasks', 'ls', 'Work']),
        isNot(contains('One')),
        reason: 'the neighbouring task really has to be gone',
      );

      final result = await run(['tasks', 'done', 'Work', reference]);

      expect(
        (result as MambaSuccessResult).output,
        'Marked "Three" complete.',
      );
    });

    test('are the same whichever way the user looks at the list', () async {
      await seed('Work', titles: ['One', 'Two']);
      final all = await outputOf(['tasks', 'ls', 'Work']);
      final incomplete = await outputOf([
        'tasks',
        'ls',
        'Work',
        '--filter',
        'incomplete',
      ]);

      expect(
        incomplete.split('\n').skip(1).map((l) => l.split(RegExp(r'\s+')).first),
        all.split('\n').skip(1).map((l) => l.split(RegExp(r'\s+')).first),
      );
    });

    test('an ambiguous prefix is refused rather than guessed', () {
      // Random identifiers make a collision vanishingly unlikely through the
      // public API, so the rule is exercised on a hand-built list.
      final list = TaskList(id: 'l1', name: 'Work', tasks: [
        Task(
          id: 'abc123def456',
          title: 'One',
          completed: false,
          createdAt: DateTime.utc(2026),
        ),
        Task(
          id: 'abc123zzz999',
          title: 'Two',
          completed: false,
          createdAt: DateTime.utc(2026),
        ),
      ]);

      expect(list.countReferenceMatches('abc123'), 2);
      expect(
        list.taskByReference('abc123'),
        isNull,
        reason: 'resolving an ambiguous prefix would edit the wrong task',
      );
      expect(list.taskByReference('abc123d')?.title, 'One');
      expect(list.taskByReference('abc123z')?.title, 'Two');
    });
  });
}
