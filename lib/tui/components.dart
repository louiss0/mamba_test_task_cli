import 'package:nocterm/nocterm.dart';

/// Marks a task row as finished without relying on colour.
///
/// The box, the label, and the strike-through each carry the state, so the
/// interface still reads correctly on a monochrome terminal or through a
/// screen reader.
const String openTaskMarker = '[ ]';
const String doneTaskMarker = '[x]';

/// The prefix on the highlighted row, and the blank that keeps the title
/// column aligned on every other row.
const String selectionMarker = '>';
const String blankMarker = ' ';

/// A single row of text.
///
/// The row never wraps and clips at whatever width the layout gives it, so a
/// long status message loses its tail instead of pushing the rest of the
/// screen down.
Component singleLine(
  String text, {
  TextStyle? style,
  EdgeInsets? padding,
}) =>
    Container(
      padding: padding,
      height: 1,
      child: Text(
        text,
        style: style,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.clip,
      ),
    );

/// A filter tab. The active tab is reversed, so it reads as selected even where
/// colour is unavailable.
Component filterTab({
  required String label,
  required bool active,
  required TextStyle idleStyle,
  required TextStyle activeStyle,
  required Color background,
}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: active ? background : null,
      child: Text(
        label,
        style: active ? activeStyle : idleStyle,
        softWrap: false,
        overflow: TextOverflow.clip,
      ),
    );

/// Explains an empty screen and what to press next, rather than leaving the
/// user looking at nothing.
Component emptyState({
  required String headline,
  required String suggestion,
  required TextStyle headlineStyle,
  required TextStyle suggestionStyle,
}) =>
    Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          singleLine(headline, style: headlineStyle),
          singleLine(suggestion, style: suggestionStyle),
        ],
      ),
    );

/// A bordered panel used for dialogs.
Component dialogBox({
  required String title,
  required List<Component> body,
  required Color borderColor,
  required Color background,
  required TextStyle titleStyle,
  required double innerWidth,
}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: background,
        border: BoxBorder.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          singleLine(title, style: titleStyle),
          for (final child in body)
            SizedBox(width: innerWidth, child: child),
        ],
      ),
    );
