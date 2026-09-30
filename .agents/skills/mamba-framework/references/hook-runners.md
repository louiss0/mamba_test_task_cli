# Hook runners

Use hook runners for lifecycle behavior that surrounds command execution.
Hooks receive the selected invocation's `ParsedInputs`, and may complete
synchronously or return a `Future`.

## Contents

- [Choose a hook runner](#choose-a-hook-runner)
- [Wrap one command](#wrap-one-command)
- [Wrap group descendants](#wrap-group-descendants)
- [Understand execution order](#understand-execution-order)
- [Read input and share state](#read-input-and-share-state)

## Choose a hook runner

| Mixin | Apply to | Scope | Context |
| --- | --- | --- | --- |
| `HookRunner` | `Command` | That command's `run` call | Read-only `MambaReadContext` |
| `PersistentHookRunner` | `GroupCommand` | Any selected descendant | Mutable `MambaContext` |

Use `HookRunner` for behavior owned by one command, such as validation,
instrumentation, or command-local cleanup. Use `PersistentHookRunner` for a
group concern that wraps every descendant, such as authentication, tracing,
or shared state setup.

## Wrap one command

Mix `HookRunner` into a command and implement `preRun`. Override `postRun` only
when cleanup or follow-up behavior is required:

```dart
final class DeployCommand extends Command with HookRunner {
  @override
  String get name => 'deploy';

  @override
  String get shortDescription => 'Deploy the application.';

  @override
  FutureOr<void> preRun(
    ParsedInputs inputs,
    MambaReadContext context,
    ProcessedStandardInput? input,
  ) {}

  @override
  FutureOr<void> postRun(
    ParsedInputs inputs,
    MambaReadContext context,
  ) {}

  @override
  String run(ParsedInputs inputs, List<String> args) => 'Deployed.';
}
```

`preRun` is the only hook that receives processed standard input. A successful
`preRun` makes `postRun` eligible, even when `run` later fails. If `preRun`
fails, Mamba skips both `run` and `postRun`. Pass `standardInput` to
`Executor.fake()` to supply input in a test.

## Wrap group descendants

Mix `PersistentHookRunner` into a group to surround execution anywhere below
that group:

```dart
final class WorkspaceCommand extends GroupCommand
    with PersistentHookRunner {
  new() : super([DeployCommand()]);

  @override
  String get name => 'workspace';

  @override
  String get shortDescription => 'Manage the workspace.';

  @override
  FutureOr<void> prePersistentRun(
    ParsedInputs inputs,
    MambaContext context,
  ) {}

  @override
  FutureOr<void> postPersistentRun(
    ParsedInputs inputs,
    MambaContext context,
  ) {}
}
```

Persistent pre-hooks run from the outermost selected group inward. Successful
pre-hooks are remembered and their post-hooks run in reverse order. This
unwinds nested groups like wrappers, including after a command or cleanup
failure. A failed persistent pre-hook prevents deeper hooks and the command
from running, then unwinds the outer hooks that already succeeded.

## Understand execution order

For a nested command with both mixins, Mamba executes:

1. Persistent pre-hooks, outermost to innermost.
2. The selected command's `preRun`.
3. The selected command's `run`.
4. The selected command's `postRun` when `preRun` succeeded.
5. Persistent post-hooks, innermost to outermost.

## Read input and share state

Use `inputs.valueOf` with the same retained declaration instances registered
on the command. In `preRun`, inspect `ProcessedStandardInput.bytes`, `text`,
`utf8Text`, or `json`; the value is `null` when no input is available.

Ordinary hooks receive `MambaReadContext`, so they can read but not mutate
executor state. Persistent hooks receive `MambaContext`, so they can store
scalar state under retained `MambaContextKey<T>` instances for descendant and
ordinary hooks. The context belongs to the executor and survives when that
executor instance is reused.

Mamba records hook exceptions as `MambaExecutionError` values with the hook's
execution phase and command path. Cleanup continues through the remaining
eligible post-hooks, and the first recorded failure determines the result's
exit code.
