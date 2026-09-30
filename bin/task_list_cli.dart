import 'package:mamba/mamba.dart';

Future<void> main(List<String> args) => Executor(
  'task_list_cli',
  'This application is a task list app',
  '0.0.0',
  [],
).create().execute(args);
