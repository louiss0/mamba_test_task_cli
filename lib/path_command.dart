import 'dart:async';
import 'dart:io';

import 'package:mamba/mamba.dart';
import 'package:path/path.dart' as p;

import 'models.dart';
import 'repository.dart';
import 'service.dart';

final dataDirectory = StringOption.withDefault(
  'data-dir',
  defaultValue:
      Platform.environment['TASK_LIST_DATA_DIR'] ??
      JsonRepository.defaultDirectory(),
  regex: RegExp(r'.+'),
  description: 'Override the application data directory.',
);

/// Opens only for an actual command, so help never locks or decodes user data.
Future<String?> withService(
  ParsedInputs inputs,
  FutureOr<String?> Function(TaskService service) operation,
) async {
  JsonRepository? repository;
  try {
    repository = await JsonRepository.open(inputs.valueOf(dataDirectory));
    return await operation(TaskService(repository));
  } on TaskFailure catch (error) {
    throw MambaException(error.message, exitCode: 1);
  } finally {
    await repository?.close();
  }
}

final class PathCommand extends Command {
  @override
  String get name => 'path';
  @override
  String get shortDescription =>
      'Print the JSON storage path (without opening it).';
  @override
  String run(ParsedInputs inputs, List<String> args) =>
      p.join(p.absolute(inputs.valueOf(dataDirectory)), 'tasks.json');
}
