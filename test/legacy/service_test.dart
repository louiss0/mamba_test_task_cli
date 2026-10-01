import 'dart:async';
import 'dart:io';

import 'package:task_list_cli/legacy/models.dart';
import 'package:task_list_cli/legacy/repository.dart';
import 'package:task_list_cli/legacy/service.dart';
import 'package:test/test.dart';

void main() {
  group('application service', () {
    late Directory directory;
    late JsonRepository repo;
    late TaskService service;
    int writes = 0;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('task-service-');
      repo = await JsonRepository.open(
        directory.path,
        writer: (file, contents) async {
          writes++;
          await JsonRepository.atomicWrite(file, contents);
        },
      );
      service = TaskService(repo);
      writes = 0;
    });
    tearDown(() async {
      await repo.close();
      await directory.delete(recursive: true);
    });

    test('creates, renames and deletes lists with stable IDs', () async {
      final list = await service.createList(' Personal ');
      expect(list.name, 'Personal');
      expect(service.getList('personal').id, list.id);
      await service.renameList(list.id, 'Home');
      expect(service.getList('HOME').id, list.id);
      expect(() => service.getList('Personal'), throwsA(isA<TaskFailure>()));
      await service.deleteList(list.id);
      expect(service.lists, isEmpty);
    });

    test(
      'prevents ambiguous case-insensitive names on creation and rename',
      () async {
        await service.createList('Work');
        final list = await service.createList('Home');
        await expectLater(
          service.createList(' work '),
          throwsA(isA<TaskFailure>()),
        );
        await expectLater(
          service.renameList(list.id, 'WORK'),
          throwsA(isA<TaskFailure>()),
        );
        expect(service.lists.map((e) => e.name), ['Work', 'Home']);
        expect(writes, 2);
      },
    );

    test(
      'task CRUD, completion, reopening and identity remain consistent',
      () async {
        final list = await service.createList('Work');
        final first = await service.createTask(list.id, 'First');
        final second = await service.createTask(list.id, 'Second');
        await service.editTask(list.id, first.id, 'Edited');
        await service.setCompletion(list.id, first.id, Completion.completed);
        expect(service.getTask(list.id, first.id).title, 'Edited');
        expect(service.getTask(list.id, first.id).completed, isTrue);
        expect(service.getTask(list.id, first.id).createdAt, first.createdAt);
        await service.setCompletion(list.id, first.id, Completion.incomplete);
        expect(service.getTask(list.id, first.id).completed, isFalse);
        await expectLater(
          service.deleteTask(list.id, first.id),
          throwsA(isA<TaskFailure>()),
        );
        await service.deleteTask(list.id, first.id, confirmed: true);
        expect(service.query(list.id).single.id, second.id);
        expect(
          () => service.getTask(list.id, first.id),
          throwsA(isA<TaskFailure>()),
        );
      },
    );

    test('list containing tasks requires explicit confirmation', () async {
      await service.createList('Work');
      await service.createTask('Work', 'Important');
      await expectLater(
        service.deleteList('Work'),
        throwsA(isA<TaskFailure>()),
      );
      expect(service.getList('Work').tasks, hasLength(1));
      await service.deleteList('Work', confirmed: true);
      expect(service.lists, isEmpty);
    });

    test(
      'all, incomplete and completed filters are isolated and never write',
      () async {
        await service.createList('Work');
        await service.createList('Home');
        final pending = await service.createTask('Work', 'Pending');
        final done = await service.createTask('Work', 'Done');
        final home = await service.createTask('Home', 'Only at home');
        await service.setCompletion('Work', done.id, Completion.completed);
        final before = writes;
        expect(service.query('Work').map((e) => e.id), [pending.id, done.id]);
        expect(
          service.query('Work', filter: TaskFilter.incomplete).single.id,
          pending.id,
        );
        expect(
          service.query('Work', filter: TaskFilter.completed).single.id,
          done.id,
        );
        expect(service.query('Home').single.id, home.id);
        expect(service.query('Home', filter: TaskFilter.completed), isEmpty);
        expect(writes, before);
        await expectLater(
          service.editTask('Home', done.id, 'Wrong list'),
          throwsA(isA<TaskFailure>()),
        );
        await expectLater(
          service.deleteTask('Home', done.id, confirmed: true),
          throwsA(isA<TaskFailure>()),
        );
        expect(service.getTask('Work', done.id).title, 'Done');
        await service.deleteList('Work', confirmed: true);
        expect(service.query('Home').single.id, home.id);
      },
    );

    test('no-op edits and completion updates do not save', () async {
      await service.createList('Work');
      final task = await service.createTask('Work', 'Task');
      final before = writes;
      await service.renameList('Work', 'Work');
      await service.editTask('Work', task.id, ' Task ');
      await service.setCompletion('Work', task.id, Completion.incomplete);
      expect(writes, before);
    });

    test('invalid mutations leave all state unchanged', () async {
      await service.createList('Work');
      final task = await service.createTask('Work', 'Task');
      final before = writes;
      await expectLater(service.createList(' '), throwsA(isA<TaskFailure>()));
      await expectLater(
        service.createTask('Work', ' '),
        throwsA(isA<TaskFailure>()),
      );
      await expectLater(
        service.editTask('Work', task.id, '\n'),
        throwsA(isA<TaskFailure>()),
      );
      expect(writes, before);
      expect(service.query('Work').single.title, 'Task');
    });
  });

  test('rejects overlapping saves instead of losing an update', () async {
    final directory = await Directory.systemTemp.createTemp('task-overlap-');
    final gate = Completer<void>();
    final repo = await JsonRepository.open(
      directory.path,
      writer: (file, text) async {
        await gate.future;
        await JsonRepository.atomicWrite(file, text);
      },
    );
    try {
      final service = TaskService(repo);
      final first = service.createList('First');
      await expectLater(
        service.createList('Second'),
        throwsA(isA<TaskFailure>()),
      );
      expect(service.lists, isEmpty);
      gate.complete();
      await first;
      expect(service.lists.single.name, 'First');
    } finally {
      await repo.close();
      await directory.delete(recursive: true);
    }
  });
}
