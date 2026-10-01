# Task List CLI

A persistent task manager with a keyboard-first **Nocterm** terminal interface and independent, automation-friendly **Mamba** commands. Data is readable, versioned JSON—no database.

## Run

Requires Dart 3.13.2 or newer:

```sh
dart pub get
dart run bin/task_list_cli.dart --help
dart run bin/task_list_cli.dart tui
```

An empty invocation displays help. The TUI requires interactive stdin and stdout; use commands when piping or scripting.

Build a standalone executable (create `build/` first):

```sh
dart compile exe bin/task_list_cli.dart -o build/task_list_cli
```

On Windows, use `build/task_list_cli.exe` as the output path. Alternatively, install with `dart pub global activate --source path .` to make `task_list_cli` available on your PATH.

## Commands

The examples below use the installed or compiled `task_list_cli` executable. From source, substitute `dart run bin/task_list_cli.dart`.

```sh
task_list_cli lists add "Personal"
task_list_cli lists add "Work"
task_list_cli lists show
task_list_cli lists show --json
task_list_cli lists rename "Work" "Projects"

task_list_cli tasks add "Personal" "Buy milk"
task_list_cli tasks show "Personal"
task_list_cli tasks show "Personal" --filter incomplete
task_list_cli tasks show "Personal" --filter completed --json

task_list_cli tasks edit "Personal" TASK_ID "Buy milk and bread"
task_list_cli tasks complete "Personal" TASK_ID
task_list_cli tasks reopen "Personal" TASK_ID
task_list_cli tasks delete "Personal" TASK_ID --yes
task_list_cli lists delete "Projects" --yes

task_list_cli path
```

`lists add` and `tasks add` print only the newly created UUID, making it easy to capture in scripts. Replace `TASK_ID` with that **full ID**, never a visible row number. Lists accept their name (case-insensitive) or full UUID. Quote multi-word titles and names.

- List names are trimmed, case-insensitively unique, and 1–80 characters. UUID-shaped names are reserved to avoid ambiguity with IDs.
- Task titles are trimmed and 1–500 characters. Names/titles cannot contain control characters.
- Normal output uses tab-separated IDs and `[ ]` / `[x]` completion markers.
- `lists show --json` emits an array of `{id, name, taskCount}` records.
- `tasks show LIST --json` emits `{list: {id, name}, filter, tasks}`. Task records contain `id`, `title`, `completed`, and `createdAt`.
- `--filter` / `-f` accepts `all` (default), `incomplete`, or `completed`.
- Task deletion always requires `--yes` / `-y`; nonempty list deletion does too. Commands never prompt for terminal input.
- Success exits 0. Invalid arguments, missing entities, confirmation failures, locking and storage errors exit 1 with diagnostics on stderr.
- Use `--help` on a group or command for its input declarations.

## Terminal UI

The sidebar shows all lists and task counts. The task pane shows the selected list's filtered tasks; the header always displays the current list and filter. The selected task's full ID and creation date appear below the panes.

| Key | Action |
| --- | --- |
| Tab / Left / Right | Switch focused pane |
| Up / Down / j / k | Select list or task |
| Home / End | First / last item |
| Page Up / Page Down | Move ten items |
| n | Create a list or task in the focused pane |
| e | Rename list or edit task title |
| Space / x | Complete or reopen selected task |
| d / Delete | Delete selected list or task after confirmation |
| 1 / 2 / 3 | All / Incomplete / Completed |
| f | Cycle completion filters |
| ? / F1 | Keyboard help |
| q | Quit |

Forms use Nocterm's text field: Enter saves, Esc cancels. Errors remain in the form so they can be corrected. Confirmation dialogs default to cancellation: only `y` deletes; `n` or Esc cancels, and Enter does not confirm. Both task and list deletions are confirmed in the TUI, including empty lists. Creating a task switches to All and selects the new task so it is visible. Completing a task in the Incomplete filter immediately removes it from that view after saving succeeds.

Every successful mutation is saved immediately; there is no separate Save action. Navigation, filtering and dialogs do not write task data. Use a terminal at least 48 columns by 14 rows; wider terminals provide more room for titles. All terminal rendering, text editing, keyboard input, styling, scrolling and dialogs are handled by Nocterm.

## Storage and recovery

`task_list_cli path` prints the exact JSON path without opening it. Default paths are located by `app_dirs`:

- Windows: `%APPDATA%\task-list-cli\data\tasks.json`
- macOS: under `~/Library/Application Support/`
- Linux: `$XDG_DATA_HOME/task-list-cli/tasks.json`, falling back to `~/.local/share/task-list-cli/tasks.json`

Override explicitly with a global option (before the command):

```sh
task_list_cli --data-dir "/my/task-data" lists show
```

Or set `TASK_LIST_DATA_DIR`. Precedence: option → environment → OS default. The current working directory is never the default storage location. Tests use temporary directories, not real user data.

Version 1 stores:

```json
{
  "version": 1,
  "lists": [
    {
      "id": "11111111-1111-4111-8111-111111111111",
      "name": "Personal",
      "tasks": [
        {
          "id": "22222222-2222-4222-8222-222222222222",
          "title": "Buy milk",
          "completed": false,
          "createdAt": "2026-01-02T03:04:00.000Z"
        }
      ]
    }
  ]
}
```

Checked generated DTO decoding validates field types and rejects unknown fields. Domain validation checks IDs, text constraints, unique names/IDs, and canonical UTC timestamps. Unsupported schema versions are rejected, not guessed or silently migrated.

**If loading fails, the original JSON is never reset or overwritten.** The diagnostic includes its path. Close the app, back up that file, and repair the reported problem. To intentionally start over, move the damaged JSON elsewhere yourself. Keep it for later recovery. Help and `path` still work when JSON is invalid.

Writes stage a unique temporary file beside the destination, flush it, and use Dart's OS-backed rename/replacement primitive. The active JSON is never truncated or explicitly deleted before replacement. Only after persistence succeeds does the service publish the new in-memory snapshot. Tests exercise replacement failures and ensure failed saves preserve disk and memory. This protects against process interruption during writing; it is not a guarantee against all power loss or unusual/network filesystem behavior. Keep backups for important data.

A lightweight OS-exclusive lock on `tasks.json.lock` is held for each command/session (including the whole TUI session). A second cooperating instance fails clearly rather than overwriting a stale snapshot. The lock file is intentionally retained; the OS releases its lock on close or process termination. Do **not** delete a lock file while another instance is running. Close the TUI before using CLI commands against the same directory. External editors do not honor this lock: edit JSON only while all app sessions are closed. Filesystems that do not implement reliable locking/replacement are not supported for concurrent use.

## Architecture and development

- `lib/models.dart`: immutable validated domain types, completion filters and versioned persistence DTOs.
- `lib/models.g.dart`: checked JSON conversion generated by `json_serializable`.
- `lib/repository.dart`: app-directory location, load validation, locking, safe JSON writes and recovery diagnostics.
- `lib/service.dart`: shared CRUD operations, list isolation, confirmation policy and save-before-publish transactions.
- `lib/lists.dart`, `lib/tasks.dart`, `lib/path_command.dart`: Mamba commands and session adapter.
- `lib/ui.dart`, `lib/tui.dart`: Nocterm components and terminal entry point, with no filesystem/JSON logic in widgets.
- `bin/task_list_cli.dart`: production executor composition root.

Infrastructure choices: Mamba handles argument parsing, `json_serializable`/`json_annotation` handle typed serialization, `dart:convert` encodes/decodes JSON, `app_dirs` resolves platform data paths, `path` handles filesystem paths, `uuid` generates identities, and Nocterm owns terminal infrastructure. Dart's built-in `dart:io` supplies OS locking and same-directory replacement; no unrelated audio/database package is pulled in merely for a filesystem helper. Domain filtering and CRUD remain ordinary application logic.

```sh
dart run build_runner build
dart format lib bin test
dart analyze
dart test
```

Generated JSON code is committed; regeneration is only needed when the DTOs change. The suite covers domain validation and serialization, service CRUD and filter isolation, persistence/restarts, invalid data recovery, write failure behavior, a second-process lock check, CLI result/error contracts, and Nocterm keyboard-driven forms, navigation, completion/filter transitions, confirmation, error handling and scrolling.
