import 'dart:async';

import 'package:nocterm/nocterm.dart';

import 'models.dart';
import 'service.dart';

final class TaskApp extends StatelessComponent {
  const TaskApp(this.service, {super.key});
  final TaskService service;
  @override
  Component build(BuildContext context) => Navigator(
    popBehavior: const PopBehavior(escapeEnabled: false),
    home: _TaskBoard(service),
  );
}

final class _TaskBoard extends StatefulComponent {
  const _TaskBoard(this.service);
  final TaskService service;
  @override
  State<_TaskBoard> createState() => _TaskBoardState();
}

final class _TaskBoardState extends State<_TaskBoard> {
  int _listIndex = 0;
  int _taskIndex = 0;
  bool _listFocus = false;
  bool _busy = false;
  bool _dialogOpen = false;
  bool _selectionScrollPending = false;
  TaskFilter _filter = TaskFilter.all;
  String _message = 'Welcome. Tab switches panes; ? opens help.';
  final _listScroll = ScrollController();
  final _taskScroll = ScrollController();

  TaskService get _service => component.service;
  TaskList? get _list => _service.lists.isEmpty
      ? null
      : _service.lists[_listIndex.clamp(0, _service.lists.length - 1)];
  List<Task> get _tasks =>
      _list == null ? [] : _service.query(_list!.id, filter: _filter);
  Task? get _task =>
      _tasks.isEmpty ? null : _tasks[_taskIndex.clamp(0, _tasks.length - 1)];

  @override
  void dispose() {
    _listScroll.dispose();
    _taskScroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _listIndex = _service.lists.isEmpty
          ? 0
          : _listIndex.clamp(0, _service.lists.length - 1);
      _taskIndex = _tasks.isEmpty ? 0 : _taskIndex.clamp(0, _tasks.length - 1);
    });
    if (_selectionScrollPending) return;
    _selectionScrollPending = true;
    // Appended rows and their scroll bounds exist only after the next layout.
    // Coalesce refreshes and use the latest selection rather than stale indices.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _selectionScrollPending = false;
      if (!mounted) return;
      _listScroll.ensureIndexVisible(index: _listIndex);
      _taskScroll.ensureIndexVisible(index: _taskIndex);
    });
  }

  Future<void> _act(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted) setState(() => _message = 'Saved.');
    } on TaskFailure catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<T?> _dialog<T>(
    Component Function(BuildContext) builder, {
    required double width,
    required double height,
  }) async {
    setState(() => _dialogOpen = true);
    try {
      return await Navigator.of(context).showDialog<T>(
        barrierDismissible: false,
        animateBarrier: false,
        width: width,
        height: height,
        builder: builder,
      );
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
      _refresh();
    }
  }

  Future<void> _prompt(
    String heading,
    String initial,
    Future<void> Function(String) save,
  ) async {
    await _dialog<bool>(
      (_) => _EditDialog(heading, initial, save),
      width: 60,
      height: 12,
    );
  }

  Future<void> _create() async {
    if (_listFocus || _list == null) {
      await _prompt('Create list', '', (value) async {
        final list = await _service.createList(value);
        _listIndex = _service.lists.indexWhere((item) => item.id == list.id);
        _taskIndex = 0;
        _listFocus = false;
      });
    } else {
      final list = _list!;
      await _prompt('Add task to ${list.name}', '', (value) async {
        final task = await _service.createTask(list.id, value);
        _filter = TaskFilter.all;
        _taskIndex = _service
            .query(list.id)
            .indexWhere((item) => item.id == task.id);
      });
    }
  }

  Future<void> _edit() async {
    final list = _list;
    final task = _task;
    if (list == null) return;
    if (_listFocus) {
      await _prompt(
        'Rename list',
        list.name,
        (value) => _service.renameList(list.id, value),
      );
    } else if (task != null) {
      await _prompt(
        'Edit task title',
        task.title,
        (value) => _service.editTask(list.id, task.id, value),
      );
    }
  }

  Future<void> _delete() async {
    final list = _list;
    final task = _task;
    if (list == null || (!_listFocus && task == null)) return;
    final deletingList = _listFocus;
    final warning = deletingList
        ? 'Delete list "${list.name}" and its ${list.tasks.length} tasks?'
        : 'Delete task "${task!.title}"?';
    final confirmed = await _dialog<bool>(
      (_) => _ConfirmDialog(warning),
      width: 60,
      height: 10,
    );
    if (confirmed != true || !mounted) return;
    await _act(() async {
      if (deletingList) {
        await _service.deleteList(list.id, confirmed: true);
        _taskIndex = 0;
      } else {
        await _service.deleteTask(list.id, task!.id, confirmed: true);
      }
    });
  }

  void _move(int delta) {
    setState(() {
      if (_listFocus && _service.lists.isNotEmpty) {
        _listIndex = (_listIndex + delta).clamp(0, _service.lists.length - 1);
        _taskIndex = 0;
        _taskScroll.jumpTo(0);
      } else if (!_listFocus && _tasks.isNotEmpty) {
        _taskIndex = (_taskIndex + delta).clamp(0, _tasks.length - 1);
      }
    });
    _refresh();
  }

  bool _onKey(KeyboardEvent event) {
    if (_dialogOpen) return false;
    if (_busy) return true;
    final key = event.logicalKey;
    if (key == LogicalKey.keyQ) {
      shutdownApp();
    } else if (key == LogicalKey.tab) {
      setState(() => _listFocus = !_listFocus);
    } else if (key == LogicalKey.arrowLeft || key == LogicalKey.arrowRight) {
      setState(() => _listFocus = key == LogicalKey.arrowLeft);
    } else if (key == LogicalKey.arrowUp || key == LogicalKey.keyK) {
      _move(-1);
    } else if (key == LogicalKey.arrowDown || key == LogicalKey.keyJ) {
      _move(1);
    } else if (key == LogicalKey.home) {
      _move(-1000000);
    } else if (key == LogicalKey.end) {
      _move(1000000);
    } else if (key == LogicalKey.pageUp || key == LogicalKey.pageDown) {
      _move(key == LogicalKey.pageUp ? -10 : 10);
    } else if (key == LogicalKey.keyN) {
      unawaited(_create());
    } else if (key == LogicalKey.keyE) {
      unawaited(_edit());
    } else if (key == LogicalKey.keyD || key == LogicalKey.delete) {
      unawaited(_delete());
    } else if (key == LogicalKey.space || key == LogicalKey.keyX) {
      final list = _list;
      final task = _task;
      if (!_listFocus && list != null && task != null) {
        unawaited(
          _act(
            () => _service.setCompletion(
              list.id,
              task.id,
              task.completed ? Completion.incomplete : Completion.completed,
            ),
          ),
        );
      }
    } else if ([
      LogicalKey.digit1,
      LogicalKey.digit2,
      LogicalKey.digit3,
      LogicalKey.keyF,
    ].contains(key)) {
      setState(() {
        _filter = key == LogicalKey.keyF
            ? TaskFilter.values[(_filter.index + 1) % 3]
            : TaskFilter.values[[
                LogicalKey.digit1,
                LogicalKey.digit2,
                LogicalKey.digit3,
              ].indexOf(key)];
        _taskIndex = 0;
        _taskScroll.jumpTo(0);
      });
    } else if (event.character == '?' || key == LogicalKey.f1) {
      unawaited(
        _dialog<void>((_) => const _HelpDialog(), width: 64, height: 17),
      );
    } else {
      return false;
    }
    return true;
  }

  Component _row(
    String text,
    bool selected,
    bool focused, {
    bool completed = false,
  }) => Container(
    color: selected ? (focused ? Colors.blue : Colors.gray) : null,
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: Text(
      '${selected ? '>' : ' '} $text',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: selected
            ? Colors.white
            : (completed ? Colors.green : Colors.white),
      ),
    ),
  );

  @override
  Component build(BuildContext context) {
    final list = _list;
    final tasks = _tasks;
    final task = _task;
    return Focusable(
      focused: !_dialogOpen,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 48 || constraints.maxHeight < 14) {
            return const Center(
              child: Text('Enlarge terminal to 48 x 14. q quits.'),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                color: Colors.blue,
                child: Text(
                  'TASK LIST  /  ${list?.name ?? 'No list selected'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                ' Filter: ${_filter.label}   1 All | 2 Incomplete | 3 Completed',
                maxLines: 1,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: constraints.maxWidth < 80 ? 20 : 28,
                      decoration: BoxDecoration(
                        border: BoxBorder.all(
                          color: _listFocus ? Colors.cyan : Colors.gray,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            ' LISTS (${_service.lists.length})${_listFocus ? ' [focus]' : ''}',
                          ),
                          Expanded(
                            child: _service.lists.isEmpty
                                ? const Text(
                                    ' No lists yet.\n Press n to create\n your first list.',
                                  )
                                : ListView.builder(
                                    controller: _listScroll,
                                    itemExtent: 1,
                                    itemCount: _service.lists.length,
                                    itemBuilder: (_, index) {
                                      final item = _service.lists[index];
                                      return _row(
                                        '${item.name} (${item.tasks.length})',
                                        index == _listIndex,
                                        _listFocus,
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: BoxBorder.all(
                            color: !_listFocus ? Colors.cyan : Colors.gray,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              ' TASKS (${tasks.length})${!_listFocus ? ' [focus]' : ''}',
                            ),
                            Expanded(
                              child: tasks.isEmpty
                                  ? Text(
                                      list == null
                                          ? ' Create a list with n to begin.'
                                          : list.tasks.isEmpty
                                          ? ' No tasks yet. Press n to add one.'
                                          : ' No ${_filter.label.toLowerCase()} tasks.\n Change filter with 1/2/3 or f.',
                                    )
                                  : ListView.builder(
                                      controller: _taskScroll,
                                      itemExtent: 1,
                                      itemCount: tasks.length,
                                      itemBuilder: (_, index) => _row(
                                        '[${tasks[index].completed ? 'x' : ' '}] ${tasks[index].title}',
                                        index == _taskIndex,
                                        !_listFocus,
                                        completed: tasks[index].completed,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                task == null ? ' No task selected.' : ' ${task.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                task == null
                    ? ' '
                    : ' ID ${task.id} | Created ${task.createdAt.toIso8601String().substring(0, 10)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.gray),
              ),
              Text(
                _busy ? ' Saving…' : ' $_message',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.yellow),
              ),
              const Text(
                ' Tab pane | ↑↓ move | n new | e edit | Space toggle',
                maxLines: 1,
              ),
              const Text(
                ' d delete | 1/2/3 filter | f cycle | ? help | q quit',
                maxLines: 1,
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _EditDialog extends StatefulComponent {
  const _EditDialog(this.heading, this.initial, this.save);
  final String heading;
  final String initial;
  final Future<void> Function(String) save;
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

final class _EditDialogState extends State<_EditDialog> {
  late final _controller = TextEditingController(text: component.initial);
  String _error = '';
  bool _saving = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await component.save(value);
      if (mounted) Navigator.of(context).pop(true);
    } on TaskFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _saving = false;
        });
      }
    }
  }

  @override
  Component build(BuildContext context) => Container(
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(
      color: Colors.black,
      border: BoxBorder.all(color: Colors.cyan),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          component.heading,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 1),
        TextField(
          controller: _controller,
          focused: true,
          readOnly: _saving,
          placeholder: 'Enter a name or task title',
          onKeyEvent: (event) {
            if (event.logicalKey == LogicalKey.escape) {
              if (!_saving) Navigator.of(context).pop(false);
              return true;
            }
            return _saving;
          },
          onSubmitted: (value) => unawaited(_submit(value)),
        ),
        const SizedBox(height: 1),
        Text(_saving ? 'Saving…' : 'Enter save | Esc cancel'),
        Expanded(
          child: Text(_error, style: const TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

final class _ConfirmDialog extends StatelessComponent {
  const _ConfirmDialog(this.warning);
  final String warning;
  @override
  Component build(BuildContext context) => Focusable(
    focused: true,
    onKeyEvent: (event) {
      if (event.logicalKey == LogicalKey.keyY) {
        Navigator.of(context).pop(true);
      } else if (event.logicalKey == LogicalKey.keyN ||
          event.logicalKey == LogicalKey.escape) {
        Navigator.of(context).pop(false);
      }
      return true;
    },
    child: Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: Colors.black,
        border: BoxBorder.all(color: Colors.red),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Permanent deletion',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
          Expanded(child: Text(warning)),
          const Text('y confirm | n / Esc cancel (default)'),
        ],
      ),
    ),
  );
}

final class _HelpDialog extends StatelessComponent {
  const _HelpDialog();
  @override
  Component build(BuildContext context) => Focusable(
    focused: true,
    onKeyEvent: (event) {
      if (event.logicalKey == LogicalKey.escape ||
          event.logicalKey == LogicalKey.enter ||
          event.logicalKey == LogicalKey.keyQ) {
        Navigator.of(context).pop<void>();
      }
      return true;
    },
    child: Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: Colors.black,
        border: BoxBorder.all(color: Colors.cyan),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Keyboard help', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: ListView(
              keyboardScrollable: true,
              children: const [
                Text('Tab / Left / Right: Switch panes'),
                Text('Up / Down / j / k: Select list or task'),
                Text('Home / End: First / last item'),
                Text('Page Up / Page Down: Move ten items'),
                Text('n: Create in the focused pane'),
                Text('e: Rename list / edit task'),
                Text('Space / x: Complete or reopen task'),
                Text('d / Delete: Delete with confirmation'),
                Text('1 / 2 / 3: All / Incomplete / Completed'),
                Text('f: Cycle completion filters'),
                Text('q: Quit (every change is saved)'),
                Text('Enter saves a form; Esc cancels it.'),
                Text('Selection uses stable IDs, not row numbers.'),
              ],
            ),
          ),
          const Text('↑↓ / PgUp/PgDn scroll | Esc close', maxLines: 1),
        ],
      ),
    ),
  );
}
