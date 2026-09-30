# Completion commands

Use a `CompletionCommand` to turn Mamba's validated command registry into a
completion artifact for Bash, Zsh, Fish, PowerShell, or Carapace. The registry
contains the command tree and its flags, options, positionals, aliases, and
descriptions, so completion generation stays aligned with parsing and help.

## Use the preset command

Register `CompletionCommand.preset()` in the executor's
command list to use Mamba's built-in generators:

```dart
Future<void> main(List<String> args) => Executor(
  'my-cli',
  'Manage application resources.',
  '1.0.0',
  [CompletionCommand.preset()],
).create().execute(args);
```

The preset creates a `completion` command with `cmp` and `cpt` aliases. It
accepts a required shell positional followed by an optional output path:

```console
my-cli completion bash ./my-cli.bash
my-cli completion powershell ./my-cli.ps1
my-cli completion carapace ./my-cli.yaml
```

When a path is present, its extension must match the selected shell and its
file name must contain the application name:

| Shell | Extension |
| --- | --- |
| `bash` | `.bash` |
| `zsh` | `.zsh` |
| `fish` | `.fish` |
| `powershell` | `.ps1` |
| `carapace` | `.yaml` |

`CompletionCommand.shellInput` and `CompletionCommand.pathInput` expose the
same retained declarations used by the preset. Use them with
`ParsedInputs.valueOf` when extending or testing the command.

## Replace destination handling

Pass a callback through the required named `createFile` parameter when another
system should handle the validated path:

```dart
final completion = CompletionCommand.preset(
  createFile: (path) => print('Handle completion output at $path'),
);
```

The callback replaces built-in artifact generation; it does not receive
generated content. It receives an empty string when the optional path is
omitted. Extend `CompletionCommand` when custom handling also needs access to
the registry or different input declarations.

## Build a custom completion command

The executor assigns `registryRecord` before execution. Select the converter
for the requested output and call `convert()`:

```dart
final content = switch (shell) {
  ShellCompletion.bash =>
    ToBashCompletionConverter(registryRecord).convert(),
  ShellCompletion.zsh => ToZshCompletionConverter(registryRecord).convert(),
  ShellCompletion.fish =>
    ToFishCompletionConverter(registryRecord).convert(),
  ShellCompletion.powershell =>
    ToPowerShellCompletionConverter(registryRecord).convert(),
  ShellCompletion.carapace => CarapaceSpecConverter(registryRecord).convert(),
};
```

## Inspect the registry record

Treat `registryRecord` as an immutable typed description, not a map. The root
is a `RegistryRecord`; its `commands` recursively contain `RegistryCommand`
objects. Nullable collections mean that the command has no entries of that
kind, so traverse them with `?? const []`.

### `RegistryCommand`

A `RegistryCommand` is one command-tree node. Use:

- `name` for its canonical command token and `aliases` for equivalent tokens;
- `description` for its combined short and optional long help text;
- `commands` for direct children;
- `positionals` and `variadic` for ordered and post-`--` values;
- `flags`, `options`, `optionGroups`, and `accessors` for its named inputs; and
- `persistentFlags` and `persistentOptions` for inputs that converters should
  carry into descendants.

Build the command path while recursing through `commands`. Records produced by
`CommandRegistry.toMap()` already place effective inherited inputs in each
command's `flags`, `options`, and `accessors`; their `persistentFlags` and
`persistentOptions` are currently `null`.

### `RegistryPositional`

List order determines the parse position. `name` and `description` provide
display text, while `required` distinguishes mandatory from discretionary
values. Offer `choices` directly when present. `defaultValue` is textual,
`pattern` contains the validation expression, and `repeatable == true` pairs
with `times` to describe an exact repeated count.

### `RegistryFlag`

`name` and `short` omit their leading dashes. `defaultValue` and `negatable`
describe boolean flags; both are `null` for flag kinds without boolean
semantics. A negatable flag also has a `--no-<name>` spelling. Suppress an
entry when `hidden` is true and use `description` as candidate help text.

### `RegistryOption`

Use `name`, `short`, `hidden`, and `description` for spelling and display.
`required`, `repeatable`, and `unique` describe cardinality. Interpret
`valueType` as `string`, `int`, `double`, or `choice`, then use the applicable
validation metadata:

- offer `choices` as finite candidates;
- treat `defaultValue` as text, including comma-separated list defaults;
- retain `pattern` for string validation; and
- use `min`, `max`, and `step` for bounded numeric candidates.

`pairedOptions` names every member of the same all-or-nothing paired group.

### `RegistryOptionGroup`

`members` lists the option names in one `PairedOptions` declaration. Supplying
one member requires all members. `required` controls whether the whole group
may be omitted. Selected-option groups are flattened into `options` and do not
produce `RegistryOptionGroup` values.

### `RegistryAccessor`

Switch on `kind` before reading variant fields:

- A `group` has `name`, `hidden`, `description`, and recursive `options`.
- A `value` has `name`, `valueType`, `description`, `choices`, `defaultValue`,
  and `pattern`.

Join ancestor and leaf names with `.` to form the long spelling. For example,
the `certificate` value below `server` and `tls` becomes
`--server.tls.certificate`. A hidden group hides its descendant leaves.

Use the unnamed `CompletionCommand` constructor to supply custom positionals
or options. Access `registryRecord` during `run`, after the executor has
initialized the command tree.
