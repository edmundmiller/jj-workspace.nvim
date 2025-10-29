local Path = require("plenary.path")
local Window = require("plenary.window.float")
local strings = require("plenary.strings")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local utils = require("telescope.utils")
local action_set = require("telescope.actions.set")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values
local jj_workspace = require("jj-workspace")

local force_next_deletion = false

local get_workspace_info = function(prompt_bufnr)
    local selection = action_state.get_selected_entry(prompt_bufnr)
    return selection.path, selection.name
end

local switch_workspace = function(prompt_bufnr)
    local workspace_path, _ = get_workspace_info(prompt_bufnr)
    actions.close(prompt_bufnr)
    if workspace_path ~= nil then
        jj_workspace.switch_workspace(workspace_path)
    end
end

local toggle_forced_deletion = function()
    -- redraw otherwise the message is not displayed when in insert mode
    if force_next_deletion then
        print('The next deletion will not be forced')
        vim.fn.execute('redraw')
    else
        print('The next deletion will be forced')
        vim.fn.execute('redraw')
        force_next_deletion = true
    end
end

local delete_success_handler = function()
    force_next_deletion = false
end

local delete_failure_handler = function()
    print("Deletion failed, use <C-f> to force the next deletion")
end

local ask_to_confirm_deletion = function(forcing)
    if forcing then
        return vim.fn.input("Force deletion of workspace? [y/n]: ")
    end

    return vim.fn.input("Delete workspace? [y/n]: ")
end

local confirm_deletion = function(forcing)
    if not jj_workspace._config.confirm_telescope_deletions then
        return true
    end

    local confirmed = ask_to_confirm_deletion(forcing)

    if string.sub(string.lower(confirmed), 0, 1) == "y" then
        return true
    end

    print("Didn't delete workspace")
    return false
end

local delete_workspace = function(prompt_bufnr)
    if not confirm_deletion() then
        return
    end

    local _, workspace_name = get_workspace_info(prompt_bufnr)
    actions.close(prompt_bufnr)
    if workspace_name ~= nil then
       jj_workspace.delete_workspace(workspace_name, {
           on_failure = delete_failure_handler,
           on_success = delete_success_handler
       })
    end
end

local create_input_prompt = function(cb)
    local path = vim.fn.input("Path to workspace > ")
    cb(path)
end

local create_workspace = function(opts)
    opts = opts or {}

    -- Prompt for workspace path
    create_input_prompt(function(path)
        if path == "" then
            print("Workspace path cannot be empty")
            return
        end

        -- Prompt for optional revision
        local revision = vim.fn.input("Revision (leave empty for current): ")
        if revision == "" then
            revision = nil
        end

        -- Prompt for optional workspace name
        local name = vim.fn.input("Workspace name (leave empty for path basename): ")
        if name == "" then
            name = nil
        end

        -- Prompt for sparse patterns
        local sparse = vim.fn.input("Sparse patterns [copy/full/empty] (default: copy): ")
        if sparse == "" then
            sparse = nil
        end

        jj_workspace.create_workspace(path, revision, {
            name = name,
            sparse_patterns = sparse
        })
    end)
end

local telescope_jj_workspace = function(opts)
    opts = opts or {}

    -- Get list of workspaces using jj workspace list
    local output = utils.get_os_command_output({"jj", "workspace", "list"})
    local results = {}
    local widths = {
        name = 0,
        path = 0,
    }

    local parse_line = function(line)
        -- Parse format: "workspace_name: /path/to/workspace"
        local name, ws_path = line:match("([^:]+):%s*(.+)")
        if name and ws_path then
            name = vim.trim(name)
            ws_path = vim.trim(ws_path)

            local entry = {
                name = name,
                path = ws_path,
            }

            local index = #results + 1
            for key, val in pairs(widths) do
                if key == 'path' then
                    local new_path = utils.transform_path(opts, entry[key])
                    local path_len = strings.strdisplaywidth(new_path or "")
                    widths[key] = math.max(val, path_len)
                else
                    widths[key] = math.max(val, strings.strdisplaywidth(entry[key] or ""))
                end
            end

            table.insert(results, index, entry)
        end
    end

    for _, line in ipairs(output) do
        parse_line(line)
    end

    if #results == 0 then
        return
    end

    local displayer = require("telescope.pickers.entry_display").create {
        separator = " ",
        items = {
            { width = widths.name },
            { width = widths.path },
        },
    }

    local make_display = function(entry)
        return displayer {
            { entry.name, "TelescopeResultsIdentifier" },
            { utils.transform_path(opts, entry.path) },
        }
    end

    pickers.new(opts or {}, {
        prompt_title = "JJ Workspaces",
        finder = finders.new_table {
            results = results,
            entry_maker = function(entry)
                entry.value = entry.name
                entry.ordinal = entry.name .. " " .. entry.path
                entry.display = make_display
                return entry
            end,
        },
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(_, map)
            action_set.select:replace(switch_workspace)

            map("i", "<c-d>", delete_workspace)
            map("n", "<c-d>", delete_workspace)
            map("i", "<c-f>", toggle_forced_deletion)
            map("n", "<c-f>", toggle_forced_deletion)

            return true
        end
    }):find()
end

return require("telescope").register_extension({
    exports = {
        jj_workspace = telescope_jj_workspace,
        jj_workspaces = telescope_jj_workspace,
        create_jj_workspace = create_workspace
    }
})
