Build a polished, persistent Task List CLI application with support for multiple task lists, practical filtering, and an interactive terminal user interface.

The application should feel like a real everyday productivity tool rather than a demonstration project.

## Development Philosophy

Prefer established, well-maintained libraries over custom implementations whenever a library already solves the problem cleanly.

Before implementing infrastructure yourself, look for appropriate libraries for:

- CLI argument and command parsing
- JSON serialization and deserialization
- schema validation when useful
- safe filesystem access
- platform-specific application data directories
- terminal user interfaces
- keyboard input and focus handling
- tables, lists, forms, dialogs, and selectable widgets
- terminal styling and colors
- filtering and searching
- date and time handling

Do not manually implement low-level terminal rendering, escape-sequence handling, raw keyboard processing, JSON parsing, or argument parsing unless the chosen ecosystem genuinely lacks a suitable library.

Favor libraries that are:

- actively maintained
- reasonably popular within the language ecosystem
- documented
- cross-platform when practical
- small enough for a CLI application
- easy to test
- compatible with producing a standalone executable when the language supports it

Avoid adding libraries merely to avoid writing trivial application logic. Libraries should handle infrastructure; the application's domain behavior should remain understandable within the project's own code.

## Core Concept

The application manages tasks organized into named lists.

A user may have lists such as:

- Personal
- Work
- Shopping
- Mamba
- Mace

Tasks belong to exactly one list.

The application's state must persist between executions of the CLI.

Persistence must use JSON files.

Do not use:

- SQLite
- SQL databases
- embedded databases
- key-value databases
- database servers

The JSON data should remain human-readable and reasonably easy for an advanced user to inspect manually.

## JSON Persistence

Use a structured JSON format as the application's persistent storage.

Prefer using a JSON serialization library rather than manually constructing or parsing JSON strings.

The application should keep persistence logic behind a dedicated repository or storage layer.

Application and UI code should not manipulate raw JSON maps directly when domain models can represent the data more safely.

A conceptual persisted structure may resemble:

```text
application data
├── version
└── lists
    ├── list
    │   ├── id
    │   ├── name
    │   └── tasks
    │       └── task
    │           ├── id
    │           ├── title
    │           ├── completed
    │           └── createdAt
    └── ...
```

The exact JSON structure may differ if another representation is cleaner.

Include a format or schema version in the persisted data so future releases can migrate older JSON formats when necessary.

## File Location

Store application data in the operating system's appropriate user-data or application-data directory.

Use an established library for locating the correct directory where one exists.

Do not place persistent application state in the current working directory by default.

The application should determine an appropriate location on platforms such as:

- Windows
- macOS
- Linux

Keep the storage path deterministic so the application always knows where to reload its state.

## Safe File Writing

Do not overwrite the active JSON file in a way that can easily corrupt all user data if the process terminates midway through a write.

Prefer a safe write strategy such as:

1. serialize the new application state
2. write it to a temporary file
3. flush or close the file successfully
4. replace the previous data file atomically when supported

Use libraries for atomic file replacement or safe file writing when the ecosystem provides them.

The existing valid JSON file should remain intact when a write fails whenever practical.

## JSON Validation and Recovery

Treat corrupted or invalid JSON as a recoverable application error rather than allowing an unhandled parsing exception to crash the program.

Validate decoded data before using it as application state.

If the application encounters malformed or incompatible persisted data:

- report the problem clearly
- do not silently discard it
- do not overwrite it automatically
- preserve the original file
- provide enough information for the user to locate the problematic storage file

Do not silently reset the user's tasks because decoding failed.

## Serialization Models

Use strongly modeled data structures where the language supports them.

Represent concepts such as:

- task list
- task
- completion state
- persisted application state
- filter state

with proper domain types instead of passing raw dynamic JSON objects throughout the application.

Keep serialization concerns separate from business logic when practical.

Conversion should conceptually follow:

```text
JSON
 ↓
Persistence representation
 ↓
Domain model
 ↓
Application behavior
```

and saving should perform the reverse transformation.

## Task Lists

Users must be able to:

- create a list
- rename a list
- delete a list
- view all lists
- open a specific list

Prevent ambiguous list names according to the application's naming rules.

Deleting a list containing tasks must require explicit confirmation in the interactive interface.

The application should always make it clear which list the user is currently viewing.

## Tasks

Every task should have at least:

- a persistent unique identifier
- a title
- a completion state
- a creation timestamp

Structure the data model so additional properties can be introduced later without redesigning the entire persistence format.

Users must be able to:

- create tasks
- view tasks
- edit task titles
- mark tasks complete
- mark completed tasks incomplete again
- delete tasks

Task identifiers must remain stable even when tasks are filtered, sorted, edited, or other tasks are deleted.

Do not use the visible row number as the persistent identity of a task.

## Completion State

Tasks have two primary states:

- incomplete
- completed

The application must make completion state visually obvious in both normal CLI output and the TUI.

Completing a task should not delete it.

A completed task can later be restored to incomplete.

## Practical Filtering

Filtering must be a first-class feature rather than an afterthought.

At minimum, support these completion filters:

- All
- Incomplete
- Completed

Filtering must work within the currently selected list.

The user should be able to switch filters quickly from inside the TUI without reopening the program.

Make the active filter clearly visible.

Changing filters must not mutate task data.

Filtering should operate on the application's loaded domain state rather than rewriting JSON simply because the visible filter changed.

Filtering should be designed so additional filters could be added later, such as:

- text search
- creation date
- tags
- priority
- due date

Do not implement those future features unless useful for the architecture, but avoid designing the current filtering system in a way that would make them difficult to add.

## CLI Interface

Provide a useful non-interactive command interface in addition to the TUI.

The CLI should support normal automation-friendly operations such as:

- listing lists
- creating a list
- removing a list
- listing tasks
- adding a task
- editing a task
- completing a task
- reopening a task
- deleting a task
- filtering listed tasks by completion state

Commands should work without requiring the TUI.

CLI output should be script-friendly where practical.

Errors should be written appropriately and should result in meaningful exit codes.

Do not make the interactive interface the only way to access application functionality.

## Interactive TUI

Create a full terminal UI for managing lists and tasks.

The TUI must support CRUD operations without requiring users to type CLI commands manually.

The main interface should make it easy to understand:

- which task list is selected
- which task is selected
- which completion filter is active
- what actions are currently available

Prefer a layout where lists and tasks can be navigated naturally.

A reasonable structure could contain:

- a list selector or sidebar
- the current task list
- a visible completion filter
- contextual controls or keyboard shortcut hints

The exact layout can vary depending on the capabilities of the selected TUI library.

## TUI List Management

From inside the TUI, users must be able to:

- create a task list
- switch between lists
- rename a list
- delete a list

List management should use appropriate TUI components such as dialogs, forms, or prompts rather than dropping the user into raw terminal input unexpectedly.

## TUI Task Management

From inside the TUI, users must be able to:

- add a task
- select a task
- edit a task
- complete a task
- reopen a completed task
- delete a task

CRUD operations should immediately update the visible interface and persistent JSON storage.

Do not require restarting the application to see changes.

The preferred sequence for mutations should be conceptually:

```text
User Action
    ↓
Application Service
    ↓
Update Domain State
    ↓
Persist JSON
    ↓
Refresh UI
```

Do not place serialization logic directly inside TUI widgets or event handlers.

## TUI Filtering

The interface must provide an easy way to switch between:

- All
- Incomplete
- Completed

Use a control appropriate for the chosen TUI framework, such as:

- tabs
- segmented controls
- selectable buttons
- a filter menu
- keyboard shortcuts

The currently selected filter must always be obvious.

When a task changes completion state, immediately reevaluate whether it belongs in the currently visible filtered view.

For example, when viewing only incomplete tasks, completing the selected task should cause it to disappear from that filtered view after the operation succeeds.

## Keyboard Navigation

The TUI should be comfortably usable without a mouse.

Provide discoverable keyboard shortcuts for common actions.

At minimum, users should be able to navigate, select, create, edit, complete or reopen, delete, change filters, switch lists, and quit.

Do not invent unconventional keyboard behavior when the selected TUI ecosystem already has established navigation conventions.

Display relevant shortcut hints somewhere in the interface or provide an accessible help view.

## Confirmation and Safety

Destructive actions should be difficult to trigger accidentally.

Require confirmation before:

- deleting a task
- deleting a list containing tasks

Do not silently destroy user data.

Input validation errors should be presented within the TUI without crashing or corrupting the interface.

## Architecture

Separate domain behavior from presentation and persistence.

The CLI commands and TUI should operate on the same underlying application or service layer rather than implementing task behavior twice.

A desirable conceptual separation is:

```text
Domain Models
      ↓
Application / Service Layer
      ↓
Persistence Repository
      ↓
JSON Serializer
      ↓
Filesystem
```

The CLI and TUI should sit above the application layer:

```text
       CLI        TUI
        \          /
         \        /
      Application Layer
             |
        Domain Models
             |
        JSON Repository
             |
         JSON File
```

The TUI should not directly read or write JSON.

CLI commands should not directly read or write JSON either.

Both should call reusable application operations.

For example, operations conceptually similar to these should exist independently of the UI:

- create list
- rename list
- delete list
- get lists
- create task
- update task
- delete task
- set task completion state
- query tasks using a filter

The exact classes, functions, interfaces, or modules should follow the conventions of the chosen language.

Do not introduce abstractions simply for architectural decoration. Use them where they create a real boundary between responsibilities.

## Persistence Lifecycle

Load the JSON state when the application starts.

For normal mutations:

1. perform validation
2. update application state
3. serialize the complete valid state
4. safely persist it
5. update the visible UI

Avoid repeatedly reading the entire JSON file during ordinary UI navigation when the application already has a current in-memory representation.

Filtering, selecting items, navigating lists, and opening dialogs should not cause unnecessary disk writes.

Only persist when application data actually changes.

## Multiple Processes

Because JSON files do not provide database-style concurrency control automatically, avoid pretending that concurrent writes are inherently safe.

If practical, use a lightweight locking library to prevent two running instances from overwriting one another.

At minimum, the implementation should recognize that simultaneous mutations from multiple processes could otherwise cause lost updates.

Prefer an existing file-locking library over inventing a custom lock protocol.

Keep this mechanism lightweight; do not introduce a database merely to solve locking.

## Testing

Design the application so core behavior can be tested without launching the interactive TUI.

Test at least:

- list creation
- list renaming
- list deletion
- task creation
- task editing
- completion
- reopening completed tasks
- deletion
- JSON serialization
- JSON deserialization
- persistence across application restarts
- invalid JSON handling
- safe write behavior where practical
- filtering all tasks
- filtering incomplete tasks
- filtering completed tasks
- isolation between multiple lists

Add focused tests around the application/service layer and persistence layer.

Tests should be able to use temporary directories and test JSON files instead of touching the user's real application data.

Where supported by the chosen TUI framework, test important UI state transitions without depending entirely on manual terminal testing.

## User Experience

Optimize for quick repeated use.

Common operations should take very few keystrokes.

Empty states should explain what the user can do next.

Examples:

- no lists exist
- selected list has no tasks
- no completed tasks match the current filter

Avoid presenting an empty unexplained screen.

Use terminal styling purposefully. Completed tasks should be visually distinguishable, but never rely on color alone to communicate state.

## Implementation Process

Before writing substantial code:

1. Inspect the ecosystem and identify suitable libraries for the CLI, JSON serialization, filesystem operations, application-data directories, TUI, and terminal styling.
2. Briefly explain which libraries you selected and what responsibility each one handles.
3. Prefer those libraries over custom infrastructure.
4. Define the domain model.
5. Define the versioned JSON persistence format.
6. Implement the JSON repository and safe persistence mechanism.
7. Implement reusable application operations.
8. Build the non-interactive CLI on top of those operations.
9. Build the TUI on top of the same operations.
10. Add filtering and ensure it behaves consistently in both interfaces.
11. Add automated tests.
12. Run the application and verify the major CRUD, persistence, and filtering workflows.

When choosing between writing substantial infrastructure yourself and using a mature library that already handles it well, strongly prefer the library.

Do not introduce a database.

The finished result should be a practical persistent task manager whose data remains understandable as ordinary JSON while still having the reliability expected from an everyday CLI application.
