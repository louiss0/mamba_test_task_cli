import 'dart:convert';
import 'dart:io';

import 'package:mamba/mamba.dart';
import 'package:task_list_cli/lists.dart';
import 'package:task_list_cli/path_command.dart';
import 'package:task_list_cli/repository.dart';
import 'package:task_list_cli/service.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('task-lists-cli-'),
  );
  tearDown(() async => directory.delete(recursive: true));
  Future<MambaExecutionResult> invoke(List<String> args) => Executor(
    'task_list_cli',
    'Tasks',
    '1.0.0',
    [Lists()],
    options: [dataDirectory],
  ).fake().execute(['--data-dir', directory.path, ...args]);
  Future<String> seed(String name, {bool withTask = false}) async {
    final repo = await JsonRepository.open(directory.path);
    try {
      final service = TaskService(repo);
      final list = await service.createList(name);
      if (withTask) await service.createTask(list.id, 'Important task');
      return list.id;
    } finally {
      await repo.close();
    }
  }

  void success(MambaExecutionResult result, Object? output) => expect(
    result,
    isA<MambaSuccessResult>()
        .having((r) => r.exitCode, 'exit code', 0)
        .having((r) => r.output, 'output', output),
  );
  void failure(
    MambaExecutionResult result,
    Object message,
    String command, {
    MambaExecutionPhase phase = MambaExecutionPhase.run,
  }) => expect(
    result,
    isA<MambaFailureResult>()
        .having((r) => r.exitCode, 'exit code', 1)
        .having((r) => r.message, 'message', message)
        .having((r) => r.output, 'output', isNull)
        .having((r) => r.errors, 'errors', hasLength(1))
        .having((r) => r.errors.single.phase, 'phase', phase)
        .having((r) => r.errors.single.commandPath, 'path', [
          'task_list_cli',
          'lists',
          command,
        ]),
  );

  group('task_list_cli', () {
    group('lists', () {
      test('help lists every child without opening storage', () async {
        success(
          await invoke(['lists', '--help']),
          allOf(
            contains('show'),
            contains('add'),
            contains('rename'),
            contains('delete'),
          ),
        );
        expect(await directory.list().toList(), isEmpty);
      });
      group('show', () {
        test('explains empty state and emits an empty JSON array', () async {
          success(
            await invoke(['lists', 'show']),
            'No lists yet. Create one with: lists add "Personal"',
          );
          success(await invoke(['lists', 'show', '--json']), '[]');
        });
        test('shows persistent IDs, names and counts', () async {
          final id = await seed('Work', withTask: true);
          success(await invoke(['lists', 'show']), '$id\tWork\t1 tasks');
          success(
            await invoke(['lists', 'show', '--json']),
            jsonEncode([
              {'id': id, 'name': 'Work', 'taskCount': 1},
            ]),
          );
        });
      });
      group('add', () {
        test(
          'accepts a quoted multi-word name and returns a persistent UUID',
          () async {
            final result = await invoke(['lists', 'add', 'Big project']);
            success(result, matches(RegExp(r'^[a-f0-9-]{36}$')));
            final repo = await JsonRepository.open(directory.path);
            try {
              expect(repo.initialState.lists.single.name, 'Big project');
              expect(
                repo.initialState.lists.single.id,
                (result as MambaSuccessResult).output,
              );
            } finally {
              await repo.close();
            }
          },
        );
        test(
          'rejects duplicate names without changing existing lists',
          () async {
            await seed('Work');
            failure(
              await invoke(['lists', 'add', 'work']),
              'A list named "work" already exists (names ignore case).',
              'add',
            );
          },
        );
        test('requires a list name', () async {
          failure(
            await invoke(['lists', 'add']),
            'The name is required at 0 after this command',
            'add',
            phase: MambaExecutionPhase.parse,
          );
        });
        test('rejects blank names at the domain boundary', () async {
          failure(
            await invoke(['lists', 'add', ' ']),
            'List name must contain 1–80 characters without control characters.',
            'add',
          );
        });
      });
      group('rename', () {
        test('renames by ID and preserves it', () async {
          final id = await seed('Work');
          success(
            await invoke(['lists', 'rename', id, 'Projects']),
            'List renamed.',
          );
          success(await invoke(['lists', 'show']), '$id\tProjects\t0 tasks');
        });
        test('reports missing lists', () async {
          failure(
            await invoke(['lists', 'rename', 'Missing', 'New']),
            'List "Missing" does not exist. Use "lists show" or create it first.',
            'rename',
          );
        });
      });
      group('delete', () {
        test('deletes an empty list without confirmation', () async {
          await seed('Work');
          success(await invoke(['lists', 'delete', 'work']), 'List deleted.');
          success(await invoke(['lists', 'show', '--json']), '[]');
        });
        test('protects nonempty lists until --yes is supplied', () async {
          await seed('Work', withTask: true);
          failure(
            await invoke(['lists', 'delete', 'Work']),
            'List "Work" contains 1 tasks. Confirm deletion with --yes.',
            'delete',
          );
          success(
            await invoke(['lists', 'delete', 'Work', '--yes']),
            'List deleted.',
          );
        });
      });
    });
  });
}
