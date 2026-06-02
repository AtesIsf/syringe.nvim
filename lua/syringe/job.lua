local M = {}

-- Namespace for syringe extmarks
M.ns_id = vim.api.nvim_create_namespace("syringe")

-- Table mapping bufnr -> active job state
M.active_jobs = {}

---Get the visual selection range (0-indexed, end exclusive)
---@return number start_row
---@return number start_col
---@return number end_row
---@return number end_col
function M.get_visual_range()
  -- Escape to normal mode to ensure visual marks '< and '> are updated
  local esc = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)
  vim.api.nvim_feedkeys(esc, "x", true)

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local mode = vim.fn.visualmode()

  local start_row = start_pos[2] - 1
  local start_col = start_pos[3] - 1
  local end_row = end_pos[2] - 1
  local end_col = end_pos[3]

  -- Get line content to determine lengths
  local lines = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, true)
  local end_line = lines[1] or ""

  if mode == "V" then
    -- Visual Line mode: select the entire line
    start_col = 0
    end_col = #end_line
  elseif mode == "v" then
    -- Visual Character mode: end_pos[3] is the 1-indexed byte index of the last character.
    -- We need to account for multi-byte characters to get the exclusive end column.
    local char_byte_len = 1
    if end_pos[3] <= #end_line then
      local lead_byte = string.byte(end_line, end_pos[3])
      if lead_byte then
        if lead_byte >= 240 then char_byte_len = 4
        elseif lead_byte >= 224 then char_byte_len = 3
        elseif lead_byte >= 192 then char_byte_len = 2
        end
      end
    end
    end_col = end_pos[3] - 1 + char_byte_len
  end

  -- Ensure we don't return negative values or index out of bounds
  start_row = math.max(0, start_row)
  start_col = math.max(0, start_col)
  end_row = math.max(0, end_row)
  end_col = math.max(0, end_col)

  -- Ensure columns are clamped within their respective line lengths to prevent out-of-range extmark errors
  local start_lines = vim.api.nvim_buf_get_lines(0, start_row, start_row + 1, true)
  local start_line = start_lines[1] or ""
  start_col = math.min(start_col, #start_line)

  local end_lines = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, true)
  local end_line_content = end_lines[1] or ""
  end_col = math.min(end_col, #end_line_content)

  return start_row, start_col, end_row, end_col
end

---Create extmarks around the selection range
---@param bufnr number The buffer handle (0 for current buffer)
---@param start_row number
---@param start_col number
---@param end_row number
---@param end_col number
---@return number start_mark_id
---@return number end_mark_id
function M.create_marks(bufnr, start_row, start_col, end_row, end_col)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

  -- Start mark with left gravity (stays before inserted text at the boundary)
  local start_mark_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns_id, start_row, start_col, {
    right_gravity = false,
  })

  -- End mark with right gravity (stays after inserted text at the boundary)
  local end_mark_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns_id, end_row, end_col, {
    right_gravity = true,
  })

  return start_mark_id, end_mark_id
end

---Retrieve the current coordinates of the extmarks
---@param bufnr number The buffer handle
---@param start_mark_id number
---@param end_mark_id number
---@return number|nil start_row
---@return number|nil start_col
---@return number|nil end_row
---@return number|nil end_col
function M.get_marked_range(bufnr, start_mark_id, end_mark_id)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

  local start_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, M.ns_id, start_mark_id, {})
  local end_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, M.ns_id, end_mark_id, {})

  if not start_pos or #start_pos == 0 or not end_pos or #end_pos == 0 then
    return nil, nil, nil, nil
  end

  return start_pos[1], start_pos[2], end_pos[1], end_pos[2]
end

---Extract the text inside the given range
---@param bufnr number
---@param start_row number
---@param start_col number
---@param end_row number
---@param end_col number
---@return string[]
function M.get_selection_text(bufnr, start_row, start_col, end_row, end_col)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  return vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
end

---Delete the extmarks
---@param bufnr number
---@param start_mark_id number
---@param end_mark_id number
function M.clear_marks(bufnr, start_mark_id, end_mark_id)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns_id, start_mark_id)
  pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns_id, end_mark_id)
end

---Extracts code block content from markdown-formatted lines
---@param lines string[]
---@return string[]
function M.extract_code_blocks(lines)
  local inside_block = false
  local code_lines = {}
  local has_blocks = false

  for _, line in ipairs(lines) do
    if line:match("^%s*```") then
      inside_block = not inside_block
      has_blocks = true
    elseif inside_block then
      table.insert(code_lines, line)
    end
  end

  -- If no code blocks were found, fallback to returning the original lines
  if not has_blocks or #code_lines == 0 then
    return lines
  end

  return code_lines
end

---Cancel the active job running in the given buffer
---@param bufnr number
function M.cancel(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local state = M.active_jobs[bufnr]
  if state then
    state.cancelled = true

    -- Stop the job
    vim.fn.jobstop(state.job_id)

    -- Close the timeout timer
    if state.timeout_timer then
      state.timeout_timer:stop()
      state.timeout_timer:close()
    end

    -- Stop the status spinner
    local ui = require("syringe.ui")
    ui.stop_spinner()

    -- Clean up marks
    M.clear_marks(bufnr, state.start_mark_id, state.end_mark_id)

    -- Clear state
    M.active_jobs[bufnr] = nil

    vim.notify("Syringe: Job cancelled.", vim.log.levels.INFO)
  end
end

---Runs the refactoring process asynchronously by calling the configured CLI tool
---@param prompt string The instruction passed to the CLI
---@param bufnr number The buffer handle
---@param start_mark_id number
---@param end_mark_id number
---@return number|nil job_id The spawned job ID, or nil if start failed
function M.run_refactor(prompt, bufnr, start_mark_id, end_mark_id)
  local syringe = require("syringe")
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

  -- Cancel any active job in this buffer to prevent overlapping replacements
  M.cancel(bufnr)

  -- 1. Retrieve the range coordinates
  local start_row, start_col, end_row, end_col = M.get_marked_range(bufnr, start_mark_id, end_mark_id)
  if not start_row then
    vim.notify("Syringe: Invalid selection coordinates.", vim.log.levels.ERROR)
    return nil
  end

  -- 2. Extract selection text to send to stdin
  local selection_text = M.get_selection_text(bufnr, start_row, start_col, end_row, end_col)

  -- 3. Construct job command
  local final_prompt = prompt
  if syringe.config.prompt_suffix and syringe.config.prompt_suffix ~= "" then
    final_prompt = prompt .. syringe.config.prompt_suffix
  end
  local cmd = { syringe.config.cmd, "--prompt", final_prompt }

  local stdout_data = {}
  local stderr_data = {}
  local timeout_timer = nil

  -- 4. Spawn job asynchronously
  local job_id
  job_id = vim.fn.jobstart(cmd, {
    stdin = "pipe",
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          table.insert(stdout_data, line)
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          table.insert(stderr_data, line)
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      local state = M.active_jobs[bufnr]
      -- If cancelled or completed by someone else, do nothing
      if not state or state.job_id ~= job_id or state.cancelled then
        return
      end

      -- Clear buffer active job state
      M.active_jobs[bufnr] = nil

      -- Close the timeout timer
      if timeout_timer then
        timeout_timer:stop()
        timeout_timer:close()
      end

      -- Stop status spinner
      local ui = require("syringe.ui")
      ui.stop_spinner()

      -- Retrieve current marks before deleting them
      local s_row, s_col, e_row, e_col = M.get_marked_range(bufnr, start_mark_id, end_mark_id)
      
      -- Clear the marks
      M.clear_marks(bufnr, start_mark_id, end_mark_id)

      if exit_code == 0 then
        if s_row then
          -- Extract code block lines from stdout if present
          local replacement_lines = M.extract_code_blocks(stdout_data)

          -- Strip trailing empty item if stream ended with a newline
          if #replacement_lines > 0 and replacement_lines[#replacement_lines] == "" then
            table.remove(replacement_lines)
          end
          vim.api.nvim_buf_set_text(bufnr, s_row, s_col, e_row, e_col, replacement_lines)
        else
          vim.notify("Syringe: Failed to locate buffer position for text replacement.", vim.log.levels.ERROR)
        end
      else
        if #stderr_data > 0 and stderr_data[#stderr_data] == "" then
          table.remove(stderr_data)
        end
        local err_msg = table.concat(stderr_data, "\n")
        if err_msg == "" then
          err_msg = "Job exited with code " .. tostring(exit_code)
        end
        vim.notify("Syringe CLI Error: " .. err_msg, vim.log.levels.ERROR)
      end
    end,
  })

  if job_id <= 0 then
    vim.notify("Syringe: Failed to start job '" .. syringe.config.cmd .. "'", vim.log.levels.ERROR)
    M.clear_marks(bufnr, start_mark_id, end_mark_id)
    return nil
  end

  -- Set up timeout auto-termination
  local timeout = syringe.config.timeout
  if timeout and timeout > 0 then
    timeout_timer = vim.loop.new_timer()
    timeout_timer:start(timeout, 0, vim.schedule_wrap(function()
      local state = M.active_jobs[bufnr]
      if state and state.job_id == job_id then
        vim.notify("Syringe: Job timed out after " .. tostring(timeout) .. "ms.", vim.log.levels.WARN)
        M.cancel(bufnr)
      end
    end))
  end

  -- Store state
  M.active_jobs[bufnr] = {
    job_id = job_id,
    start_mark_id = start_mark_id,
    end_mark_id = end_mark_id,
    timeout_timer = timeout_timer,
    cancelled = false,
  }

  -- 5. Send selection text to stdin and close channel
  local input_str = table.concat(selection_text, "\n")
  vim.fn.chansend(job_id, input_str)
  vim.fn.chanclose(job_id, "stdin")

  return job_id
end

return M
