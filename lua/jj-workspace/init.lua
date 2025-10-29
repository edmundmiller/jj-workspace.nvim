local Job = require("plenary.job")
local Path = require("plenary.path")
local Enum = require("jj-workspace.enum")

local Status = require("jj-workspace.status")

local status = Status:new()
local M = {}
local jj_repo_root = nil
local current_workspace_path = nil
local on_change_callbacks = {}

M.setup_jj_info = function()
    local cwd = vim.loop.cwd()

    -- Find jj repo root by looking for .jj directory
    local find_root_job = Job:new({
        'jj', 'workspace', 'root',
        cwd = cwd,
    })

    local stdout, code = find_root_job:sync()
    if code ~= 0 then
        status:log().error("Error: not in a jj repository")
        jj_repo_root = nil
        current_workspace_path = nil
        return
    end

    local root_path = table.concat(stdout, "")
    root_path = vim.trim(root_path)
    jj_repo_root = root_path
    current_workspace_path = root_path

    status:log():debug("jj repository root is: " .. jj_repo_root)
end

local function on_tree_change_handler(op, metadata)
    if M._config.update_on_change then
        if op == Enum.Operations.Switch then
            local changed = M.update_current_buffer(metadata["prev_path"])
            if not changed then
                status:log().debug("Could not change to the file in the new workspace, running the `update_on_change_command`")
                vim.cmd(M._config.update_on_change_command)
            end
        end
    end
end

local function emit_on_change(op, metadata)
    -- TODO: We don't have a way to async update what is running
    status:next_status(string.format("Running post %s callbacks", op))
    on_tree_change_handler(op, metadata)
    for idx = 1, #on_change_callbacks do
        on_change_callbacks[idx](op, metadata)
    end
end

local function change_dirs(path)
    local workspace_path = M.get_workspace_path(path)

    local previous_workspace = current_workspace_path

    if Path:new(workspace_path):exists() then
        local cmd = string.format("%s %s", M._config.change_directory_command, workspace_path)
        status:log().debug("Changing to directory " .. workspace_path)
        vim.cmd(cmd)
        current_workspace_path = workspace_path
    else
        status:error('Could not change to directory: ' .. workspace_path)
    end

    if M._config.clearjumps_on_change then
        status:log().debug("Clearing jumps")
        vim.cmd("clearjumps")
    end

    return previous_workspace
end

local function create_workspace_job(path, revision, opts)
    opts = opts or {}

    local workspace_add_cmd = 'jj'
    local workspace_add_args = {'workspace', 'add'}

    -- Add optional workspace name
    if opts.name then
        table.insert(workspace_add_args, '--name')
        table.insert(workspace_add_args, opts.name)
    end

    -- Add optional revision
    if revision then
        table.insert(workspace_add_args, '-r')
        table.insert(workspace_add_args, revision)
    end

    -- Add sparse patterns option
    local sparse_patterns = opts.sparse_patterns or M._config.default_sparse_patterns or 'copy'
    table.insert(workspace_add_args, '--sparse-patterns')
    table.insert(workspace_add_args, sparse_patterns)

    -- Add destination path
    table.insert(workspace_add_args, path)

    return Job:new({
        command = workspace_add_cmd,
        args = workspace_add_args,
        cwd = jj_repo_root,
        on_start = function()
            status:next_status(workspace_add_cmd .. " " .. table.concat(workspace_add_args, " "))
        end
    })
end

-- Check if workspace exists by listing all workspaces
local function has_workspace(path, cb)
    local found = false
    local plenary_path = Path:new(path)
    local workspace_names = {}

    local job = Job:new({
        'jj', 'workspace', 'list',
        on_stdout = function(_, data)
            -- Parse jj workspace list output
            -- Format is typically: workspace_name: /path/to/workspace
            local name, ws_path = data:match("([^:]+):%s*(.+)")
            if name and ws_path then
                workspace_names[vim.trim(name)] = vim.trim(ws_path)

                local target_path
                if plenary_path:is_absolute() then
                    target_path = path
                else
                    target_path = Path:new(jj_repo_root, path):absolute()
                end

                if vim.trim(ws_path) == target_path then
                    found = true
                end
            end
        end,
        cwd = jj_repo_root
    })

    job:after(function()
        cb(found, workspace_names)
    end)

    status:next_status("Checking for workspace " .. path)
    job:start()
end

local function failure(from, cmd, path, soft_error)
    return function(e)
        local error_message = string.format(
            "%s Failed: PATH %s CMD %s RES %s, ERR %s",
            from,
            path,
            vim.inspect(cmd),
            vim.inspect(e:result()),
            vim.inspect(e:stderr_result()))

        if soft_error then
            status:status(error_message)
        else
            status:error(error_message)
        end
    end
end

local function create_workspace(path, revision, opts)
    opts = opts or {}
    local create = create_workspace_job(path, revision, opts)

    local workspace_path
    if Path:new(path):is_absolute() then
        workspace_path = path
    else
        workspace_path = Path:new(jj_repo_root, path):absolute()
    end

    create:after(function()
        if create.code ~= 0 then
            status:error("Failed to create workspace")
            return
        end

        vim.schedule(function()
            emit_on_change(Enum.Operations.Create, {
                path = path,
                revision = revision,
                name = opts.name,
                sparse_patterns = opts.sparse_patterns
            })
            M.switch_workspace(path)
        end)
    end)

    create:after_failure(failure("create_workspace", create.args, jj_repo_root))
    create:start()
end

M.create_workspace = function(path, revision, opts)
    status:reset(3)
    M.setup_jj_info()

    has_workspace(path, function(found, workspace_names)
        if found then
            status:error("workspace already exists")
            return
        end

        -- Prompt for revision if configured to do so
        if M._config.prompt_for_revision and not revision then
            vim.ui.input({
                prompt = 'Enter revision (leave empty for current): ',
            }, function(input)
                if input and input ~= "" then
                    revision = input
                end
                create_workspace(path, revision, opts)
            end)
        else
            create_workspace(path, revision, opts)
        end
    end)
end

M.switch_workspace = function(path)
    status:reset(2)
    M.setup_jj_info()
    has_workspace(path, function(found, workspace_names)

        if not found then
            status:error("workspace does not exist, please create it first: " .. path)
            return
        end

        vim.schedule(function()
            local prev_path = change_dirs(path)
            emit_on_change(Enum.Operations.Switch, { path = path, prev_path = prev_path })
        end)

    end)
end

M.delete_workspace = function(workspace_name, opts)
    if not opts then
        opts = {}
    end

    status:reset(2)
    M.setup_jj_info()

    -- jj workspace forget takes workspace name, not path
    -- We need to find the workspace name from the path if given
    local cmd = {
        "jj", "workspace", "forget", workspace_name
    }

    local delete = Job:new({
        command = cmd[1],
        args = {cmd[2], cmd[3], cmd[4]},
        cwd = jj_repo_root,
    })

    delete:after_success(vim.schedule_wrap(function()
        emit_on_change(Enum.Operations.Delete, { workspace_name = workspace_name })
        if opts.on_success then
            opts.on_success()
        end
    end))

    delete:after_failure(function(e)
        if opts.on_failure then
            opts.on_failure(e)
        end
        failure("delete_workspace", cmd, vim.loop.cwd())(e)
    end)

    delete:start()
end

M.rename_workspace = function(new_name, opts)
    if not opts then
        opts = {}
    end

    status:reset(2)
    M.setup_jj_info()

    local cmd = {
        "jj", "workspace", "rename", new_name
    }

    local rename = Job:new({
        command = cmd[1],
        args = {cmd[2], cmd[3], cmd[4]},
        cwd = current_workspace_path,
    })

    rename:after_success(vim.schedule_wrap(function()
        emit_on_change(Enum.Operations.Rename, { new_name = new_name })
        if opts.on_success then
            opts.on_success()
        end
    end))

    rename:after_failure(function(e)
        if opts.on_failure then
            opts.on_failure(e)
        end
        failure("rename_workspace", cmd, vim.loop.cwd())(e)
    end)

    rename:start()
end

M.list_workspaces = function(cb)
    M.setup_jj_info()
    local workspaces = {}

    local job = Job:new({
        'jj', 'workspace', 'list',
        on_stdout = function(_, data)
            local name, ws_path = data:match("([^:]+):%s*(.+)")
            if name and ws_path then
                table.insert(workspaces, {
                    name = vim.trim(name),
                    path = vim.trim(ws_path)
                })
            end
        end,
        cwd = jj_repo_root
    })

    job:after(function()
        if cb then
            cb(workspaces)
        end
    end)

    job:start()
end

M.set_repo_root = function(root)
    jj_repo_root = root
end

M.set_current_workspace_path = function(path)
    current_workspace_path = path
end

M.update_current_buffer = function(prev_path)
    if prev_path == nil then
        return false
    end

    local cwd = vim.loop.cwd()
    local current_buf_name = vim.api.nvim_buf_get_name(0)
    if not current_buf_name or current_buf_name == "" then
        return false
    end

    local name = Path:new(current_buf_name):absolute()
    local start, fin = string.find(name, cwd..Path.path.sep, 1, true)
    if start ~= nil then
        return true
    end

    start, fin = string.find(name, prev_path, 1, true)
    if start == nil then
        return false
    end

    local local_name = name:sub(fin + 2)

    local final_path = Path:new({cwd, local_name}):absolute()

    if not Path:new(final_path):exists() then
        return false
    end

    local bufnr = vim.fn.bufnr(final_path, true)
    vim.api.nvim_set_current_buf(bufnr)
    return true
end

M.on_tree_change = function(cb)
    table.insert(on_change_callbacks, cb)
end

M.reset = function()
    on_change_callbacks = {}
end

M.get_root = function()
    return jj_repo_root
end

M.get_current_workspace_path = function()
    return current_workspace_path
end

M.get_workspace_path = function(path)
    if Path:new(path):is_absolute() then
        return path
    else
        return Path:new(jj_repo_root, path):absolute()
    end
end

M.setup = function(config)
    config = config or {}
    M._config = vim.tbl_deep_extend("force", {
        change_directory_command = "cd",
        update_on_change = true,
        update_on_change_command = "e .",
        clearjumps_on_change = true,
        confirm_telescope_deletions = false,
        -- jj-specific options
        default_sparse_patterns = "copy",  -- copy, full, or empty
        prompt_for_revision = false,
    }, config)
end

M.set_status = function(msg)
    -- TODO: make this so #1
end

M.setup()
M.Operations = Enum.Operations

return M
