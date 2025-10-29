local jj_workspace = require('jj-workspace')
local Job = require('plenary.job')
local Path = require("plenary.path")

local M = {}

local get_os_command_output = function(cmd)
    local command = table.remove(cmd, 1)
    local stderr = {}
    local stdout, ret = Job:new({
        command = command,
        args = cmd,
        cwd = jj_workspace.get_root(),
        on_stderr = function(_, data)
            table.insert(stderr, data)
        end
    }):sync()
    return stdout, ret, stderr
end

-- Create a simple jj repo with some initial commits
local prepare_jj_repo = function(dir)
    local repo_path = '/tmp/' .. dir
    Path:new(repo_path):mkdir()

    -- Initialize jj repo
    Job:new({
        command = 'jj',
        args = {'git', 'init', '--colocate'},
        cwd = repo_path,
    }):sync()

    -- Create a test file and describe the initial commit
    local test_file = repo_path .. '/test.txt'
    vim.fn.writefile({'initial content'}, test_file)

    Job:new({
        command = 'jj',
        args = {'describe', '-m', 'Initial commit'},
        cwd = repo_path,
    }):sync()

    -- Create a couple more commits for testing
    Job:new({
        command = 'jj',
        args = {'new'},
        cwd = repo_path,
    }):sync()

    vim.fn.writefile({'second content'}, repo_path .. '/test2.txt')
    Job:new({
        command = 'jj',
        args = {'describe', '-m', 'Second commit'},
        cwd = repo_path,
    }):sync()
end

local random_string = function()
    math.randomseed(os.clock()^5)
    local ret = ""
    for _ = 1, 5 do
        local random_char = math.random(97,122)
        ret = ret .. string.char(random_char)
    end
    return ret
end

local change_dir = function(dir)
    vim.api.nvim_set_current_dir('/tmp/'..dir)
    jj_workspace.set_repo_root('/tmp/'..dir)
end

local cleanup_repos = function()
    vim.api.nvim_exec('silent !rm -rf /tmp/jj_workspace_test*', true)
end

local create_workspace = function(path, revision)
    revision = revision or '@'
    vim.api.nvim_exec('!jj workspace add ' .. path .. ' -r ' .. revision, true)
end

local project_dir = vim.api.nvim_exec('pwd', true)

local reset_cwd = function()
    vim.cmd('cd ' .. project_dir)
    vim.api.nvim_set_current_dir(project_dir)
end

local config_jj_workspace = function()
    jj_workspace.setup({})
end

-- Test in a non-jj directory
M.in_non_jj_repo = function(cb)
    return function()
        local random_id = random_string()
        local dir = "jj_workspace_test_repo_" .. random_id

        config_jj_workspace()
        cleanup_repos()

        Path:new("/tmp/" .. dir):mkdir()
        change_dir(dir)

        local _, err = pcall(cb)

        reset_cwd()
        cleanup_repos()

        if err ~= nil then
            error(err)
        end
    end
end

-- Test in a jj repo with no additional workspaces
M.in_jj_repo_no_workspaces = function(cb)
    return function()
        local random_id = random_string()
        local repo_dir = 'jj_workspace_test_repo_' .. random_id

        config_jj_workspace()
        cleanup_repos()

        prepare_jj_repo(repo_dir)
        change_dir(repo_dir)

        local _, err = pcall(cb)

        reset_cwd()
        cleanup_repos()

        if err ~= nil then
            error(err)
        end
    end
end

-- Test in a jj repo with 1 additional workspace
M.in_jj_repo_1_workspace = function(cb)
    return function()
        local random_id = random_string()
        local repo_dir = 'jj_workspace_test_repo_' .. random_id

        config_jj_workspace()
        cleanup_repos()

        prepare_jj_repo(repo_dir)
        change_dir(repo_dir)
        create_workspace('feature', '@')

        local _, err = pcall(cb)

        reset_cwd()
        cleanup_repos()

        if err ~= nil then
            error(err)
        end
    end
end

-- Test in a jj repo with 2 additional workspaces
M.in_jj_repo_2_workspaces = function(cb)
    return function()
        local random_id = random_string()
        local repo_dir = 'jj_workspace_test_repo_' .. random_id

        config_jj_workspace()
        cleanup_repos()

        prepare_jj_repo(repo_dir)
        change_dir(repo_dir)
        create_workspace('feature1', '@')
        create_workspace('feature2', '@')

        local _, err = pcall(cb)

        reset_cwd()
        cleanup_repos()

        if err ~= nil then
            error(err)
        end
    end
end

-- Test with similarly named workspaces
M.in_jj_repo_2_similar_named_workspaces = function(cb)
    return function()
        local random_id = random_string()
        local repo_dir = 'jj_workspace_test_repo_' .. random_id

        config_jj_workspace()
        cleanup_repos()

        prepare_jj_repo(repo_dir)
        change_dir(repo_dir)
        create_workspace('feat', '@')
        create_workspace('feat-69', '@')

        local _, err = pcall(cb)

        reset_cwd()
        cleanup_repos()

        if err ~= nil then
            error(err)
        end
    end
end

-- Check if a workspace exists at the given path
M.check_workspace_exists = function(path)
    local stdout, ret = get_os_command_output({'jj', 'workspace', 'list'})
    if ret ~= 0 then
        return false
    end

    for _, line in ipairs(stdout) do
        if line:match(path) then
            return true
        end
    end
    return false
end

-- Check if a workspace with given name exists
M.check_workspace_name_exists = function(name)
    local stdout, ret = get_os_command_output({'jj', 'workspace', 'list'})
    if ret ~= 0 then
        return false
    end

    for _, line in ipairs(stdout) do
        local ws_name = line:match("^([^:]+):")
        if ws_name and vim.trim(ws_name) == name then
            return true
        end
    end
    return false
end

-- Get current workspace name
M.get_current_workspace_name = function()
    local root = jj_workspace.get_root()
    local cwd = vim.loop.cwd()

    -- Get workspace list and find which one matches current directory
    local stdout, ret = get_os_command_output({'jj', 'workspace', 'list'})
    if ret ~= 0 then
        return nil
    end

    for _, line in ipairs(stdout) do
        local name, path = line:match("([^:]+):%s*(.+)")
        if name and path and vim.trim(path) == cwd then
            return vim.trim(name)
        end
    end

    -- Default workspace (at repo root)
    if cwd == root then
        return "default"
    end

    return nil
end

return M
