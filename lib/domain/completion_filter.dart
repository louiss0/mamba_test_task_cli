/// Which tasks a query should return.
enum CompletionFilter {
  /// Every task, completed or not.
  all('all'),

  /// Only tasks that still need doing.
  incomplete('incomplete'),

  /// Only tasks that are already finished.
  completed('completed');

  const CompletionFilter(this.cliName);

  /// The token accepted on the command line.
  final String cliName;

  /// The title shown on the filter control.
  String get label => switch (this) {
        CompletionFilter.all => 'All',
        CompletionFilter.incomplete => 'Incomplete',
        CompletionFilter.completed => 'Completed',
      };

  /// Parses a [cliName], returning null when it names no filter.
  static CompletionFilter? fromCliName(String value) {
    for (final filter in values) {
      if (filter.cliName == value) return filter;
    }
    return null;
  }
}
