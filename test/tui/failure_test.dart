import 'dart:io';

import 'package:task_list_cli/domain/validation.dart';
import 'package:task_list_cli/persistence/corrupted_book_exception.dart';
import 'package:task_list_cli/tui/failure.dart';
import 'package:test/test.dart';

void main() {
  group('describeFailure', () {
    test('names a missing task or list without burying the reason', () {
      final failure = describeFailure(
        NotFoundException('List "Work" has no task with reference abc.'),
      );

      expect(failure.title, 'No longer there');
      expect(failure.detail, contains('reference abc'));
      expect(
        failure.needsReading,
        isFalse,
        reason: 'a single sentence fits in the status bar',
      );
    });

    test('passes a rejected value through for the dialog to show', () {
      final failure = describeFailure(
        ValidationException('A list named "work" already exists.'),
      );

      expect(failure.detail, 'A list named "work" already exists.');
      expect(failure.needsReading, isFalse);
    });

    test('keeps the file path for unreadable saved data', () {
      final failure = describeFailure(
        CorruptedBookException(path: '/data/task_book.json', reason: 'bad'),
      );

      expect(failure.title, 'Saved data cannot be read');
      expect(failure.detail, contains('/data/task_book.json'));
      expect(failure.detail, contains('left in place'));
      expect(
        failure.needsReading,
        isTrue,
        reason: 'the recovery steps must not be clipped away',
      );
    });

    test('says the change was not saved when the file cannot be written', () {
      final failure = describeFailure(
        const FileSystemException('disk full', '/data/task_book.json'),
      );

      expect(failure.title, 'Cannot save the data file');
      expect(failure.detail, contains('not saved'));
      expect(failure.detail, contains('/data/task_book.json'));
      expect(failure.needsReading, isTrue);
    });

    test('still explains an unexpected error rather than swallowing it', () {
      final failure = describeFailure(StateError('index out of range'));

      expect(failure.title, 'Something went wrong');
      expect(failure.detail, contains('StateError'));
      expect(failure.detail, contains('index out of range'));
      expect(failure.needsReading, isTrue);
    });
  });
}
