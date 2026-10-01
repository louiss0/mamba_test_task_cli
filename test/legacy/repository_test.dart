import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:task_list_cli/legacy/models.dart';
import 'package:task_list_cli/legacy/repository.dart';
import 'package:task_list_cli/legacy/service.dart';
import 'package:test/test.dart';

void main() {
  group('JSON repository', () {
    late Directory directory;
    final sessions = <JsonRepository>[];
    setUp(
      () async =>
          directory = await Directory.systemTemp.createTemp('task-repo-'),
    );
    tearDown(() async {
      for (final session in sessions) {
        await session.close();
      }
      sessions.clear();
      await directory.delete(recursive: true);
    });
    Future<JsonRepository> open({
      StateWriter writer = JsonRepository.atomicWrite,
    }) async {
      final session = await JsonRepository.open(directory.path, writer: writer);
      sessions.add(session);
      return session;
    }

    test('missing storage starts empty without creating JSON', () async {
      final repo = await open();
      expect(repo.initialState.lists, isEmpty);
      expect(await repo.file.exists(), isFalse);
      expect(
        p.isWithin(Directory.current.path, JsonRepository.defaultDirectory()),
        isFalse,
      );
    });

    test('persists readable versioned JSON across restarts', () async {
      final repo = await open();
      final service = TaskService(repo);
      final list = await service.createList('Work');
      final task = await service.createTask(list.id, 'Ship it');
      await service.setCompletion(list.id, task.id, Completion.completed);
      final text = await repo.file.readAsString();
      expect(text, contains('\n  "version": 1'));
      expect(jsonDecode(text), isA<Map<String, dynamic>>());
      await repo.close();
      final restarted = TaskService(await open());
      expect(restarted.getList('work').id, list.id);
      expect(restarted.getTask(list.id, task.id).completed, isTrue);
      expect(restarted.getTask(list.id, task.id).createdAt, task.createdAt);
    });

    final invalidDocuments = <String, String>{
      'malformed JSON': '{broken',
      'truncated JSON': '{"version":1,"lists":[',
      'non-object root': '[]',
      'missing version': '{"lists":[]}',
      'wrong version type': '{"version":"1","lists":[]}',
      'fractional version': '{"version":1.5,"lists":[]}',
      'floating-point version': '{"version":1.0,"lists":[]}',
      'incompatible version': '{"version":2,"lists":[]}',
      'wrong lists type': '{"version":1,"lists":{}}',
      'null lists': '{"version":1,"lists":null}',
      'unknown fields': '{"version":1,"lists":[],"surprise":1}',
      'invalid list identity':
          '{"version":1,"lists":[{"id":"1","name":"Work","tasks":[]}]}',
      'invalid list title': '{"version":1,"lists":[{"id":"11111111-1111-4111-8111-111111111111","name":" ","tasks":[]}]}',
    };
    for (final entry in invalidDocuments.entries) {
      test('preserves ${entry.key} and reports recovery path', () async {
        final file = File(p.join(directory.path, 'tasks.json'));
        await file.writeAsString(entry.value);
        await expectLater(
          open(),
          throwsA(
            isA<TaskFailure>()
                .having((e) => e.message, 'path', contains(file.path))
                .having(
                  (e) => e.message,
                  'recovery',
                  contains('Original file preserved'),
                ),
          ),
        );
        expect(await file.readAsString(), entry.value);
        // Failed loading releases the lock so repair is possible immediately.
        await file.writeAsString('{"version":1,"lists":[]}');
        expect((await open()).initialState.lists, isEmpty);
      });
    }

    test(
      'failed writes preserve disk and unpublished in-memory state',
      () async {
        bool fail = false;
        final repo = await open(
          writer: (destination, contents) async {
            if (fail) throw const FileSystemException('Simulated disk full');
            await JsonRepository.atomicWrite(destination, contents);
          },
        );
        final service = TaskService(repo);
        await service.createList('Work');
        final before = await repo.file.readAsString();
        fail = true;
        await expectLater(
          service.createTask('Work', 'Must not appear'),
          throwsA(
            isA<TaskFailure>().having(
              (e) => e.message,
              'message',
              contains('Could not save'),
            ),
          ),
        );
        expect(service.getList('Work').tasks, isEmpty);
        expect(await repo.file.readAsString(), before);
        fail = false;
        await service.createTask('Work', 'Now saved');
        expect(service.getList('Work').tasks.single.title, 'Now saved');
      },
    );

    test(
      'atomic writer replaces existing file and cleans temporary files',
      () async {
        final destination = File(p.join(directory.path, 'tasks.json'));
        await destination.writeAsString('old');
        await JsonRepository.atomicWrite(destination, 'new');
        expect(await destination.readAsString(), 'new');
        expect(
          await directory.list().where((e) => e.path.endsWith('.tmp')).toList(),
          isEmpty,
        );
      },
    );

    test(
      'failed atomic rename preserves destination and removes staged file',
      () async {
        final target = Directory(p.join(directory.path, 'blocked.json'));
        await target.create();
        final sentinel = File(p.join(target.path, 'old-data'));
        await sentinel.writeAsString('untouched');
        await expectLater(
          JsonRepository.atomicWrite(File(target.path), 'new'),
          throwsA(isA<FileSystemException>()),
        );
        expect(await sentinel.readAsString(), 'untouched');
        expect(
          await directory.list().where((e) => e.path.endsWith('.tmp')).toList(),
          isEmpty,
        );
      },
    );

    test('rejects another session and releases lock on close', () async {
      final first = await open();
      await expectLater(
        open(),
        throwsA(
          isA<TaskFailure>().having(
            (e) => e.message,
            'message',
            contains('already in use'),
          ),
        ),
      );
      await first.close();
      expect((await open()).initialState.lists, isEmpty);
    });

    test('OS lock prevents a second process from mutating storage', () async {
      final first = await open();
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/task_list_legacy.dart',
        '--data-dir',
        directory.path,
        'lists',
        'add',
        'Lost update',
      ], workingDirectory: Directory.current.path);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('already in use'));
      expect(await first.file.exists(), isFalse);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
