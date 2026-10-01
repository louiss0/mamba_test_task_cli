import 'dart:convert';

import 'package:task_list_cli/domain/task.dart';
import 'package:task_list_cli/domain/task_book_state.dart';
import 'package:task_list_cli/domain/task_list.dart';
import 'package:task_list_cli/persistence/book_codec.dart';
import 'package:task_list_cli/persistence/corrupted_book_exception.dart';
import 'package:task_list_cli/persistence/persisted_state.dart';
import 'package:test/test.dart';

void main() {
  const path = '/data/task_book.json';

  final book = TaskBookState(
    lists: [
      TaskList(
        id: 'list-1',
        name: 'Work',
        tasks: [
          Task(
            id: 'task-1',
            title: 'Write the report',
            completed: false,
            createdAt: DateTime.utc(2026, 2, 3, 9, 30),
          ),
          Task(
            id: 'task-2',
            title: 'Send the invoice',
            completed: true,
            createdAt: DateTime.utc(2026, 2, 4, 11),
          ),
        ],
      ),
      TaskList(id: 'list-2', name: 'Personal'),
    ],
  );

  group('serialize', () {
    test('writes the version and every list and task', () {
      final json = jsonDecode(BookCodec.encode(book)) as Map<String, dynamic>;

      expect(json['version'], currentSchemaVersion);
      final lists = json['lists'] as List<dynamic>;
      expect(lists, hasLength(2));
      expect((lists.first as Map<String, dynamic>)['name'], 'Work');
      expect(
        (lists.first as Map<String, dynamic>)['tasks'],
        hasLength(2),
      );
    });

    test('keeps a task reference, title, state, and creation time', () {
      final json = jsonDecode(BookCodec.encode(book)) as Map<String, dynamic>;
      final first = ((json['lists'] as List<dynamic>).first
          as Map<String, dynamic>)['tasks'] as List<dynamic>;
      final task = first.first as Map<String, dynamic>;

      expect(task['id'], 'task-1');
      expect(task['title'], 'Write the report');
      expect(task['completed'], isFalse);
      expect(task['createdAt'], '2026-02-03T09:30:00.000Z');
    });

    test('indents the document so it stays readable by hand', () {
      expect(BookCodec.encode(book), contains('\n  "version": $currentSchemaVersion'));
    });

    test('round-trips a book without losing anything', () {
      final decoded = BookCodec.decode(BookCodec.encode(book), path: path);

      expect(decoded.lists, hasLength(2));
      expect(decoded.lists.first.name, 'Work');
      expect(decoded.lists.first.tasks, hasLength(2));
      expect(decoded.lists.first.tasks.first.title, 'Write the report');
      expect(decoded.lists.first.tasks.last.completed, isTrue);
      expect(
        decoded.lists.first.tasks.first.createdAt.isAtSameMomentAs(
          book.lists.first.tasks.first.createdAt,
        ),
        isTrue,
        reason: 'a round trip must preserve the instant, not the offset',
      );
    });

    test('round-trips an empty book', () {
      final decoded = BookCodec.decode(
        BookCodec.encode(TaskBookState.empty),
        path: path,
      );

      expect(decoded.lists, isEmpty);
    });
  });

  group('deserialize', () {
    Matcher rejects(String reasonFragment) => throwsA(
          isA<CorruptedBookException>()
              .having((error) => error.path, 'path', path)
              .having(
                (error) => error.reason,
                'reason',
                contains(reasonFragment),
              ),
        );

    test('rejects text that is not JSON', () {
      expect(() => BookCodec.decode('not json at all', path: path), rejects('not valid JSON'));
    });

    test('rejects a JSON document that is not an object', () {
      expect(() => BookCodec.decode('[1, 2, 3]', path: path), rejects('Expected a JSON object'));
    });

    test('rejects a document with no version', () {
      expect(
        () => BookCodec.decode('{"lists": []}', path: path),
        rejects('version'),
      );
    });

    test('rejects a version this build cannot read', () {
      expect(
        () => BookCodec.decode('{"version": 99, "lists": []}', path: path),
        rejects('schema version 99'),
      );
    });

    test('rejects a missing required field', () {
      expect(
        () => BookCodec.decode('{"version": 1, "lists": [{"id": "a"}]}', path: path),
        rejects('required field'),
      );
    });

    test('rejects a task whose completion state has the wrong type', () {
      expect(
        () => BookCodec.decode(
          '{"version": 1, "lists": [{"id": "a", "name": "A", "tasks": '
          '[{"id": "t", "title": "x", "completed": "yes", '
          '"createdAt": "2026-01-01T00:00:00.000Z"}]}]}',
          path: path,
        ),
        rejects('required field'),
      );
    });

    test('rejects a creation time that is not a date', () {
      expect(
        () => BookCodec.decode(
          '{"version": 1, "lists": [{"id": "a", "name": "A", "tasks": '
          '[{"id": "t", "title": "x", "completed": false, '
          '"createdAt": "yesterday"}]}]}',
          path: path,
        ),
        rejects('ISO-8601'),
      );
    });

    test('rejects two lists sharing a name', () {
      expect(
        () => BookCodec.decode(
          '{"version": 1, "lists": ['
          '{"id": "a", "name": "Work", "tasks": []},'
          '{"id": "b", "name": "work", "tasks": []}]}',
          path: path,
        ),
        rejects('share the name'),
      );
    });

    test('rejects two tasks in one list sharing a reference', () {
      expect(
        () => BookCodec.decode(
          '{"version": 1, "lists": [{"id": "a", "name": "A", "tasks": ['
          '{"id": "t", "title": "x", "completed": false, '
          '"createdAt": "2026-01-01T00:00:00.000Z"},'
          '{"id": "t", "title": "y", "completed": false, '
          '"createdAt": "2026-01-01T00:00:00.000Z"}]}]}',
          path: path,
        ),
        rejects('share the id'),
      );
    });

    test('names the file so the user can find it', () {
      expect(
        () => BookCodec.decode('broken', path: path),
        throwsA(
          isA<CorruptedBookException>().having(
            (error) => error.toString(),
            'message',
            allOf(contains(path), contains('left in place')),
          ),
        ),
      );
    });
  });

  group('values the application would never write', () {
    Matcher rejects(String reasonFragment) => throwsA(
          isA<CorruptedBookException>()
              .having((error) => error.path, 'path', path)
              .having(
                (error) => error.reason,
                'reason',
                contains(reasonFragment),
              ),
        );

    /// Wraps [body] in a minimal valid document with one list.
    String document({required String listId, required String name, String tasks = '[]'}) =>
        '{"version": 1, "lists": [{"id": $listId, "name": $name, '
        '"tasks": $tasks}]}';

    String oneTask(String id, String title) =>
        '[{"id": $id, "title": $title, "completed": false, '
        '"createdAt": "2026-02-03T09:30:00.000Z"}]';

    test('rejects a list with an empty id', () {
      expect(
        () => BookCodec.decode(
          document(listId: '""', name: '"Work"'),
          path: path,
        ),
        rejects('empty id'),
      );
    });

    test('rejects a task with an empty id', () {
      expect(
        () => BookCodec.decode(
          document(
            listId: '"a"',
            name: '"Work"',
            tasks: oneTask('""', '"Buy milk"'),
          ),
          path: path,
        ),
        rejects('empty id'),
      );
    });

    test('rejects an id with surrounding spaces', () {
      expect(
        () => BookCodec.decode(
          document(listId: '" a "', name: '"Work"'),
          path: path,
        ),
        rejects('surrounding spaces'),
      );
    });

    test('rejects an empty task title', () {
      expect(
        () => BookCodec.decode(
          document(
            listId: '"a"',
            name: '"Work"',
            tasks: oneTask('"t1"', '""'),
          ),
          path: path,
        ),
        rejects('cannot be empty'),
      );
    });

    test('rejects a whitespace-only task title', () {
      expect(
        () => BookCodec.decode(
          document(
            listId: '"a"',
            name: '"Work"',
            tasks: oneTask('"t1"', '"   "'),
          ),
          path: path,
        ),
        rejects('cannot be empty'),
      );
    });

    test('rejects an empty list name', () {
      expect(
        () => BookCodec.decode(
          document(listId: '"a"', name: '""'),
          path: path,
        ),
        rejects('cannot be empty'),
      );
    });

    test('rejects a list name with surrounding spaces', () {
      // The name has to be stored exactly as the user typed it after trimming,
      // otherwise a lookup for "Work" cannot find a list called " Work ".
      expect(
        () => BookCodec.decode(
          document(listId: '"a"', name: '" Work "'),
          path: path,
        ),
        rejects('surrounding spaces'),
      );
    });

    test('rejects a name longer than the application allows', () {
      final long = 'x' * 300;
      expect(
        () => BookCodec.decode(
          document(listId: '"a"', name: '"$long"'),
          path: path,
        ),
        rejects('cannot be longer than'),
      );
    });

    test('rejects a title containing a control character', () {
      expect(
        () => BookCodec.decode(
          document(
            listId: '"a"',
            name: '"Work"',
            tasks: oneTask('"t1"', r'"Buy\u0007milk"'),
          ),
          path: path,
        ),
        rejects('control characters'),
      );
    });

    test('accepts a title with an ordinary space', () {
      final state = BookCodec.decode(
        document(
          listId: '"a"',
          name: '"Work"',
          tasks: oneTask('"t1"', '"Buy milk"'),
        ),
        path: path,
      );

      expect(state.lists.single.tasks.single.title, 'Buy milk');
    });
  });
}
