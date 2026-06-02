local syringe = require("syringe")
local syringe_job = require("syringe.job")

describe("syringe config", function()
  before_each(function()
    -- Reset default config before each test
    syringe.config = {
      cmd = "agy",
      timeout = 120000,
      default_keymaps = true,
      prompt_suffix = "\n\nCRITICAL: Do not write, create, or edit any files on disk. Do not run commands. Only generate the requested refactoring. Output your answer inside markdown code blocks.",
    }
  end)

  it("should load with default configuration options", function()
    assert.are.equal("agy", syringe.config.cmd)
    assert.are.equal(120000, syringe.config.timeout)
    assert.are.equal("\n\nCRITICAL: Do not write, create, or edit any files on disk. Do not run commands. Only generate the requested refactoring. Output your answer inside markdown code blocks.", syringe.config.prompt_suffix)
  end)

  it("should allow overriding all configuration options", function()
    syringe.setup({
      cmd = "agy",
      timeout = 60000,
      prompt_suffix = "custom suffix",
    })
    assert.are.equal("agy", syringe.config.cmd)
    assert.are.equal(60000, syringe.config.timeout)
    assert.are.equal("custom suffix", syringe.config.prompt_suffix)
  end)

  it("should allow partial configuration overrides", function()
    syringe.setup({
      timeout = 30000,
    })
    assert.are.equal("agy", syringe.config.cmd)
    assert.are.equal(30000, syringe.config.timeout)
    assert.are.equal("\n\nCRITICAL: Do not write, create, or edit any files on disk. Do not run commands. Only generate the requested refactoring. Output your answer inside markdown code blocks.", syringe.config.prompt_suffix)
  end)
end)

describe("visual range and extmark tracking", function()
  local bufnr

  before_each(function()
    -- Create a clean scratch buffer
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, bufnr) -- set it to current window for visual marks to work
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "line one: hello world",
      "line two: foo bar",
      "line three: last line",
    })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("should capture visual character selection range", function()
    -- Select "hello world" in line 1.
    -- "hello world" starts at index 11 (1-indexed) and ends at 21 (1-indexed).
    vim.cmd("normal! 1G11|v21|")

    local start_row, start_col, end_row, end_col = syringe_job.get_visual_range()
    assert.are.equal(0, start_row)
    assert.are.equal(10, start_col)
    assert.are.equal(0, end_row)
    assert.are.equal(21, end_col)

    local text = syringe_job.get_selection_text(bufnr, start_row, start_col, end_row, end_col)
    assert.are.same({ "hello world" }, text)
  end)

  it("should capture visual line selection range", function()
    -- Select the entire second line
    vim.cmd("normal! 2G_V")

    local start_row, start_col, end_row, end_col = syringe_job.get_visual_range()
    assert.are.equal(1, start_row)
    assert.are.equal(0, start_col)
    assert.are.equal(1, end_row)
    assert.are.equal(17, end_col)

    local text = syringe_job.get_selection_text(bufnr, start_row, start_col, end_row, end_col)
    assert.are.same({ "line two: foo bar" }, text)
  end)

  it("should track the selection range using extmarks when lines are inserted above", function()
    -- Select second line
    vim.cmd("normal! 2G_V")
    local start_row, start_col, end_row, end_col = syringe_job.get_visual_range()

    local start_mark_id, end_mark_id = syringe_job.create_marks(bufnr, start_row, start_col, end_row, end_col)

    -- Insert a line at the top of the buffer (index 0)
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new inserted line at top" })

    -- Retrieve tracked coordinates
    local new_start_row, new_start_col, new_end_row, new_end_col = syringe_job.get_marked_range(bufnr, start_mark_id, end_mark_id)

    -- Assert coordinates shifted down by 1 row
    assert.are.equal(2, new_start_row)
    assert.are.equal(0, new_start_col)
    assert.are.equal(2, new_end_row)
    assert.are.equal(17, new_end_col)

    -- Extract text using tracked coordinates and verify correctness
    local text = syringe_job.get_selection_text(bufnr, new_start_row, new_start_col, new_end_row, new_end_col)
    assert.are.same({ "line two: foo bar" }, text)

    syringe_job.clear_marks(bufnr, start_mark_id, end_mark_id)
  end)

  it("should clamp out-of-range columns to line lengths to prevent extmark errors", function()
    -- Set end visual mark col to a very large number (v:maxcol equivalent)
    vim.fn.setpos("'<", { bufnr, 1, 5, 0 })
    vim.fn.setpos("'>", { bufnr, 1, 2147483647, 0 })

    local start_row, start_col, end_row, end_col = syringe_job.get_visual_range()
    assert.are.equal(0, start_row)
    assert.are.equal(4, start_col)
    assert.are.equal(0, end_row)
    -- Length of "line one: hello world" is 21. It should be clamped to 21.
    assert.are.equal(21, end_col)

    -- Assert create_marks succeeds and doesn't throw out of range error
    local start_mark_id, end_mark_id = syringe_job.create_marks(bufnr, start_row, start_col, end_row, end_col)
    assert.is_not_nil(start_mark_id)
    assert.is_not_nil(end_mark_id)

    syringe_job.clear_marks(bufnr, start_mark_id, end_mark_id)
  end)
end)

describe("asynchronous CLI job execution", function()
  local bufnr

  before_each(function()
    -- Create a clean scratch buffer
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "line one: hello",
      "line two: world",
    })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("should successfully replace the selection with the uppercase text and prompt suffix", function()
    -- Configure syringe to use our mock script
    local syringe_mod = require("syringe")
    syringe_mod.setup({
      cmd = "./tests/mock_agy.sh",
      prompt_suffix = "",
    })

    -- Select the first line
    vim.cmd("normal! 1G_V")
    local start_row, start_col, end_row, end_col = syringe_job.get_visual_range()
    local start_mark_id, end_mark_id = syringe_job.create_marks(bufnr, start_row, start_col, end_row, end_col)

    -- Trigger the job
    local job_id = syringe_job.run_refactor("add some suffix", bufnr, start_mark_id, end_mark_id)
    assert.is_not_nil(job_id)

    -- Wait for the job to complete (up to 2000ms)
    local exit_codes = vim.fn.jobwait({ job_id }, 2000)
    assert.are.equal(0, exit_codes[1])

    -- Wait briefly for the Neovim event loop to process callbacks
    vim.wait(100, function() return false end)

    -- Assert buffer content replaced
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({
      "LINE ONE: HELLO - add some suffix",
      "line two: world",
    }, lines)
  end)

  it("should append the prompt_suffix to the prompt when executing the job", function()
    local syringe_mod = require("syringe")
    syringe_mod.setup({
      cmd = "./tests/mock_agy.sh",
      prompt_suffix = " - injected_suffix",
    })

    -- Select the first line
    vim.cmd("normal! 1G_V")
    local start_row, start_col, end_row, end_col = syringe_job.get_visual_range()
    local start_mark_id, end_mark_id = syringe_job.create_marks(bufnr, start_row, start_col, end_row, end_col)

    -- Trigger the job
    local job_id = syringe_job.run_refactor("base prompt", bufnr, start_mark_id, end_mark_id)
    assert.is_not_nil(job_id)

    -- Wait for the job to complete
    local exit_codes = vim.fn.jobwait({ job_id }, 2000)
    assert.are.equal(0, exit_codes[1])

    -- Wait briefly for callbacks
    vim.wait(100, function() return false end)

    -- Assert buffer content has the appended suffix
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({
      "LINE ONE: HELLO - base prompt - injected_suffix",
      "line two: world",
    }, lines)
  end)


  it("should notify on CLI failure and leave the buffer content unchanged", function()
    local syringe_mod = require("syringe")
    syringe_mod.setup({
      cmd = "./tests/mock_agy_error.sh",
    })

    -- Mock vim.notify
    local notify_called = false
    local notify_msg = ""
    local notify_level
    local old_notify = vim.notify
    vim.notify = function(msg, level, opts)
      notify_called = true
      notify_msg = msg
      notify_level = level
    end

    -- Select the first line
    vim.cmd("normal! 1G_V")
    local start_row, start_col, end_row, end_col = syringe_job.get_visual_range()
    local start_mark_id, end_mark_id = syringe_job.create_marks(bufnr, start_row, start_col, end_row, end_col)

    -- Trigger the job
    local job_id = syringe_job.run_refactor("unused prompt", bufnr, start_mark_id, end_mark_id)
    assert.is_not_nil(job_id)

    -- Wait for process to exit
    local exit_codes = vim.fn.jobwait({ job_id }, 2000)
    assert.are.equal(1, exit_codes[1])

    -- Wait briefly for event loop processing
    vim.wait(100, function() return false end)

    -- Restore notify
    vim.notify = old_notify

    -- Assert notify was called with error
    assert.is_true(notify_called)
    assert.is_not_nil(string.find(notify_msg, "Simulation of a compilation or API error"))
    assert.are.equal(vim.log.levels.ERROR, notify_level)

    -- Assert buffer remains unchanged
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({
      "line one: hello",
      "line two: world",
    }, lines)
  end)
end)

describe("user interface and feedback", function()
  local bufnr
  local old_ui_input
  local old_echo

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "some initial text to modify",
    })
    
    old_ui_input = vim.ui.input
    old_echo = vim.api.nvim_echo
  end)

  after_each(function()
    vim.ui.input = old_ui_input
    vim.api.nvim_echo = old_echo
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("should trigger input prompt, start spinner, run job, replace text, and stop spinner", function()
    local syringe_mod = require("syringe")
    syringe_mod.setup({
      cmd = "./tests/mock_agy.sh",
      prompt_suffix = "",
    })

    -- 1. Mock vim.ui.input to simulate user entering a prompt
    local input_called = false
    vim.ui.input = function(opts, cb)
      input_called = true
      assert.are.equal("Syringe Prompt: ", opts.prompt)
      cb("applied prompt")
    end

    -- 2. Mock vim.api.nvim_echo to track spinner animation calls
    local echo_chunks = {}
    vim.api.nvim_echo = function(chunks, history, opts)
      table.insert(echo_chunks, chunks)
    end

    -- Select the first line
    vim.cmd("normal! 1G_V")

    -- Call the main run function!
    syringe_mod.run()

    -- Assert input prompt was displayed
    assert.is_true(input_called)

    -- Wait for the buffer text to be replaced (up to 2000ms)
    local success = vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      return lines[1] == "SOME INITIAL TEXT TO MODIFY - applied prompt"
    end, 50)

    assert.is_true(success, "Buffer replacement failed or timed out")

    -- Wait briefly for final callbacks (spinner shutdown)
    vim.wait(100, function() return false end)

    -- Assert spinner was started (meaning we received echoing containing "executing...")
    local spinner_started = false
    for _, chunk in ipairs(echo_chunks) do
      if chunk and chunk[1] and chunk[1][1] then
        local text = chunk[1][1]
        if string.find(text, "executing...") then
          spinner_started = true
        end
      end
    end
    assert.is_true(spinner_started, "Spinner was not started")

    -- Assert spinner was cleared at the end (the last echo is empty string)
    assert.is_true(#echo_chunks > 0)
    local last_echo = echo_chunks[#echo_chunks][1][1]
    assert.are.equal("", last_echo)
  end)
end)

describe("cancellation and timeout handling", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "initial buffer line one",
      "initial buffer line two",
    })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("should terminate job and restore state when cancel is explicitly called", function()
    local syringe_mod = require("syringe")
    syringe_mod.setup({
      cmd = "./tests/mock_agy_sleep.sh",
      timeout = 10000,
    })

    -- Mock notifications
    local cancel_notified = false
    local old_notify = vim.notify
    vim.notify = function(msg, level, opts)
      if string.find(msg, "cancelled") then
        cancel_notified = true
      end
    end

    -- Select the first line
    vim.cmd("normal! 1G_V")
    local start_row, start_col, end_row, end_col = syringe_job.get_visual_range()
    local start_mark_id, end_mark_id = syringe_job.create_marks(bufnr, start_row, start_col, end_row, end_col)

    local job_id = syringe_job.run_refactor("unused", bufnr, start_mark_id, end_mark_id)
    assert.is_not_nil(job_id)

    -- Assert job is tracked as active in the buffer
    assert.is_not_nil(syringe_job.active_jobs[bufnr])

    -- Call cancel
    syringe_job.cancel(bufnr)

    -- Assert state cleaned up
    assert.is_nil(syringe_job.active_jobs[bufnr])
    assert.is_true(cancel_notified)

    -- Restore notification function
    vim.notify = old_notify

    -- Assert buffer remained unchanged
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({
      "initial buffer line one",
      "initial buffer line two",
    }, lines)
  end)

  it("should automatically terminate job when timeout is reached", function()
    local syringe_mod = require("syringe")
    syringe_mod.setup({
      cmd = "./tests/mock_agy_sleep.sh",
      timeout = 300, -- short timeout in ms
    })

    -- Mock notifications
    local timeout_notified = false
    local old_notify = vim.notify
    vim.notify = function(msg, level, opts)
      if string.find(msg, "timed out") then
        timeout_notified = true
      end
    end

    -- Select the first line
    vim.cmd("normal! 1G_V")
    local start_row, start_col, end_row, end_col = syringe_job.get_visual_range()
    local start_mark_id, end_mark_id = syringe_job.create_marks(bufnr, start_row, start_col, end_row, end_col)

    local job_id = syringe_job.run_refactor("unused", bufnr, start_mark_id, end_mark_id)
    assert.is_not_nil(job_id)

    -- Wait for timeout timer to fire (wait 600ms)
    local success = vim.wait(1000, function()
      return timeout_notified
    end, 50)

    assert.is_true(success, "Timeout was not triggered")
    assert.is_nil(syringe_job.active_jobs[bufnr], "Active job state not cleaned up after timeout")

    -- Restore notification function
    vim.notify = old_notify

    -- Assert buffer remained unchanged
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({
      "initial buffer line one",
      "initial buffer line two",
    }, lines)
  end)
end)

describe("commands and keymaps", function()
  local bufnr
  local old_leader

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, bufnr)
    
    old_leader = vim.g.mapleader
    vim.g.mapleader = ","

    -- Setup with default keymaps
    syringe.setup({
      cmd = "./tests/mock_agy.sh",
      default_keymaps = true,
    })
  end)

  after_each(function()
    vim.g.mapleader = old_leader
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("should define SyringeRun and SyringeCancel user commands", function()
    -- Load the plugin commands file
    vim.cmd("runtime plugin/syringe.lua")

    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands["SyringeRun"])
    assert.is_not_nil(commands["SyringeCancel"])
  end)

  it("should define keymaps in visual and normal modes", function()
    -- Check visual mode maps
    local vmaps = vim.api.nvim_get_keymap("v")
    local found_run = false
    for _, map in ipairs(vmaps) do
      if map.lhs == ",sr" then
        found_run = true
        assert.are.equal(":SyringeRun<CR>", map.rhs)
      end
    end
    assert.is_true(found_run)

    -- Check normal mode maps
    local nmaps = vim.api.nvim_get_keymap("n")
    local found_cancel = false
    for _, map in ipairs(nmaps) do
      if map.lhs == ",sc" then
        found_cancel = true
        assert.are.equal(":SyringeCancel<CR>", map.rhs)
      end
    end
    assert.is_true(found_cancel)
  end)

  it("should not define keymaps if default_keymaps is set to false", function()
    -- Clear current keymaps before setup
    pcall(vim.keymap.del, "v", ",sr")
    pcall(vim.keymap.del, "n", ",sc")

    syringe.setup({
      default_keymaps = false,
    })

    local vmaps = vim.api.nvim_get_keymap("v")
    local found_run = false
    for _, map in ipairs(vmaps) do
      if map.lhs == ",sr" then
        found_run = true
      end
    end
    assert.is_false(found_run)
  end)
end)

describe("markdown code block extraction", function()
  it("should extract code inside single code blocks and ignore surrounding text", function()
    local input = {
      "Explanation text",
      "```go",
      "func test() {",
      "  print(1)",
      "}",
      "```",
      "Some more trailing explanation text",
    }
    local output = syringe_job.extract_code_blocks(input)
    assert.are.same({
      "func test() {",
      "  print(1)",
      "}",
    }, output)
  end)

  it("should concatenate multiple code blocks together", function()
    local input = {
      "First block:",
      "```lua",
      "local a = 1",
      "```",
      "Second block:",
      "```lua",
      "local b = 2",
      "```",
    }
    local output = syringe_job.extract_code_blocks(input)
    assert.are.same({
      "local a = 1",
      "local b = 2",
    }, output)
  end)

  it("should return nil if no code blocks are detected", function()
    local input = {
      "just pure text",
      "without any markdown code delimiters",
    }
    local output = syringe_job.extract_code_blocks(input)
    assert.is_nil(output)
  end)

  it("should successfully extract code block and replace buffer in-place during integration run", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "original line of code here",
    })

    syringe.setup({
      cmd = "./tests/mock_agy_markdown.sh",
    })

    vim.cmd("normal! 1G_V")
    local start_row, start_col, end_row, end_col = syringe_job.get_visual_range()
    local start_mark_id, end_mark_id = syringe_job.create_marks(bufnr, start_row, start_col, end_row, end_col)

    local job_id = syringe_job.run_refactor("unused prompt", bufnr, start_mark_id, end_mark_id)
    assert.is_not_nil(job_id)

    local exit_codes = vim.fn.jobwait({ job_id }, 2000)
    assert.are.equal(0, exit_codes[1])

    vim.wait(100, function() return false end)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({
      "func main() {",
      "    println(\"Hello, Markdown World!\")",
      "}",
    }, lines)

    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("should fail gracefully and notify the user if output does not contain markdown code blocks", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "original line of code here",
    })

    syringe.setup({
      cmd = "./tests/mock_agy_plain.sh",
      prompt_suffix = "",
    })

    local notify_called = false
    local notify_msg = ""
    local notify_level
    local old_notify = vim.notify
    vim.notify = function(msg, level, opts)
      notify_called = true
      notify_msg = msg
      notify_level = level
    end

    vim.cmd("normal! 1G_V")
    local start_row, start_col, end_row, end_col = syringe_job.get_visual_range()
    local start_mark_id, end_mark_id = syringe_job.create_marks(bufnr, start_row, start_col, end_row, end_col)

    local job_id = syringe_job.run_refactor("some prompt", bufnr, start_mark_id, end_mark_id)
    assert.is_not_nil(job_id)

    local exit_codes = vim.fn.jobwait({ job_id }, 2000)
    assert.are.equal(0, exit_codes[1])

    vim.wait(100, function() return false end)

    vim.notify = old_notify

    assert.is_true(notify_called)
    assert.are.equal("Syringe Error: No markdown code blocks found in agent output. Buffer unchanged.", notify_msg)
    assert.are.equal(vim.log.levels.ERROR, notify_level)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({
      "original line of code here",
    }, lines)

    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)
end)

describe("workspace context gathering", function()
  it("should gather read-only context of other files with the same extension in the workspace", function()
    local root = vim.fn.getcwd()
    local active_file = root .. "/lua/syringe/init.lua"
    
    local context = syringe_job.get_workspace_context(active_file)
    assert.is_true(#context > 0)
    
    -- Verify it contains content of job.lua but not init.lua itself
    local has_job = false
    local has_init = false
    
    for _, line in ipairs(context) do
      if string.match(line, "^### Context File: lua/syringe/job.lua") then
        has_job = true
      end
      if string.match(line, "^### Context File: lua/syringe/init.lua") then
        has_init = true
      end
    end
    
    assert.is_true(has_job, "Should include job.lua context")
    assert.is_false(has_init, "Should not include active file init.lua context")
  end)
end)
