import 'dart:convert';

import 'package:mamba/mamba.dart';

import 'models.dart';
import 'path_command.dart';

final _list = NormalPositional(
  'list',
  regExp: RegExp(r'.+'),
  description: 'List name or full ID.',
);
final _id = NormalPositional(
  'id',
  description: 'Full persistent task ID, not a row number.',
);
final _title = NormalPositional('title', regExp: RegExp(r'.+'));
final _filter = ChoiceOption.withDefault(
  'filter',
  choices: TaskFilter.values,
  defaultValue: TaskFilter.all,
  short: 'f',
  description: 'all, incomplete, or completed',
);
final _json = BooleanFlag('json', description: 'Emit JSON for scripts.');
final _yes = BooleanFlag(
  'yes',
  short: 'y',
  description: 'Confirm permanent task deletion.',
);

final class Tasks extends GroupCommand {
  new()
    : super([
        TaskShow(),
        TaskAdd(),
        TaskEdit(),
        TaskComplete(),
        TaskReopen(),
        TaskDelete(),
      ]);
  @override
  String get name => 'tasks';
  @override
  String get shortDescription => 'Manage tasks in a named list.';
}

final class TaskShow extends Command {
  new()
    : super(mandatoryPositionals: [_list], options: [_filter], flags: [_json]);
  @override
  String get name => 'show';
  @override
  String get shortDescription =>
      'Open a list; show tasks with a completion filter.';
  @override
  Future<String?> run(
    ParsedInputs inputs,
    List<String> args,
  ) => withService(inputs, (service) {
    final list = service.getList(inputs.valueOf(_list));
    final filter = inputs.valueOf(_filter);
    final tasks = service.query(list.id, filter: filter);
    if (inputs.valueOf(_json)) {
      return jsonEncode({
        'list': {'id': list.id, 'name': list.name},
        'filter': filter.name,
        'tasks': tasks
            .map((task) => StoredTask.fromDomain(task).toJson())
            .toList(),
      });
    }
    final heading = '${list.name} | ${filter.label} | ${tasks.length} tasks';
    if (tasks.isEmpty) {
      return '$heading\nNo matching tasks. Add one with: tasks add "${list.name}" "Task title"';
    }
    return '$heading\n${tasks.map((task) => '${task.id}\t[${task.completed ? 'x' : ' '}]\t${task.title}').join('\n')}';
  });
}

final class TaskAdd extends Command {
  new() : super(mandatoryPositionals: [_list, _title]);
  @override
  String get name => 'add';
  @override
  String get shortDescription => 'Add a task and print its persistent ID.';
  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) => withService(
    inputs,
    (service) async => (await service.createTask(
      inputs.valueOf(_list),
      inputs.valueOf(_title),
    )).id,
  );
}

final class TaskEdit extends Command {
  new() : super(mandatoryPositionals: [_list, _id, _title]);
  @override
  String get name => 'edit';
  @override
  String get shortDescription => 'Change a task title.';
  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      withService(inputs, (service) async {
        await service.editTask(
          inputs.valueOf(_list),
          inputs.valueOf(_id),
          inputs.valueOf(_title),
        );
        return 'Task updated.';
      });
}

final class TaskComplete extends Command {
  new() : super(mandatoryPositionals: [_list, _id]);
  @override
  String get name => 'complete';
  @override
  String get shortDescription => 'Mark a task completed without deleting it.';
  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      withService(inputs, (service) async {
        await service.setCompletion(
          inputs.valueOf(_list),
          inputs.valueOf(_id),
          Completion.completed,
        );
        return 'Task completed.';
      });
}

final class TaskReopen extends Command {
  new() : super(mandatoryPositionals: [_list, _id]);
  @override
  String get name => 'reopen';
  @override
  String get shortDescription => 'Mark a completed task incomplete again.';
  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      withService(inputs, (service) async {
        await service.setCompletion(
          inputs.valueOf(_list),
          inputs.valueOf(_id),
          Completion.incomplete,
        );
        return 'Task reopened.';
      });
}

final class TaskDelete extends Command {
  new() : super(mandatoryPositionals: [_list, _id], flags: [_yes]);
  @override
  String get name => 'delete';
  @override
  String get shortDescription => 'Permanently delete a task (requires --yes).';
  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      withService(inputs, (service) async {
        await service.deleteTask(
          inputs.valueOf(_list),
          inputs.valueOf(_id),
          confirmed: inputs.valueOf(_yes),
        );
        return 'Task deleted.';
      });
}
