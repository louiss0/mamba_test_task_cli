import 'package:intl/intl.dart';

final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
final DateFormat _timeFormat = DateFormat('HH:mm');

/// Renders [when] as a stable, sortable, timezone-free stamp.
///
/// CLI output uses this fixed 24-hour form so it stays easy to read and to
/// compare; the TUI uses [formatRelative] instead.
String formatTimestamp(DateTime when) =>
    '${_dateFormat.format(when)} ${_timeFormat.format(when)}';

/// Renders [when] as a short phrase relative to [now].
///
/// Anything older than a week falls back to [formatTimestamp] so the phrase
/// always carries the actual day.
String formatRelative(DateTime when, DateTime now) {
  final difference = now.difference(when);
  if (difference.inSeconds < 60) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays == 1) return 'yesterday';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return formatTimestamp(when);
}
