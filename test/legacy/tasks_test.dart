import 'dart:convert';
import 'dart:io';

import 'package:mamba/mamba.dart';
import 'package:task_list_cli/legacy/models.dart';
import 'package:task_list_cli/legacy/path_command.dart';
import 'package:task_list_cli/legacy/repository.dart';
import 'package:task_list_cli/legacy/service.dart';
import 'package:task_list_cli/legacy/tasks.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late String listId;
  late Task task;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('task-tasks-cli-');
    final repo = await JsonRepository.open(directory.path);
    try {
      final service = TaskService(repo);
      listId = (await service.createList('Work')).id;
      task = await service.createTask(listId, 'Initial title');
    } finally {
      await repo.close();
    }
  });
  tearDown(() async => directory.delete(recursive: true));
  Future<MambaExecutionResult> invoke(List<String> args) => Executor(
    'task_list_cli',
    'Tasks',
    '1.0.0',
    [Tasks()],
    options: [dataDirectory],
  ).fake().execute(['--data-dir', directory.path, ...args]);
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
          'tasks',
          command,
        ]),
  );

  group('task_list_cli', () {
    group('tasks', () {
      test('help describes every child', () async {
        success(
          await invoke(['tasks', '--help']),
          allOf(
            contains('show'),
            contains('add'),
            contains('edit'),
            contains('complete'),
            contains('reopen'),
            contains('delete'),
          ),
        );
      });
      group('show', () {
        test(
          'shows current list, active filter, IDs and completion markers',
          () async {
            success(
              await invoke(['tasks', 'show', 'work']),
              'Work | All | 1 tasks\n${task.id}\t[ ]\tInitial title',
            );
          },
        );
        for (final filter in TaskFilter.values) {
          test('emits script-friendly ${filter.name} filtering', () async {
            final expectedTasks = filter == TaskFilter.completed
                ? <Object>[]
                : [StoredTask.fromDomain(task).toJson()];
            success(
              await invoke([
                'tasks',
                'show',
                listId,
                '--filter',
                filter.name,
                '--json',
              ]),
              jsonEncode({
                'list': {'id': listId, 'name': 'Work'},
                'filter': filter.name,
                'tasks': expectedTasks,
              }),
            );
          });
        }
        test('rejects invalid filter values at parse time', () async {
          failure(
            await invoke(['tasks', 'show', 'Work', '--filter', 'wrong']),
            contains('wrong'),
            'show',
            phase: MambaExecutionPhase.parse,
          );
        });
        test('reports missing lists', () async {
          failure(
            await invoke(['tasks', 'show', 'Missing']),
            'List "Missing" does not exist. Use "lists show" or create it first.',
            'show',
          );
        });
      });
      group('add', () {
        test('accepts a multi-word title and returns an ID', () async {
          success(
            await invoke(['tasks', 'add', 'Work', 'Buy groceries today']),
            matches(RegExp(r'^[a-f0-9-]{36}$')),
          );
        });
        test('rejects blank titles', () async {
          failure(
            await invoke(['tasks', 'add', 'Work', ' ']),
            'Task title must contain 1–500 characters without control characters.',
            'add',
          );
        });
        test('requires the title', () async {
          failure(
            await invoke(['tasks', 'add', 'Work']),
            'The title is required at 1 after this command',
            'add',
            phase: MambaExecutionPhase.parse,
          );
        });
      });
      group('edit', () {
        test('changes title without changing ID', () async {
          success(
            await invoke(['tasks', 'edit', 'Work', task.id, 'Updated title']),
            'Task updated.',
          );
          success(
            await invoke(['tasks', 'show', 'Work']),
            'Work | All | 1 tasks\n${task.id}\t[ ]\tUpdated title',
          );
        });
        test('refuses a row number as identity', () async {
          failure(
            await invoke(['tasks', 'edit', 'Work', '1', 'Wrong']),
            'Task "1" does not exist in this list. Use the full persistent ID.',
            'edit',
          );
        });
      });
      group('complete', () {
        test('completes and immediately leaves the incomplete view', () async {
          success(
            await invoke(['tasks', 'complete', 'Work', task.id]),
            'Task completed.',
          );
          success(
            await invoke([
              'tasks',
              'show',
              'Work',
              '-f',
              'incomplete',
              '--json',
            ]),
            jsonEncode({
              'list': {'id': listId, 'name': 'Work'},
              'filter': 'incomplete',
              'tasks': <Object>[],
            }),
          );
          success(
            await invoke(['tasks', 'show', 'Work', '--filter=completed']),
            'Work | Completed | 1 tasks\n${task.id}\t[x]\tInitial title',
          );
        });
      });
      group('reopen', () {
        test('restores incomplete state on the same task', () async {
          success(
            await invoke(['tasks', 'complete', 'Work', task.id]),
            'Task completed.',
          );
          success(
            await invoke(['tasks', 'reopen', 'Work', task.id]),
            'Task reopened.',
          );
          success(
            await invoke(['tasks', 'show', 'Work']),
            'Work | All | 1 tasks\n${task.id}\t[ ]\tInitial title',
          );
        });
      });
      group('delete', () {
        test(
          'requires explicit confirmation and supports the short flag',
          () async {
            failure(
              await invoke(['tasks', 'delete', 'Work', task.id]),
              'Confirm task deletion with --yes.',
              'delete',
            );
            success(
              await invoke(['tasks', 'delete', 'Work', task.id, '-y']),
              'Task deleted.',
            );
            success(
              await invoke(['tasks', 'show', 'Work', '--json']),
              jsonEncode({
                'list': {'id': listId, 'name': 'Work'},
                'filter': 'all',
                'tasks': <Object>[],
              }),
            );
          },
        );
      });
    });
  });
}
