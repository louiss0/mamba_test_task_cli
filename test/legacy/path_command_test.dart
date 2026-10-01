import 'dart:io';

import 'package:mamba/mamba.dart';
import 'package:path/path.dart' as p;
import 'package:task_list_cli/legacy/path_command.dart';
import 'package:test/test.dart';

void main() {
  group('task_list_cli', () {
    group('path', () {
      test(
        'prints the overridden path without opening or creating storage',
        () async {
          final directory = await Directory.systemTemp.createTemp('task-path-');
          try {
            final result = await Executor(
              'task_list_cli',
              'Tasks',
              '1.0.0',
              [PathCommand()],
              options: [dataDirectory],
            ).fake().execute(['--data-dir', directory.path, 'path']);
            expect(
              result,
              isA<MambaSuccessResult>()
                  .having((r) => r.exitCode, 'exit code', 0)
                  .having(
                    (r) => r.output,
                    'output',
                    p.join(directory.path, 'tasks.json'),
                  ),
            );
            expect(await directory.list().toList(), isEmpty);
          } finally {
            await directory.delete();
          }
        },
      );
    });
  });
}
