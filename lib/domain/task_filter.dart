import 'completion_filter.dart';
import 'task.dart';

/// A composable rule for selecting tasks out of a list.
///
/// The type is sealed, so the whole set of filters is visible in one place and
/// the compiler forces every new filter to be handled where filters are
/// summarised. Adding text search, creation date, tags, priority, or due date
/// means adding one subtype here; callers that build filters with [and] do not
/// change.
sealed class TaskFilter {
  const TaskFilter();

  /// Selects every task, completed or not.
  static const TaskFilter every = _EveryTaskFilter();

  /// Returns a filter that selects tasks by completion state.
  static CompletionTaskFilter byCompletion(CompletionFilter filter) =>
      CompletionTaskFilter(filter);

  /// Returns whether [task] passes this filter.
  bool matches(Task task);

  /// Returns a filter that requires both this filter and [other] to pass.
  TaskFilter and(TaskFilter other) => _AllTaskFilter([this, other]);
}

/// Matches every task.
final class _EveryTaskFilter extends TaskFilter {
  const _EveryTaskFilter();

  @override
  bool matches(Task task) => true;
}

/// Matches tasks by completion state.
final class CompletionTaskFilter extends TaskFilter {
  const CompletionTaskFilter(this.filter);

  final CompletionFilter filter;

  @override
  bool matches(Task task) => switch (filter) {
        CompletionFilter.all => true,
        CompletionFilter.incomplete => !task.completed,
        CompletionFilter.completed => task.completed,
      };
}

/// Matches tasks that satisfy every contained filter.
final class _AllTaskFilter extends TaskFilter {
  const _AllTaskFilter(this.parts);

  final List<TaskFilter> parts;

  @override
  bool matches(Task task) => parts.every((part) => part.matches(task));
}
