import 'package:task_list_cli/application/task_book.dart';
import 'package:task_list_cli/domain/completion_filter.dart';
import 'package:task_list_cli/domain/task_filter.dart';
import 'package:task_list_cli/domain/validation.dart';
import 'package:task_list_cli/persistence/in_memory_task_repository.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late CountingRepository repository;
  late TaskBook book;

  setUp(() async {
    repository = CountingRepository(InMemoryTaskRepository());
    book = TaskBook(repository, ids: deterministicIds());
    await book.load();
  });

  /// Returns a fresh book that reloads the same repository, standing in for a
  /// second run of the application.
  Future<TaskBook> restart() async {
    final reopened = TaskBook(repository, ids: deterministicIds());
    await reopened.load();
    return reopened;
  }

  List<String> titlesOf(Iterable<dynamic> tasks) =>
      [for (final task in tasks) '${task.title}:${task.completed}'];

  group('lists', () {
    test('a new book has no lists', () {
      expect(book.lists, isEmpty);
      expect(book.defaultList, isNull);
    });

    test('creates a list', () async {
      final list = await book.createList('Work');

      expect(list.name, 'Work');
      expect(book.lists, hasLength(1));
    });

    test('trims the name', () async {
      expect((await book.createList('  Work  ')).name, 'Work');
    });

    test('refuses an empty name', () async {
      expect(
        book.createList('   '),
        throwsA(isA<ValidationException>()),
      );
    });

    test('refuses a name that is already taken', () async {
      await book.createList('Work');

      expect(
        book.createList('Work'),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
    });

    test('refuses a name that only differs in case', () async {
      await book.createList('Work');

      expect(book.createList('work'), throwsA(isA<ValidationException>()));
    });

    test('refuses a name longer than the limit', () async {
      expect(
        book.createList('x' * 500),
        throwsA(isA<ValidationException>()),
      );
    });

    test('renames a list and keeps its tasks', () async {
      final list = await book.createList('Work');
      await book.addTask(list.id, 'Ship it');

      final renamed = await book.renameList(list.id, 'Office');

      expect(renamed.name, 'Office');
      expect(renamed.tasks.single.title, 'Ship it');
    });

    test('refuses to rename a list onto another list name', () async {
      await book.createList('Work');
      final office = await book.createList('Office');

      expect(
        book.renameList(office.id, 'Work'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('refuses to rename a list that no longer exists', () async {
      final list = await book.createList('Work');
      await book.deleteList(list.id);

      expect(book.renameList(list.id, 'Office'), throwsA(isA<NotFoundException>()));
    });

    test('deletes a list and its tasks', () async {
      final list = await book.createList('Work');
      await book.addTask(list.id, 'Ship it');

      await book.deleteList(list.id);

      expect(book.lists, isEmpty);
      expect((await repository.load()).lists, isEmpty);
    });

    test('finds a list by name ignoring case', () async {
      await book.createList('Work');

      expect(book.requireListByName('  wOrK ').name, 'Work');
    });

    test('reports an unknown list name', () {
      expect(
        () => book.requireListByName('Nope'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('the default list is the first one', () async {
      await book.createList('Work');
      await book.createList('Personal');

      expect(book.defaultList?.name, 'Work');
    });
  });

  group('tasks', () {
    late String listId;

    setUp(() async {
      listId = (await book.createList('Work')).id;
    });

    test('adds an incomplete task with a creation time', () async {
      final task = await book.addTask(listId, 'Write the report');

      expect(task.title, 'Write the report');
      expect(task.completed, isFalse);
      expect(task.id, isNotEmpty);
      expect(task.createdAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(book.requireList(listId).tasks, hasLength(1));
    });

    test('trims the title', () async {
      expect((await book.addTask(listId, '  Buy milk  ')).title, 'Buy milk');
    });

    test('refuses an empty title', () async {
      expect(book.addTask(listId, '   '), throwsA(isA<ValidationException>()));
    });

    test('edits a title and leaves the identity and state alone', () async {
      final task = await book.addTask(listId, 'Old title');
      await book.setTaskCompleted(listId, task.id, true);

      final edited = await book.editTask(listId, task.id, 'New title');

      expect(edited.title, 'New title');
      expect(edited.id, task.id);
      expect(edited.completed, isTrue);
    });

    test('completes a task without removing it', () async {
      final task = await book.addTask(listId, 'Write the report');

      final completed = await book.setTaskCompleted(listId, task.id, true);

      expect(completed.completed, isTrue);
      expect(book.requireList(listId).tasks, hasLength(1));
    });

    test('reopens a completed task', () async {
      final task = await book.addTask(listId, 'Write the report');
      await book.setTaskCompleted(listId, task.id, true);

      final reopened = await book.setTaskCompleted(listId, task.id, false);

      expect(reopened.completed, isFalse);
      expect(book.requireList(listId).tasks, hasLength(1));
    });

    test('deletes a task', () async {
      final task = await book.addTask(listId, 'Write the report');
      await book.addTask(listId, 'Keep me');

      await book.deleteTask(listId, task.id);

      expect(
        titlesOf(book.requireList(listId).tasks),
        ['Keep me:false'],
      );
    });

    test('refuses to add to a list that no longer exists', () async {
      await book.deleteList(listId);

      expect(book.addTask(listId, 'Orphan'), throwsA(isA<NotFoundException>()));
    });

    test('reports an unknown task', () async {
      expect(
        () => book.requireList(listId).requireTask('nope'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('every task gets its own identity', () async {
      final first = await book.addTask(listId, 'One');
      final second = await book.addTask(listId, 'Two');

      expect(first.id, isNot(second.id));
    });

    test('a reference resolves only its own task', () async {
      final first = await book.addTask(listId, 'One');
      final second = await book.addTask(listId, 'Two');
      final list = book.requireList(listId);

      expect(list.taskByReference(first.reference)?.id, first.id);
      expect(list.countReferenceMatches(first.reference), 1);
      expect(list.taskByReference(second.reference)?.id, second.id);
    });
  });

  group('filtering', () {
    late String listId;

    setUp(() async {
      listId = (await book.createList('Work')).id;
    });

    test('shows every task for the all filter', () async {
      final open = await book.addTask(listId, 'Open one');
      final done = await book.addTask(listId, 'Done one');
      await book.setTaskCompleted(listId, done.id, true);
      await book.setTaskCompleted(listId, open.id, false);

      final shown = book.queryTasks(
        listId,
        TaskFilter.byCompletion(CompletionFilter.all),
      );

      expect(titlesOf(shown), ['Open one:false', 'Done one:true']);
    });

    test('shows only unfinished tasks for the incomplete filter', () async {
      final open = await book.addTask(listId, 'Open one');
      final done = await book.addTask(listId, 'Done one');
      await book.setTaskCompleted(listId, done.id, true);
      await book.setTaskCompleted(listId, open.id, false);

      final shown = book.queryTasks(
        listId,
        TaskFilter.byCompletion(CompletionFilter.incomplete),
      );

      expect(titlesOf(shown), ['Open one:false']);
    });

    test('shows only finished tasks for the completed filter', () async {
      final open = await book.addTask(listId, 'Open one');
      final done = await book.addTask(listId, 'Done one');
      await book.setTaskCompleted(listId, done.id, true);
      await book.setTaskCompleted(listId, open.id, false);

      final shown = book.queryTasks(
        listId,
        TaskFilter.byCompletion(CompletionFilter.completed),
      );

      expect(titlesOf(shown), ['Done one:true']);
    });

    test('does not change the stored tasks', () async {
      await book.addTask(listId, 'Open one');
      final done = await book.addTask(listId, 'Done one');
      await book.setTaskCompleted(listId, done.id, true);
      final writesBefore = repository.writeCount;

      book.queryTasks(
        listId,
        TaskFilter.byCompletion(CompletionFilter.incomplete),
      );
      book.queryTasks(
        listId,
        TaskFilter.byCompletion(CompletionFilter.completed),
      );

      expect(book.requireList(listId).tasks, hasLength(2));
      expect(
        repository.writeCount,
        writesBefore,
        reason: 'reading through a filter must never write to disk',
      );
    });

    test('follows a task across a completion change', () async {
      final open = await book.addTask(listId, 'Open one');
      final done = await book.addTask(listId, 'Done one');
      await book.setTaskCompleted(listId, done.id, true);
      await book.setTaskCompleted(listId, open.id, false);
      final incomplete = TaskFilter.byCompletion(CompletionFilter.incomplete);

      expect(titlesOf(book.queryTasks(listId, incomplete)), ['Open one:false']);

      await book.setTaskCompleted(listId, open.id, true);

      expect(book.queryTasks(listId, incomplete), isEmpty);
    });

    test('combines filters so more can be added later', () async {
      final open = await book.addTask(listId, 'Keep me');
      final done = await book.addTask(listId, 'Hide me');
      await book.setTaskCompleted(listId, done.id, true);
      await book.setTaskCompleted(listId, open.id, false);

      final combined = TaskFilter.byCompletion(CompletionFilter.incomplete)
          .and(TaskFilter.every);

      expect(titlesOf(book.queryTasks(listId, combined)), ['Keep me:false']);
    });
  });

  group('isolation between lists', () {
    test('a task in one list never appears in another', () async {
      final work = await book.createList('Work');
      final home = await book.createList('Personal');
      await book.addTask(work.id, 'Deploy');
      await book.addTask(home.id, 'Water plants');

      expect(titlesOf(book.requireList(work.id).tasks), ['Deploy:false']);
      expect(titlesOf(book.requireList(home.id).tasks), ['Water plants:false']);
    });

    test('filtering one list does not touch another', () async {
      final work = await book.createList('Work');
      final home = await book.createList('Personal');
      final deployed = await book.addTask(work.id, 'Deploy');
      await book.addTask(home.id, 'Water plants');
      await book.setTaskCompleted(work.id, deployed.id, true);

      final completed = TaskFilter.byCompletion(CompletionFilter.completed);

      expect(book.queryTasks(work.id, completed), hasLength(1));
      expect(book.queryTasks(home.id, completed), isEmpty);
    });

    test('deleting a list leaves the others untouched', () async {
      final work = await book.createList('Work');
      final home = await book.createList('Personal');
      await book.addTask(work.id, 'Deploy');
      await book.addTask(home.id, 'Water plants');

      await book.deleteList(work.id);

      expect(titlesOf(book.requireList(home.id).tasks), ['Water plants:false']);
    });

    test('two tasks with the same title stay separate', () async {
      final work = await book.createList('Work');
      final home = await book.createList('Personal');
      final inWork = await book.addTask(work.id, 'Review');
      final inHome = await book.addTask(home.id, 'Review');
      await book.setTaskCompleted(work.id, inWork.id, true);

      expect(inWork.id, isNot(inHome.id));
      expect(book.requireList(home.id).tasks.single.completed, isFalse);
    });
  });

  group('persistence', () {
    test('survives a restart', () async {
      final list = await book.createList('Work');
      final task = await book.addTask(list.id, 'Write the report');
      await book.setTaskCompleted(list.id, task.id, true);

      final reopened = await restart();

      expect(reopened.lists.single.name, 'Work');
      expect(reopened.lists.single.tasks.single.title, 'Write the report');
      expect(reopened.lists.single.tasks.single.completed, isTrue);
    });

    test('keeps identities stable across a restart', () async {
      final list = await book.createList('Work');
      final task = await book.addTask(list.id, 'Write the report');

      final reopened = await restart();

      expect(reopened.lists.single.id, list.id);
      expect(reopened.lists.single.tasks.single.id, task.id);
    });

    test('saves only when something actually changed', () async {
      final list = await book.createList('Work');
      final writesAfterCreate = repository.writeCount;

      book.queryTasks(list.id, TaskFilter.every);
      book.lists;

      expect(repository.writeCount, writesAfterCreate);
    });

    test('picks up a change another process made in the meantime', () async {
      final list = await book.createList('Work');
      final stale = await restart();

      // Another instance renames the list while this one is holding a copy.
      await book.renameList(list.id, 'Office');

      // The next change from the stale instance is applied on top of the
      // current file, not on top of its outdated copy, so the rename is not
      // silently rolled back.
      await stale.addTask(list.id, 'Deploy');

      final observer = await restart();
      expect(observer.requireList(list.id).name, 'Office');
      expect(titlesOf(observer.requireList(list.id).tasks), ['Deploy:false']);
    });
  });
}
