import 'package:app_dirs/app_dirs.dart';
import 'package:path/path.dart' as p;

/// Where the task data lives on this machine.
///
/// The path is derived only from the platform conventions and the application
/// name, so the same installation always resolves to the same file and the app
/// can reload its state without being told where to look.
abstract final class StorageLocations {
  /// The name used to build the platform-specific directory.
  static const String applicationName = 'task_list';

  /// The platform's user data directory for this application.
  ///
  /// Resolves to `%APPDATA%\task_list` on Windows,
  /// `~/Library/Application Support/task_list` on macOS, and
  /// `~/.local/share/task_list` on Linux.
  static String get dataDirectory => getAppDirs(
        application: applicationName,
        preferUnixConventions: true,
      ).data;

  /// The JSON file holding the whole book.
  static String get bookFile => p.join(dataDirectory, 'task_book.json');

  /// The sidecar used for cross-process locking. It holds no task data.
  static String get lockFile => p.join(dataDirectory, 'task_book.lock');
}
