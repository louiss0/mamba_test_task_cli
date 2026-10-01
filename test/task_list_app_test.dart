import 'dart:io';

import 'package:mamba/mamba.dart';
import 'package:task_list_cli/persistence/in_memory_task_repository.dart';
import 'package:task_list_cli/task_list_app.dart';
import 'package:task_list_cli/tui.dart';
import 'package:test/test.dart';

import 'support/test_workspace.dart';

void main() {
  late InMemoryTaskRepository repository;
  late TestWorkspace workspace;

  setUp(() {
    repository = InMemoryTaskRepository();
    workspace = TestWorkspace.create();
    addTearDown(workspace.dispose);
  });

  MambaExecutor<MambaExecutionResult> cli() =>
      createTaskListExecutor(repository: repository).fake();

  group('task_list', () {
    test('lists every command group in its help', () async {
      final result = await cli().execute(['--help']);

      expect(
        result,
        isA<MambaSuccessResult>()
            .having((value) => value.exitCode, 'exit code', 0)
            .having(
              (value) => value.output,
              'output',
              allOf(
                contains('lists'),
                contains('tasks'),
                contains('tui'),
                contains('completion'),
              ),
            ),
      );
    });

    test('reports its version', () async {
      final result = await cli().execute(['--version']);

      expect(
        result,
        isA<MambaSuccessResult>().having(
          (value) => value.output,
          'output',
          'task_list $applicationVersion',
        ),
      );
    });

    test('falls through to the interactive interface with no arguments',
        () async {
      final result = await cli().execute([]);

      // The interface needs a real terminal, so a captured run says so instead
      // of painting over the test output. The important part is that the
      // fallback lands on the tui command.
      expect(
        result,
        isA<MambaFailureResult>()
            .having((value) => value.exitCode, 'exit code', 4)
            .having(
              (value) => value.message,
              'message',
              contains('needs a terminal'),
            )
            .having(
              (value) => value.errors.single.commandPath,
              'command path',
              ['task_list', TuiCommand.commandName],
            ),
      );
    });

    test('shares one book across the whole command tree', () async {
      await cli().execute(['lists', 'create', 'Work']);
      await cli().execute(['tasks', 'add', 'Work', 'Buy milk']);

      // A separate invocation is a separate TaskBook over the same repository,
      // which is how persistence is expected to work.
      final listed = await cli().execute(['tasks', 'ls', 'Work']);

      expect(
        (listed as MambaSuccessResult).output,
        contains('Buy milk'),
      );
    });
  });

  group('completion', () {
    test('rejects a shell it does not know', () async {
      final result = await cli().execute(['completion', 'tcsh']);

      expect(result, isA<MambaFailureResult>());
    });

    test('writes a script that names the real commands', () async {
      final path = workspace.pathOf('task_list.bash');

      final result = await cli().execute(['completion', 'bash', path]);

      expect(
        result,
        isA<MambaSuccessResult>().having(
          (value) => value.output,
          'output',
          contains(path),
        ),
      );

      final script = File(path).readAsStringSync();
      expect(script, contains('lists'));
      expect(script, contains('tasks'));
      expect(script, contains('tui'));
    });

    test('refuses a path that does not match the shell', () async {
      final result = await cli().execute([
        'completion',
        'bash',
        workspace.pathOf('task_list.zsh'),
      ]);

      expect(
        result,
        isA<MambaFailureResult>().having(
          (value) => value.message,
          'message',
          contains('must end in .bash'),
        ),
      );
    });
  });
}
