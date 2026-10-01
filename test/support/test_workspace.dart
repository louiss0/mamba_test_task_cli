import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:task_list_cli/domain/id_source.dart';
import 'package:task_list_cli/domain/task_book_state.dart';
import 'package:task_list_cli/persistence/json_task_repository.dart';

/// A throwaway directory for one test.
///
/// Every persistence test works inside one of these instead of the real
/// application data directory, so a test run can never touch the user's tasks.
final class TestWorkspace {
  TestWorkspace._(this.directory);

  final Directory directory;

  /// Creates a workspace and arranges for it to be removed afterwards.
  ///
  /// Pass it to `addTearDown` or use it inside a `setUp`/`tearDown` pair.
  static TestWorkspace create() {
    final directory = Directory.systemTemp.createTempSync('task_list_test_');
    return TestWorkspace._(directory);
  }

  /// The path of [name] inside the workspace.
  String pathOf(String name) => p.join(directory.path, name);

  void dispose() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

/// A source of identifiers and timestamps that never changes between runs.
///
/// Ids are still unique, but a test can assert on exact values and a failure
/// reproduces.
///
/// One instance must be shared by everything that creates identifiers in a
/// test. Each call reseeds the generator, so two sources would hand out the
/// same sequence and two lists could end up with the same id.
IdSource deterministicIds({DateTime? now}) => IdSource(
      clock: () => now ?? DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(7),
    );

/// Wraps a repository and counts how often the book was written.
///
/// The count is how the tests prove that reading, navigating, and changing the
/// filter never touch the file.
final class CountingRepository implements TaskRepository {
  CountingRepository(this._inner);

  final TaskRepository _inner;

  int _writes = 0;

  /// How many times the book has been written.
  int get writeCount => _writes;

  @override
  Future<TaskBookState> load() => _inner.load();

  @override
  Future<TaskBookState> update(
    TaskBookState Function(TaskBookState current) change,
  ) {
    _writes++;
    return _inner.update(change);
  }
}
