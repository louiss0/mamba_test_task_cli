import 'package:uuid/uuid.dart';

import 'models.dart';
import 'repository.dart';

/// Both presentations use the same immutable snapshot and transactional writes.
final class TaskService(final JsonRepository repository) {
  AppState _state = repository.initialState;
  bool _saving = false;
  List<TaskList> get lists => _state.lists;

  TaskList getList(String reference) {
    for (final list in lists) {
      if (list.id == reference ||
          list.name.toLowerCase() == reference.trim().toLowerCase()) {
        return list;
      }
    }
    throw TaskFailure(
      'List "$reference" does not exist. Use "lists show" or create it first.',
    );
  }

  Task getTask(String listReference, String taskId) {
    for (final task in getList(listReference).tasks) {
      if (task.id == taskId) return task;
    }
    throw TaskFailure(
      'Task "$taskId" does not exist in this list. Use the full persistent ID.',
    );
  }

  List<Task> query(
    String listReference, {
    TaskFilter filter = TaskFilter.all,
  }) => List.unmodifiable(getList(listReference).tasks.where(filter.matches));

  Future<void> _commit(AppState next) async {
    if (_saving) {
      throw TaskFailure('A save is already in progress. Please retry.');
    }
    _saving = true;
    try {
      await repository.save(next);
      _state = next;
    } finally {
      _saving = false;
    }
  }

  Future<TaskList> createList(String name) async {
    final list = TaskList.create(id: const Uuid().v4(), name: name);
    await _commit(AppState.create([...lists, list]));
    return list;
  }

  Future<void> _replaceList(TaskList next) => _commit(
    AppState.create([
      for (final list in lists)
        if (list.id == next.id) next else list,
    ]),
  );

  Future<void> renameList(String reference, String name) async {
    final current = getList(reference);
    final next = current.update(name: name);
    if (current.name != next.name) await _replaceList(next);
  }

  Future<void> deleteList(String reference, {bool confirmed = false}) async {
    final list = getList(reference);
    if (list.tasks.isNotEmpty && !confirmed) {
      throw TaskFailure(
        'List "${list.name}" contains ${list.tasks.length} tasks. Confirm deletion with --yes.',
      );
    }
    await _commit(AppState.create(lists.where((item) => item.id != list.id)));
  }

  Future<Task> createTask(String reference, String title) async {
    final list = getList(reference);
    final task = Task.create(
      id: const Uuid().v4(),
      title: title,
      completion: Completion.incomplete,
      createdAt: DateTime.now().toUtc(),
    );
    await _replaceList(list.update(tasks: [...list.tasks, task]));
    return task;
  }

  Future<void> _replaceTask(String reference, Task next) => _replaceList(
    getList(reference).update(
      tasks: [
        for (final task in getList(reference).tasks)
          if (task.id == next.id) next else task,
      ],
    ),
  );

  Future<void> editTask(String reference, String id, String title) async {
    final current = getTask(reference, id);
    final next = current.update(title: title);
    if (current.title != next.title) await _replaceTask(reference, next);
  }

  Future<void> setCompletion(
    String reference,
    String id,
    Completion completion,
  ) async {
    final current = getTask(reference, id);
    if (current.completion != completion) {
      await _replaceTask(reference, current.update(completion: completion));
    }
  }

  Future<void> deleteTask(
    String reference,
    String id, {
    bool confirmed = false,
  }) async {
    final list = getList(reference);
    getTask(reference, id);
    if (!confirmed) throw TaskFailure('Confirm task deletion with --yes.');
    await _replaceList(
      list.update(tasks: list.tasks.where((task) => task.id != id)),
    );
  }
}
