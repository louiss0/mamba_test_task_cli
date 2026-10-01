import 'package:task_list_cli/presentation/table.dart';
import 'package:task_list_cli/presentation/timestamps.dart';
import 'package:test/test.dart';

void main() {
  group('renderTable', () {
    test('pads every column to its widest cell', () {
      final table = renderTable(
        headings: const ['A', 'BB'],
        rows: const [
          ['one', 'x'],
          ['two', 'y'],
        ],
      );

      expect(table.split('\n'), [
        'A    BB',
        'one  x',
        'two  y',
      ]);
    });

    test('keeps the last column unpadded so lines have no trailing spaces', () {
      final table = renderTable(
        headings: const ['REF', 'TITLE'],
        rows: const [
          ['abc', 'Buy milk'],
        ],
      );

      for (final line in table.split('\n')) {
        expect(line, isNot(endsWith(' ')));
      }
    });

    test('emits a header even when there are no rows', () {
      expect(renderTable(headings: const ['A', 'B'], rows: const []), 'A  B');
    });

    test('widens the header when a heading is the longest cell', () {
      final table = renderTable(
        headings: const ['REFERENCE', 'TITLE'],
        rows: const [
          ['a', 'x'],
        ],
      );

      expect(table.split('\n').first, 'REFERENCE  TITLE');
    });
  });

  group('formatRelative', () {
    final now = DateTime(2026, 5, 10, 12);

    test('describes a very recent time', () {
      expect(
        formatRelative(now.subtract(const Duration(seconds: 10)), now),
        'just now',
      );
    });

    test('describes minutes, hours, and days', () {
      expect(
        formatRelative(now.subtract(const Duration(minutes: 5)), now),
        '5m ago',
      );
      expect(
        formatRelative(now.subtract(const Duration(hours: 3)), now),
        '3h ago',
      );
      expect(
        formatRelative(now.subtract(const Duration(days: 1)), now),
        'yesterday',
      );
      expect(
        formatRelative(now.subtract(const Duration(days: 4)), now),
        '4d ago',
      );
    });

    test('falls back to a stamp once the time is more than a week old', () {
      expect(
        formatRelative(DateTime(2026, 5, 1, 9, 5), now),
        '2026-05-01 09:05',
      );
    });
  });

  group('formatTimestamp', () {
    test('is stable, sortable, and 24-hour', () {
      expect(
        formatTimestamp(DateTime(2026, 12, 5, 23, 4)),
        '2026-12-05 23:04',
      );
    });

    test('pads every field to a fixed width', () {
      expect(
        formatTimestamp(DateTime(2026, 1, 2, 3, 4)),
        '2026-01-02 03:04',
      );
    });
  });
}
