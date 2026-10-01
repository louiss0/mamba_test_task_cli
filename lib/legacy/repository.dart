import 'dart:convert';
import 'dart:io';

import 'package:app_dirs/app_dirs.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'models.dart';

typedef StateWriter = Future<void> Function(File destination, String contents);

/// One session owns an OS lock on a sidecar (never on the replaced JSON file).
/// The lock file stays in place; the OS releases locks after process termination.
final class JsonRepository._(
  final File file,
  final RandomAccessFile _lock,
  final StateWriter _writer,
  final AppState initialState,
) {
  static final _openPaths = <String>{};
  bool _closed = false;

  static String defaultDirectory() =>
      getAppDirs(application: 'task-list-cli').data;

  static Future<JsonRepository> open(
    String directory, {
    StateWriter writer = atomicWrite,
  }) async {
    final file = File(p.join(p.normalize(p.absolute(directory)), 'tasks.json'));
    final key = p.canonicalize(file.path);
    if (!_openPaths.add(key)) {
      throw TaskFailure(
        'Storage is already in use: ${file.path}. Close the other session and retry.',
      );
    }
    RandomAccessFile? lock;
    try {
      await file.parent.create(recursive: true);
      lock = await File('${file.path}.lock').open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive, 0, 1);
      } on FileSystemException {
        throw TaskFailure(
          'Storage is already in use: ${file.path}. Close the other instance and retry.',
        );
      }
      final state = await _load(file);
      return JsonRepository._(file, lock, writer, state);
    } catch (error) {
      await lock?.close();
      _openPaths.remove(key);
      if (error is TaskFailure) rethrow;
      throw TaskFailure('Cannot open storage ${file.path}: $error');
    }
  }

  static Future<AppState> _load(File file) async {
    if (!await file.exists()) return AppState.create([]);
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('The storage root must be a JSON object.');
      }
      return StoredState.fromJson(decoded).toDomain();
    } catch (error) {
      throw TaskFailure(
        'Cannot read valid task data at ${file.path}: $error\n'
        'Original file preserved. Back it up, then repair it or move it aside to start fresh.',
      );
    }
  }

  Future<void> save(AppState state) async {
    if (_closed) throw TaskFailure('Storage session is closed.');
    try {
      final json = const JsonEncoder.withIndent('  ')
          .convert(StoredState.fromDomain(state).toJson());
      await _writer(file, '$json\n');
    } catch (error) {
      throw TaskFailure(
        'Could not save ${file.path}: $error. Previous state remains active.',
      );
    }
  }

  /// Same-directory rename uses the OS replacement primitive; never delete the
  /// destination first. A failed write/rename leaves the old file in place.
  /// This guards process interruption, not every filesystem/power-loss scenario.
  static Future<void> atomicWrite(File destination, String contents) async {
    final temporary = File('${destination.path}.${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _lock.close();
    } finally {
      _openPaths.remove(p.canonicalize(file.path));
    }
  }
}
