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
