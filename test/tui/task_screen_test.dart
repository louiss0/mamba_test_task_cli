import 'package:task_list_cli/application/task_book.dart';
import 'package:task_list_cli/domain/completion_filter.dart';
import 'package:task_list_cli/domain/task_list.dart';
import 'package:task_list_cli/domain/validation.dart';
import 'package:task_list_cli/persistence/in_memory_task_repository.dart';
import 'package:task_list_cli/tui/pane.dart';
import 'package:task_list_cli/tui/task_screen.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late CountingRepository repository;
  late TaskBook book;
  late TaskScreen screen;

  setUp(() async {
    repository = CountingRepository(InMemoryTaskRepository());
    book = TaskBook(repository, ids: deterministicIds());
    await book.load();
    screen = TaskScreen(book);
  });

  List<String> titles() =>
      [for (final task in screen.visibleTasks) task.title];

  /// Creates a list with [titles] and opens the screen on it.
  Future<TaskList> seedList(String name, List<String> titles) async {
    final list = await book.createList(name);
    for (final title in titles) {
      await book.addTask(list.id, title);
    }
    return book.requireList(list.id);
  }

  group('opening', () {
    test('shows an empty book', () {
      screen.open();

      expect(screen.lists, isEmpty);
      expect(screen.currentList, isNull);
      expect(screen.visibleTasks, isEmpty);
      expect(screen.selectedTask, isNull);
      expect(screen.selectedIndex, -1);
    });

    test('starts on the first list with its first task selected', () async {
      await seedList('Work', ['One', 'Two']);
      await book.createList('Personal');

      screen.open();

      expect(screen.currentList?.name, 'Work');
      expect(screen.selectedTask?.title, 'One');
      expect(screen.pane, Pane.tasks);
    });
  });

  group('navigation', () {
    setUp(() async {
      await seedList('Work', ['One', 'Two', 'Three']);
      await book.createList('Personal');
      screen.open();
    });

    test('moves down and up through the tasks', () {
      expect(screen.selectedTask?.title, 'One');

      screen.moveSelection(1);
      expect(screen.selectedTask?.title, 'Two');

      screen.moveSelection(1);
      expect(screen.selectedTask?.title, 'Three');

      screen.moveSelection(-1);
      expect(screen.selectedTask?.title, 'Two');
    });

    test('stops at the ends instead of wrapping', () {
      screen.moveSelectionToEdge(last: true);
      expect(screen.selectedTask?.title, 'Three');

      screen.moveSelection(1);
      expect(screen.selectedTask?.title, 'Three');

      screen.moveSelectionToEdge(last: false);
      screen.moveSelection(-1);
      expect(screen.selectedTask?.title, 'One');
    });

    test('switches between the list pane and the task pane', () {
      screen.moveSelection(1);
      expect(screen.pane, Pane.tasks);
      expect(screen.selectedTask?.title, 'Two');

      screen.togglePane();
      expect(screen.pane, Pane.lists);
      expect(screen.selectedListIndex, 0);

      screen.moveSelection(1);
      expect(screen.currentList?.name, 'Personal');
      expect(screen.visibleTasks, isEmpty);

      screen.togglePane();
      expect(screen.pane, Pane.tasks);
      expect(screen.currentList?.name, 'Personal');
    });

    test('keeps the highlight on a task, not a row number', () async {
      final chosen = screen.selectedTask!;

      await book.addTask(book.requireListByName('Work').id, 'Zero');

      screen.reconcile();

      expect(
        screen.selectedTask?.id,
        chosen.id,
        reason: 'a new task above must not move the highlight',
      );
      expect(screen.selectedTask?.title, 'One');
    });
  });

  group('filters', () {
    setUp(() async {
      final list = await seedList('Work', ['Open one', 'Open two']);
      final done = book.requireList(list.id).tasks.last;
      await book.setTaskCompleted(list.id, done.id, true);
      screen.open();
    });

    test('starts on all tasks', () {
      expect(screen.filter, CompletionFilter.all);
      expect(titles(), ['Open one', 'Open two']);
    });

    test('hides completed tasks under the incomplete filter', () {
      screen.applyFilter(CompletionFilter.incomplete);

      expect(titles(), ['Open one']);
    });

    test('shows only completed tasks under the completed filter', () {
      screen.applyFilter(CompletionFilter.completed);

      expect(titles(), ['Open two']);
    });

    test('steps forward and backward through every filter, wrapping around',
        () {
      screen.stepFilter(1);
      expect(screen.filter, CompletionFilter.incomplete);
      screen.stepFilter(1);
      expect(screen.filter, CompletionFilter.completed);
      screen.stepFilter(1);
      expect(screen.filter, CompletionFilter.all);
      screen.stepFilter(-1);
      expect(screen.filter, CompletionFilter.completed);
    });

    test('applies within the list that is open', () async {
      await seedList('Personal', ['Other']);
      screen.applyFilter(CompletionFilter.incomplete);
      screen.selectList(book.requireListByName('Personal').id);

      expect(titles(), ['Other']);
    });

    test('does not change the saved book', () {
      final writesBefore = repository.writeCount;

      screen.applyFilter(CompletionFilter.completed);
      screen.stepFilter(1);
      screen.stepFilter(-1);
      screen.applyFilter(CompletionFilter.incomplete);

      expect(book.requireListByName('Work').tasks, hasLength(2));
      expect(repository.writeCount, writesBefore);
    });
  });

  group('completing a task', () {
    setUp(() async {
      await seedList('Work', ['One', 'Two', 'Three']);
      screen.open();
    });

    test('marks the selected task complete', () async {
      await screen.toggleSelectedTask();

      expect(screen.selectedTask?.completed, isTrue);
      expect(screen.status, 'Completed "One".');
    });

    test('reopens a completed task', () async {
      await screen.toggleSelectedTask();

      await screen.toggleSelectedTask();

      expect(screen.selectedTask?.completed, isFalse);
      expect(screen.status, 'Reopened "One".');
    });

    test('drops the row from the incomplete view and moves the highlight on',
        () async {
      screen.applyFilter(CompletionFilter.incomplete);
      expect(screen.selectedTask?.title, 'One');
      expect(titles(), ['One', 'Two', 'Three']);

      await screen.toggleSelectedTask();

      expect(
        titles(),
        ['Two', 'Three'],
        reason: 'the completed task no longer belongs in this view',
      );
      expect(
        screen.selectedTask?.title,
        'Two',
        reason: 'the highlight lands on the task that took its place',
      );
    });

    test('leaves the task in the all view after reopening it', () async {
      await screen.toggleSelectedTask();
      await screen.toggleSelectedTask();

      expect(titles(), ['One', 'Two', 'Three']);
      expect(screen.selectedTask?.title, 'One');
      expect(screen.selectedTask?.completed, isFalse);
    });

    test('leaves the other tasks alone', () async {
      await screen.toggleSelectedTask();

      expect(
        [for (final task in book.requireListByName('Work').tasks) task.completed],
        [true, false, false],
      );
    });
  });

  group('adding and editing', () {
    setUp(() async {
      await seedList('Work', ['One']);
      screen.open();
    });

    test('adds a task and highlights it', () async {
      await screen.addTask('Two');

      expect(titles(), ['One', 'Two']);
      expect(screen.selectedTask?.title, 'Two');
      expect(screen.status, 'Added "Two".');
    });

    test('trims the title it is given', () async {
      await screen.addTask('  Two  ');

      expect(titles(), ['One', 'Two']);
    });

    test('reports an empty title and leaves the book alone', () async {
      await expectLater(
        screen.addTask('   '),
        throwsA(isA<ValidationException>()),
      );

      expect(titles(), ['One']);
      expect(screen.statusIsError, isTrue);
      expect(screen.status, contains('cannot be empty'));
    });

    test('renames the selected task', () async {
      await screen.renameSelectedTask('Renamed');

      expect(titles(), ['Renamed']);
      expect(screen.status, contains('Renamed'));
    });

    test('reports that nothing is selected', () async {
      screen.applyFilter(CompletionFilter.completed);

      await screen.renameSelectedTask('Renamed');

      expect(screen.status, 'Select a task first.');
      expect(screen.statusIsError, isTrue);
    });
  });

  group('deleting', () {
    setUp(() async {
      await seedList('Work', ['One', 'Two']);
      screen.open();
    });

    test('deletes the selected task', () async {
      await screen.deleteSelectedTask();

      expect(titles(), ['Two']);
      expect(screen.status, 'Deleted "One".');
    });

    test('moves the highlight to the neighbour when the last row goes', () async {
      screen.moveSelectionToEdge(last: true);

      await screen.deleteSelectedTask();

      expect(screen.selectedTask?.title, 'One');
    });

    test('deletes a list and moves to the one that remains', () async {
      await book.createList('Personal');

      await screen.deleteCurrentList();

      expect(screen.currentList?.name, 'Personal');
      expect(screen.status, 'Deleted list "Work" and 2 tasks.');
    });

    test('lands on the first list when the only one is deleted', () async {
      await screen.deleteCurrentList();

      expect(screen.currentList, isNull);
      expect(screen.lists, isEmpty);
    });

    test('reports that there is no list to delete', () async {
      await screen.deleteCurrentList();

      await screen.deleteCurrentList();

      expect(screen.statusIsError, isTrue);
      expect(screen.status, 'There is no list to delete.');
    });
  });

  group('lists', () {
    test('creates a list and opens it', () async {
      await screen.createList('Work');

      expect(screen.currentList?.name, 'Work');
      expect(screen.status, 'Created list "Work".');
    });

    test('reports a duplicate name without changing the book', () async {
      await screen.createList('Work');

      await expectLater(
        screen.createList('work'),
        throwsA(isA<ValidationException>()),
      );
      expect(screen.lists, hasLength(1));
      expect(screen.statusIsError, isTrue);
    });

    test('renames the open list and keeps following it', () async {
      await seedList('Work', ['One']);
      screen.open();

      await screen.renameCurrentList('Office');

      expect(screen.currentList?.name, 'Office');
      expect(titles(), ['One']);
    });
  });

  group('reconcile', () {
    test('lands on a neighbour when the open list disappears', () async {
      await seedList('Work', ['One']);
      await book.createList('Personal');
      screen.open();

      await book.deleteList(book.requireListByName('Work').id);
      screen.reconcile();

      expect(screen.currentList?.name, 'Personal');
    });

    test('keeps the highlight on the same task across an external change',
        () async {
      final list = await seedList('Work', ['One', 'Two', 'Three']);
      screen.open();
      screen.moveSelection(2);
      final chosen = screen.selectedTask!;

      await book.addTask(list.id, 'Zero');
      screen.reconcile();

      expect(screen.selectedTask?.id, chosen.id);
    });
  });
}
