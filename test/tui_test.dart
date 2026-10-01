import 'dart:io';

import 'package:mamba/mamba.dart';
import 'package:task_list_cli/path_command.dart';
import 'package:task_list_cli/tui.dart';
import 'package:test/test.dart';

void main() {
  group('task_list_cli', () {
    group('tui', () {
      test(
        'describes the interactive entry point without opening storage',
        () async {
          final result = await Executor(
            'task_list_cli',
            'Tasks',
            '1.0.0',
            [Tui()],
            options: [dataDirectory],
          ).fake().execute(['tui', '--help']);
          expect(
            result,
            isA<MambaSuccessResult>()
                .having((r) => r.exitCode, 'exit code', 0)
                .having(
                  (r) => r.output,
                  'output',
                  contains('interactive task manager'),
                ),
          );
        },
      );
      test('redirected input reports a meaningful nonzero error', () async {
        final result = await Executor(
          'task_list_cli',
          'Tasks',
          '1.0.0',
          [Tui()],
          options: [dataDirectory],
        ).fake().execute(['tui']);
        expect(
          result,
          isA<MambaFailureResult>()
              .having((r) => r.exitCode, 'exit code', 1)
              .having(
                (r) => r.message,
                'message',
                'The TUI needs an interactive terminal. Use lists/tasks commands for scripts.',
              )
              .having((r) => r.output, 'output', isNull)
              .having((r) => r.errors, 'errors', hasLength(1))
              .having(
                (r) => r.errors.single.phase,
                'phase',
                MambaExecutionPhase.run,
              )
              .having((r) => r.errors.single.commandPath, 'path', [
                'task_list_cli',
                'tui',
              ]),
        );
      }, skip: stdin.hasTerminal && stdout.hasTerminal);
    });
  });
}
