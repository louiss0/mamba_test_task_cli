import 'dart:async';

import '../domain/task_book_state.dart';
import 'json_task_repository.dart';

/// A [TaskRepository] that keeps the book in memory.
///
/// It obeys the same re-read-then-write contract as the on-disk repository, so
/// it is a faithful stand-in for driving the application layer and the
/// interface without touching the file system.
final class InMemoryTaskRepository implements TaskRepository {
  InMemoryTaskRepository([TaskBookState? initial])
      : _state = initial ?? TaskBookState.empty;

  TaskBookState _state;

  @override
  Future<TaskBookState> load() async => _state;

  @override
  Future<TaskBookState> update(
    TaskBookState Function(TaskBookState current) change,
  ) async {
    _state = change(_state);
    return _state;
  }
}
