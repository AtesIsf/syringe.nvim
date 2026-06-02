local M = {}

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local active_jobs_count = 0
local timer = nil
local spinner_idx = 1

---Prompt the user for input instructions
---@param callback fun(input: string) Callback to invoke with the input string
function M.prompt_instruction(callback)
  vim.ui.input({
    prompt = "Syringe Prompt: ",
  }, function(input)
    if input and input ~= "" then
      callback(input)
    end
  end)
end

---Start status-line spinner with a message
---@param message string
function M.start_spinner(message)
  active_jobs_count = active_jobs_count + 1
  if timer then
    return
  end
  message = message or "Syringe running..."
  spinner_idx = 1
  timer = vim.loop.new_timer()
  timer:start(0, 100, vim.schedule_wrap(function()
    if not timer then return end
    local frame = spinner_frames[spinner_idx]
    vim.api.nvim_echo({ { string.format("%s %s", frame, message), "Normal" } }, false, {})
    spinner_idx = (spinner_idx % #spinner_frames) + 1
  end))
end

---Decrement job counter and stop spinner if all jobs completed
function M.stop_spinner()
  active_jobs_count = math.max(0, active_jobs_count - 1)
  if active_jobs_count == 0 and timer then
    timer:stop()
    timer:close()
    timer = nil
    -- Clear echo area
    vim.api.nvim_echo({ { "", "Normal" } }, false, {})
  end
end

return M
