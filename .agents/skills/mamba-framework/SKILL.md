---
name: mamba
description: Develop and test Dart CLI applications that use Mamba. Use when adding or changing executors, commands, command groups, typed inputs, injected dependencies, hooks, context, standard input, output, errors, help, or shell completions.
compatibility: requires mamba cli and dart cli
---


Mamba is the CLI framework for making CLI's! It's main focus is on `Executor.create` and `Executor.fake`.
The call to `create` always belongs in a root dart file! The `fake` function should always be called in test files.

It's framework that supports flags and options as separate concepts.
Flags that make a boolean are called boolean flags! The ones that return an incrementing number are called count flags.

When it comes to options there's a difference between single and repatable options! 
The single options are the ones that will make scalar values! While the repeatable ones will make value lists.
An option that has dots it's name is called an _accessor_. These types of flags are meant to represent nested dot operator access!

When it comes to arguments they are called _positionals_. 
The required ones are the ones mandatory positionals they are always on the left.
The optional ones are the ones that are not required and are after mandatory positionals.
Any unparsed values are called _variadics_.


Before the first task always look for a file that looks like this! 

```dart
import 'package:mamba/mamba.dart';

void main(List<String> args) {
  Executor().create();
}
```

If there are multiple files that have calls to `Executor.create` then please ask which one will be the one that's worked on!
When it's clear which file has the executor that needs to be changed then work!

## Executor

Use `Executor` as the application's composition root. Pass the application
name, short description, semantic version, and root commands in that order:

```dart
Future<void> main(List<String> args) => Executor(
  'acme',
  'Manage Acme deployments.',
  '1.0.0',
  [Deploy(), Workspace()],
).create().execute(args);
```

Keep this call in the executable's `main` function. `create()` connects the
executor to the current process, and `execute(args)` parses and runs the
selected command.

Register an input on the executor when every command must be able to read the
same declaration. Retain the declaration outside the executor call so
commands can pass that exact instance to `ParsedInputs.valueOf`:

```dart
final profile = StringOption.withDefault(
  'profile',
  defaultValue: 'development',
);

Future<void> main(List<String> args) => Executor(
  'acme',
  'Manage Acme deployments.',
  '1.0.0',
  [DeployCommand()],
  options: [profile],
  flags: [MambaBuiltInFlags.dryRun],
).create().execute(args);
```

Every executor already supplies help, version (`-V`, `--version`), and
verbosity (`-v`, `--verbose`). Dry-run is reusable but opt-in. Use `flags`,
`options`, and `accessors` for root inputs, `defaultCommandPath` to select a
command for an empty invocation, `context` for hook state, and `helpFormatter`
to replace help rendering.


## Commands

Use `Command` for an executable action and `GroupCommand` for a named branch
that owns child commands. Start a command in its own file:
Declare each input once, register it through `super`, and retain that same
declaration for `run`. Keep declarations private, then give the parsed value a domain name inside `run`:

```dart
final class Deploy extends Command {
  new() : super(mandatoryPositionals: [_environment], flags: [_force]);

  static final _environment = NormalPositional('environment');
  static final _force = BooleanFlag(
    'force',
    short: 'f',
    description: 'Replace the current deployment.',
  );

  @override
  String get name => 'deploy';

  @override
  String get shortDescription => 'Deploy the application.';

  @override
  String run(ParsedInputs inputs, List<String> args) {
    final environment = inputs.valueOf(_environment);
    final force = inputs.valueOf(_force);
    return 'Deploying to $environment (force: $force).';
  }
}
```

Read the matching API reference before choosing declarations. Register
required unnamed values in `mandatoryPositionals`, optional unnamed values in
`discretionaryPositionals`, switches in `flags`, named values in `options`,
and dotted trees in `accessors`. Use `args` only for values after `--`.

Create a group and append related commands to the same source file:
A group receives its children through `super` and may register inputs for
itself or propagate inputs to descendants:

```dart
final class Workspace extends GroupCommand {
  new() : super([Deploy()]);

  @override
  String get name => 'workspace';

  @override
  String get shortDescription => 'Manage workspaces.';
}
```

After creating or editing a command, register the root command in the
executor or the child command in its parent group's command list.

## References 

- [Arguments](references/arguments.md) for mandatory and discretionary
  positionals or values after `--`.
- [Flags](references/flags.md) for boolean switches and occurrence counters.
- [Options](references/options.md) for scalar, repeatable, paired, selected, or dotted accessor values.
- [Completions](references/completion-commands.md) for how to register completions 
- [Hooks](references/hook-runners.md) for how to use hooks
- [Testing](references/testing.md) before writing or changing command tests;
  it defines command-tree groups, parameterized cases, input and hook coverage,
  and complete result assertions.
