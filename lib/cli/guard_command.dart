import 'package:mamba/mamba.dart';

import '../domain/validation.dart';
import '../persistence/corrupted_book_exception.dart';

/// Exit code for a lookup that found nothing.
const int exitNotFound = 3;

/// Exit code for input the application refuses to accept.
const int exitRejected = 4;

/// Exit code for storage the application cannot read.
const int exitCorruptData = 5;

/// Runs [action], translating application failures into command failures.
///
/// Domain and persistence code reports problems with its own types so it stays
/// independent of the CLI. This is the one place that turns them into a
/// `MambaException`, which is what gives the process a meaningful exit code and
/// sends the message to standard error.
Future<String?> guardCommand(Future<String?> Function() action) async {
  try {
    return await action();
  } on MambaException {
    rethrow;
  } on NotFoundException catch (error) {
    throw MambaException(error.message, exitCode: exitNotFound);
  } on ValidationException catch (error) {
    throw MambaException(error.message, exitCode: exitRejected);
  } on CorruptedBookException catch (error) {
    throw MambaException(error.toString(), exitCode: exitCorruptData);
  }
}
