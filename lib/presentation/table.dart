/// Renders a plain-text table with columns padded to their widest cell.
///
/// CLI output stays unstyled on purpose: no colour and no box drawing, so it
/// can be piped into `grep`, `awk`, or `cut` without post-processing.
String renderTable({
  required List<String> headings,
  required List<List<String>> rows,
}) {
  final widths = <int>[
    for (var column = 0; column < headings.length; column++)
      rows.fold<int>(
        headings[column].length,
        (widest, row) => row[column].length > widest ? row[column].length : widest,
      ),
  ];

  String line(List<String> cells) => [
        for (var column = 0; column < cells.length; column++)
          if (column == cells.length - 1)
            cells[column]
          else
            cells[column].padRight(widths[column]),
      ].join('  ');

  return [
    line(headings),
    for (final row in rows) line(row),
  ].join('\n');
}
