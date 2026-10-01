# Code Review

## Scope and verification

- **Baseline:** `f64a99f9f77fbbc933e7007eefb6be10891e2b18`
- **Reviewed commit:** `b27e3ac` — task-list CLI and interactive TUI implementation.
- **Diff:** `git diff f64a99f...HEAD` (50 files).
- **Spec:** `TODO.md`; **standards:** `AGENTS.md`, `CLAUDE.md`, and the Mamba skill.
- **Checks:** `dart analyze` passed; `dart test` passed all **198 tests** on Windows, Dart 3.13.2. `git diff --check f64a99f...HEAD` passed.
- Additional disposable probes exercised domain selection, decoding, and the actual Nocterm component tree. They used in-memory repositories or temporary directories, never the user's task storage.
- The two review axes were performed separately by one reviewer; parallel sub-agents were unavailable. No application code was changed.

Priorities: **P1** = high-priority reliability issue; **P2** = normal-priority correctness issue.

## Standards

### S1 — P2: Preserve task identity when switching filters

**Location:** `lib/tui/task_screen.dart:170–174`.

**Documented rule:** `AGENTS.md:70–71`: “Selection is a task identifier, never a row number. A task stays selected while the list around it is filtered, sorted, or edited.”

`applyFilter` unconditionally executes `_taskId = null; _taskIndex = 0;`. Selecting the second of two incomplete tasks, then switching from All to Incomplete, moves selection to the first task even though the original selection still matches. A subsequent completion or deletion targets a different task than the user had selected.

**Verified:** the probe printed `Before filter: Second` and `After filter (both still visible): First`.

**Fix:** retain the selected identifier if it remains visible; choose a neighboring fallback only when it disappears, and synchronize the navigation index. Add a regression test covering a selected non-first task surviving a filter change.

This is a documented-standard violation, not a heuristic smell. No additional smell-only findings are asserted.

## Spec

### F1 — P1: Handle asynchronous TUI mutation failures

**Location:** `lib/tui/task_list_app.dart:269–285`.

**Requirement:** `TODO.md:130`: treat corrupted data as “a recoverable application error.”

The unawaited action catches only `ValidationException`. `CorruptedBookException`, `NotFoundException`, and filesystem failures escape without a visible recovery message. Probes reproduced unhandled async errors after corrupting the file while the TUI was open and after another book deleted the selected task's list. The command-level guard cannot catch this detached future.

**Fix:** handle expected domain/storage errors here, expose them in the dialog or status bar, and retain usable screen state. Test corruption, stale selections, and failed writes through Nocterm.

### F2 — P2: Scroll the list sidebar with its selection

**Location:** `lib/tui/task_list_app.dart:298–310`.

**Requirement:** `TODO.md:290`: make clear “which task list is selected.”

`_revealSelection` returns immediately for the lists pane; `_listScroll` never follows keyboard selection. At 80×24 with 30 populated lists, navigating to `List29` displayed its tasks while the sidebar still showed `List0`–`List14`; the selected list name was absent from the entire screen.

**Fix:** reveal `selectedListIndex` through `_listScroll`, including after creation and deletion. Add an overflowing-sidebar navigation test.

### F3 — P2: Validate persisted domain values, not only JSON types

**Location:** `lib/persistence/book_codec.dart:118–174`.

**Requirement:** `TODO.md:132`: “Validate decoded data before using it as application state.”

The decoder accepts empty task IDs/titles and list names with surrounding whitespace. A probe loaded `name: " Work "` and a task with `id: "", title: ""`; looking up `Work` then returned null. These values bypass the application's normal naming rules and can be rewritten as accepted data on subsequent mutations.

**Fix:** enforce domain invariants at decoding, translating failures into path-bearing `CorruptedBookException`s; test rejection and original-file preservation.

### F4 — P2: Require explicit confirmation for CLI task deletion

**Location:** `lib/tasks.dart:292–321`.

**Requirement:** `TODO.md:386–389`: “Require confirmation before: deleting a task.”

`TasksRm` deletes immediately, with no confirmation flag or prompt. Unlike populated-list removal, an ordinary invocation irreversibly removes data without a second explicit authorization.

**Fix:** require `--force`/`--yes` for non-interactive deletion, preserving automation support. Test refusal without confirmation and successful deletion with it. This finding is based on code inspection.

## Coverage limitations

Linux/macOS behavior and a visible native-terminal session were not tested. The existing locking tests exercise sequential updates, not simultaneous writers. The safe-replacement failure test assumes an open destination prevents rename, which is Windows-specific; its portability should be checked separately.

**Summary:** Standards: **1 finding**, worst S1 (P2, selection identity lost). Spec: **4 findings**, worst F1 (P1, unhandled asynchronous TUI failures).
