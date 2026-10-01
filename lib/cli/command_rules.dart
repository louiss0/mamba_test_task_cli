/// The two rules every command in this application follows about its inputs.
///
/// Both exist so the decisions are made once, in one place, rather than
/// repeated in each command where they could drift apart.
library;

import '../persistence/json_task_repository.dart';

/// Accepts any non-empty run of characters, spaces included.
///
/// Mamba's default for a positional is `\S+`, which would split or reject a
/// name like `Weekly Review` or a title like `Buy milk` before the command ever
/// saw it. Trimming and the real rules live in the domain, which is the one
/// place that gets to decide what a valid name or title is.
final RegExp freeText = RegExp(r'.+');

/// Returns the repository a command should read and write through.
///
/// The default lives here, in the one place every command tree passes through.
/// Commands take a non-nullable repository, so no leaf command can quietly
/// fall back to the user's real data on its own.
TaskRepository resolveRepository(TaskRepository? repository) =>
    repository ?? TaskRepository.onDisk();
