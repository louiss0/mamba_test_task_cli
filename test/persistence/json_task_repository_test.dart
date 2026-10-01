import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:task_list_cli/domain/task.dart';
import 'package:task_list_cli/domain/task_book_state.dart';
import 'package:task_list_cli/domain/task_list.dart';
import 'package:task_list_cli/persistence/corrupted_book_exception.dart';
import 'package:task_list_cli/persistence/json_task_repository.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  late JsonTaskRepository repository;
  late File bookFile;

  setUp(() {
    workspace = TestWorkspace.create();
    addTearDown(workspace.dispose);
    repository = JsonTaskRepository.inDirectory(workspace.directory);
    bookFile = File(repository.bookPath);
  });

  TaskBookState sampleBook() => TaskBookState(
        lists: [
          TaskList(
            id: 'list-1',
            name: 'Work',
            tasks: [
              Task(
                id: 'task-1',
                title: 'Ship the release',
                completed: false,
                createdAt: DateTime.utc(2026, 3, 1, 8),
              ),
            ],
          ),
        ],
      );

  group('load', () {
    test('returns an empty book when nothing has been saved', () async {
      final state = await repository.load();

      expect(state.lists, isEmpty);
    });

    test('does not create the file just by reading', () async {
      await repository.load();

      expect(bookFile.existsSync(), isFalse);
    });

    test('reads back what update wrote', () async {
      await repository.update((_) => sampleBook());

      final state = await repository.load();

      expect(state.lists.single.name, 'Work');
      expect(state.lists.single.tasks.single.title, 'Ship the release');
    });
  });

  group('update', () {
    test('creates the data directory and the file', () async {
      await repository.update((_) => sampleBook());

      expect(bookFile.existsSync(), isTrue);
    });

    test('applies the change to the state already on disk', () async {
      await repository.update((current) => current.withList(
            TaskList(id: 'list-1', name: 'Work'),
          ));

      await repository.update((current) => current.withList(
            TaskList(id: 'list-2', name: 'Personal'),
          ));

      final names = (await repository.load()).lists.map((list) => list.name);
      expect(names, ['Work', 'Personal']);
    });

    test('keeps the document valid when the change throws', () async {
      await repository.update((_) => sampleBook());

      await expectLater(
        repository.update((_) => throw StateError('rejected')),
        throwsStateError,
      );

      final state = await repository.load();
      expect(state.lists.single.name, 'Work');
    });

    test('leaves no temporary file behind', () async {
      await repository.update((_) => sampleBook());

      final strays = workspace.directory
          .listSync()
          .map((entry) => p.basename(entry.path))
          .where((name) => name.endsWith('.tmp'));

      expect(strays, isEmpty);
    });

    test('keeps the previous file complete when the replacement fails', () async {
      await repository.update((_) => sampleBook());

      // Holding the data file open blocks the atomic replace, which is the
      // same situation a second process or a scanner creates. The new content
      // is already written to a separate file at this point.
      final blocker = bookFile.openSync();
      addTearDown(blocker.closeSync);

      await expectLater(
        repository.update((current) => current.withList(
              TaskList(id: 'list-2', name: 'Later'),
            )),
        throwsA(isA<FileSystemException>()),
      );

      expect(
        (await repository.load()).lists.map((list) => list.name),
        ['Work'],
        reason: 'the saved tasks must survive a failed write',
      );
    });

    test('writes human-readable JSON', () async {
      await repository.update((_) => sampleBook());

      expect(
        bookFile.readAsStringSync(),
        allOf(contains('"version": 1'), contains('\n  "lists"')),
      );
    });
  });

  group('damaged data', () {
    test('reports the file instead of crashing', () async {
      bookFile.parent.createSync(recursive: true);
      bookFile.writeAsStringSync('{ this is not json');

      expect(
        repository.load,
        throwsA(
          isA<CorruptedBookException>().having(
            (error) => error.path,
            'path',
            bookFile.path,
          ),
        ),
      );
    });

    test('never overwrites the file it could not read', () async {
      bookFile.parent.createSync(recursive: true);
      const damaged = '{ "version": 1, "lists": [ oops';
      bookFile.writeAsStringSync(damaged);

      await expectLater(repository.load, throwsA(isA<CorruptedBookException>()));

      expect(bookFile.readAsStringSync(), damaged);
    });

    test('refuses to write over a file it cannot read', () async {
      bookFile.parent.createSync(recursive: true);
      const damaged = 'not json';
      bookFile.writeAsStringSync(damaged);

      await expectLater(
        repository.update((_) => sampleBook()),
        throwsA(isA<CorruptedBookException>()),
      );

      expect(bookFile.readAsStringSync(), damaged);
    });

    test('reports an empty file', () async {
      bookFile.parent.createSync(recursive: true);
      bookFile.writeAsStringSync('   ');

      expect(
        repository.load,
        throwsA(
          isA<CorruptedBookException>().having(
            (error) => error.reason,
            'reason',
            contains('empty'),
          ),
        ),
      );
    });

    test('refuses a file holding values the application would not write',
        () async {
      bookFile.parent.createSync(recursive: true);
      // A list named with surrounding spaces is invisible to a lookup for the
      // trimmed name, so it must be reported rather than loaded.
      const foreign = '{"version": 1, "lists": [{"id": "a", "name": " Work ", '
          '"tasks": []}]}';
      bookFile.writeAsStringSync(foreign);

      expect(
        repository.load,
        throwsA(
          isA<CorruptedBookException>().having(
            (error) => error.reason,
            'reason',
            contains('surrounding spaces'),
          ),
        ),
      );

      await expectLater(
        repository.update((_) => sampleBook()),
        throwsA(isA<CorruptedBookException>()),
      );

      expect(
        bookFile.readAsStringSync(),
        foreign,
        reason: 'the original file has to survive untouched',
      );
    });
  });

  group('locking', () {
    test('a second repository over the same file sees the first write', () async {
      final other = JsonTaskRepository(
        bookPath: repository.bookPath,
        lockPath: repository.lockPath,
      );

      await repository.update((_) => sampleBook());
      await other.update((current) =>
          current.withList(TaskList(id: 'list-2', name: 'Personal')));

      expect(
        (await repository.load()).lists.map((list) => list.name),
        ['Work', 'Personal'],
      );
    });

    test('a change is applied on top of the other repository state', () async {
      final other = JsonTaskRepository(
        bookPath: repository.bookPath,
        lockPath: repository.lockPath,
      );

      // Both instances start from the same stale in-memory copy. The write
      // goes through the repository, so the second one must not lose the
      // first one's list.
      final staleA = await repository.load();
      final staleB = await other.load();
      expect(staleA.lists, isEmpty);
      expect(staleB.lists, isEmpty);

      await repository.update((current) =>
          current.withList(TaskList(id: 'list-1', name: 'From A')));
      await other.update((current) =>
          current.withList(TaskList(id: 'list-2', name: 'From B')));

      expect(
        (await repository.load()).lists.map((list) => list.name),
        ['From A', 'From B'],
      );
    });
  });
}
