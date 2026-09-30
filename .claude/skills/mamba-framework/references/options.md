# Options

Use options for named inputs that take values. Mamba has four command
registration lists:

| `Command` parameter | Register |
| --- | --- |
| `options` | scalar and repeatable options |
| `pairedOptions` | all-or-nothing groups |
| `selectedOptions` | independently selectable groups |
| `accessors` | dotted option trees |

Retain the option or group declaration and pass the same instance to
`ParsedInputs.valueOf`; declarations are identity-based typed keys.

## Scalar options

Register scalar declarations in `options`. Use the direct constructor for an
optional value, `.required` for a required value, or `.withDefault` for a
non-null fallback.

| Family | Optional type | Required type | Defaulted type |
| --- | --- | --- | --- |
| `StringOption` | `String?` | `String` | `String` |
| `IntOption` | `int?` | `int` | `int` |
| `DoubleOption` | `double?` | `double` | `double` |
| `ChoiceOption<T>` | `T?` | `T` | `T` |

All scalar forms accept `name`, `short`, `description`, and `hidden`.
`StringOption` accepts `regex`, defaulting to `\S+`. Integer options accept
inclusive `min` and `max`. Double options accept inclusive `min`, `max`, and
`step`. Choice options accept enum `choices`; defaulted choices also require a
member from that enum.

```dart
enum OutputFormat { text, json }

final output = StringOption.required(
  'output',
  short: 'o',
  regex: RegExp(r'.+'),
);
final retries = IntOption.withDefault(
  'retries',
  defaultValue: 3,
  min: 0,
  max: 10,
);
final threshold = DoubleOption(
  'threshold',
  min: 0,
  max: 1,
  step: 0.1,
);
final format = ChoiceOption.withDefault(
  'format',
  choices: OutputFormat.values,
  defaultValue: OutputFormat.text,
);

final class BuildCommand extends Command {
  BuildCommand()
    : super(options: [output, retries, threshold, format]);

  // Implement name, shortDescription, and run.
}
```

Long options accept `--name value` and `--name=value`. A short alias accepts
`-n value`. Hidden options remain parseable but are omitted from generated
help.

## Repeatable options

Register repeatable declarations in `options`. Each occurrence appends a value
to an immutable ordered list.

| Family | Optional type | Required type | Defaulted type |
| --- | --- | --- | --- |
| `RepeatableStringOption` | `List<String>?` | `List<String>` | `List<String>` |
| `RepeatableIntOption` | `List<int>?` | `List<int>` | `List<int>` |
| `RepeatableDoubleOption` | `List<double>?` | `List<double>` | `List<double>` |
| `RepeatableChoiceOption<T>` | `List<T>?` | `List<T>` | `List<T>` |

Use the direct constructor, `.required`, or `.withDefault` as with scalar
options. String, integer, and double validation parameters are the same as
their scalar equivalents. `RepeatableChoiceOption` takes `choices` as its
second positional argument and accepts `unique: true` to reject duplicate
members.

```dart
final labels = RepeatableStringOption('label');
final ports = RepeatableIntOption.required(
  'port',
  min: 1,
  max: 65535,
);
final formats = RepeatableChoiceOption.withDefault(
  'format',
  OutputFormat.values,
  defaultValue: [OutputFormat.text],
  unique: true,
);

final class ServeCommand extends Command {
  ServeCommand() : super(options: [labels, ports, formats]);

  // Implement name, shortDescription, and run.
}
```

## Paired options

Use `PairedOptions<T>` when supplying any member must require every member.
Register the group in `pairedOptions`, then read the group declaration as an
immutable `Map<String, T>` keyed by member name.

The direct constructor makes the entire group optional. The `.required`
constructor requires the complete group.

```dart
final credentials = PairedOptions<String>.required(
  [
    PairStringOption('username'),
    PairStringOption('password'),
  ],
  description: 'Credentials for the remote service.',
);

final class LoginCommand extends Command {
  LoginCommand() : super(pairedOptions: [credentials]);

  // inputs.valueOf(credentials) returns Map<String, String>.
  // Implement name, shortDescription, and run.
}
```

Pair member APIs are:

- `PairStringOption`, with optional `regex`;
- `PairIntOption`, with optional `min` and `max`;
- `PairDoubleOption`, with optional `min`, `max`, and `step`;
- `PairChoiceOption<T>`, with required enum `choices`;
- `RepeatablePairStringOption`, with optional `regex`;
- `RepeatablePairIntOption`, with optional `min` and `max`; and
- `RepeatablePairDoubleOption`, with optional `min`, `max`, and `step`.

Every pair member accepts `name`, `short`, and `description`. Repeatable pair
members produce lists inside the group's map. Pair members are declarations
within the group; query the retained `PairedOptions` declaration with
`valueOf`.

## Selected options

Use `SelectedOptions<T>` when members may be supplied independently. It uses
the same `PairOption<T>` member APIs and produces an immutable
`Map<String, T>` containing the supplied members.

```dart
final output = SelectedOptions<String>.required(
  [
    PairStringOption('json'),
    PairStringOption('text'),
  ],
  description: 'Select an output destination.',
  single: true,
);

final class ExportCommand extends Command {
  ExportCommand() : super(selectedOptions: [output]);

  // inputs.valueOf(output) returns Map<String, String>.
  // Implement name, shortDescription, and run.
}
```

The direct constructor allows zero or more members. `.required` requires at
least one. `single: true` permits at most one, so combining it with `.required`
requires exactly one.

## Accessor options

Use an `AccessorListOption` tree for dotted names. Register only the top-level
list in `accessors`; read that same top-level declaration as an immutable,
nested `Map<String, Object?>`.

```dart
final server = AccessorListOption(
  'server',
  [
    AccessorStringOption.required('host'),
    AccessorIntOption.withDefault('port', defaultValue: 443),
    AccessorListOption(
      'tls',
      [AccessorStringOption('certificate')],
    ),
  ],
  description: 'Server connection settings.',
);

final class ConnectCommand extends Command {
  ConnectCommand() : super(accessors: [server]);

  // --server.host example.com --server.tls.certificate cert.pem
  // Implement name, shortDescription, and run.
}
```

Accessor leaf families are `AccessorStringOption`, `AccessorIntOption`,
`AccessorDoubleOption`, and `AccessorChoiceOption<T>`. Each has a direct
optional constructor plus `.required` and `.withDefault` factories. String
leaves accept `regex`; choice leaves accept enum `choices`. The current
integer and double accessor APIs do not expose range or step parameters.

Every accessor accepts `name` and `description`. `AccessorListOption` also
accepts `hidden`; hiding a group hides its descendant leaves from help while
preserving parsing.

## Registration scope

- `Command(options: [...])` and `GroupCommand(..., options: [...])` register
  scalar or repeatable options locally.
- `GroupCommand(..., propagatedOptions: [...])` makes scalar or repeatable
  options available to the group and its descendants.
- `Executor(..., options: [...])` makes scalar or repeatable options global.
- Paired, selected, and accessor registrations belong to the command lists
  shown at the top of this page. Executor supports global accessors, but not
  paired or selected groups.

## Conflicts and presence

Use `Command.conflicts` to reject incompatible named inputs before `run`.
Names may refer to flags, ordinary options, paired or selected members, or
accessor leaves. Use the full dotted name for an accessor leaf:

```dart
ConnectCommand()
  : super(
      flags: [local],
      accessors: [server],
      conflicts: {
        'local': ['server.host'],
      },
    );
```

Use `inputs.contains(declaration)` before reading an omitted optional scalar or
repeatable option. Defaulted options always contain their parsed or fallback
value. Paired groups, selected groups, and top-level accessors always contain
a map; an omitted optional group has an empty map, and optional accessor leaves
are absent from their containing map.
