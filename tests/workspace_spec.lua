local jj_workspace = require('jj-workspace')
local Path = require('plenary.path')

local harness = require('tests.jj_harness')
local in_non_jj_repo = harness.in_non_jj_repo
local in_jj_repo_no_workspaces = harness.in_jj_repo_no_workspaces
local in_jj_repo_1_workspace = harness.in_jj_repo_1_workspace
local in_jj_repo_2_workspaces = harness.in_jj_repo_2_workspaces
local in_jj_repo_2_similar_named_workspaces = harness.in_jj_repo_2_similar_named_workspaces
local check_workspace_exists = harness.check_workspace_exists
local check_workspace_name_exists = harness.check_workspace_name_exists
local get_current_workspace_name = harness.get_current_workspace_name

describe('jj-workspace', function()

    local completed_create = false
    local completed_switch = false
    local completed_delete = false
    local completed_rename = false

    local reset_variables = function()
        completed_create = false
        completed_switch = false
        completed_delete = false
        completed_rename = false
    end

    before_each(function()
        reset_variables()
        jj_workspace.on_tree_change(function(op, _, _)
            if op == jj_workspace.Operations.Create then
                completed_create = true
            end
            if op == jj_workspace.Operations.Switch then
                completed_switch = true
            end
            if op == jj_workspace.Operations.Delete then
                completed_delete = true
            end
            if op == jj_workspace.Operations.Rename then
                completed_rename = true
            end
        end)
    end)

    after_each(function()
        jj_workspace.reset()
    end)

    describe('Setup', function()
        it('should fail to setup in a non-jj repository',
            in_non_jj_repo(function()
                jj_workspace.setup_jj_info()
                local root = jj_workspace.get_root()
                assert.is_nil(root)
            end))

        it('should successfully setup in a jj repository',
            in_jj_repo_no_workspaces(function()
                jj_workspace.setup_jj_info()
                local root = jj_workspace.get_root()
                assert.is_not_nil(root)
                assert.True(root:match('/tmp/jj_workspace_test_repo_') ~= nil)
            end))
    end)

    describe('Create', function()

        it('can create a workspace with relative path and switch to it',
            in_jj_repo_no_workspaces(function()

            local path = "feature"
            jj_workspace.create_workspace(path)

            vim.fn.wait(
                10000,
                function()
                    return completed_create and completed_switch
                end,
                1000
            )

            local expected_path = jj_workspace.get_root() .. Path.path.sep .. path
            -- Check to make sure directory was switched
            assert.are.same(expected_path, vim.loop.cwd())

            -- Check to make sure it is added to jj workspace list
            assert.True(check_workspace_exists(expected_path))

        end))

        it('can create a workspace with absolute path and switch to it',
            in_jj_repo_no_workspaces(function()

            local path = jj_workspace.get_root() .. Path.path.sep .. "feature"
            jj_workspace.create_workspace(path)

            vim.fn.wait(
                10000,
                function()
                    return completed_create and completed_switch
                end,
                1000
            )

            -- Check to make sure directory was switched
            assert.are.same(vim.loop.cwd(), path)

            -- Check to make sure it is added to jj workspace list
            assert.True(check_workspace_exists(path))

        end))

        it('can create a workspace with a custom name',
            in_jj_repo_no_workspaces(function()

            local path = "feature-work"
            local name = "my-feature"
            jj_workspace.create_workspace(path, nil, {name = name})

            vim.fn.wait(
                10000,
                function()
                    return completed_create and completed_switch
                end,
                1000
            )

            -- Check workspace exists with custom name
            assert.True(check_workspace_name_exists(name))

        end))

        it('can create a workspace at a specific revision',
            in_jj_repo_no_workspaces(function()

            local path = "feature"
            local revision = "@-" -- Parent of current commit
            jj_workspace.create_workspace(path, revision)

            vim.fn.wait(
                10000,
                function()
                    return completed_create and completed_switch
                end,
                1000
            )

            local expected_path = jj_workspace.get_root() .. Path.path.sep .. path
            assert.are.same(expected_path, vim.loop.cwd())
            assert.True(check_workspace_exists(expected_path))

        end))

        it('should not create a workspace that already exists',
            in_jj_repo_1_workspace(function()

            local path = "feature"
            jj_workspace.create_workspace(path)

            vim.fn.wait(
                5000,
                function()
                    return completed_create
                end,
                1000
            )

            -- Should not have created or switched
            assert.False(completed_create)
            assert.False(completed_switch)

        end))

    end)

    describe('Switch', function()

        it('can switch to an existing workspace (relative path)',
            in_jj_repo_1_workspace(function()

            local path = "feature"
            jj_workspace.switch_workspace(path)

            vim.fn.wait(
                10000,
                function()
                    return completed_switch
                end,
                1000
            )

            local expected_path = jj_workspace.get_root() .. Path.path.sep .. path
            assert.are.same(expected_path, vim.loop.cwd())

        end))

        it('can switch to an existing workspace (absolute path)',
            in_jj_repo_1_workspace(function()

            local path = jj_workspace.get_root() .. Path.path.sep .. "feature"
            jj_workspace.switch_workspace(path)

            vim.fn.wait(
                10000,
                function()
                    return completed_switch
                end,
                1000
            )

            assert.are.same(path, vim.loop.cwd())

        end))

        it('should not switch to a non-existent workspace',
            in_jj_repo_no_workspaces(function()

            local path = "nonexistent"
            jj_workspace.switch_workspace(path)

            vim.fn.wait(
                5000,
                function()
                    return completed_switch
                end,
                1000
            )

            -- Should not have switched
            assert.False(completed_switch)

        end))

        it('can switch between multiple workspaces',
            in_jj_repo_2_workspaces(function()

            local path1 = "feature1"
            local path2 = "feature2"

            -- Switch to first workspace
            jj_workspace.switch_workspace(path1)
            vim.fn.wait(5000, function() return completed_switch end, 1000)
            assert.True(completed_switch)

            local expected_path1 = jj_workspace.get_root() .. Path.path.sep .. path1
            assert.are.same(expected_path1, vim.loop.cwd())

            -- Reset and switch to second workspace
            reset_variables()
            jj_workspace.switch_workspace(path2)
            vim.fn.wait(5000, function() return completed_switch end, 1000)
            assert.True(completed_switch)

            local expected_path2 = jj_workspace.get_root() .. Path.path.sep .. path2
            assert.are.same(expected_path2, vim.loop.cwd())

        end))

    end)

    describe('Delete', function()

        it('can delete an existing workspace by name',
            in_jj_repo_1_workspace(function()

            local workspace_name = "feature"
            jj_workspace.delete_workspace(workspace_name)

            vim.fn.wait(
                10000,
                function()
                    return completed_delete
                end,
                1000
            )

            assert.True(completed_delete)
            -- Workspace should no longer exist
            assert.False(check_workspace_name_exists(workspace_name))

        end))

        it('should not delete a non-existent workspace',
            in_jj_repo_no_workspaces(function()

            local workspace_name = "nonexistent"
            jj_workspace.delete_workspace(workspace_name)

            vim.fn.wait(
                5000,
                function()
                    return completed_delete
                end,
                1000
            )

            -- Should not have deleted
            assert.False(completed_delete)

        end))

    end)

    describe('Rename', function()

        it('can rename the current workspace',
            in_jj_repo_1_workspace(function()

            -- Switch to the workspace first
            local path = "feature"
            jj_workspace.switch_workspace(path)
            vim.fn.wait(5000, function() return completed_switch end, 1000)

            -- Now rename it
            reset_variables()
            local new_name = "my-awesome-feature"
            jj_workspace.rename_workspace(new_name)

            vim.fn.wait(
                10000,
                function()
                    return completed_rename
                end,
                1000
            )

            assert.True(completed_rename)
            -- Check new name exists
            assert.True(check_workspace_name_exists(new_name))
            -- Old name should not exist
            assert.False(check_workspace_name_exists("feature"))

        end))

    end)

    describe('List Workspaces', function()

        it('can list all workspaces',
            in_jj_repo_2_workspaces(function()

            local workspaces
            jj_workspace.list_workspaces(function(ws)
                workspaces = ws
            end)

            vim.fn.wait(
                10000,
                function()
                    return workspaces ~= nil
                end,
                1000
            )

            assert.is_not_nil(workspaces)
            -- Should have at least the default workspace + 2 created
            assert.True(#workspaces >= 2)

            -- Check structure
            assert.is_not_nil(workspaces[1].name)
            assert.is_not_nil(workspaces[1].path)

        end))

    end)

    describe('Edge Cases', function()

        it('handles similarly named workspaces correctly',
            in_jj_repo_2_similar_named_workspaces(function()

            -- Switch to 'feat' (not 'feat-69')
            local path = "feat"
            jj_workspace.switch_workspace(path)

            vim.fn.wait(5000, function() return completed_switch end, 1000)

            local expected_path = jj_workspace.get_root() .. Path.path.sep .. path
            assert.are.same(expected_path, vim.loop.cwd())

            -- Switch to 'feat-69' (not 'feat')
            reset_variables()
            local path2 = "feat-69"
            jj_workspace.switch_workspace(path2)

            vim.fn.wait(5000, function() return completed_switch end, 1000)

            local expected_path2 = jj_workspace.get_root() .. Path.path.sep .. path2
            assert.are.same(expected_path2, vim.loop.cwd())

        end))

    end)

    describe('Configuration', function()

        it('respects change_directory_command config',
            in_jj_repo_1_workspace(function()

            jj_workspace.setup({
                change_directory_command = "cd"
            })

            local path = "feature"
            jj_workspace.switch_workspace(path)

            vim.fn.wait(5000, function() return completed_switch end, 1000)

            local expected_path = jj_workspace.get_root() .. Path.path.sep .. path
            assert.are.same(expected_path, vim.loop.cwd())

        end))

        it('fires on_tree_change callbacks with correct metadata',
            in_jj_repo_no_workspaces(function()

            local create_metadata
            local switch_metadata

            jj_workspace.on_tree_change(function(op, metadata)
                if op == jj_workspace.Operations.Create then
                    create_metadata = metadata
                end
                if op == jj_workspace.Operations.Switch then
                    switch_metadata = metadata
                end
            end)

            local path = "feature"
            jj_workspace.create_workspace(path)

            vim.fn.wait(10000, function()
                return create_metadata ~= nil and switch_metadata ~= nil
            end, 1000)

            -- Check create metadata
            assert.is_not_nil(create_metadata)
            assert.are.same(path, create_metadata.path)

            -- Check switch metadata
            assert.is_not_nil(switch_metadata)
            assert.are.same(path, switch_metadata.path)
            assert.is_not_nil(switch_metadata.prev_path)

        end))

    end)

end)
