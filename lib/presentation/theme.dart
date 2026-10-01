import 'package:nocterm/nocterm.dart';

/// The colour schemes the interface offers.
enum AppTheme {
  /// Ask the terminal whether it has a light or a dark background.
  auto('auto'),
  dark('dark'),
  light('light'),
  nord('nord'),
  dracula('dracula'),
  catppuccinMocha('catppuccin-mocha'),
  gruvboxDark('gruvbox-dark');

  const AppTheme(this.cliName);

  final String cliName;

  /// The built-in theme this option selects, or null when [auto] has to ask
  /// the terminal.
  TuiThemeData? get preset => switch (this) {
        AppTheme.auto => null,
        AppTheme.dark => TuiThemeData.dark,
        AppTheme.light => TuiThemeData.light,
        AppTheme.nord => TuiThemeData.nord,
        AppTheme.dracula => TuiThemeData.dracula,
        AppTheme.catppuccinMocha => TuiThemeData.catppuccinMocha,
        AppTheme.gruvboxDark => TuiThemeData.gruvboxDark,
      };
}

/// Returns the palette for [appTheme].
///
/// `auto` cannot ask the terminal before the interface is running, so it
/// resolves to the dark palette, which is the common case and never renders
/// dark text on a dark background.
TuiThemeData resolveTheme(AppTheme appTheme) =>
    appTheme.preset ?? TuiThemeData.dark;
