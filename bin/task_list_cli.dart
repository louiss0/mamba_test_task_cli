import 'package:mamba/mamba.dart';
import 'package:task_list_cli/lists.dart';
import 'package:task_list_cli/path_command.dart';
import 'package:task_list_cli/tasks.dart';
import 'package:task_list_cli/tui.dart';

Future<void> main(List<String> args) => Executor(
  'task_list_cli',
  'Persistent lists and tasks, at your fingertips.',
  '1.0.0',
  [Lists(), Tasks(), Tui(), PathCommand()],
  options: [dataDirectory],
).create().execute(args);
