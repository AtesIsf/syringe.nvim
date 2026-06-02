local M = {}

---@class SyringeConfig
---@field cmd string Path to the CLI executable
---@field timeout number Timeout in milliseconds for the job
---@field default_keymaps boolean Setup default keymaps in setup()

---@type SyringeConfig
M.config = {
  cmd = "agy",
  timeout = 120000, -- 2 minutes
  default_keymaps = true,
  prompt_suffix = "\n\nCRITICAL: Do not write, create, or edit any files on disk. Do not run commands. Only generate the requested refactoring. Output your answer inside markdown code blocks.",
}

---Configure the syringe plugin and set up keymaps if enabled
---@param opts? SyringeConfig Custom configuration options
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  if M.config.default_keymaps then
    -- Visual mode: <leader>sr to run
    vim.keymap.set("v", "<leader>sr", ":SyringeRun<CR>", { desc = "Syringe Run Selection", silent = true })
    -- Normal mode: <leader>sc to cancel
    vim.keymap.set("n", "<leader>sc", ":SyringeCancel<CR>", { desc = "Syringe Cancel Active Job", silent = true })
  end
end

---Trigger the main Syringe prompting and refactoring flow on the current visual selection
function M.run()
  local job = require("syringe.job")
  local ui = require("syringe.ui")

  -- 1. Extract visual selection range coordinates
  local start_row, start_col, end_row, end_col = job.get_visual_range()

  -- 2. Prompt user for instruction
  ui.prompt_instruction(function(prompt)
    local bufnr = vim.api.nvim_get_current_buf()

    -- 3. Set extmarks to track selection bounds
    local start_mark_id, end_mark_id = job.create_marks(bufnr, start_row, start_col, end_row, end_col)

    -- 4. Start progress feedback spinner
    ui.start_spinner("Syringe executing...")

    -- 5. Trigger the job
    local job_id = job.run_refactor(prompt, bufnr, start_mark_id, end_mark_id)
    if not job_id then
      ui.stop_spinner()
    end
  end)
end

---Cancel the active job in the current buffer
function M.cancel()
  local job = require("syringe.job")
  job.cancel(0)
end

return M
