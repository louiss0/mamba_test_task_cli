import 'dart:convert';

import 'package:task_list_cli/models.dart';
import 'package:test/test.dart';

const listId = '11111111-1111-4111-8111-111111111111';
const taskId = '22222222-2222-4222-8222-222222222222';

void main() {
  group('domain and serialization', () {
    test('checked DTO round trip preserves every field and UTC time', () {
      final task = Task.create(
        id: taskId,
        title: ' Buy milk ',
        completion: Completion.completed,
        createdAt: DateTime.utc(2026, 1, 2, 3, 4),
      );
      final state = AppState.create([
        TaskList.create(id: listId, name: ' Personal ', tasks: [task]),
      ]);
      final wire = StoredState.fromDomain(state).toJson();
      expect(wire, {
        'version': 1,
        'lists': [
          {
            'id': listId,
            'name': 'Personal',
            'tasks': [
              {
                'id': taskId,
                'title': 'Buy milk',
                'completed': true,
                'createdAt': '2026-01-02T03:04:00.000Z',
              },
            ],
          },
        ],
      });
      final loaded = StoredState.fromJson(
        jsonDecode(jsonEncode(wire)) as Map<String, dynamic>,
      ).toDomain();
      final restored = loaded.lists.single.tasks.single;
      expect(restored.id, task.id);
      expect(restored.title, task.title);
      expect(restored.completion, task.completion);
      expect(restored.createdAt, task.createdAt);
      expect(StoredState.fromDomain(loaded).toJson(), wire);
      expect(() => loaded.lists.clear(), throwsUnsupportedError);
      expect(() => loaded.lists.single.tasks.clear(), throwsUnsupportedError);
    });

    test('updates never alter persistent identity or creation time', () {
      final task = Task.create(
        id: taskId,
        title: 'Original',
        completion: Completion.incomplete,
        createdAt: DateTime.utc(2026),
      );
      final updated = task.update(
        title: 'Edited',
        completion: Completion.completed,
      );
      expect(updated.id, taskId);
      expect(updated.createdAt, task.createdAt);
      expect(task.title, 'Original');
    });

    test('rejects invalid names, titles, IDs and duplicate identity', () {
      for (final name in ['', ' ', 'A\nB', 'x' * 81, listId]) {
        expect(
          () => TaskList.create(id: listId, name: name),
          throwsA(isA<TaskFailure>()),
        );
      }
      for (final title in ['', '\t', 'x' * 501, 'A\x1bB']) {
        expect(
          () => Task.create(
            id: taskId,
            title: title,
            completion: Completion.incomplete,
            createdAt: DateTime.utc(2026),
          ),
          throwsA(isA<TaskFailure>()),
        );
      }
      expect(
        () => TaskList.create(id: '1', name: 'Work'),
        throwsFormatException,
      );
      final list = TaskList.create(id: listId, name: 'Work');
      expect(() => AppState.create([list, list]), throwsA(isA<TaskFailure>()));
      final task = Task.create(
        id: taskId,
        title: 'Task',
        completion: Completion.incomplete,
        createdAt: DateTime.utc(2026),
      );
      expect(
        () => AppState.create([
          list.update(tasks: [task, task]),
        ]),
        throwsFormatException,
      );
    });

    test('rejects non-canonical and impossible timestamps', () {
      for (final date in [
        'nonsense',
        '2026-02-30T00:00:00.000Z',
        '2026-01-01T00:00:00',
        '2026-01-01T00:00:00.000+02:00',
      ]) {
        expect(
          () => StoredTask(
            id: taskId,
            title: 'Task',
            completed: false,
            createdAt: date,
          ).toDomain(),
          throwsFormatException,
        );
      }
    });
  });
}
