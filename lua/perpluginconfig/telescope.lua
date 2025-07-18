local function find_files(command_info)
    local is_okay, telescope = pcall(require, "telescope.builtin")
    if not is_okay then
        print("Telescope is not installed.")
        return
    end
    telescope.find_files()
end

local function show_file_diagnostics(command_info)
    local is_okay, telescope = pcall(require, "telescope.builtin")
    if not is_okay then
        print("Telescope is not installed.")
        return
    end
    telescope.diagnostics({ bufnr = 0 })
end

local function show_project_diagnostics(command_info)
    local is_okay, telescope = pcall(require, "telescope.builtin")
    if not is_okay then
        print("Telescope is not installed.")
        return
    end
    telescope.diagnostics()
end

local function show_buffers(command_info)
    local is_okay, telescope = pcall(require, "telescope.builtin")
    if not is_okay then
        print("Telescope is not installed.")
        return
    end
    telescope.buffers({
        only_cwd = true,
    })
end

local function live_grep(command_info)
    local is_okay, telescope = pcall(require, "telescope.builtin")
    if not is_okay then
        print("Telescope is not installed.")
        return
    end
    telescope.live_grep({})
end

vim.api.nvim_create_user_command("SearchInProject", live_grep, {})
vim.api.nvim_create_user_command("ShowBuffers", show_buffers, {})
vim.api.nvim_create_user_command("ShowFileDiagnostics", show_file_diagnostics, {})
vim.api.nvim_create_user_command("ShowProjectDiagnostics", show_project_diagnostics, {})
vim.api.nvim_create_user_command("Open", find_files, {})
