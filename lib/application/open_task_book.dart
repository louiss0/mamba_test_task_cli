import 'task_book.dart';
import '../persistence/json_task_repository.dart';

/// Opens the book for a one-shot command invocation.
///
/// Each CLI invocation is a fresh process, so the book is loaded once here and
/// discarded when the command returns. Tests pass [repository] to work in a
/// temporary directory instead of the real application data.
Future<TaskBook> openTaskBook({TaskRepository? repository}) async {
  final book = TaskBook(repository ?? TaskRepository.onDisk());
  await book.load();
  return book;
}
