import 'id_source.dart';
import 'task_list.dart';

/// The complete set of application state.
///
/// Every value is immutable, so a query can never change what is stored and a
/// mutation always produces a new book that is swapped in as a whole.
final class TaskBookState {
  TaskBookState({List<TaskList> lists = const []})
      : lists = List.unmodifiable(lists);

  /// The empty book, used before the first list is created.
  static final TaskBookState empty = TaskBookState();

  /// Every list, in creation order.
  final List<TaskList> lists;

  bool get isEmpty => lists.isEmpty;

  /// Returns the list with [id], or null when there is none.
  TaskList? byId(Identifier id) {
    for (final list in lists) {
      if (list.id == id) return list;
    }
    return null;
  }

  /// Returns the list named [name], ignoring case and surrounding whitespace.
  TaskList? byName(String name) {
    final wanted = name.trim().toLowerCase();
    for (final list in lists) {
      if (list.name.toLowerCase() == wanted) return list;
    }
    return null;
  }

  /// Returns the list with [id], or throws when there is none.
  TaskList require(Identifier id) {
    final list = byId(id);
    if (list == null) {
      throw StateError('No list with id $id.');
    }
    return list;
  }

  /// Returns a copy with [list] appended, or replacing the list that shares its
  /// id.
  TaskBookState withList(TaskList list) {
    final index = lists.indexWhere((existing) => existing.id == list.id);
    if (index < 0) {
      return TaskBookState(lists: [...lists, list]);
    }
    final updated = [...lists];
    updated[index] = list;
    return TaskBookState(lists: updated);
  }

  /// Returns a copy without the list identified by [id].
  TaskBookState withoutList(Identifier id) => TaskBookState(
        lists: lists.where((list) => list.id != id).toList(),
      );
}
