import 'package:nocterm/nocterm.dart';

/// Something the user can ask the interface to do.
enum Action {
  moveUp,
  moveDown,
  jumpToFirst,
  jumpToLast,
  togglePane,
  addTask,
  editTask,
  toggleDone,
  deleteTask,
  newList,
  renameList,
  deleteList,
  previousFilter,
  nextFilter,
  showAll,
  showIncomplete,
  showCompleted,
  showHelp,
  quit,
}

/// The single source of truth for keyboard behaviour.
///
/// The key handler, the hint bar, and the help view all read this table, so a
/// shortcut cannot be offered in one place and bound to something else in
/// another.
abstract final class Shortcuts {
  /// Returns the action [event] triggers, or null when the interface should
  /// leave the key alone.
  ///
  /// The key handler is only consulted while no dialog is open; a dialog
  /// interprets Enter and Escape itself.
  static Action? actionFor(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) return null;
    if (event.matches(LogicalKey.keyC, ctrl: true)) return Action.quit;

    switch (event.logicalKey) {
      case LogicalKey.arrowUp:
        return Action.moveUp;
      case LogicalKey.arrowDown:
        return Action.moveDown;
      case LogicalKey.home:
        return Action.jumpToFirst;
      case LogicalKey.end:
        return Action.jumpToLast;
      case LogicalKey.tab:
        return Action.togglePane;
      case LogicalKey.space:
      case LogicalKey.enter:
        return Action.toggleDone;
      default:
        break;
    }

    final pressed = _keyLabel(event);
    return switch (pressed) {
      'k' => Action.moveUp,
      'j' => Action.moveDown,
      'g' => Action.jumpToFirst,
      'a' => Action.addTask,
      'e' => Action.editTask,
      'd' => Action.deleteTask,
      'l' => Action.newList,
      'r' => Action.renameList,
      'L' => Action.deleteList,
      '[' => Action.previousFilter,
      ']' => Action.nextFilter,
      '1' => Action.showAll,
      '2' => Action.showIncomplete,
      '3' => Action.showCompleted,
      '?' => Action.showHelp,
      'q' => Action.quit,
      _ => null,
    };
  }

  /// The keys shown in the hint bar for [action].
  static String keysFor(Action action) => switch (action) {
        Action.moveUp => 'up/k',
        Action.moveDown => 'down/j',
        Action.jumpToFirst => 'home',
        Action.jumpToLast => 'end',
        Action.togglePane => 'tab',
        Action.addTask => 'a',
        Action.editTask => 'e',
        Action.toggleDone => 'space',
        Action.deleteTask => 'd',
        Action.newList => 'l',
        Action.renameList => 'r',
        Action.deleteList => 'L',
        Action.previousFilter => '[',
        Action.nextFilter => ']',
        Action.showAll => '1',
        Action.showIncomplete => '2',
        Action.showCompleted => '3',
        Action.showHelp => '?',
        Action.quit => 'q',
      };

  /// A terse label for [action], used by the hint bar and the help view.
  ///
  /// The hint bar has one line for the whole width, so its wording is kept
  /// short enough that the full set fits an eighty column terminal. The help
  /// view has room and spells the actions out.
  static String hint(Action action) => switch (action) {
        Action.moveUp => 'up',
        Action.moveDown => 'down',
        Action.jumpToFirst => 'top',
        Action.jumpToLast => 'bottom',
        Action.togglePane => 'pane',
        Action.addTask => 'add',
        Action.editTask => 'edit',
        Action.toggleDone => 'done',
        Action.deleteTask => 'del',
        Action.newList => 'list',
        Action.renameList => 'rename',
        Action.deleteList => 'drop list',
        Action.previousFilter => 'prev',
        Action.nextFilter => 'next',
        Action.showAll => 'all',
        Action.showIncomplete => 'open',
        Action.showCompleted => 'done',
        Action.showHelp => 'help',
        Action.quit => 'quit',
      };

  /// The actions listed in the help view, in the order they are shown.
  static const List<Action> helpOrder = [
    Action.moveUp,
    Action.moveDown,
    Action.jumpToFirst,
    Action.jumpToLast,
    Action.togglePane,
    Action.addTask,
    Action.editTask,
    Action.toggleDone,
    Action.deleteTask,
    Action.newList,
    Action.renameList,
    Action.deleteList,
    Action.previousFilter,
    Action.nextFilter,
    Action.showAll,
    Action.showIncomplete,
    Action.showCompleted,
    Action.showHelp,
    Action.quit,
  ];

  /// The actions advertised in the bottom hint bar, in the order shown.
  ///
  /// Together with [hint] these have to fit one eighty column line, which is
  /// the narrowest terminal most people use. Anything not listed here is
  /// still reachable and is documented by the help view.
  static const List<Action> hintOrder = [
    Action.addTask,
    Action.editTask,
    Action.toggleDone,
    Action.deleteTask,
    Action.newList,
    Action.previousFilter,
    Action.nextFilter,
    Action.showHelp,
    Action.quit,
  ];

  /// The one-line summary of every advertised shortcut.
  static String hintLine() => [
        for (final action in hintOrder) '${keysFor(action)} ${hint(action)}',
      ].join('  ');

  /// The literal key a user presses, preferring the typed character.
  ///
  /// Terminals report an upper-case letter as the same logical key with a
  /// shifted character, while a headless test may send only the logical key.
  /// Both forms have to resolve to the same shortcut.
  static String? _keyLabel(KeyboardEvent event) {
    final character = event.character;
    if (character != null && character.length == 1) return character;

    final name = event.logicalKey.debugName;
    if (name.startsWith('key') && name.length == 4) {
      final letter = name.substring(3).toLowerCase();
      return event.isShiftPressed ? _upper(letter) : letter;
    }
    if (name.startsWith('digit') && name.length == 6) {
      return name.substring(5);
    }
    return switch (event.logicalKey) {
      LogicalKey.slash => '/',
      LogicalKey.question => '?',
      LogicalKey.bracketLeft => '[',
      LogicalKey.bracketRight => ']',
      _ => null,
    };
  }

  static String _upper(String value) => value.toUpperCase();
}
