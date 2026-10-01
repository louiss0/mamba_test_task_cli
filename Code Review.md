# Code Review

## Scope and verification

- Reviewed `git diff f64a99f...HEAD`: commit `13e7148` (`feat(tasks): add persistent CLI and Nocterm task manager`).
- Specification: `TODO.md`; additional user-facing promises: `README.md`.
- Standards: `AGENTS.md`, `CLAUDE.md`, and the project Mamba skill/references; considered the Fowler smell baseline separately from hard violations.
- `dart analyze`: no issues. `dart test`: **70 tests passed** on Windows, Dart 3.13.2.
- Additional temporary Nocterm probes reproduced both findings below. These inspected rendered terminal output; they were not native-terminal tests. Probe files were removed; application code was not changed.
- Standards and specification were assessed separately by one reviewer because sub-agent tools were unavailable. Linux/macOS behavior was not executed. Scaffolding provenance cannot be established from the diff.

## Standards

No actionable documented-standard violations or substantial baseline smells identified. Production commands are wired into the executor, use `create()` rather than `fake()`, and convert application failures into `MambaException`. CLI tests exercise the fake executor and structured result contracts.

## Spec

### 1. [P2] Scroll the selected item into view after the updated list is laid out

**Location:** `lib/ui.dart:51–61` (`_refresh`).

**Requirement:** `TODO.md`: “CRUD operations should immediately update the visible interface” and the interface should make clear “which task is selected.” `README.md` additionally promises that creating a task selects it “so it is visible.”

**Reproduction:** Populate a list with 40 tasks, open the TUI at 80×24, press `n`, enter a new title, and save. After rendering settles, the count is 41 and the detail footer names the new task, but the task pane ends at the previous last task. No selected row is visible.

**Cause:** `_refresh()` calls `ensureIndexVisible` immediately after `setState`, before the viewport has the updated item count and scroll bounds. The scroll request therefore uses the old extent; later layout does not retry it.

**Recommendation:** Ensure selection visibility after the updated viewport finishes layout, with a mounted check. Add regression coverage for appending tasks and lists beyond the viewport; assert the selected **row**, not just the footer title, is visible.

### 2. [P3] Make keyboard help readable at supported terminal sizes

**Location:** `lib/ui.dart:243–245` and `lib/ui.dart:538–573` (`_HelpDialog`).

**Requirement:** `TODO.md`: “Display relevant shortcut hints somewhere in the interface or provide an accessible help view.” `README.md` documents a minimum terminal size of 48×14.

**Reproduction:** At 48×14, press F1. The help dialog is constrained below its requested 64×17 size; wrapped text fills the fixed, non-scrollable column. Rendering cuts off during the deletion shortcut, hiding filtering, quit, form controls, and the dismissal hint. Pressing navigation keys dismisses help rather than revealing the missing content.

**Recommendation:** Use a responsive, scrollable or paginated help view and reserve visible dismissal/navigation instructions. Test all help entries at the documented minimum size.

**Summary:** Standards: 0 findings; no actionable violation identified. Spec: 2 findings; highest severity P2, newly created tasks can remain off-screen.
