# Testing

Test a Mamba application at its porcelain boundary: pass command-line tokens
to `Executor.fake().execute(...)`, then assert the complete structured result.
Use Git-shaped examples and organize the test suite like the command tree so a
failure immediately identifies the affected command path.

## Mirror the command tree

Every `group()` must be affiliated with the executor or a command. Name groups
with command tokens rather than class names, implementation concepts, or broad
labels such as `success cases`.

```dart
void main() {
  group('git', () {
    group('commit', () {
      test('records staged changes', () async {});
    });

    group('remote', () {
      test('shows its child commands', () async {});

      group('add', () {
        test('adds a named remote', () async {});
      });

      group('remove', () {
        test('removes a named remote', () async {});
      });
    });
  });
}
```

The outer `git` group belongs to the executor. A root `Command` gets one group
inside it. A `GroupCommand` gets one group containing a nested group for every
child command, including when a child has only one test. Put a test directly
inside a group only when it exercises behavior owned by that exact command
path. Test descriptions state behavior without repeating the path:

```dart
group('commit', () {
  test('records the selected path', () async {});
  test('requires a message', () async {});
});
```

Create a fresh fake executor in each test unless the behavior under test is
executor reuse. This keeps command and context state local to the test that
creates it.

## Assert the result contract

Every success assertion covers the result variant, zero exit code, and exact
output. Assert `null` explicitly when silence is the intended output.

```dart
expect(
  result,
  isA<MambaSuccessResult>()
      .having((value) => value.exitCode, 'exit code', 0)
      .having((value) => value.output, 'output', 'Committed README.md.'),
);
```

Every failure assertion covers the result variant, non-zero exit code,
surfaced message, output, error phase, and resolved command path. The
`message` assertion is mandatory: it proves the user receives the intended
diagnostic instead of only proving that an internal failure exists.

```dart
expect(
  result,
  isA<MambaFailureResult>()
      .having((value) => value.exitCode, 'exit code', 64)
      .having(
        (value) => value.message,
        'message',
        'Option --message is required.',
      )
      .having((value) => value.output, 'output', isNull)
      .having((value) => value.errors, 'errors', hasLength(1))
      .having(
        (value) => value.errors.single.phase,
        'phase',
        MambaExecutionPhase.parse,
      )
      .having(
        (value) => value.errors.single.commandPath,
        'command path',
        ['git', 'commit'],
      ),
);
```

Use the exact message when it is part of the command's contract. For several
failures collected during cleanup, assert the ordered message and phase lists:

```dart
expect(
  failure.errors.map((error) => error.exception.message),
  ['fatal: push rejected', 'failed to close transport'],
);
expect(
  failure.errors.map((error) => error.phase),
  [MambaExecutionPhase.run, MambaExecutionPhase.postRun],
);
```

## Test a single command and its inputs

Exercise inputs through the command rather than calling `Parser` directly.
The command's output or injected dependency should expose the values it
received.

```dart
final class CommitCommand extends Command {
  new({this.hasStagedChanges = true})
    : super(
        mandatoryPositionals: [_path],
        flags: [_amend],
        options: [_message],
      );

  static final _path = NormalPositional('path');
  static final _amend = BooleanFlag('amend');
  static final _message = StringOption.required('message', short: 'm');

  final bool hasStagedChanges;

  @override
  String get name => 'commit';

  @override
  String get shortDescription => 'Record changes.';

  @override
  String run(ParsedInputs inputs, List<String> args) {
    if (!hasStagedChanges) {
      throw MambaException('nothing to commit, working tree clean');
    }
    final path = inputs.valueOf(_path);
    final message = inputs.valueOf(_message);
    final amend = inputs.valueOf(_amend);
    final action = amend ? 'Amended' : 'Committed';
    return '$action $path with message: $message';
  }
}
```

Place parameterized cases inside the command's group. Keep one record per
behavior and create the executor inside each generated test. The case name
describes the behavior; the surrounding groups supply the `git commit` path.
Use separate case tables when success and failure require different expected
fields, but keep both loops directly inside the `commit` group:

```dart
group('git', () {
  group('commit', () {
    final successCases = [
      (
        name: 'records a path with a message',
        command: CommitCommand(),
        arguments: ['commit', 'README.md', '-m', 'Document testing'],
        output: 'Committed README.md with message: Document testing',
      ),
      (
        name: 'amends the previous commit',
        command: CommitCommand(),
        arguments: [
          'commit',
          'README.md',
          '--message',
          'Clarify testing',
          '--amend',
        ],
        output: 'Amended README.md with message: Clarify testing',
      ),
    ];

    for (final testCase in successCases) {
      test(testCase.name, () async {
        final result = await Executor(
          'git',
          'Track source changes.',
          '1.0.0',
          [testCase.command],
        ).fake().execute(testCase.arguments);

        expect(
          result,
          isA<MambaSuccessResult>()
              .having((value) => value.exitCode, 'exit code', 0)
              .having((value) => value.output, 'output', testCase.output),
        );
      });
    }

    final failureCases = [
      (
        name: 'requires a message',
        command: CommitCommand(),
        arguments: ['commit', 'README.md'],
        message: 'Option --message is required.',
        phase: MambaExecutionPhase.parse,
      ),
      (
        name: 'surfaces a clean working tree',
        command: CommitCommand(hasStagedChanges: false),
        arguments: ['commit', 'README.md', '-m', 'Document testing'],
        message: 'nothing to commit, working tree clean',
        phase: MambaExecutionPhase.run,
      ),
    ];

    for (final testCase in failureCases) {
      test(testCase.name, () async {
        final result = await Executor(
          'git',
          'Track source changes.',
          '1.0.0',
          [testCase.command],
        ).fake().execute(testCase.arguments);

        expect(
          result,
          isA<MambaFailureResult>()
              .having((value) => value.exitCode, 'exit code', 1)
              .having(
                (value) => value.message,
                'message',
                testCase.message,
              )
              .having((value) => value.output, 'output', isNull)
              .having((value) => value.errors, 'errors', hasLength(1))
              .having(
                (value) => value.errors.single.phase,
                'phase',
                testCase.phase,
              )
              .having(
                (value) => value.errors.single.commandPath,
                'command path',
                ['git', 'commit'],
              ),
        );
      });
    }
  });
});
```

For optional and defaulted inputs, test both omission and explicit input. For
repeatable, paired, selected, accessor, conflicting, and variadic inputs, test
one accepted shape and every user-visible rejection rule configured by the
command.

## Test group commands

Build the production command hierarchy and invoke children through their full
path. The test hierarchy must match it.

```dart
final class RemoteCommand extends GroupCommand {
  new() : super([RemoteAddCommand(), RemoteRemoveCommand()]);

  @override
  String get name => 'remote';

  @override
  String get shortDescription => 'Manage remotes.';
}

final class RemoteAddCommand extends Command {
  new() : super(mandatoryPositionals: [_name, _url]);

  static final _name = NormalPositional('name');
  static final _url = NormalPositional('url');

  @override
  String get name => 'add';

  @override
  String get shortDescription => 'Add a remote.';

  @override
  String run(ParsedInputs inputs, List<String> args) {
    final name = inputs.valueOf(_name);
    final url = inputs.valueOf(_url);
    return 'Added remote $name at $url.';
  }
}

final class RemoteRemoveCommand extends Command {
  new() : super(mandatoryPositionals: [_name]);

  static final _name = NormalPositional('name');

  @override
  String get name => 'remove';

  @override
  String get shortDescription => 'Remove a remote.';

  @override
  String run(ParsedInputs inputs, List<String> args) {
    final name = inputs.valueOf(_name);
    return 'Removed remote $name.';
  }
}
```

```dart
group('git', () {
  group('remote', () {
    test('shows its child commands', () async {
      final result = await Executor(
        'git',
        'Track source changes.',
        '1.0.0',
        [RemoteCommand()],
      ).fake().execute(['remote', '--help']);

      expect(
        result,
        isA<MambaSuccessResult>()
            .having((value) => value.exitCode, 'exit code', 0)
            .having(
              (value) => value.output,
              'output',
              allOf(contains('add'), contains('remove')),
            ),
      );
    });

    group('add', () {
      test('adds a named remote', () async {
        final result = await Executor(
          'git',
          'Track source changes.',
          '1.0.0',
          [RemoteCommand()],
        ).fake().execute([
          'remote',
          'add',
          'origin',
          'git@example.com:team/project.git',
        ]);

        expect(
          result,
          isA<MambaSuccessResult>()
              .having((value) => value.exitCode, 'exit code', 0)
              .having(
                (value) => value.output,
                'output',
                'Added remote origin at '
                    'git@example.com:team/project.git.',
              ),
        );
      });

      test('requires a remote URL', () async {
        final result = await Executor(
          'git',
          'Track source changes.',
          '1.0.0',
          [RemoteCommand()],
        ).fake().execute(['remote', 'add', 'origin']);

        expect(
          result,
          isA<MambaFailureResult>()
              .having((value) => value.exitCode, 'exit code', 1)
              .having(
                (value) => value.message,
                'message',
                'The url is required at 1 after this command',
              )
              .having((value) => value.output, 'output', isNull)
              .having((value) => value.errors, 'errors', hasLength(1))
              .having(
                (value) => value.errors.single.phase,
                'phase',
                MambaExecutionPhase.parse,
              )
              .having(
                (value) => value.errors.single.commandPath,
                'command path',
                ['git', 'remote', 'add'],
              ),
        );
      });
    });

    group('remove', () {
      test('removes a named remote', () async {
        final result = await Executor(
          'git',
          'Track source changes.',
          '1.0.0',
          [RemoteCommand()],
        ).fake().execute(['remote', 'remove', 'upstream']);

        expect(
          result,
          isA<MambaSuccessResult>()
              .having((value) => value.exitCode, 'exit code', 0)
              .having(
                (value) => value.output,
                'output',
                'Removed remote upstream.',
              ),
        );
      });
    });
  });
});
```

Test group-owned help, propagated inputs, default subcommands, and persistent
hooks directly inside the parent command's group. Test child behavior only
inside that child's nested group.

## Test command hooks

Record observable lifecycle events in a list owned by the test. Assert the
result contract and the event order. This proves both user-facing behavior and
the hook lifecycle.

```dart
final class PushCommand extends Command with HookRunner {
  new(this.events, {this.rejectAuthentication = false});

  final List<String> events;
  final bool rejectAuthentication;

  @override
  String get name => 'push';

  @override
  String get shortDescription => 'Update a remote.';

  @override
  void preRun(
    ParsedInputs inputs,
    MambaReadContext context,
    ProcessedStandardInput? input,
  ) {
    events.add('authenticate');
    if (rejectAuthentication) {
      throw MambaException('fatal: authentication failed', exitCode: 128);
    }
  }

  @override
  String run(ParsedInputs inputs, List<String> args) {
    events.add('push');
    return 'Pushed to origin.';
  }

  @override
  void postRun(ParsedInputs inputs, MambaReadContext context) {
    events.add('close transport');
  }
}
```

```dart
group('git', () {
  group('push', () {
    test('runs hooks around the command', () async {
      final events = <String>[];
      final result = await Executor(
        'git',
        'Track source changes.',
        '1.0.0',
        [PushCommand(events)],
      ).fake().execute(['push']);

      expect(
        result,
        isA<MambaSuccessResult>()
            .having((value) => value.exitCode, 'exit code', 0)
            .having((value) => value.output, 'output', 'Pushed to origin.'),
      );
      expect(events, ['authenticate', 'push', 'close transport']);
    });

    test('surfaces a pre-hook failure', () async {
      final events = <String>[];
      final result = await Executor(
        'git',
        'Track source changes.',
        '1.0.0',
        [PushCommand(events, rejectAuthentication: true)],
      ).fake().execute(['push']);

      expect(
        result,
        isA<MambaFailureResult>()
            .having((value) => value.exitCode, 'exit code', 128)
            .having(
              (value) => value.message,
              'message',
              'fatal: authentication failed',
            )
            .having((value) => value.output, 'output', isNull)
            .having((value) => value.errors, 'errors', hasLength(1))
            .having(
              (value) => value.errors.single.phase,
              'phase',
              MambaExecutionPhase.preRun,
            )
            .having(
              (value) => value.errors.single.commandPath,
              'command path',
              ['git', 'push'],
            ),
      );
      expect(events, ['authenticate']);
    });
  });
});
```

Test a `PersistentHookRunner` through a selected child path and assert outer
pre-hook, child hooks and run, then outer post-hook in order. For each hook
that can fail, assert its exact surfaced message, exit code, phase, command
path, retained output, and which cleanup hooks still ran.

Pass `ProcessedStandardInput` to `fake()` when `preRun` reads piped input:

```dart
import 'dart:convert';

final input = ProcessedStandardInput(utf8.encode('ref=main\n'));
final result = await Executor(
  'git',
  'Track source changes.',
  '1.0.0',
  [ApplyCommand()],
).fake(standardInput: input).execute(['apply']);
```

Assert what the hook observed in addition to the complete execution result.

## Completion checklist

Before finishing a command test suite, verify:

- the `group()` hierarchy mirrors every tested command path;
- every child of a tested `GroupCommand` has a nested group;
- parameterized case loops stay inside the group for their command path;
- every success asserts its variant, exit code, and exact or intentionally
  matched output;
- every failure asserts its variant, exit code, surfaced message, output,
  error count, phase, and command path;
- every registered input has meaningful accepted and rejected coverage;
- command-domain failures are distinct from parse failures;
- hook tests assert lifecycle order and cleanup behavior; and
- standard input and context are asserted when a hook consumes them.

The suite is complete only when every tested command and every expected user
diagnostic can be located from the command-group tree alone.
