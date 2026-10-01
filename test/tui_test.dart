import 'package:mamba/mamba.dart';
import 'package:task_list_cli/tui.dart';
import 'package:test/test.dart';

void main() {
  group('TuiCommand', () {
    test('shows help', () async {
      final result = await Executor('test', 'Test.', '1.0.0', [
        TuiCommand(),
      ]).fake().execute(['tui', '--help']);

      expect(result, isA<MambaSuccessResult>());
    });
  });
}
