import 'dart:async';

import 'package:nocterm/nocterm.dart';

import '../application/task_book.dart';
import '../domain/completion_filter.dart';
import '../domain/naming.dart';
import '../domain/task.dart';
import '../domain/task_filter.dart';
import '../domain/task_list.dart';
import '../domain/validation.dart';
import '../presentation/timestamps.dart';
import 'components.dart';
import 'failure.dart';
import 'pane.dart';
import 'screen_dialog.dart';
import 'shortcuts.dart';
import 'task_screen.dart';

/// The interactive interface.
///
/// This component draws the screen and turns keys into calls on [TaskScreen].
/// It never reads or writes the JSON file: every change goes through the
/// application layer, which persists and hands back the new state, and the
/// next build redraws from that.
///
/// One [Focusable] owns the keyboard for the whole screen. It sits above the
/// dialogs, and the framework delivers keys to the deepest handler first, so a
/// text field gets its own keys and everything else falls through to here.
final class TaskListApp extends StatefulComponent {
  const TaskListApp({super.key, required this.book, required this.screen});

  /// The application object that owns the book and every operation on it.
  final TaskBook book;

  /// The screen state, held outside the widget tree so it can also be driven
  /// directly by tests.
  final TaskScreen screen;

  @override
  State<TaskListApp> createState() => _TaskListAppState();
}

class _TaskListAppState extends State<TaskListApp> {
  static const double sidebarWidth = 26;
  static const double dialogWidth = 60;

  final ScrollController _taskScroll = ScrollController();
  final ScrollController _listScroll = ScrollController();

  ScreenDialog? _dialog;
  TextEditingController? _prompt;
  String? _dialogError;
  DateTime _now = DateTime.now();

  TaskScreen get _screen => component.screen;

  @override
  void initState() {
    super.initState();
    _screen.open();
  }

  @override
  void dispose() {
    _prompt?.dispose();
    _taskScroll.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- key input

  bool _onKey(KeyboardEvent event) {
    final dialog = _dialog;
    if (dialog != null) {
      final handled = _onDialogKey(dialog, event);
      if (handled) _afterChange();
      return handled;
    }

    final action = Shortcuts.actionFor(event);
    if (action == null) return false;

    switch (action) {
      case Action.moveUp:
        _screen.moveSelection(-1);
      case Action.moveDown:
        _screen.moveSelection(1);
      case Action.jumpToFirst:
        _screen.moveSelectionToEdge(last: false);
      case Action.jumpToLast:
        _screen.moveSelectionToEdge(last: true);
      case Action.togglePane:
        _screen.togglePane();
      case Action.addTask:
        _openPrompt(
          title: 'Add a task',
          actionLabel: 'Add',
          onSubmit: _screen.addTask,
        );
      case Action.editTask:
        _promptForTask();
      case Action.toggleDone:
        _run(_screen.toggleSelectedTask);
      case Action.deleteTask:
        _confirmForTask();
      case Action.newList:
        _openPrompt(
          title: 'New list',
          actionLabel: 'Create',
          validate: _validateListName,
          onSubmit: _screen.createList,
        );
      case Action.renameList:
        _promptForRename();
      case Action.deleteList:
        _confirmForList();
      case Action.previousFilter:
        _screen.stepFilter(-1);
      case Action.nextFilter:
        _screen.stepFilter(1);
      case Action.showAll:
        _screen.applyFilter(CompletionFilter.all);
      case Action.showIncomplete:
        _screen.applyFilter(CompletionFilter.incomplete);
      case Action.showCompleted:
        _screen.applyFilter(CompletionFilter.completed);
      case Action.showHelp:
        _dialog = const HelpDialog();
      case Action.quit:
        shutdownApp();
        return true;
    }

    _afterChange();
    return true;
  }

  bool _onDialogKey(ScreenDialog dialog, KeyboardEvent event) {
    switch (dialog) {
      case PromptDialog():
        // The field handles every editing key. Only the keys that must leave
        // the field are interpreted here, so a stray `d` cannot delete a task
        // while the user is typing.
        if (event.logicalKey != LogicalKey.escape) return false;
        _closeDialog();
        return true;
      case ConfirmDialog():
        final confirmed = event.logicalKey == LogicalKey.enter ||
            event.matches(LogicalKey.keyY, ctrl: false);
        _closeDialog();
        if (confirmed) _run(dialog.onConfirm);
        return true;
      case HelpDialog():
      case MessageDialog():
        _closeDialog();
        return true;
    }
  }

  void _promptForTask() {
    final task = _screen.selectedTask;
    if (task == null) {
      _screen.report('Select a task to edit.');
      return;
    }
    _openPrompt(
      title: 'Edit task',
      actionLabel: 'Save',
      initialValue: task.title,
      onSubmit: _screen.renameSelectedTask,
      validate: (value) {
        normalizeTaskTitle(value);
        return null;
      },
    );
  }

  void _confirmForTask() {
    final task = _screen.selectedTask;
    if (task == null) {
      _screen.report('Select a task to delete.');
      return;
    }
    _dialog = ConfirmDialog(
      title: 'Delete task',
      message: 'Delete "${task.title}"? This cannot be undone.',
      confirmLabel: 'Delete',
      onConfirm: _screen.deleteSelectedTask,
    );
  }

  void _promptForRename() {
    final list = _screen.currentList;
    if (list == null) {
      _screen.report('There is no list to rename.');
      return;
    }
    _openPrompt(
      title: 'Rename list',
      actionLabel: 'Save',
      initialValue: list.name,
      onSubmit: _screen.renameCurrentList,
      validate: (value) {
        normalizeListName(value);
        return null;
      },
    );
  }

  void _confirmForList() {
    final list = _screen.currentList;
    if (list == null) {
      _screen.report('There is no list to delete.');
      return;
    }
    final count = list.tasks.length;
    _dialog = ConfirmDialog(
      title: 'Delete list',
      message: 'Delete "${list.name}" and its $count '
          '${count == 1 ? 'task' : 'tasks'}? This cannot be undone.',
      confirmLabel: 'Delete',
      onConfirm: _screen.deleteCurrentList,
    );
  }

  String? _validateListName(String value) {
    try {
      normalizeListName(
        value,
        existingNames: _screen.lists.map((list) => list.name),
      );
      return null;
    } on ValidationException catch (error) {
      return error.message;
    }
  }

  void _openPrompt({
    required String title,
    required String actionLabel,
    required Future<void> Function(String) onSubmit,
    String initialValue = '',
    String? Function(String value)? validate,
  }) {
    _prompt?.dispose();
    _prompt = TextEditingController(text: initialValue);
    _dialogError = null;
    _dialog = PromptDialog(
      title: title,
      actionLabel: actionLabel,
      controller: _prompt!,
      validate: validate,
      onSubmit: onSubmit,
    );
  }

  void _closeDialog() {
    _prompt?.dispose();
    _prompt = null;
    _dialog = null;
    _dialogError = null;
  }

  /// Runs a task from a key press, keeping any rejection on screen.
  void _run(Future<void> Function() action) {
    _runDialogAction(action, closeOnSuccess: _dialog == null);
  }

  /// Runs an action whose failures must never reach the terminal unhandled.
  ///
  /// A key press runs the application layer on a detached future, so nothing
  /// else stands between a rejected change and an unhandled async error. Every
  /// failure is therefore turned into something the user can read, and the
  /// screen is left in a usable state afterwards.
  void _runDialogAction(
    Future<void> Function() action, {
    required bool closeOnSuccess,
  }) {
    unawaited(() async {
      try {
        await action();
      } on ValidationException catch (error) {
        // A rejected value belongs in the dialog that asked for it, so the
        // user can correct it without retyping everything.
        if (mounted) setState(() => _dialogError = error.message);
        return;
      } on Object catch (error) {
        _reportFailure(error);
        return;
      }
      if (!mounted) return;
      if (closeOnSuccess) _closeDialog();
      _afterChange();
    }());
  }

  /// Shows a failure and re-settles the selection around it.
  ///
  /// A change can fail because the book moved on without this instance, for
  /// example when another process removed the selected task. Reconciling here
  /// means the screen lands on whatever still exists instead of pointing at
  /// something that is gone.
  void _reportFailure(Object error) {
    if (!mounted) return;
    final failure = describeFailure(error);
    setState(() {
      _screen.report(failure.title);
      _screen.reconcile();
      _dialog = failure.needsReading
          ? MessageDialog(title: failure.title, body: failure.detail.split('\n'))
          : _dialog;
      _dialogError = failure.needsReading ? null : failure.detail;
    });
    _revealSelection();
  }

  void _afterChange() {
    if (!mounted) return;
    setState(() {
      _now = DateTime.now();
    });
    _revealSelection();
  }

  /// Scrolls the task area so the highlighted row stays on screen.
  ///
  /// The controller already knows how many rows the viewport shows, so the
  /// widget never has to measure the screen itself.
  void _revealSelection() {
    if (_screen.pane != Pane.tasks) return;
    final index = _screen.selectedIndex;
    if (index < 0) return;
    final rows = _taskScroll.viewportDimension.toInt();
    if (rows <= 0) return;
    final top = _taskScroll.offset.toInt();
    if (index < top) {
      _taskScroll.jumpTo(index.toDouble());
    } else if (index >= top + rows) {
      _taskScroll.jumpTo((index - rows + 1).toDouble());
    }
  }

  // ------------------------------------------------------------------ drawing

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Focusable(
      focused: true,
      onKeyEvent: _onKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              _header(theme),
              _filterBar(theme),
              Divider(color: theme.outlineVariant),
              Expanded(child: _body(theme)),
              Divider(color: theme.outlineVariant),
              _hintBar(theme),
              _statusBar(theme),
            ],
          ),
          if (_dialog != null) _overlay(theme, _dialog!),
        ],
      ),
    );
  }

  Component _header(TuiThemeData theme) => singleLine(
        ' task_list',
        padding: const EdgeInsets.only(left: 1),
        style: TextStyle(color: theme.primary, fontWeight: FontWeight.bold),
      );

  Component _filterBar(TuiThemeData theme) => Container(
        height: 1,
        padding: const EdgeInsets.only(left: 1),
        child: Row(
          children: [
            for (final option in CompletionFilter.values) ...[
              filterTab(
                label: '${option.label} ${_countFor(option)}',
                active: option == _screen.filter,
                idleStyle: TextStyle(color: theme.secondary),
                activeStyle: TextStyle(
                  color: theme.onPrimary,
                  backgroundColor: theme.primary,
                  fontWeight: FontWeight.bold,
                ),
                background: theme.primary,
              ),
              const SizedBox(width: 1, height: 1, child: Text(' ')),
            ],
          ],
        ),
      );

  int _countFor(CompletionFilter filter) =>
      _screen.currentList?.tasks.where(TaskFilter.byCompletion(filter).matches).length ??
      0;

  Component _body(TuiThemeData theme) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sidebar(theme),
          Expanded(child: _taskArea(theme)),
        ],
      );

  Component _sidebar(TuiThemeData theme) {
    final lists = _screen.lists;
    return Container(
      width: sidebarWidth,
      padding: const EdgeInsets.only(left: 1, top: 1),
      decoration: BoxDecoration(
        border: BoxBorder(right: BorderSide(color: theme.outlineVariant)),
      ),
      child: lists.isEmpty
          ? emptyState(
              headline: 'No lists',
              suggestion: 'Press l to add one',
              headlineStyle: TextStyle(color: theme.secondary),
              suggestionStyle: TextStyle(
                color: theme.secondary,
                fontStyle: FontStyle.italic,
              ),
            )
          : ListView.builder(
              controller: _listScroll,
              itemExtent: 1,
              itemCount: lists.length,
              itemBuilder: (context, index) =>
                  _listRow(theme, lists[index], index),
            ),
    );
  }

  Component _listRow(TuiThemeData theme, TaskList list, int index) {
    final isCurrent = index == _screen.selectedListIndex;
    final focused = isCurrent && _screen.pane == Pane.lists;
    return Container(
      height: 1,
      color: focused ? theme.selectionColor : null,
      padding: const EdgeInsets.only(right: 1),
      child: Text(
        '${isCurrent ? selectionMarker : blankMarker} ${list.name}  '
        '${list.openCount}/${list.tasks.length}',
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(
          color: isCurrent ? theme.primary : theme.onBackground,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Component _taskArea(TuiThemeData theme) {
    final list = _screen.currentList;
    if (list == null) return const SizedBox(width: 0, height: 0);

    final tasks = _screen.visibleTasks;
    if (tasks.isEmpty) {
      return emptyState(
        headline: _emptyHeadline(list),
        suggestion: _emptySuggestion(list),
        headlineStyle: TextStyle(color: theme.secondary),
        suggestionStyle: TextStyle(
          color: theme.secondary,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return ListView.builder(      controller: _taskScroll,
      itemExtent: 1,
      itemCount: tasks.length,
      itemBuilder: (context, index) => _taskRow(theme, tasks[index], index),
    );
  }

  Component _taskRow(TuiThemeData theme, Task task, int index) {
    final selected = index == _screen.selectedIndex && _screen.pane == Pane.tasks;
    final style = TextStyle(
      color: task.completed ? theme.secondary : theme.onBackground,
      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      decoration:
          task.completed ? TextDecoration.lineThrough : TextDecoration.none,
    );
    return Container(
      height: 1,
      color: selected ? theme.selectionColor : null,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Row(
        children: [
          // The checkbox, the strike-through, and the colour each report the
          // state, so the row still reads correctly without colour.
          Text(
            '${selected ? selectionMarker : blankMarker} '
            '${task.completed ? doneTaskMarker : openTaskMarker} ',
            style: style,
            softWrap: false,
          ),
          Expanded(
            child: Text(
              task.title,
              style: style,
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          ),
          Text(
            ' ${formatRelative(task.createdAt, _now)}',
            style: TextStyle(color: theme.secondary),
            softWrap: false,
          ),
        ],
      ),
    );
  }

  String _emptyHeadline(TaskList list) => switch (_screen.filter) {
        CompletionFilter.all => 'No tasks in "${list.name}"',
        CompletionFilter.incomplete => 'Nothing left in "${list.name}"',
        CompletionFilter.completed => 'Nothing finished in "${list.name}"',
      };

  String _emptySuggestion(TaskList list) {
    if (list.tasks.isEmpty) return 'Press a to add one';
    return switch (_screen.filter) {
      CompletionFilter.all => 'Press a to add one',
      CompletionFilter.incomplete => 'Press 3 to see finished tasks',
      CompletionFilter.completed => 'Press 2 to see what is left',
    };
  }

  Component _hintBar(TuiThemeData theme) => singleLine(
        Shortcuts.hintLine(),
        padding: const EdgeInsets.only(left: 1),
        style: TextStyle(color: theme.secondary),
      );

  Component _statusBar(TuiThemeData theme) => singleLine(
        _screen.status,
        padding: const EdgeInsets.only(left: 1),
        style: TextStyle(
          color: _screen.statusIsError ? theme.error : theme.success,
        ),
      );

  // ------------------------------------------------------------------ dialogs

  Component _overlay(TuiThemeData theme, ScreenDialog dialog) => Stack(
        fit: StackFit.expand,
        children: [
          Container(color: theme.background.withOpacity(0.75)),
          Center(
            child: switch (dialog) {
              PromptDialog() => _promptDialog(theme, dialog),
              ConfirmDialog() => _confirmDialog(theme, dialog),
              HelpDialog() => _helpDialog(theme),
              MessageDialog() => _messageDialog(theme, dialog),
            },
          ),
        ],
      );

  static double get _innerWidth => dialogWidth - 2;

  Component _promptDialog(TuiThemeData theme, PromptDialog dialog) =>
      dialogBox(
        title: dialog.title,
        borderColor: _dialogError == null ? theme.primary : theme.error,
        background: theme.surface,
        innerWidth: _innerWidth,
        titleStyle: TextStyle(
          color: theme.primary,
          fontWeight: FontWeight.bold,
        ),
        body: [
          const SizedBox(height: 1),
          TextField(
            controller: dialog.controller,
            focused: true,
            placeholder: 'Type here',
            width: _innerWidth,
            onSubmitted: (value) => _submitPrompt(dialog, value),
            decoration: InputDecoration(
              border: BoxBorder.all(color: theme.outline),
              contentPadding: const EdgeInsets.symmetric(horizontal: 1),
            ),
          ),
          singleLine(
            _dialogError ?? 'Enter ${dialog.actionLabel.toLowerCase()}  |  '
                'Esc cancels',
            style: TextStyle(
              color: _dialogError == null ? theme.secondary : theme.error,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );

  void _submitPrompt(PromptDialog dialog, String value) {
    try {
      final problem = dialog.validate?.call(value);
      if (problem != null) {
        setState(() => _dialogError = problem);
        return;
      }
    } on ValidationException catch (error) {
      setState(() => _dialogError = error.message);
      return;
    }
    // The dialog stays open until the value is accepted, so a rejection from
    // the application layer is shown here instead of behind a closed box.
    _runDialogAction(() async => dialog.onSubmit(value), closeOnSuccess: true);
  }

  Component _confirmDialog(TuiThemeData theme, ConfirmDialog dialog) =>
      dialogBox(
        title: dialog.title,
        borderColor: theme.error,
        background: theme.surface,
        innerWidth: _innerWidth,
        titleStyle: TextStyle(color: theme.error, fontWeight: FontWeight.bold),
        body: [
          const SizedBox(height: 1),
          singleLine(dialog.message),
          const SizedBox(height: 1),
          singleLine(
            '${dialog.confirmLabel} with Enter or y  |  any key cancels',
            style: TextStyle(
              color: theme.secondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );

  Component _messageDialog(TuiThemeData theme, MessageDialog dialog) =>
      dialogBox(
        title: dialog.title,
        borderColor: theme.error,
        background: theme.surface,
        innerWidth: _innerWidth,
        titleStyle: TextStyle(color: theme.error, fontWeight: FontWeight.bold),
        body: [
          const SizedBox(height: 1),
          for (final line in dialog.body)
            singleLine(
              line,
              style: line.isEmpty ? null : TextStyle(color: theme.onSurface),
            ),
          const SizedBox(height: 1),
          singleLine(
            ' Press any key to continue',
            style: TextStyle(
              color: theme.secondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );

  Component _helpDialog(TuiThemeData theme) {
    // Two columns keep the reference inside a short terminal.
    final half = (Shortcuts.helpOrder.length / 2).ceil();
    final left = Shortcuts.helpOrder.take(half);
    final right = Shortcuts.helpOrder.skip(half);
    return dialogBox(
      title: 'Keyboard',
      borderColor: theme.primary,
      background: theme.surface,
      innerWidth: dialogWidth - 2,
      titleStyle: TextStyle(color: theme.primary, fontWeight: FontWeight.bold),
      body: [
        const SizedBox(height: 1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: [for (final a in left) _helpRow(a)])),
            Expanded(child: Column(children: [for (final a in right) _helpRow(a)])),
          ],
        ),
        const SizedBox(height: 1),
        singleLine(
          ' Press any key to close',
          style: TextStyle(
            color: theme.secondary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Component _helpRow(Action action) => singleLine(
        '${Shortcuts.keysFor(action).padRight(7)}'
        '${Shortcuts.hint(action)}',
      );
}
