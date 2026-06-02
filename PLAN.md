# Plan for syringe.nvim

This document details the architecture, design decisions, and sequential implementation roadmap for `syringe.nvim`—a Neovim plugin that allows users to highlight a portion of code, prompt the agy CLI, and replace the highlighted area in-place with the CLI's output.

---

## 1. Understanding Summary

*   **What is being built:** A Neovim plugin (`syringe.nvim`) that integrates with the `agy` CLI tool to provide in-buffer LLM-powered code transformations.
*   **Why it exists:** To make refactoring, boilerplate generation, and migration tasks seamless within Neovim.
*   **Who it is for:** Developers using Neovim and the agy agentic workspace assistant.
*   **Key constraints:**
    *   **Async Job execution:** Must run asynchronously using Neovim's job API so the editor remains responsive.
    *   **Visual replacement:** Replaces the highlighted selection in-place.
    *   **Status feedback:** Displays a status-line spinner/message while the job runs.
    *   **Cancellation:** Allows the user to cancel running executions.
*   **Explicit non-goals:**
    *   Building the actual `agy` CLI binary/server itself (we assume a CLI command exists and outputs the replacement code to stdout).
    *   Real-time word-by-word streaming of code (the snippet will be inserted all at once upon completion).
    *   An interactive side-by-side diff UI before applying (standard Neovim undo `u` can be used to revert changes).

---

## 2. Assumptions & Risks

### Assumptions
1.  **CLI Interface:** The CLI tool (e.g. `agy`) accepts the highlighted snippet on `stdin`, the user prompt as an argument (e.g. `--prompt "..."`), and runs in the workspace root directory.
2.  **Neovim Version:** Targets Neovim 0.8+ to leverage modern Lua APIs (`vim.ui.input`, `vim.keymap.set`, `vim.api.nvim_buf_set_text`).
3.  **Test Suite:** The plugin's tests will run using a standard Neovim testing framework like `plenary.test_harness` or `mini.test`.

### Risks & Mitigations
*   **Risk (Buffer Mutation):** User changes the buffer or cursor location while the CLI job is running, causing the replacement text to overwrite the wrong lines.
    *   *Mitigation:* Use Neovim's **extmarks** to track the boundaries of the visual selection. Extmarks automatically adjust their positions when text is inserted/deleted elsewhere in the buffer.
*   **Risk (Hanging Jobs):** CLI process hangs due to API issues, freezing buffer state trackers.
    *   *Mitigation:* Introduce a configurable timeout (e.g. 2 minutes) that kills the spawned job automatically.

---

## 3. Decision Log

| Decision | Chosen Option | Alternatives Considered | Rationale |
| :--- | :--- | :--- | :--- |
| **Backend Integration** | **CLI Tool (`agy`)** | Direct API calls, local RPC daemon | Keep Neovim plugin lightweight, defer LLM agent capabilities to the existing CLI tool, follow UNIX pipeline philosophy. |
| **UX & Replacement** | **In-place visual replacement** | Side-by-side diff preview, streaming | Simple and immediate, matches user workflow, allows quick undo with standard `u`. |
| **Context Scope** | **Selection only + Workspace Access** | Send entire file context | The plugin sends only the selection to the CLI, but the CLI (since it runs in the project root) has the freedom to read any local project files it needs. |
| **Execution Method** | **Asynchronous Job (`jobstart`)** | Synchronous blocking | LLM operations can take seconds or minutes. Blocking the UI would freeze Neovim. Async is essential for a good UX. |
| **Position Tracking** | **Extmarks (Extended Marks)** | Line/Column numbers | If the user makes edits to the file while the job is running in the background, absolute line/col numbers would shift. Extmarks track position dynamically. |

---

## 4. Final Design Specification

### Directory Structure

```
syringe.nvim/
├── plugin/
│   └── syringe.lua          # Command definitions and visual mode map helpers
├── lua/
│   └── syringe/
│       ├── init.lua         # Entry point, config/setup, public interface
│       ├── job.lua          # Spawns/manages background process, handles stdin/stdout
│       └── ui.lua           # Displays input prompt and loading spinners
└── tests/
    └── syringe_spec.lua     # Integration tests
```

### Components and Data Flow

1.  **Selection Capture:**
    When `:SyringeRun` is triggered in visual mode, the plugin:
    *   Escapes visual mode (`esc`) to update selection marks.
    *   Gets start/end line and column marks using `vim.fn.getpos("'<")` and `vim.fn.getpos("'>")`.
    *   Creates an namespace and sets two **extmarks** (start and end) to guard the selection range.
    *   Extracts the text inside this range.
2.  **User Input:**
    *   Calls `vim.ui.input` to request instructions (e.g., "Implement these endpoints").
3.  **Process Invocation:**
    *   Spawns `agy --prompt "<instruction>"` using `vim.fn.jobstart` in the current workspace directory.
    *   Pipes the visually selected text into the process's `stdin`.
    *   Begins status-line loading animation.
4.  **Completion & In-place Replacement:**
    *   Collects `stdout` chunk by chunk.
    *   On code `0` exit:
        *   Retrieves updated visual selection coordinates from the extmarks.
        *   Replaces the text range with `stdout` lines using `vim.api.nvim_buf_set_text`.
        *   Cleans up extmarks and stops the status spinner.
    *   On non-zero exit or cancellation:
        *   Retains the original text.
        *   Notifies user of the error/cancellation via `vim.notify`.

---

## 5. Sequential Implementation Roadmap

### Phase 1: Directory Setup & Configuration
Create the plugin structure and configuration infrastructure.
- **Task 1.1:** Setup project directories.
- **Task 1.2:** Implement `lua/syringe/init.lua` with `setup(opts)` function supporting:
  *   `cmd`: Path to the CLI executable (default `"agy"`).
  *   `timeout`: Timeout in milliseconds (default `120000` / 2 minutes).
- **Task 1.3:** Set up a unit test suite config using a testing harness (`plenary.test_harness` or `mini.test`).
- **Tests:** Verify configuration defaults are correctly set and merged.

### Phase 2: Visual Selection & Position Tracking
Implement visual range extraction and robust boundary tracking.
- **Task 2.1:** Implement visual text extraction logic in `lua/syringe/job.lua`.
- **Task 2.2:** Set up extmarks to track selection start and end coordinates.
- **Tests:**
  *   Write a test that captures a visual selection in a mock buffer and asserts the text matches exactly.
  *   Write a test that inserts text above the selection while a mock job runs, asserting the extmarks successfully shift and track the selection.

### Phase 3: Async CLI Invocation & Process Piping
Hook up asynchronous job execution and stdin/stdout handling.
- **Task 3.1:** Implement CLI process spawning using `vim.fn.jobstart`.
- **Task 3.2:** Write captured selection text to `stdin` and close it to notify the process.
- **Task 3.3:** Aggregate `stdout` and `stderr` streams.
- **Task 3.4:** On successful exit, replace visual selection range using the tracked extmarks.
- **Tests:**
  *   Mock the `agy` process with a shell script. Verify that a simple replacement behaves as expected.
  *   Test error exit codes and verify `vim.notify` displays stderr without changing the buffer.

### Phase 4: Prompt UI & Status feedback
Interface with the user and provide visual indicators.
- **Task 4.1:** Implement prompt input dialog inside `lua/syringe/ui.lua` using `vim.ui.input()`.
- **Task 4.2:** Implement a status-line spinner or echo indicator when a job is running, using `vim.loop.new_timer()`.
- **Tests:**
  *   Verify calling `syringe.run()` displays the input box.
  *   Verify the status line indicates running state and ceases upon job completion.

### Phase 5: Cancellation & Timeout Logic
Add safety mechanisms for long-running executions.
- **Task 5.1:** Track buffer-local active jobs in a global state table (`buf_nr -> job_id`).
- **Task 5.2:** Implement `syringe.cancel()` to kill the active job using `vim.fn.jobstop()`.
- **Task 5.3:** Set up a timer to auto-terminate jobs exceeding the configured `timeout`.
- **Tests:**
  *   Spawn a long-running mock job (e.g. `sleep 10`) and call `cancel()`. Verify it exits and the buffer remains unmodified.
  *   Set the config timeout to `500` ms, spawn a mock job that takes `2` seconds, and assert it is auto-terminated.

### Phase 6: Keymaps & Command Bindings
Expose commands to the user interface.
- **Task 6.1:** Create `:SyringeRun` and `:SyringeCancel` user commands in `plugin/syringe.lua`.
- **Task 6.2:** Create helper mappings to bind visual range selection automatically.
- **Tests:** End-to-end integration tests mimicking keypress triggers in visual mode.
