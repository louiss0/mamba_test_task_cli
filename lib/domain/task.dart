import 'id_source.dart';

/// A single unit of work inside a [TaskList].
final class Task {
  const Task({
    required this.id,
    required this.title,
    required this.completed,
    required this.createdAt,
  });

  /// The stable identity of this task. Never shown as a row number.
  final Identifier id;

  /// The human-written description of the work.
  final String title;

  /// Whether the work is finished. Completing never removes the task.
  final bool completed;

  /// When the task was first added.
  final DateTime createdAt;

  /// The short handle the CLI uses to address this task.
  ///
  /// It is a prefix of [id], never the visible position, so it survives
  /// filtering, sorting, and deletion of other tasks.
  String get reference => id.length <= 12 ? id : id.substring(0, 12);

  Task copyWith({String? title, bool? completed}) => Task(
        id: id,
        title: title ?? this.title,
        completed: completed ?? this.completed,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          other.id == id &&
          other.title == title &&
          other.completed == completed &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, title, completed, createdAt);

  @override
  String toString() => 'Task($id, $title, completed: $completed)';
}
