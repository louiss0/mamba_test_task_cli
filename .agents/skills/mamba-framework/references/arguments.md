# Arguments

Use arguments for unnamed command input. Mamba separates arguments into
positionals before `--` and variadics after `--`.

## Register arguments

Register positionals on `Command` or `GroupCommand` in list order:

```dart
final source = NormalPositional('source');
final destination = NormalPositional.optional('destination');

final class CopyCommand extends Command {
  CopyCommand()
    : super(
        mandatoryPositionals: [source],
        discretionaryPositionals: [destination],
      );

  @override
  String get name => 'copy';

  @override
  String get shortDescription => 'Copy a file.';

  @override
  String run(ParsedInputs inputs, List<String> args) {
    final sourceValue = inputs.valueOf(source);
    final destinationValue = inputs.valueOf(destination);
    return 'Copy $sourceValue to ${destinationValue ?? 'the default path'}';
  }
}
```

`mandatoryPositionals` accepts `MandatoryPositional` declarations.
`discretionaryPositionals` accepts optional or defaulted
`DiscretionaryPositional` declarations. Retain each declaration and pass the
same instance to `ParsedInputs.valueOf`; declarations are identity-based typed
keys.

Register at most one `Variadic` with the `variadic` parameter. Its validated
strings are passed to `run` through `args`, not through `ParsedInputs`.

## Positional API

All positionals accept `name` and optional `description`. Normal string
positionals also accept `regExp`; the default pattern is `\S+`.

| Declaration | Registration | Parsed type |
| --- | --- | --- |
| `NormalPositional(name)` | mandatory | `String` |
| `NormalPositional.optional(name)` | discretionary | `String?` |
| `ChoicePositional(name, choices: values)` | mandatory | enum `T` |
| `ChoicePositional.optional(name, choices: values)` | discretionary | `T?` |
| `ChoicePositional.withDefault(...)` | discretionary | enum `T` |
| `RepeatedStringPositional(name)` | mandatory | `List<String>` |
| `RepeatedStringPositional.optional(name)` | discretionary | `List<String>?` |
| `RepeatedChoicePositional(name, choices: values)` | mandatory | `List<T>` |
| `RepeatedChoicePositional.optional(...)` | discretionary | `List<T>?` |
| `RepeatedChoicePositional.withDefault(...)` | discretionary | `List<T>` |

Choice declarations accept enum values and parse the selected member by its
`.name`:

```dart
enum OutputFormat { text, json }

final format = ChoicePositional.withDefault(
  'format',
  choices: OutputFormat.values,
  defaultValue: OutputFormat.text,
);
```

Repeated string positionals accept `regExp`. Repeated choice positionals accept
`choices`; their default is a `List<T>`. Both accept `times`, which defaults to
`1` and is the maximum number of values that declaration consumes. `times`
must be zero or greater. A mandatory repeated positional must still consume at
least one value.

Repeated positionals consume greedily in registration order until `times` is
reached or the next token fails their validation. Their parsed lists and
configured choice/default lists are immutable.

```dart
final sources = RepeatedStringPositional(
  'source',
  regExp: RegExp(r'.+\.dart'),
  times: 3,
);

final formats = RepeatedChoicePositional.optional(
  'format',
  choices: OutputFormat.values,
  times: 2,
);

final class BuildCommand extends Command {
  BuildCommand()
    : super(
        mandatoryPositionals: [sources],
        discretionaryPositionals: [formats],
      );

  // Implement name, shortDescription, and run.
}
```

## Variadic API

`NormalVariadic` validates every token after the first `--`. It accepts an
optional `description` and `regExp`; the default pattern is `\S+`.

```dart
final class ForwardCommand extends Command {
  ForwardCommand()
    : super(variadic: NormalVariadic(regExp: RegExp(r'.+')));

  @override
  String get name => 'forward';

  @override
  String get shortDescription => 'Forward trailing arguments.';

  @override
  String run(ParsedInputs inputs, List<String> args) => args.join(' ');
}
```

`ChoiceVariadic<T>` accepts `choices`, optional `description`, and optional
`defaultValue`. It validates at most one trailing enum name. The default is
registry metadata; it does not insert a value into `args` when the user omits
one. `run` receives the original string rather than the enum member:

```dart
ChoiceVariadic<OutputFormat>(
  choices: OutputFormat.values,
  defaultValue: OutputFormat.text,
)
```

Without a registered variadic, Mamba passes tokens after `--` to `run`
unchanged and does not validate them.

## Presence checks

Use `inputs.contains(declaration)` to check whether an optional positional
produced a value before calling `valueOf`. Defaulted positionals always contain
their parsed or fallback value. Variadics have no declaration value to query.
