import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:task_list_cli/persistence/storage_locations.dart';
import 'package:test/test.dart';

void main() {
  group('StorageLocations', () {
    test('puts the data under the platform user data directory', () {
      // The exact shape differs by platform: `%APPDATA%\task_list\data` on
      // Windows, `~/.local/share/task_list` on Linux, and
      // `~/Library/Application Support/task_list` on macOS. What matters is
      // that the app lands inside the user data area and names itself.
      final base = switch (Platform.operatingSystem) {
        'windows' => Platform.environment['APPDATA']!,
        'macos' => p.join(
            Platform.environment['HOME']!,
            'Library',
            'Application Support',
          ),
        _ => Platform.environment['XDG_DATA_HOME'] ??
            p.join(Platform.environment['HOME']!, '.local', 'share'),
      };
      final directory = StorageLocations.dataDirectory;

      expect(
        p.isWithin(base, directory),
        isTrue,
        reason: '$directory must sit under $base',
      );
      // `app_dirs` adds its own final segment on some platforms, so the app
      // name only has to appear somewhere in the path.
      expect(
        p.split(directory),
        contains(StorageLocations.applicationName),
        reason: '$directory must be namespaced to this application',
      );
    });

    test('never falls back to the current directory', () {
      final relative = p.isRelative(StorageLocations.bookFile);

      expect(relative, isFalse);
    });

    test('resolves to the same place every time', () {
      expect(StorageLocations.bookFile, StorageLocations.bookFile);
      expect(StorageLocations.dataDirectory, StorageLocations.dataDirectory);
    });

    test('names the book and its lock inside the data directory', () {
      expect(
        p.dirname(StorageLocations.bookFile),
        StorageLocations.dataDirectory,
      );
      expect(
        p.dirname(StorageLocations.lockFile),
        StorageLocations.dataDirectory,
      );
      expect(StorageLocations.bookFile, endsWith('.json'));
      expect(StorageLocations.bookFile, isNot(StorageLocations.lockFile));
    });
  });
}
