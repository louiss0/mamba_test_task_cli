import 'dart:io';

import 'package:nocterm/nocterm.dart' hide isEmpty;
import 'package:task_list_cli/models.dart';
import 'package:task_list_cli/repository.dart';
import 'package:task_list_cli/service.dart';
import 'package:task_list_cli/ui.dart';
import 'package:test/test.dart';

void main() {
  group('Nocterm task manager', () {
    late Directory directory;
    late JsonRepository repo;
    late TaskService service;
    int writes = 0;
    bool failWrites = false;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('task-ui-');
      writes = 0;
      failWrites = false;
      repo = await JsonRepository.open(
        directory.path,
        writer: (file, contents) async {
          if (failWrites) {
            throw const FileSystemException('Simulated disk full');
          }
          await JsonRepository.atomicWrite(file, contents);
          writes++;
        },
      );
      service = TaskService(repo);
    });
    tearDown(() async {
      await repo.close();
      await directory.delete(recursive: true);
    });
    Future<void> settle(NoctermTester tester) =>
        tester.pump(const Duration(milliseconds: 250));
    Future<void> until(NoctermTester tester, bool Function() predicate) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!predicate() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(predicate(), isTrue, reason: tester.renderToString());
      await settle(tester);
      // Paint any scroll changes requested by post-layout callbacks.
      await tester.pump();
    }

    test('empty state creates a list and task using forms, with immediate persistence', () async {
      await testNocterm('empty CRUD', (tester) async {
        await tester.pumpComponent(TaskApp(service));
        expect(tester.terminalState, containsText('No lists yet.'));
        await tester.sendKey(LogicalKey.keyN);
        await settle(tester);
        expect(tester.terminalState, containsText('Create list'));
        await tester.enterText('Personal');
        await tester.sendEnter();
        await until(tester, () => service.lists.isNotEmpty);
        expect(tester.terminalState, containsText('Personal'));
        expect(tester.terminalState, containsText('No tasks yet.'));
        await tester.sendKey(LogicalKey.keyN);
        await settle(tester);
        expect(tester.terminalState, containsText('Add task to Personal'));
        await tester.enterText('Buy milk');
        await tester.sendEnter();
        await until(tester, () => service.getList('Personal').tasks.isNotEmpty);
        expect(tester.terminalState, containsText('[ ] Buy milk'));
        expect(writes, 2);
        expect(await repo.file.readAsString(), contains('Buy milk'));
      });
    });

    test(
      'completion and reopening immediately reevaluate the active filter',
      () async {
        await service.createList('Work');
        final task = await service.createTask('Work', 'Finish release');
        await testNocterm('filtered toggle', (tester) async {
          await tester.pumpComponent(TaskApp(service));
          await tester.sendKey(LogicalKey.digit2);
          expect(tester.terminalState, containsText('Filter: Incomplete'));
          await tester.sendKey(LogicalKey.space);
          await until(tester, () => service.getTask('Work', task.id).completed);
          expect(tester.terminalState, containsText('No incomplete tasks.'));
          expect(tester.terminalState, isNot(containsText('Finish release')));
          await tester.sendKey(LogicalKey.digit3);
          expect(tester.terminalState, containsText('[x] Finish release'));
          await tester.sendKey(LogicalKey.keyX);
          await until(
            tester,
            () => !service.getTask('Work', task.id).completed,
          );
          expect(tester.terminalState, containsText('No completed tasks.'));
          await tester.sendKey(LogicalKey.digit1);
          expect(tester.terminalState, containsText('[ ] Finish release'));
        });
      },
    );

    test(
      'switching lists and filters never writes and isolates tasks',
      () async {
        await service.createList('Work');
        await service.createTask('Work', 'Work task');
        await service.createList('Home');
        await service.createTask('Home', 'Home task');
        final before = writes;
        await testNocterm('navigation', (tester) async {
          await tester.pumpComponent(TaskApp(service));
          await tester.sendTab();
          await tester.sendArrowDown();
          expect(tester.terminalState, containsText('TASK LIST  /  Home'));
          expect(tester.terminalState, containsText('Home task'));
          expect(tester.terminalState, isNot(containsText('Work task')));
          await tester.sendKey(LogicalKey.keyF);
          expect(tester.terminalState, containsText('Filter: Incomplete'));
          await tester.sendKey(LogicalKey.keyF);
          expect(tester.terminalState, containsText('Filter: Completed'));
          expect(tester.terminalState, containsText('No completed tasks.'));
          expect(writes, before);
        });
      },
    );

    test(
      'form errors stay in the dialog and escape cancels without writes',
      () async {
        await service.createList('Work');
        final before = writes;
        await testNocterm('validation', (tester) async {
          await tester.pumpComponent(TaskApp(service));
          await tester.sendKey(LogicalKey.keyN);
          await settle(tester);
          await tester.sendEnter();
          await settle(tester);
          expect(tester.terminalState, containsText('Task title must contain'));
          expect(service.query('Work'), isEmpty);
          await tester.sendEscape();
          await settle(tester);
          expect(tester.terminalState, containsText('No tasks yet.'));
          expect(writes, before);
        });
      },
    );

    test('edits task titles and list names using the focused pane', () async {
      await service.createList('Work');
      final task = await service.createTask('Work', 'Old');
      await testNocterm('editing', (tester) async {
        await tester.pumpComponent(TaskApp(service));
        await tester.sendKey(LogicalKey.keyE);
        await settle(tester);
        for (var i = 0; i < 3; i++) {
          await tester.sendBackspace();
        }
        await tester.enterText('New title');
        await tester.sendEnter();
        await until(
          tester,
          () => service.getTask('Work', task.id).title == 'New title',
        );
        expect(tester.terminalState, containsText('[ ] New title'));
        await tester.sendTab();
        await tester.sendKey(LogicalKey.keyE);
        await settle(tester);
        for (var i = 0; i < 4; i++) {
          await tester.sendBackspace();
        }
        await tester.enterText('Projects');
        await tester.sendEnter();
        await until(tester, () => service.lists.single.name == 'Projects');
        expect(tester.terminalState, containsText('TASK LIST  /  Projects'));
        expect(service.getTask('Projects', task.id).id, task.id);
      });
    });

    test('deletion defaults to cancellation and requires y for tasks and nonempty lists', () async {
      await service.createList('Work');
      await service.createTask('Work', 'Keep me');
      await testNocterm('confirmation', (tester) async {
        await tester.pumpComponent(TaskApp(service));
        await tester.sendKey(LogicalKey.keyD);
        await settle(tester);
        expect(tester.terminalState, containsText('Permanent deletion'));
        await tester.sendEnter();
        expect(service.query('Work'), hasLength(1));
        await tester.sendEscape();
        await settle(tester);
        expect(service.query('Work'), hasLength(1));
        await tester.sendKey(LogicalKey.keyD);
        await settle(tester);
        await tester.sendKey(LogicalKey.keyY);
        await until(tester, () => service.query('Work').isEmpty);
        expect(tester.terminalState, containsText('No tasks yet.'));
        await service.createTask('Work', 'Another task');
        await tester.sendTab();
        await tester.sendKey(LogicalKey.keyD);
        await settle(tester);
        expect(tester.terminalState, containsText('and its 1 tasks?'));
        await tester.sendKey(LogicalKey.keyN);
        await settle(tester);
        expect(service.lists, hasLength(1));
        await tester.sendKey(LogicalKey.keyD);
        await settle(tester);
        await tester.sendKey(LogicalKey.keyY);
        await until(tester, () => service.lists.isEmpty);
        expect(tester.terminalState, containsText('No lists yet.'));
      });
    });

    test(
      'filtered selection mutates the persistent task, never a row number',
      () async {
        await service.createList('Work');
        final first = await service.createTask('Work', 'First');
        final second = await service.createTask('Work', 'Second');
        await service.setCompletion('Work', first.id, Completion.completed);
        await testNocterm('stable selection', (tester) async {
          await tester.pumpComponent(TaskApp(service));
          await tester.sendKey(LogicalKey.digit2);
          await tester.sendKey(LogicalKey.space);
          await until(
            tester,
            () => service.getTask('Work', second.id).completed,
          );
          expect(service.getTask('Work', first.id).completed, isTrue);
          expect(service.query('Work', filter: TaskFilter.incomplete), isEmpty);
        });
      },
    );

    test(
      'save errors stay visible without publishing a changed task',
      () async {
        await service.createList('Work');
        final task = await service.createTask('Work', 'Safe');
        failWrites = true;
        await testNocterm('failed save', (tester) async {
          await tester.pumpComponent(TaskApp(service));
          await tester.sendKey(LogicalKey.space);
          await settle(tester);
          expect(tester.terminalState, containsText('Could not save'));
          expect(tester.terminalState, containsText('[ ] Safe'));
          expect(service.getTask('Work', task.id).completed, isFalse);
        });
      },
    );

    test(
      'appending a task beyond the viewport reveals its selected row',
      () async {
        await service.createList('Work');
        for (var i = 0; i < 40; i++) {
          await service.createTask('Work', 'Task $i');
        }
        await testNocterm('append task visibility', (tester) async {
          await tester.pumpComponent(TaskApp(service));
          await tester.sendKey(LogicalKey.keyN);
          await tester.enterText('New task');
          await tester.sendEnter();
          await until(tester, () => service.query('Work').length == 41);
          await tester.pump();
          expect(tester.terminalState, containsText('> [ ] New task'));
          expect(service.query('Work').last.title, 'New task');
        });
      },
    );

    test(
      'appending a list beyond the viewport reveals its selected row',
      () async {
        for (var i = 0; i < 40; i++) {
          await service.createList('List $i');
        }
        await testNocterm('append list visibility', (tester) async {
          await tester.pumpComponent(TaskApp(service));
          await tester.sendTab();
          await tester.sendKey(LogicalKey.keyN);
          await tester.enterText('New list');
          await tester.sendEnter();
          await until(tester, () => service.lists.length == 41);
          await tester.pump();
          expect(tester.terminalState, containsText('> New list (0)'));
          expect(tester.terminalState, containsText('TASK LIST  /  New list'));
        });
      },
    );

    test(
      'keyboard help is readable and scrollable at the minimum size',
      () async {
        final before = writes;
        await testNocterm('minimum-size help', (tester) async {
          await tester.pumpComponent(TaskApp(service));
          await tester.sendKey(LogicalKey.f1);
          expect(tester.terminalState, containsText('Keyboard help'));
          expect(tester.terminalState, containsText('Esc close'));
          final screens = <String>[tester.renderToString()];
          for (var i = 0; i < 30; i++) {
            await tester.sendArrowDown();
            expect(tester.terminalState, containsText('Keyboard help'));
            expect(tester.terminalState, containsText('Esc close'));
            screens.add(tester.renderToString());
          }
          final visibleHelp = screens.join('\n');
          for (final entry in [
            'Tab / Left / Right: Switch panes',
            'Up / Down / j / k: Select list or task',
            'Home / End: First / last item',
            'Page Up / Page Down: Move ten items',
            'n: Create in the focused pane',
            'e: Rename list / edit task',
            'Space / x: Complete or reopen task',
            'd / Delete: Delete with confirmation',
            '1 / 2 / 3: All / Incomplete / Completed',
            'f: Cycle completion filters',
            'q: Quit (every change is saved)',
            'Enter saves a form; Esc cancels it.',
            'Selection uses stable IDs, not row numbers.',
          ]) {
            expect(visibleHelp, contains(entry));
          }
          await tester.sendKey(LogicalKey.home);
          expect(tester.terminalState, containsText('Tab / Left / Right'));
          await tester.sendKey(LogicalKey.pageDown);
          expect(tester.terminalState, containsText('Keyboard help'));
          expect(tester.terminalState, containsText('stable IDs'));
          await tester.sendKey(LogicalKey.pageUp);
          expect(tester.terminalState, containsText('Tab / Left / Right'));
          await tester.sendKey(LogicalKey.end);
          expect(tester.terminalState, containsText('stable IDs'));
          await tester.sendKey(LogicalKey.keyN);
          expect(tester.terminalState, containsText('Keyboard help'));
          await tester.sendEscape();
          await tester.pump();
          expect(tester.terminalState, isNot(containsText('Keyboard help')));
          expect(writes, before);
        }, size: const Size(48, 14));
      },
    );

    test('long lists keep keyboard-selected rows visible', () async {
      await service.createList('Work');
      for (var i = 0; i < 40; i++) {
        await service.createTask('Work', 'Task $i');
      }
      await testNocterm('scrolling', (tester) async {
        await tester.pumpComponent(TaskApp(service));
        await tester.sendKey(LogicalKey.end);
        // The post-layout scroll request paints on the following frame.
        await tester.pump();
        expect(tester.terminalState, containsText('> [ ] Task 39'));
        await tester.sendKey(LogicalKey.home);
        await tester.pump();
        expect(tester.terminalState, containsText('> [ ] Task 0'));
        await tester.sendKey(LogicalKey.f1);
        await settle(tester);
        expect(tester.terminalState, containsText('Keyboard help'));
        await tester.sendEscape();
        await settle(tester);
        expect(tester.terminalState, containsText('TASK LIST  /  Work'));
      });
    });
  });
}
