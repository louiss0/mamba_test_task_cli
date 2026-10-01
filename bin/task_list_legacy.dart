import 'package:mamba/mamba.dart';
import 'package:task_list_cli/legacy/lists.dart';
import 'package:task_list_cli/legacy/path_command.dart';
import 'package:task_list_cli/legacy/tasks.dart';
import 'package:task_list_cli/legacy/tui.dart';

/// The original flat implementation, kept alongside the layered rewrite.
///
/// `bin/task_list_cli.dart` runs the layered implementation in
/// `lib/domain`, `lib/application` and `lib/persistence`. This entry point
/// runs the original flat implementation preserved under `lib/legacy`.
Future<void> main(List<String> args) => Executor(
  'task_list_legacy',
  'Persistent lists and tasks, at your fingertips.',
  '1.0.0',
  [Lists(), Tasks(), Tui(), PathCommand()],
  options: [dataDirectory],
).create().execute(args);
