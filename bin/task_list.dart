import 'package:task_list_cli/task_list_app.dart';

Future<void> main(List<String> args) =>
    createTaskListExecutor().create().execute(args);
