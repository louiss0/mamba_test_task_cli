# Flags

Use flags for named inputs that take no value. Register a flag in `flags` on a
`Command` or `GroupCommand` when it belongs to that command only.

```dart
final class DeployCommand extends Command {
  DeployCommand() : super(flags: [force, verbosity]);

  static const force = BooleanFlag(
    'force',
    short: 'f',
    description: 'Replace the existing deployment.',
    negatable: true,
  );

  static const verbosity = CountFlag(
    'verbose',
    short: 'v',
    description: 'Increase output verbosity.',
  );

  @override
  String get name => 'deploy';

  @override
  String get shortDescription => 'Deploy the application.';

  @override
  String run(ParsedInputs inputs, List<String> args) {
    final forceValue = inputs.valueOf(force);
    final verbosityValue = inputs.valueOf(verbosity);
    return 'force: $forceValue, verbosity: $verbosityValue';
  }
}
```

Retain each declaration and pass the same instance to
`ParsedInputs.valueOf`; declarations are identity-based typed keys.

## `BooleanFlag`

```dart
BooleanFlag(
  name,
  short: short,
  description: description,
  hidden: false,
  defaultValue: false,
  negatable: false,
)
```

A boolean flag returns `bool`. Its long spelling is `--name`; `short` adds a
one-character spelling such as `-f`. When omitted, it returns `defaultValue`.
The ordinary spelling sets it to `true`.

Set `negatable: true` to add `--no-name`, which sets the value to `false`.
Set `hidden: true` to omit it from generated help while keeping it parseable.

## `CountFlag`

```dart
CountFlag(
  name,
  short: short,
  description: description,
  hidden: false,
)
```

A count flag returns `int`. It starts at `0` and increments for each
occurrence, including repeated short aliases such as `-vv`.

## Registration scope

- `Command(flags: [...])` registers flags only for that command.
- `GroupCommand(..., flags: [...])` registers flags only for the group itself.
- `GroupCommand(..., propagatedFlags: [...])` makes flags available to the
  group and its descendants.
- `Executor(..., flags: [...])` makes flags available across the command tree.

Mamba provides these reusable declarations:

| Declaration | Spelling | Value |
| --- | --- | --- |
| `MambaBuiltInFlags.help` | `--help`, `-h` | `bool` |
| `MambaBuiltInFlags.dryRun` | `--dry-run` | `bool` |
| `MambaBuiltInFlags.verbose` | `--verbose`, `-v` | `int` |
| `MambaBuiltInFlags.version` | `--version`, `-V` | `bool` |

The executor supplies verbose and version globally. Help is built into command
registries. Register `MambaBuiltInFlags.dryRun` through `Executor.flags` when
the application supports dry-run behavior. Avoid registering inputs with
reserved names or short aliases in a scope where they collide.

## Conflicts and presence

Flags may participate in a command's `conflicts` map by long name:

```dart
DeployCommand()
  : super(
      flags: [force],
      options: [plan],
      conflicts: {
        'force': ['plan'],
      },
    );
```

`valueOf` always returns the flag's value. Parsed flags always satisfy
`inputs.contains(flag)` because Mamba materializes `false`, the configured
boolean default, or `0` after parsing. Inspecting `ParsedInputs` cannot
distinguish an omitted flag from an explicit spelling that produces the same
value.
