# AGENTS.md

This project is a Mamba command-line application. The `mamba` skill installed
in this project documents the Mamba API; this file documents driving the
`mamba` CLI.

## The mamba CLI

Four commands write files. Run `mamba --help` for the full surface.

| Command | Writes | Use it to |
| --- | --- | --- |
| `mamba command <name>` | `lib/<name>.dart` | Start a command. |
| `mamba command <name> --group` | `lib/<name>.dart` | Start a command that owns child commands. |
| `mamba command <name> --test` | `lib/<name>.dart` and its suite | Start a command with tests. |
| `mamba command <name> --append <file>` | appends to `<file>` | Add a command to an existing file. |
| `mamba test <name>` | `test/<name>_test.dart` | Add a suite for an existing command. |
| `mamba binary <name>` | `bin/<name>.dart` | Add a second executable. |

`<file>` and `--append` require each other, so pass both or neither. `mamba
test` mirrors `lib/a/b.dart` to `test/a/b_test.dart` and rejects a source file
outside `lib/`.

## What the application is

`task_list` is a persistent task manager. Tasks live in named lists and are
saved as indented JSON in the platform user data directory. Two front ends sit
on one application layer: a Mamba CLI and an interactive terminal interface
built with `nocterm`.

```text
       CLI        TUI
        \          /
         \        /
      TaskBook (application)
             |
      TaskBookState (domain)
             |
      TaskRepository
             |
      BookCodec + json_serializable
             |
        task_book.json
```

| Directory | Holds | Depends on |
| --- | --- | --- |
| `lib/domain/` | `Task`, `TaskList`, `TaskFilter`, naming rules | nothing |
| `lib/persistence/` | the repository, the JSON codec, storage paths | `lib/domain/` |
| `lib/application/` | `TaskBook`, the operations both front ends call | `lib/domain/`, `lib/persistence/` |
| `lib/presentation/` | table and timestamp formatting shared by the front ends | `intl` |
| `lib/cli/` | input rules and the mapping from application errors to exit codes | `lib/application/` |
| `lib/tui/` | `TaskScreen` state and the `nocterm` components | `lib/application/` |
| `lib/lists.dart`, `lib/tasks.dart`, `lib/tui.dart` | the Mamba commands | `lib/cli/`, `lib/application/` |

Rules the layering exists to enforce:

- **The JSON format lives in `lib/persistence/` alone.** Neither front end
  reads or writes it. Add a persisted field by editing the DTOs in
  `persisted_state.dart`, bumping `currentSchemaVersion`, and adding a step to
  the migration chain in `book_codec.dart`.
- **Every change goes through `TaskRepository.update`.** It re-reads the file
  under a lock, applies the change to what is on disk, and saves. Writing a
  caller's in-memory state back wholesale would lose another process's edits.
- **Only mutations write.** Selecting a list, changing the filter, and
  navigating never call `update`.
- **`TaskScreen` holds the interactive state, not a widget.** It can be driven
  directly in tests, which is why the interface's behaviour is testable without
  a terminal.
- **Selection is a task identifier, never a row number.** A task stays selected
  while the list around it is filtered, sorted, or edited.

## What not to do

- **Do not hand-write `lib/` or `test/` Dart files.** Scaffold each command and
  each suite with `mamba command` and `mamba test`, so imports, class names,
  and mirrored paths stay correct.
- **Do not leave a scaffolded command unwired.** It runs nothing until its
  instance reaches the executor's command list or its parent's constructor.
- **Do not call `Executor.fake()` from `bin/`.** Call `create()` in the
  executable and keep `fake()` in `test/`.
- **Do not report a rejected invocation by returning a string.** Return the
  success message, and throw `MambaException` when the invocation cannot be
  honoured.
- **Do not expect scaffolding to run the application.** `mamba create` runs
  `dart pub get` and installs the Mamba skills; every other command only writes
  files.
- **Do not let a command fall back to the real data directory on its own.**
  Commands take a non-nullable `TaskRepository` and `resolveRepository` is the
  single place the default is chosen, so a test can never touch the user's
  tasks by accident.
- **Do not build a filter that only handles the three completion states.**
  `TaskFilter` is sealed and composes with `and`; add a subtype instead.
- **Do not hand-format JSON.** Change the DTOs and re-run `dart run
  build_runner build`.

## Testing

Run `dart analyze` and `dart test`. Suites mirror their source file:

| Suite | Covers |
| --- | --- |
| `test/application/task_book_test.dart` | list and task CRUD, completion, filtering, isolation, persistence |
| `test/persistence/book_codec_test.dart` | serialization, deserialization, and every rejection the decoder makes |
| `test/persistence/json_task_repository_test.dart` | reads, writes, safe replacement, locking, damaged files |
| `test/persistence/storage_locations_test.dart` | where the data lives |
| `test/tui/task_screen_test.dart` | the interactive state machine |
| `test/tui/task_list_app_test.dart` | the real `nocterm` component tree, driven through `NoctermTester` |
| `test/lists_test.dart`, `test/tasks_test.dart`, `test/ui_test.dart`, `test/task_list_app_test.dart` | the CLI, one suite per command tree |

`test/support/test_workspace.dart` holds the shared helpers: a temporary
directory, a reproducible identifier source, and a write-counting repository
decorator. Pass a `TaskRepository` to a command to keep a test out of the real
data directory.
