import 'dart:convert';

import 'package:mamba/mamba.dart';

import 'path_command.dart';

final _list = NormalPositional(
  'list',
  regExp: RegExp(r'.+'),
  description: 'List name (case-insensitive) or full ID.',
);
final _newName = NormalPositional('name', regExp: RegExp(r'.+'));
final _json = BooleanFlag('json', description: 'Emit JSON for scripts.');
final _yes = BooleanFlag(
  'yes',
  short: 'y',
  description: 'Confirm permanent deletion.',
);

final class Lists extends GroupCommand {
  new() : super([ListShow(), ListAdd(), ListRename(), ListDelete()]);
  @override
  String get name => 'lists';
  @override
  String get shortDescription => 'Show, create, rename, and delete lists.';
}

final class ListShow extends Command {
  new() : super(flags: [_json]);
  @override
  String get name => 'show';
  @override
  String get shortDescription =>
      'Show every list with its persistent ID and task count.';
  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) => withService(
    inputs,
    (service) {
      if (inputs.valueOf(_json)) {
        return jsonEncode([
          for (final list in service.lists)
            {'id': list.id, 'name': list.name, 'taskCount': list.tasks.length},
        ]);
      }
      if (service.lists.isEmpty) {
        return 'No lists yet. Create one with: lists add "Personal"';
      }
      return service.lists
          .map((list) => '${list.id}\t${list.name}\t${list.tasks.length} tasks')
          .join('\n');
    },
  );
}

final class ListAdd extends Command {
  new() : super(mandatoryPositionals: [_newName]);
  @override
  String get name => 'add';
  @override
  String get shortDescription => 'Create a named list and print its ID.';
  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) => withService(
    inputs,
    (service) async => (await service.createList(inputs.valueOf(_newName))).id,
  );
}

final class ListRename extends Command {
  new() : super(mandatoryPositionals: [_list, _newName]);
  @override
  String get name => 'rename';
  @override
  String get shortDescription => 'Rename a list without changing its ID.';
  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) => withService(
    inputs,
    (service) async {
      await service.renameList(inputs.valueOf(_list), inputs.valueOf(_newName));
      return 'List renamed.';
    },
  );
}

final class ListDelete extends Command {
  new() : super(mandatoryPositionals: [_list], flags: [_yes]);
  @override
  String get name => 'delete';
  @override
  String get shortDescription =>
      'Delete a list; --yes is required if it contains tasks.';
  @override
  Future<String?> run(ParsedInputs inputs, List<String> args) =>
      withService(inputs, (service) async {
        await service.deleteList(
          inputs.valueOf(_list),
          confirmed: inputs.valueOf(_yes),
        );
        return 'List deleted.';
      });
}
