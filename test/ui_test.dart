import 'package:mamba/mamba.dart';
import 'package:nocterm/nocterm.dart' show TuiThemeData;
import 'package:task_list_cli/persistence/in_memory_task_repository.dart';
import 'package:task_list_cli/presentation/theme.dart';
import 'package:task_list_cli/tui.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryTaskRepository repository;

  setUp(() {
    repository = InMemoryTaskRepository();
  });

  MambaExecutor<MambaExecutionResult> cli() => Executor(
        'task_list',
        'Manage persistent task lists.',
        '1.0.0',
        [TuiCommand(repository: repository)],
      ).fake();

  group('tui', () {
    test('offers a theme', () async {
      final result = await cli().execute(['tui', '--help']);

      expect(
        result,
        isA<MambaSuccessResult>()
            .having((value) => value.exitCode, 'exit code', 0)
            .having(
              (value) => value.output,
              'output',
              allOf(contains('--theme'), contains('nord')),
            ),
      );
    });

    test('rejects an unknown theme', () async {
      final result = await cli().execute(['tui', '--theme', 'neon']);

      expect(result, isA<MambaFailureResult>());
    });

    test('explains that a terminal is required', () async {
      final result = await cli().execute(['tui']);

      // The tests have no terminal to paint on, so the command has to say so
      // and point at the commands that do work.
      expect(
        result,
        isA<MambaFailureResult>()
            .having((value) => value.exitCode, 'exit code', 4)
            .having(
              (value) => value.message,
              'message',
              allOf(
                contains('needs a terminal'),
                contains('"lists"'),
                contains('"tasks"'),
              ),
            )
            .having((value) => value.output, 'output', isNull)
            .having(
              (value) => value.errors.single.phase,
              'phase',
              MambaExecutionPhase.run,
            )
            .having(
              (value) => value.errors.single.commandPath,
              'command path',
              ['task_list', 'tui'],
            ),
      );
    });
  });

  group('themes', () {
    test('every option resolves to a palette', () {
      for (final appTheme in AppTheme.values) {
        expect(
          resolveTheme(appTheme),
          isA<TuiThemeData>(),
          reason: '${appTheme.cliName} must resolve to a palette',
        );
      }
    });

    test('auto resolves to a readable default', () {
      expect(resolveTheme(AppTheme.auto), TuiThemeData.dark);
    });

    test('a named option resolves to its preset', () {
      expect(resolveTheme(AppTheme.nord), TuiThemeData.nord);
      expect(resolveTheme(AppTheme.light), TuiThemeData.light);
    });
  });
}
