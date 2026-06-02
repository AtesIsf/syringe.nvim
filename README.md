# syringe.nvim

This project was heavily inspired by the Primeagen's 99 plugin, but is specific to Google Antigravity.
I would suggest checking that project out first.

`syringe.nvim` is a lightweight, asynchronous Neovim plugin designed to refactor and transform your code in-place using Google's `agy` agentic CLI tool. Highlight a range of code, enter a prompt instruction (e.g. *"migrate this function from using X to Y"* or *"implement this API endpoint"*), and let `syringe.nvim` replace the buffer range with the refactored result.

---

## Features

*   **Asynchronous Processing:** Non-blocking job execution using Neovim's `jobstart` API. Neovim remains fully responsive while the agent is generating code.
*   **Dynamic Range Tracking:** Uses Neovim **extmarks** to track the visual selection boundaries. If you make edits to other parts of the buffer while the refactor is running in the background, the replacement will still target the correct relative text range.
*   **Smart Code Block Extraction:** Automatically parses the CLI's markdown output, extracting **only** the lines within markdown code blocks (e.g. ` ```go ... ``` `) and discarding any surrounding conversational text or explanations. Falls back to raw output if no delimiters are found.
*   **Cancel & Timeout Safety:** Supports cancelling active jobs via command or keymap. Automatically terminates jobs that exceed a configurable timeout (default 2 minutes) to prevent background leaks.
*   **Visual Progress Feedback:** Displays a non-blocking animated status spinner (`⠋`) in the command area while the background job executes.

---

## Requirements

*   Neovim `0.8+`
*   `agy` (Google Antigravity) CLI tool installed and available in your shell `$PATH`

---

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "AtesIsf/syringe.nvim",
  config = function()
    require("syringe").setup({
      cmd = "agy",            -- CLI binary name or path
      timeout = 120000,       -- Job timeout in milliseconds (2 minutes)
      default_keymaps = true, -- Setup default keymaps in setup()
    })
  end
}
```

---

## Configuration

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `cmd` | `string` | `"agy"` | The CLI executable command or path. |
| `timeout` | `number` | `120000` | Process execution timeout in milliseconds. |
| `default_keymaps` | `boolean` | `true` | Map the default keybindings on setup. |

---

## Mappings & Usage

If `default_keymaps` is set to `true`, the following keymaps will be registered:

*   **Visual Mode:** `<leader>sr` -> Triggers the prompt dialog and executes the refactoring job on the selection.
*   **Normal Mode:** `<leader>sc` -> Aborts/cancels the active refactoring job in the current buffer.

### User Commands

You can also run these operations via standard command-line commands:

*   `:SyringeRun` — Runs the prompt replacement on the selected visual selection.
*   `:SyringeCancel` — Cancels the active refactoring job running in the current buffer.

---

## Testing

The plugin includes a full Plenary unit and integration test suite. You can run all tests locally using the helper script:

```bash
./run_tests.sh
```
