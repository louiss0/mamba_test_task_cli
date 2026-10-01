import '../application/task_book.dart';
import '../domain/completion_filter.dart';
import '../domain/id_source.dart';
import '../domain/task.dart';
import '../domain/task_filter.dart';
import '../domain/task_list.dart';
import '../domain/validation.dart';
import 'pane.dart';

/// The interactive screen's state, with no rendering attached.
///
/// Every keystroke the user makes turns into a call on this class, and every
/// change to the book turns into a rebuild of this class. Keeping it separate
/// from the widgets means the behaviour can be tested without a terminal, and
/// it keeps the widget layer to nothing but drawing.
///
/// Selection is held as a task identifier, never as a row number, so a task
/// stays selected while the view around it is filtered, sorted, or edited.
final class TaskScreen {
  TaskScreen(this._book);

  final TaskBook _book;

  Identifier? _listId;
  Identifier? _taskId;
  int _taskIndex = 0;
  int _listIndex = 0;
  CompletionFilter _filter = CompletionFilter.all;
  Pane _pane = Pane.tasks;
  String _status = '';
  bool _statusIsError = false;

  /// Every list, in creation order.
  List<TaskList> get lists => _book.lists;

  /// The list the user is looking at, or null when the book has none.
  TaskList? get currentList {
    final all = lists;
    if (all.isEmpty) return null;
    return all[_listIndex.clamp(0, all.length - 1)];
  }

  /// The active completion filter.
  CompletionFilter get filter => _filter;

  /// The pane that currently owns the keyboard.
  Pane get pane => _pane;

  /// The pane the user moved away from, used to describe the "back" action.
  Pane get otherPane => _pane == Pane.tasks ? Pane.lists : Pane.tasks;

  /// The tasks of [currentList] that pass the active filter.
  List<Task> get visibleTasks {
    final list = currentList;
    if (list == null) return const [];
    return _book.queryTasks(list.id, TaskFilter.byCompletion(_filter));
  }

  /// Where the selection sits inside [visibleTasks], or -1 when nothing is
  /// shown.
  ///
  /// The first visible task is always selected, so the user can act on a row
  /// straight away. The stored identifier is only an anchor: when the task it
  /// names has left this view, the highlight stays at the position it held.
  int get selectedIndex {
    final tasks = visibleTasks;
    if (tasks.isEmpty) return -1;
    final index = tasks.indexWhere((Task task) => task.id == _taskId);
    if (index >= 0) return index;
    return _taskIndex.clamp(0, tasks.length - 1);
  }

  /// The highlighted task, or null when the view is empty.
  Task? get selectedTask {
    final index = selectedIndex;
    if (index < 0) return null;
    return visibleTasks[index];
  }

  /// The index of the highlighted list.
  int get selectedListIndex {
    final all = lists;
    return all.isEmpty ? -1 : _listIndex.clamp(0, all.length - 1);
  }

  /// The most recent outcome, shown in the status line.
  String get status => _status;

  /// Whether [status] reports a problem rather than a completed action.
  bool get statusIsError => _statusIsError;

  /// Loads the book and points the screen at the first list.
  void open() {
    final first = _book.defaultList;
    _listId = first?.id;
    _listIndex = 0;
    _taskId = null;
    _taskIndex = 0;
  }

  /// Re-reads the visible list after the book changed and returns the pane the
  /// user should land on.
  ///
  /// Deleting the selected list moves to its neighbour, and losing the selected
  /// task moves the highlight down to whatever took its place rather than
  /// resetting to the top.
  Pane reconcile() {
    final all = lists;
    if (all.isEmpty) {
      _listId = null;
      _taskId = null;
      _pane = Pane.tasks;
      return Pane.tasks;
    }

    if (_listId == null || all.every((TaskList list) => list.id != _listId)) {
      _listId = all[_listIndex.clamp(0, all.length - 1)].id;
      _taskId = null;
      _taskIndex = 0;
    } else {
      _listIndex = all.indexWhere((TaskList list) => list.id == _listId);
    }

    final tasks = visibleTasks;
    if (tasks.isEmpty) {
      _pane = Pane.tasks;
    }
    _reanchorSelection();
    return _pane;
  }

  /// Keeps the highlight on the same task when the visible set changes.
  ///
  /// A task that is still shown stays selected, because it is the one the user
  /// was looking at: narrowing a filter must not silently aim the next
  /// completion or deletion at a different task. Only when the selected task
  /// leaves the view does the highlight move, and then it lands near the
  /// position it held.
  void _reanchorSelection() {
    final tasks = visibleTasks;
    if (tasks.isEmpty) {
      _taskId = null;
      _taskIndex = 0;
      return;
    }
    final kept = _taskId == null
        ? -1
        : tasks.indexWhere((Task task) => task.id == _taskId);
    if (kept >= 0) {
      _taskIndex = kept;
      return;
    }
    _taskIndex = _taskIndex.clamp(0, tasks.length - 1);
    _taskId = tasks[_taskIndex].id;
  }

  /// Moves keyboard focus between the list pane and the task pane.
  void togglePane() {
    _pane = otherPane;
    _syncSelectionToPane();
  }

  /// Moves the highlight within the pane that owns the keyboard.
  void moveSelection(int delta) {
    if (_pane == Pane.lists) {
      final all = lists;
      if (all.isEmpty) return;
      _listIndex = (_listIndex + delta).clamp(0, all.length - 1);
      _listId = all[_listIndex].id;
      _taskId = null;
      _taskIndex = 0;
      return;
    }

    final tasks = visibleTasks;
    if (tasks.isEmpty) return;
    _taskIndex = (_taskIndex + delta).clamp(0, tasks.length - 1);
    _taskId = tasks[_taskIndex].id;
  }

  /// Jumps the highlight to the first or last visible task.
  void moveSelectionToEdge({required bool last}) {
    final tasks = visibleTasks;
    if (tasks.isEmpty) return;
    _taskIndex = last ? tasks.length - 1 : 0;
    _taskId = tasks[_taskIndex].id;
  }

  /// Shows a different completion state.
  ///
  /// This only changes what is drawn. The book is untouched and nothing is
  /// written to disk.
  void applyFilter(CompletionFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    _reanchorSelection();
  }

  /// Moves to the previous or next completion state, wrapping around.
  void stepFilter(int delta) {
    const order = CompletionFilter.values;
    final next = (order.indexOf(_filter) + delta) % order.length;
    applyFilter(order[next < 0 ? next + order.length : next]);
  }

  /// Points the screen at [list] and clears the task selection.
  void selectList(Identifier listId) {
    _listId = listId;
    final all = lists;
    _listIndex = all.indexWhere((TaskList list) => list.id == listId);
    if (_listIndex < 0) _listIndex = 0;
    _taskId = null;
    _taskIndex = 0;
    _pane = Pane.tasks;
  }

  /// Adds a task titled [title] to the selected list.
  Future<void> addTask(String title) async {
    final list = currentList;
    if (list == null) {
      _fail('Create a list before adding tasks.');
      return;
    }
    try {
      final task = await _book.addTask(list.id, title);
      _taskId = task.id;
      _taskIndex = visibleTasks.indexWhere((entry) => entry.id == task.id);
      _pane = Pane.tasks;
      _succeed('Added "${task.title}".');
    } on ValidationException catch (error) {
      _fail(error.message);
      rethrow;
    }
  }

  /// Replaces the title of the selected task.
  Future<void> renameSelectedTask(String title) async {
    final list = currentList;
    final task = selectedTask;
    if (list == null || task == null) {
      _fail('Select a task first.');
      return;
    }
    try {
      await _book.editTask(list.id, task.id, title);
      _succeed('Renamed "${task.title}" to "$title".');
    } on ValidationException catch (error) {
      _fail(error.message);
      rethrow;
    }
  }

  /// Toggles the selected task between complete and incomplete.
  ///
  /// When the active filter hides the task afterwards, the highlight moves to
  /// the task that took its place, which is what makes completing a task under
  /// the Incomplete filter appear to remove the row.
  Future<void> toggleSelectedTask() async {
    final list = currentList;
    final task = selectedTask;
    if (list == null || task == null) {
      _fail('Select a task first.');
      return;
    }
    final updated = await _book.setTaskCompleted(
      list.id,
      task.id,
      !task.completed,
    );
    final anchor = _taskIndex;
    _taskId = updated.id;
    _taskIndex = anchor;
    reconcile();
    _succeed(
      updated.completed
          ? 'Completed "${updated.title}".'
          : 'Reopened "${updated.title}".',
    );
  }

  /// Deletes the selected task.
  Future<void> deleteSelectedTask() async {
    final list = currentList;
    final task = selectedTask;
    if (list == null || task == null) {
      _fail('Select a task first.');
      return;
    }
    await _book.deleteTask(list.id, task.id);
    _taskId = null;
    reconcile();
    _succeed('Deleted "${task.title}".');
  }

  /// Creates a list named [name] and opens it.
  Future<void> createList(String name) async {
    try {
      final list = await _book.createList(name);
      selectList(list.id);
      _succeed('Created list "${list.name}".');
    } on ValidationException catch (error) {
      _fail(error.message);
      rethrow;
    }
  }

  /// Renames the selected list.
  Future<void> renameCurrentList(String name) async {
    final list = currentList;
    if (list == null) {
      _fail('Create a list first.');
      return;
    }
    try {
      final renamed = await _book.renameList(list.id, name);
      _listId = renamed.id;
      _succeed('Renamed to "${renamed.name}".');
    } on ValidationException catch (error) {
      _fail(error.message);
      rethrow;
    }
  }

  /// Deletes the selected list along with its tasks.
  Future<void> deleteCurrentList() async {
    final list = currentList;
    if (list == null) {
      _fail('There is no list to delete.');
      return;
    }
    final name = list.name;
    final taskCount = list.tasks.length;
    await _book.deleteList(list.id);
    _listId = null;
    _taskId = null;
    reconcile();
    _succeed(
      taskCount == 0
          ? 'Deleted list "$name".'
          : 'Deleted list "$name" and $taskCount '
              '${taskCount == 1 ? 'task' : 'tasks'}.',
    );
  }

  /// Replaces the status line with a neutral note.
  void report(String message) {
    _status = message;
    _statusIsError = false;
  }

  void _succeed(String message) {
    _status = message;
    _statusIsError = false;
  }

  void _fail(String message) {
    _status = message;
    _statusIsError = true;
  }

  /// Lines the stored highlight up with the pane the user just entered.
  ///
  /// Entering a pane always shows a highlight, so there is something to act on
  /// straight away.
  void _syncSelectionToPane() {
    if (_pane == Pane.lists) {
      final all = lists;
      if (all.isEmpty) return;
      _listIndex = _listIndex.clamp(0, all.length - 1);
      _listId = all[_listIndex].id;
      return;
    }
    final tasks = visibleTasks;
    if (tasks.isEmpty) return;
    _taskIndex = _taskIndex.clamp(0, tasks.length - 1);
    _taskId = tasks[_taskIndex].id;
  }
}
