import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/task_book_state.dart';
import 'book_codec.dart';
import 'corrupted_book_exception.dart';
import 'storage_locations.dart';

/// Reads and writes the book.
///
/// Every change goes through [update], which re-reads the file while holding
/// the lock and applies the change to what is on disk. That is what keeps two
/// running instances from overwriting each other: a stale in-memory book is
/// never written back wholesale.
abstract interface class TaskRepository {
  /// The default location on this machine.
  static TaskRepository onDisk() => JsonTaskRepository(
        bookPath: StorageLocations.bookFile,
        lockPath: StorageLocations.lockFile,
      );

  /// Reads the saved book, or an empty book when nothing has been saved yet.
  ///
  /// Throws [CorruptedBookException] when a file exists but cannot be read.
  Future<TaskBookState> load();

  /// Applies [change] to the saved book and saves the result.
  ///
  /// Returns the state that was written.
  Future<TaskBookState> update(
    TaskBookState Function(TaskBookState current) change,
  );
}

/// A [TaskRepository] backed by one JSON file.
///
/// Writes are crash-safe: the new document goes to a temporary file in the
/// same directory, is flushed to disk, and only then replaces the previous one
/// with a rename. A crash part-way through leaves the old file untouched, and
/// a stale temporary file is never mistaken for real data because only the
/// final name is ever read.
final class JsonTaskRepository implements TaskRepository {
  JsonTaskRepository({required this.bookPath, required this.lockPath});

  /// Builds a repository over paths inside [directory], for tests.
  factory JsonTaskRepository.inDirectory(Directory directory) =>
      JsonTaskRepository(
        bookPath: p.join(directory.path, 'task_book.json'),
        lockPath: p.join(directory.path, 'task_book.lock'),
      );

  /// The JSON file holding the book.
  final String bookPath;

  /// The sidecar used for cross-process locking. It holds no task data.
  final String lockPath;

  @override
  Future<TaskBookState> load() async {
    final file = File(bookPath);
    if (!file.existsSync()) return TaskBookState.empty;
    return _read(file);
  }

  @override
  Future<TaskBookState> update(
    TaskBookState Function(TaskBookState current) change,
  ) async {
    final bookFile = File(bookPath);
    await bookFile.parent.create(recursive: true);
    final lockFile = File(lockPath);
    if (!lockFile.existsSync()) {
      await lockFile.create(recursive: true);
    }

    // A blocking exclusive lock makes a concurrent instance wait instead of
    // racing. dart:io exposes the operating system's own file lock, so this
    // works on Windows, macOS, and Linux without a bespoke protocol.
    final lock = await lockFile.open(mode: FileMode.write);
    final locked = await lock.lock(FileLock.blockingExclusive);
    try {
      final current = _read(bookFile);
      final updated = change(current);
      await _writeSafely(bookFile, BookCodec.encode(updated));
      return updated;
    } finally {
      await locked.unlock();
      await lock.close();
    }
  }

  TaskBookState _read(File file) {
    if (!file.existsSync()) return TaskBookState.empty;

    final String source;
    try {
      source = file.readAsStringSync(encoding: utf8);
    } on FileSystemException catch (error) {
      throw CorruptedBookException(
        path: bookPath,
        reason: 'The file could not be read (${error.osError?.message}).',
      );
    }

    if (source.trim().isEmpty) {
      throw CorruptedBookException(
        path: bookPath,
        reason: 'The file is empty.',
      );
    }
    return BookCodec.decode(source, path: bookPath);
  }

  /// Serialises, flushes, and atomically replaces the data file.
  ///
  /// `File.rename` maps to an atomic replace on all three target platforms, so
  /// a reader either sees the whole previous document or the whole new one.
  /// The new content is written to a separate file first, which means a crash
  /// or a failure at any point leaves the previous document complete and
  /// readable.
  Future<void> _writeSafely(File bookFile, String contents) async {
    final temporary = File(
      p.join(bookFile.parent.path, '.${p.basename(bookFile.path)}.tmp'),
    );
    // A temporary file left by an earlier crash must never be mistaken for
    // data, and must not block this write.
    _discard(temporary);

    final sink = temporary.openWrite(encoding: utf8);
    try {
      sink.write(contents);
      await sink.flush();
    } catch (_) {
      await sink.close();
      _discard(temporary);
      rethrow;
    }
    await sink.close();

    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await temporary.rename(bookFile.path);
        return;
      } on FileSystemException {
        // Another process or a scanner can hold the destination open for a
        // moment. Retrying briefly clears that without ever risking the data:
        // the new content is still in the temporary file and the previous
        // document is still in place.
        await Future<void>.delayed(Duration(milliseconds: 20 * (attempt + 1)));
      }
    }

    // The replacement could not be completed. The previous document is
    // untouched, so the saved tasks are still safe; surface the reason.
    _discard(temporary);
    throw FileSystemException(
      'Could not replace ${bookFile.path} after several attempts.',
      bookFile.path,
    );
  }

  void _discard(File file) {
    if (file.existsSync()) file.deleteSync();
  }
}
