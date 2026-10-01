import 'package:mamba/mamba.dart';
import 'package:task_list_cli/application/task_book.dart';
import 'package:task_list_cli/domain/id_source.dart';
import 'package:task_list_cli/lists.dart';
import 'package:task_list_cli/persistence/in_memory_task_repository.dart';
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
        'Manage persistent task lists.',
        '1.0.0',
        [ListsCommand(repository: repository)],
      ).fake();

  /// Runs [tokens] and returns the result, for the common success case.
  Future<MambaExecutionResult> run(List<String> tokens) => cli().execute(tokens);

  /// Seeds a list, optionally with tasks, and returns the book.
  ///
  /// One identifier source is shared by every call so two seeded lists never
  /// collide on an id.
  Future<TaskBook> seed(String name, {List<String> tasks = const []}) async {
    final book = TaskBook(repository, ids: ids);
    await book.load();
    final list = await book.createList(name);
    for (final title in tasks) {
      await book.addTask(list.id, title);
    }
    return book;
  }

  Matcher succeeds(Object? output) => isA<MambaSuccessResult>()
      .having((value) => value.exitCode, 'exit code', 0)
      .having((value) => value.output, 'output', output);

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

  group('lists', () {
    test('shows its child commands', () async {
      final result = await run(['lists', '--help']);

      expect(
        result,
        succeeds(
          allOf(contains('create'), contains('rename'), contains('rm')),
        ),
      );
    });

    group('ls', () {
      test('explains what to do when there are no lists', () async {
        final result = await run(['lists', 'ls']);

        expect(
          result,
          succeeds(
            allOf(
              contains('No lists yet'),
              contains('task_list lists create'),
            ),
          ),
        );
      });

      test('lists each name with its task counts', () async {
        await seed('Work', tasks: ['One', 'Two']);

        final result = await run(['lists', 'ls']);

        expect(
          result,
          succeeds(allOf(contains('NAME'), contains('Work'), contains('2'))),
        );
      });

      test('separates open and done counts', () async {
        final book = await seed('Work', tasks: ['One', 'Two']);
        final list = book.requireListByName('Work');
        await book.setTaskCompleted(list.id, list.tasks.first.id, true);

        final result = await run(['lists', 'ls']);

        expect(
          result,
          succeeds(
            allOf(
              contains('TASKS'),
              contains('OPEN'),
              contains('DONE'),
              // Two tasks in total, one finished, so one still open.
              contains(RegExp(r'Work\s+2\s+1\s+1')),
            ),
          ),
        );
      });
    });

    group('create', () {
      test('creates a list', () async {
        final result = await run(['lists', 'create', 'Work']);

        expect(result, succeeds('Created list "Work".'));
      });

      test('trims the name', () async {
        final result = await run(['lists', 'create', '  Work  ']);

        expect(result, succeeds('Created list "Work".'));
      });

      test('rejects a duplicate name', () async {
        await seed('Work');

        final result = await run(['lists', 'create', 'work']);

        expect(
          result,
          fails(
            exitCode: 4,
            message: 'A list named "work" already exists.',
            phase: MambaExecutionPhase.run,
            commandPath: ['task_list', 'lists', 'create'],
          ),
        );
      });

      test('rejects an empty name', () async {
        final result = await run(['lists', 'create', '   ']);

        expect(
          result,
          fails(
            exitCode: 4,
            message: 'A list name cannot be empty.',
            phase: MambaExecutionPhase.run,
            commandPath: ['task_list', 'lists', 'create'],
          ),
        );
      });

      test('requires a name', () async {
        final result = await run(['lists', 'create']);

        expect(result, isA<MambaFailureResult>());
      });
    });

    group('rename', () {
      test('renames a list, ignoring the case it was asked for', () async {
        await seed('Work');

        final result = await run(['lists', 'rename', 'work', 'Office']);

        expect(result, succeeds('Renamed "Work" to "Office".'));
      });

      test('reports an unknown list', () async {
        final result = await run(['lists', 'rename', 'Nope', 'Office']);

        expect(
          result,
          fails(
            exitCode: 3,
            message: allOf(contains('No list named "Nope"')),
            phase: MambaExecutionPhase.run,
            commandPath: ['task_list', 'lists', 'rename'],
          ),
        );
      });

      test('rejects a name already in use', () async {
        await seed('Work');
        await seed('Office');

        final result = await run(['lists', 'rename', 'Work', 'office']);

        expect(
          result,
          fails(
            exitCode: 4,
            message: 'A list named "office" already exists.',
            phase: MambaExecutionPhase.run,
            commandPath: ['task_list', 'lists', 'rename'],
          ),
        );
      });
    });

    group('rm', () {
      test('removes an empty list without asking for force', () async {
        await seed('Work');

        final result = await run(['lists', 'rm', 'Work']);

        expect(result, succeeds('Removed list "Work".'));
      });

      test('refuses to drop a list that still holds tasks', () async {
        await seed('Work', tasks: ['One']);

        final result = await run(['lists', 'rm', 'Work']);

        expect(
          result,
          fails(
            exitCode: 4,
            message: allOf(
              contains('still holds 1 task'),
              contains('--force'),
            ),
            phase: MambaExecutionPhase.run,
            commandPath: ['task_list', 'lists', 'rm'],
          ),
        );
      });

      test('removes a list with its tasks when forced', () async {
        await seed('Work', tasks: ['One', 'Two']);

        final result = await run(['lists', 'rm', 'Work', '--force']);

        expect(
          result,
          succeeds('Removed list "Work" and 2 tasks.'),
        );
      });

      test('accepts the short force flag', () async {
        await seed('Work', tasks: ['One']);

        final result = await run(['lists', 'rm', 'Work', '-f']);

        expect(result, succeeds('Removed list "Work" and 1 task.'));
      });

      test('reports an unknown list', () async {
        final result = await run(['lists', 'rm', 'Nope']);

        expect(
          result,
          fails(
            exitCode: 3,
            message: contains('No list named "Nope"'),
            phase: MambaExecutionPhase.run,
            commandPath: ['task_list', 'lists', 'rm'],
          ),
        );
      });
    });
  });
}
