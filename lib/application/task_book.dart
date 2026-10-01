import '../domain/id_source.dart';
import '../domain/naming.dart';
import '../domain/task.dart';
import '../domain/task_book_state.dart';
import '../domain/task_filter.dart';
import '../domain/task_list.dart';
import '../domain/validation.dart';
import '../persistence/json_task_repository.dart';

/// Every behaviour the CLI and the TUI share.
///
/// Both front ends call this one class, so task behaviour is written once.
/// The current state is held in memory for fast reads, and each mutation goes
/// through the repository, which re-reads and saves. After a mutation the book
/// returned by the repository replaces the in-memory copy, so a change made by
/// another process in the meantime is not silently thrown away.
final class TaskBook {
  TaskBook(this._repository, {IdSource? ids})
      : _ids = ids ?? IdSource();

  final TaskRepository _repository;
  final IdSource _ids;

  TaskBookState _state = TaskBookState.empty;

  /// The current state. Reading this never touches the disk.
  TaskBookState get state => _state;

  /// Loads the saved book into memory.
  Future<void> load() async {
    _state = await _repository.load();
  }

  /// Every list, in creation order.
  List<TaskList> get lists => _state.lists;

  /// Returns the list named [name], ignoring case, or throws.
  TaskList requireListByName(String name) {
    final list = _state.byName(name);
    if (list == null) {
      throw NotFoundException(
        'No list named "$name" exists. Run "task_list lists ls" to see the '
        'available lists.',
      );
    }
    return list;
  }

  /// Returns the list with [id], or throws.
  TaskList requireList(Identifier id) {
    final list = _state.byId(id);
    if (list == null) {
      throw NotFoundException('No list with id $id exists.');
    }
    return list;
  }

  /// The list selected when the application opens, or null when there are none.
  ///
  /// Choosing the first list keeps the TUI from opening on an empty screen
  /// once the user has any data at all.
  TaskList? get defaultList => _state.lists.isEmpty ? null : _state.lists.first;

  /// Creates a list named [rawName] and saves the book.
  Future<TaskList> createList(String rawName) async {
    final taken = _state.lists.map((list) => list.name);
    final name = normalizeListName(rawName, existingNames: taken);
    final list = TaskList(id: _ids.next(), name: name);

    _state = await _repository.update((current) {
      if (current.byName(name) != null) {
        throw ValidationException('A list named "$name" already exists.');
      }
      return current.withList(list);
    });
    return _state.require(list.id);
  }

  /// Renames the list [id] to [rawName] and saves the book.
  Future<TaskList> renameList(Identifier id, String rawName) async {
    final current = requireList(id);
    final others = _state.lists
        .where((list) => list.id != id)
        .map((list) => list.name);
    final name = normalizeListName(rawName, existingNames: others);

    _state = await _repository.update((latest) {
      final list = latest.byId(id);
      if (list == null) {
        throw NotFoundException('The list "$current.name" no longer exists.');
      }
      if (latest.byName(name)?.id != null && latest.byName(name)!.id != id) {
        throw ValidationException('A list named "$name" already exists.');
      }
      return latest.withList(list.withName(name));
    });
    return _state.require(id);
  }

  /// Deletes the list [id], its tasks included, and saves the book.
  Future<void> deleteList(Identifier id) async {
    requireList(id);
    _state = await _repository.update(
      (latest) => latest.withoutList(id),
    );
  }

  /// The tasks of [listId] that pass [filter], in list order.
  ///
  /// This is a read. It never writes, so changing the visible filter does not
  /// touch the JSON file.
  List<Task> queryTasks(Identifier listId, TaskFilter filter) =>
      requireList(listId).tasks.where(filter.matches).toList();

  /// Adds a task titled [rawTitle] to [listId] and saves the book.
  Future<Task> addTask(Identifier listId, String rawTitle) async {
    requireList(listId);
    final title = normalizeTaskTitle(rawTitle);
    final task = Task(
      id: _ids.next(),
      title: title,
      completed: false,
      createdAt: _ids.now(),
    );

    _state = await _repository.update((latest) {
      final list = latest.byId(listId);
      if (list == null) {
        throw NotFoundException('The list for "$title" no longer exists.');
      }
      return latest.withList(list.withTask(task));
    });
    return _state.require(listId).requireTask(task.id);
  }

  /// Changes the title of [taskId] in [listId] and saves the book.
  Future<Task> editTask(
    Identifier listId,
    Identifier taskId,
    String rawTitle,
  ) async {
    requireList(listId).requireTask(taskId);
    final title = normalizeTaskTitle(rawTitle);

    _state = await _repository.update((latest) {
      final list = latest.byId(listId);
      if (list == null || list.taskById(taskId) == null) {
        throw NotFoundException('Task $taskId no longer exists.');
      }
      return latest.withList(
        list.withChangedTask(taskId, (task) => task.copyWith(title: title)),
      );
    });
    return _state.require(listId).requireTask(taskId);
  }

  /// Marks [taskId] in [listId] complete or incomplete and saves the book.
  ///
  /// The task stays in the list either way, so it can be reopened later.
  Future<Task> setTaskCompleted(
    Identifier listId,
    Identifier taskId,
    bool completed,
  ) async {
    requireList(listId).requireTask(taskId);

    _state = await _repository.update((latest) {
      final list = latest.byId(listId);
      if (list == null || list.taskById(taskId) == null) {
        throw NotFoundException('Task $taskId no longer exists.');
      }
      return latest.withList(
        list.withChangedTask(
          taskId,
          (task) => task.copyWith(completed: completed),
        ),
      );
    });
    return _state.require(listId).requireTask(taskId);
  }

  /// Deletes [taskId] from [listId] and saves the book.
  Future<void> deleteTask(Identifier listId, Identifier taskId) async {
    requireList(listId).requireTask(taskId);

    _state = await _repository.update((latest) {
      final list = latest.byId(listId);
      if (list == null || list.taskById(taskId) == null) {
        throw NotFoundException('Task $taskId no longer exists.');
      }
      return latest.withList(list.withoutTask(taskId));
    });
  }
}
