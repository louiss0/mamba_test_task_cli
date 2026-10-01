import 'dart:io';

import 'package:nocterm/nocterm.dart' hide isEmpty;
import 'package:task_list_cli/application/task_book.dart';
import 'package:task_list_cli/domain/id_source.dart';
import 'package:task_list_cli/domain/task_book_state.dart';
import 'package:task_list_cli/persistence/corrupted_book_exception.dart';
import 'package:task_list_cli/persistence/in_memory_task_repository.dart';
import 'package:task_list_cli/presentation/theme.dart';
import 'package:task_list_cli/tui/shortcuts.dart';
import 'package:task_list_cli/tui/task_list_app.dart';
import 'package:task_list_cli/tui/task_screen.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late CountingRepository repository;
  late TaskBook book;
  late TaskScreen screen;
  late IdSource ids;

  setUp(() async {
    repository = CountingRepository(InMemoryTaskRepository());
    book = TaskBook(repository, ids: ids = deterministicIds());
    await book.load();
    screen = TaskScreen(book);
  });

  /// Sends the key a user would press for [action].
  ///
  /// The mapping is written out rather than derived from the label, because
  /// several actions answer to more than one key and the test has to say which
  /// one it is exercising.
  Future<void> press(NoctermTester tester, Action action) async {
    final (key, character) = switch (action) {
      Action.moveUp => (LogicalKey.keyK, 'k'),
      Action.moveDown => (LogicalKey.keyJ, 'j'),
      Action.jumpToFirst => (LogicalKey.keyG, 'g'),
      Action.jumpToLast => (LogicalKey.end, null),
      Action.togglePane => (LogicalKey.tab, null),
      Action.addTask => (LogicalKey.keyA, 'a'),
      Action.editTask => (LogicalKey.keyE, 'e'),
      Action.toggleDone => (LogicalKey.space, null),
      Action.deleteTask => (LogicalKey.keyD, 'd'),
      Action.newList => (LogicalKey.keyL, 'l'),
      Action.renameList => (LogicalKey.keyR, 'r'),
      Action.deleteList => (LogicalKey.keyL, 'L'),
      Action.previousFilter => (LogicalKey.bracketLeft, '['),
      Action.nextFilter => (LogicalKey.bracketRight, ']'),
      Action.showAll => (LogicalKey.digit1, '1'),
      Action.showIncomplete => (LogicalKey.digit2, '2'),
      Action.showCompleted => (LogicalKey.digit3, '3'),
      Action.showHelp => (LogicalKey.slash, '?'),
      Action.quit => (LogicalKey.keyQ, 'q'),
    };
    await tester.sendKeyEvent(
      KeyboardEvent(logicalKey: key, character: character),
    );
    await tester.pump();
  }

  /// Sends a named key with no character, as a terminal without a keyboard
  /// protocol would report it.
  Future<void> pressBare(NoctermTester tester, LogicalKey key) async {
    await tester.sendKeyEvent(KeyboardEvent(logicalKey: key));
    await tester.pump();
  }

  Future<void> type(NoctermTester tester, String text) async {
    await tester.enterText(text);
    await tester.pump();
  }

  Future<void> boot(NoctermTester tester) async {
    await tester.pumpComponent(
      TuiTheme(
        data: resolveTheme(AppTheme.dark),
        child: TaskListApp(book: book, screen: screen),
      ),
      const Duration(milliseconds: 20),
    );
  }

  /// The text of the sidebar column alone.
  ///
  /// The main pane repeats the open list's name in its empty state, so an
  /// assertion over the whole screen would pass even with the sidebar scrolled
  /// away from it. Reading the column is what actually proves the finding.
  String sidebarOf(NoctermTester tester) => tester.terminalState.getText(
        area: Rect.fromLTWH(
          0,
          0,
          TaskListApp.sidebarWidth,
          tester.terminalState.size.height,
        ),
      );

  group('empty book', () {
    test('explains how to start', () async {
      await testNocterm('empty book', (tester) async {
        await boot(tester);

        expect(tester.terminalState, containsText('No lists'));
        expect(tester.terminalState, containsText('Press l to add one'));
      });
    });
  });

  group('rendering', () {
    setUp(() async {
      final list = await book.createList('Work');
      await book.addTask(list.id, 'Buy milk');
      await book.addTask(list.id, 'Write the report');
    });

    test('shows the list, its tasks, and the filter counts', () async {
      await testNocterm('renders the book', (tester) async {
        await boot(tester);

        expect(tester.terminalState, containsText('Work'));
        expect(tester.terminalState, containsText('Buy milk'));
        expect(tester.terminalState, containsText('Write the report'));
        expect(tester.terminalState, containsText('All 2'));
        expect(tester.terminalState, containsText('Incomplete 2'));
        expect(tester.terminalState, containsText('Completed 0'));
      });
    });

    test('marks a completed task without relying on colour', () async {
      await testNocterm('marks completion', (tester) async {
        await boot(tester);

        expect(tester.terminalState, containsText('[ ]'));

        await press(tester, Action.toggleDone);

        expect(tester.terminalState, containsText('[x]'));
        expect(tester.terminalState, containsText('Completed "Buy milk".'));
      });
    });

    test('explains a list with no tasks', () async {
      await testNocterm('empty list', (tester) async {
        final list = await book.createList('Personal');
        await book.deleteList(book.requireListByName('Work').id);
        expect(book.requireList(list.id).tasks, isEmpty);
        screen.open();

        await boot(tester);

        expect(tester.terminalState, containsText('No tasks in "Personal"'));
        expect(tester.terminalState, containsText('Press a to add one'));
      });
    });

    test('always shows the shortcut hints', () async {
      await testNocterm('hints', (tester) async {
        await boot(tester);

        expect(tester.terminalState, containsText('a add'));
        expect(tester.terminalState, containsText('? help'));
      });
    });

    test('shows every hint without cutting any off', () async {
      await testNocterm('hints fit', (tester) async {
        await boot(tester);

        expect(
          Shortcuts.hintLine().length,
          lessThanOrEqualTo(78),
          reason: 'the bar is one line wide, so a longer summary gets clipped',
        );
        expect(tester.terminalState, containsText('q quit'));
      }, size: const Size(80, 24));
    });
  });

  group('filters', () {
    setUp(() async {
      final list = await book.createList('Work');
      final done = await book.addTask(list.id, 'Send the invoice');
      await book.addTask(list.id, 'Buy milk');
      await book.setTaskCompleted(list.id, done.id, true);
    });

    test('hides completed tasks under the incomplete filter', () async {
      await testNocterm('incomplete filter', (tester) async {
        await boot(tester);
        expect(tester.terminalState, containsText('Send the invoice'));

        await press(tester, Action.showIncomplete);

        expect(tester.terminalState, isNot(containsText('Send the invoice')));
        expect(tester.terminalState, containsText('Buy milk'));
      });
    });

    test('shows only completed tasks under the completed filter', () async {
      await testNocterm('completed filter', (tester) async {
        await boot(tester);

        await press(tester, Action.showCompleted);

        expect(tester.terminalState, containsText('Send the invoice'));
        expect(tester.terminalState, isNot(containsText('Buy milk')));
      });
    });

    test('steps through the filters with the bracket keys', () async {
      await testNocterm('cycle filters', (tester) async {
        await boot(tester);

        await press(tester, Action.nextFilter);
        expect(screen.filter.name, 'incomplete');

        await press(tester, Action.nextFilter);
        expect(screen.filter.name, 'completed');

        await press(tester, Action.previousFilter);
        expect(screen.filter.name, 'incomplete');
      });
    });

    test('removes a completed task from the incomplete view straight away',
        () async {
      await testNocterm('complete under a filter', (tester) async {
        await boot(tester);
        await press(tester, Action.showIncomplete);
        expect(tester.terminalState, containsText('Buy milk'));

        await press(tester, Action.toggleDone);
        await tester.pump(const Duration(milliseconds: 20));

        expect(
          tester.terminalState,
          containsText('Nothing left in "Work"'),
          reason: 'the task no longer belongs in this view',
        );
        expect(
          tester.terminalState,
          containsText('Incomplete 0'),
        );
        expect(
          screen.selectedTask,
          isNull,
        );
      });
    });

    test('does not write to the book just to change the filter', () async {
      await testNocterm('filter is a read', (tester) async {
        await boot(tester);
        final writesBefore = repository.writeCount;

        await press(tester, Action.showIncomplete);
        await press(tester, Action.showCompleted);
        await press(tester, Action.showAll);

        expect(repository.writeCount, writesBefore);
      });
    });
  });

  group('keyboard navigation', () {
    setUp(() async {
      final list = await book.createList('Work');
      await book.addTask(list.id, 'One');
      await book.addTask(list.id, 'Two');
    });

    test('moves the highlight with the arrow keys', () async {
      await testNocterm('arrows', (tester) async {
        await boot(tester);
        expect(screen.selectedTask?.title, 'One');

        await pressBare(tester, LogicalKey.arrowDown);
        expect(screen.selectedTask?.title, 'Two');

        await pressBare(tester, LogicalKey.arrowUp);
        expect(screen.selectedTask?.title, 'One');
      });
    });

    test('moves the highlight with the vim keys', () async {
      await testNocterm('vim keys', (tester) async {
        await boot(tester);

        await press(tester, Action.moveDown);
        expect(screen.selectedTask?.title, 'Two');

        await press(tester, Action.moveUp);
        expect(screen.selectedTask?.title, 'One');
      });
    });

    test('switches focus to the lists and back', () async {
      await testNocterm('pane switch', (tester) async {
        await boot(tester);

        await pressBare(tester, LogicalKey.tab);
        expect(screen.pane.name, 'lists');

        await pressBare(tester, LogicalKey.tab);
        expect(screen.pane.name, 'tasks');
      });
    });
  });

  group('dialogs', () {
    setUp(() async {
      await book.createList('Work');
    });

    test('adds a task through the prompt', () async {
      await testNocterm('add dialog', (tester) async {
        await boot(tester);

        await press(tester, Action.addTask);
        expect(tester.terminalState, containsText('Add a task'));

        await type(tester, 'Water the plants');
        await pressBare(tester, LogicalKey.enter);
        await tester.pump(const Duration(milliseconds: 20));

        expect(tester.terminalState, containsText('Water the plants'));
        expect(book.requireListByName('Work').tasks.single.title,
            'Water the plants');
      });
    });

    test('cancels the prompt with escape and adds nothing', () async {
      await testNocterm('cancel add', (tester) async {
        await boot(tester);

        await press(tester, Action.addTask);
        await type(tester, 'Never saved');
        await pressBare(tester, LogicalKey.escape);
        await tester.pump(const Duration(milliseconds: 20));

        expect(tester.terminalState, isNot(containsText('Never saved')));
        expect(book.requireListByName('Work').tasks, isEmpty);
      });
    });

    test('keeps the dialog open and explains a rejected value', () async {
      await testNocterm('reject add', (tester) async {
        await boot(tester);

        await press(tester, Action.addTask);
        await pressBare(tester, LogicalKey.enter);
        await tester.pump(const Duration(milliseconds: 20));

        expect(tester.terminalState, containsText('Add a task'));
        expect(tester.terminalState, containsText('cannot be empty'));
        expect(book.requireListByName('Work').tasks, isEmpty);
      });
    });

    test('refuses a duplicate list name inside the dialog', () async {
      await testNocterm('reject duplicate list', (tester) async {
        await boot(tester);

        await press(tester, Action.newList);
        await type(tester, 'work');
        await pressBare(tester, LogicalKey.enter);
        await tester.pump(const Duration(milliseconds: 20));

        expect(tester.terminalState, containsText('New list'));
        expect(tester.terminalState, containsText('already exists'));
        expect(book.lists, hasLength(1));
      });
    });

    test('keeps a d typed into the field from deleting a task', () async {
      await testNocterm('keys stay in the field', (tester) async {
        final list = book.requireListByName('Work');
        await book.addTask(list.id, 'One');
        await boot(tester);

        await press(tester, Action.addTask);
        await type(tester, 'delete');
        await tester.pump(const Duration(milliseconds: 20));

        expect(tester.terminalState, containsText('delete'));
        expect(
          book.requireList(list.id).tasks,
          hasLength(1),
          reason: 'typing a title must never delete anything',
        );
      });
    });

    test('creates a list through the prompt', () async {
      await testNocterm('new list dialog', (tester) async {
        await boot(tester);

        await press(tester, Action.newList);
        await type(tester, 'Personal');
        await pressBare(tester, LogicalKey.enter);
        await tester.pump(const Duration(milliseconds: 20));

        expect(book.lists.map((list) => list.name), ['Work', 'Personal']);
        expect(tester.terminalState, containsText('Created list "Personal".'));
      });
    });
  });

  group('destructive actions', () {
    setUp(() async {
      final list = await book.createList('Work');
      await book.addTask(list.id, 'Buy milk');
    });

    test('asks before deleting a task and does nothing on cancel', () async {
      await testNocterm('cancel delete task', (tester) async {
        await boot(tester);

        await press(tester, Action.deleteTask);
        expect(tester.terminalState, containsText('Delete task'));
        expect(tester.terminalState, containsText('Delete "Buy milk"?'));

        await pressBare(tester, LogicalKey.escape);
        await tester.pump(const Duration(milliseconds: 20));

        expect(book.requireListByName('Work').tasks, hasLength(1));
      });
    });

    test('deletes the task once confirmed', () async {
      await testNocterm('confirm delete task', (tester) async {
        await boot(tester);

        await press(tester, Action.deleteTask);
        await pressBare(tester, LogicalKey.enter);
        await tester.pump(const Duration(milliseconds: 20));

        expect(book.requireListByName('Work').tasks, isEmpty);
        expect(tester.terminalState, containsText('Deleted "Buy milk".'));
      });
    });

    test('asks before deleting a list and states how many tasks go', () async {
      await testNocterm('confirm delete list', (tester) async {
        await boot(tester);

        await press(tester, Action.deleteList);

        expect(tester.terminalState, containsText('Delete list'));
        expect(
          tester.terminalState,
          containsText('Delete "Work" and its 1 task?'),
        );
        expect(book.lists, hasLength(1));
      });
    });

    test('deletes the list once confirmed', () async {
      await testNocterm('delete list', (tester) async {
        await boot(tester);

        await press(tester, Action.deleteList);
        await pressBare(tester, LogicalKey.enter);
        await tester.pump(const Duration(milliseconds: 20));

        expect(book.lists, isEmpty);
      });
    });
  });

  group('help', () {
    test('opens and closes with the help key', () async {
      await testNocterm('help', (tester) async {
        await book.createList('Work');
        await boot(tester);

        await press(tester, Action.showHelp);
        expect(tester.terminalState, containsText('Keyboard'));
        expect(tester.terminalState, containsText('drop list'));
        expect(tester.terminalState, containsText('rename'));
        expect(tester.terminalState, containsText('Press any key to close'));

        await pressBare(tester, LogicalKey.escape);
        expect(tester.terminalState, isNot(containsText('Keyboard')));
      });
    });

    test('fits inside a short terminal', () async {
      await testNocterm('help fits', (tester) async {
        await book.createList('Work');
        await boot(tester);

        await press(tester, Action.showHelp);

        expect(
          tester.terminalState,
          containsText('Press any key to close'),
          reason: 'the whole reference has to be readable at once',
        );
      }, size: const Size(80, 24));
    });
  });

  group('persistence through the interface', () {
    test('a change made in the interface reaches the saved book', () async {
      await testNocterm('persists', (tester) async {
        await book.createList('Work');
        await boot(tester);

        await press(tester, Action.addTask);
        await type(tester, 'Ship it');
        await pressBare(tester, LogicalKey.enter);
        await tester.pump(const Duration(milliseconds: 20));

        final reopened = TaskBook(repository);
        await reopened.load();
        expect(
          reopened.requireListByName('Work').tasks.single.title,
          'Ship it',
        );
      });
    });
  });

  group('the sidebar always names the open list', () {
    /// Creates [count] lists named `List0` .. `List<count - 1>`.
    Future<void> seedMany(int count) async {
      for (var i = 0; i < count; i++) {
        await book.createList('List$i');
      }
    }

    test('follows the highlight down an overflowing sidebar', () async {
      await testNocterm('sidebar scrolls', (tester) async {
        await seedMany(30);
        await boot(tester);

        await pressBare(tester, LogicalKey.tab);
        for (var i = 0; i < 29; i++) {
          await press(tester, Action.moveDown);
        }

        expect(screen.currentList?.name, 'List29');
        expect(
          sidebarOf(tester),
          contains('List29'),
          reason: 'the open list has to stay on screen at all',
        );
        expect(
          sidebarOf(tester),
          isNot(contains('List0 ')),
          reason: 'the sidebar scrolls rather than growing',
        );
      }, size: const Size(80, 24));
    });

    test('reveals a list created below the fold', () async {
      await testNocterm('sidebar reveals new list', (tester) async {
        await seedMany(28);
        await boot(tester);
        await pressBare(tester, LogicalKey.tab);
        for (var i = 0; i < 27; i++) {
          await press(tester, Action.moveDown);
        }

        await press(tester, Action.newList);
        await type(tester, 'Fresh');
        await pressBare(tester, LogicalKey.enter);
        await tester.pump(const Duration(milliseconds: 20));

        expect(screen.currentList?.name, 'Fresh');
        expect(sidebarOf(tester), contains('Fresh'));
      }, size: const Size(80, 24));
    });

    test('reveals the neighbour taken over after a deletion', () async {
      await testNocterm('sidebar follows deletion', (tester) async {
        await seedMany(28);
        await boot(tester);
        await pressBare(tester, LogicalKey.tab);
        for (var i = 0; i < 27; i++) {
          await press(tester, Action.moveDown);
        }
        expect(screen.currentList?.name, 'List27');

        await press(tester, Action.deleteList);
        await pressBare(tester, LogicalKey.enter);
        await tester.pump(const Duration(milliseconds: 20));

        expect(screen.currentList?.name, 'List26');
        expect(
          sidebarOf(tester),
          contains('List26'),
          reason: 'the list that took over has to be on screen',
        );
      }, size: const Size(80, 24));
    });
  });

  group('failures the interface has to survive', () {
    /// Opens a screen over a book whose writes always fail with [error].
    Future<TaskScreen> failingScreen(Object error) async {
      final starter = TaskBook(InMemoryTaskRepository(), ids: ids);
      await starter.load();
      final list = await starter.createList('Work');
      await starter.addTask(list.id, 'Buy milk');
      final saved = starter.state;

      final failing = TaskBook(
        FailingRepository(error, saved),
        ids: ids,
      );
      await failing.load();
      return TaskScreen(failing);
    }

    test('unreadable saved data is explained in full', () async {
      await testNocterm('corrupted data', (tester) async {
        screen = await failingScreen(
          CorruptedBookException(
            path: '/data/task_book.json',
            reason: 'The file is not valid JSON.',
          ),
        );
        await boot(tester);

        await press(tester, Action.toggleDone);
        await tester.pump(const Duration(milliseconds: 30));

        expect(tester.terminalState, containsText('Saved data cannot be read'));
        expect(
          tester.terminalState,
          containsText('/data/task_book.json'),
          reason: 'the user has to be able to find the file',
        );
        expect(tester.terminalState, containsText('Press any key to continue'));
      });
    });

    test('a file it cannot write says the change was not saved', () async {
      await testNocterm('failed write', (tester) async {
        screen = await failingScreen(
          FileSystemException('disk full', '/data/task_book.json'),
        );
        await boot(tester);

        await press(tester, Action.toggleDone);
        await tester.pump(const Duration(milliseconds: 30));

        expect(tester.terminalState, containsText('Cannot save the data file'));
        expect(tester.terminalState, containsText('not saved'));
      });
    });

    test('the interface keeps working after a failure', () async {
      await testNocterm('recovers', (tester) async {
        screen = await failingScreen(
          CorruptedBookException(path: '/data/task_book.json', reason: 'bad'),
        );
        await boot(tester);

        await press(tester, Action.toggleDone);
        await tester.pump(const Duration(milliseconds: 30));
        expect(tester.terminalState, containsText('cannot be read'));

        await pressBare(tester, LogicalKey.escape);
        await tester.pump();
        expect(tester.terminalState, isNot(containsText('Press any key')));

        // The task is untouched and the screen still draws and navigates.
        expect(tester.terminalState, containsText('Buy milk'));
        expect(screen.selectedTask?.title, 'Buy milk');
        await press(tester, Action.moveDown);
        expect(tester.terminalState, containsText('Buy milk'));
      });
    });

    test('a selection that another book removed is reported, not fatal',
        () async {
      await testNocterm('stale selection', (tester) async {
        final starter = TaskBook(InMemoryTaskRepository(), ids: ids);
        await starter.load();
        final list = await starter.createList('Work');
        await starter.addTask(list.id, 'Buy milk');

        // This instance loaded a book that still has the list; the file has
        // since lost it.
        final diverging = TaskBook(
          DivergingRepository(
            loaded: starter.state,
            onDisk: TaskBookState.empty,
          ),
          ids: ids,
        );
        await diverging.load();
        screen = TaskScreen(diverging);
        await boot(tester);
        expect(screen.selectedTask?.title, 'Buy milk');

        await press(tester, Action.toggleDone);
        await tester.pump(const Duration(milliseconds: 30));

        expect(tester.terminalState, containsText('No longer there'));
        expect(
          screen.selectedTask?.completed,
          isFalse,
          reason: 'a change that could not be saved must not look applied',
        );

        // Dismissing leaves a usable screen rather than a blank one.
        await pressBare(tester, LogicalKey.escape);
        await tester.pump();
        expect(tester.terminalState, containsText('Buy milk'));
        expect(screen.status, 'No longer there');
      });
    });
  });
}
