# jj-workspace.nvim<a name="jj-workspacenvim"></a>

A simple wrapper around jj workspace operations: create, switch, delete, and rename.
This plugin provides a seamless way to manage Jujutsu (jj) workspaces from within Neovim.

<!-- mdformat-toc start --slug=github --maxlevel=6 --minlevel=1 -->

- [jj-workspace.nvim](#jj-workspacenvim)
  - [Known Issues](#known-issues)
  - [Dependencies](#dependencies)
  - [Getting Started](#getting-started)
  - [Setup](#setup)
  - [Options](#options)
  - [Usage](#usage)
  - [Telescope](#telescope)
  - [Hooks](#hooks)
  - [JJ-Specific Features](#jj-specific-features)

<!-- mdformat-toc end -->

## Known Issues<a name="known-issues"></a>
Please file issues on the GitHub repository if you encounter any problems!

## Dependencies<a name="dependencies"></a>

- Requires NeoVim 0.5+
- Requires [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Requires [Jujutsu (jj)](https://github.com/martinvonz/jj) installed and accessible in PATH
- Optional [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for telescope extension

## Getting Started<a name="getting-started"></a>

First, ensure you have jj installed:

```console
# macOS
brew install jj

# Or see https://github.com/martinvonz/jj#installation
```

Then, install the plugin using your preferred plugin manager:

```lua
-- lazy.nvim
{
  'edmundmiller/jj-workspace.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
}

-- packer.nvim
use {
  'edmundmiller/jj-workspace.nvim',
  requires = { 'nvim-lua/plenary.nvim' }
}

-- vim-plug
Plug 'nvim-lua/plenary.nvim'
Plug 'edmundmiller/jj-workspace.nvim'
```

## Setup<a name="setup"></a>

```lua
require("jj-workspace").setup({
    change_directory_command = "cd",  -- or "tcd" for tab-local
    update_on_change = true,
    update_on_change_command = "e .",
    clearjumps_on_change = true,
    confirm_telescope_deletions = false,
    -- jj-specific options
    default_sparse_patterns = "copy",  -- "copy", "full", or "empty"
    prompt_for_revision = false,
})
```

### Debugging

jj-workspace writes logs to a `jj-workspace-nvim.log` file that resides in Neovim's cache path. (`:echo stdpath("cache")` to find where that is for you.)

By default, logging is enabled for warnings and above. This can be changed by setting `vim.g.jj_workspace_log_level` variable to one of the following log levels: `trace`, `debug`, `info`, `warn`, `error`, or `fatal`. Note that this would have to be done **before** jj-workspace's `setup` call. Alternatively, it can be more convenient to launch Neovim with an environment variable, e.g. `> JJ_WORKSPACE_NVIM_LOG=trace nvim`. In case both, `vim.g` and an environment variable are used, the log level set by the environment variable overrules. Supplying an invalid log level defaults back to warnings.

## Options<a name="options"></a>

`change_directory_command`: The vim command used to change to the new workspace directory.
Set this to `tcd` if you want to only change the `pwd` for the current vim Tab.

`update_on_change`:  Updates the current buffer to point to the new workspace if
the file is found in the new project. Otherwise, the following command will be run.

`update_on_change_command`: The vim command to run during the `update_on_change` event.
Note, that this command will only be run when the current file is not found in the new workspace.
This option defaults to `e .` which opens the root directory of the new workspace.

`clearjumps_on_change`: Every time you switch workspaces, your jumplist will be
cleared so that you don't accidentally go backward to a different workspace and
edit the wrong files.

`default_sparse_patterns`: Default sparse pattern mode when creating workspaces.
- `"copy"` (default): Copy sparse patterns from current workspace
- `"full"`: Include all files in the new workspace
- `"empty"`: Clear all files from the workspace (it will be empty)

`prompt_for_revision`: Whether to prompt for a revision when creating a workspace via the API.

```lua
require("jj-workspace").setup({
    change_directory_command = "cd",  -- default: "cd"
    update_on_change = true,           -- default: true
    update_on_change_command = "e .",  -- default: "e ."
    clearjumps_on_change = true,       -- default: true
    confirm_telescope_deletions = false, -- default: false
    default_sparse_patterns = "copy",   -- default: "copy"
    prompt_for_revision = false,        -- default: false
})
```

## Usage<a name="usage"></a>

The plugin provides several functions for workspace management:

```lua
-- Create a workspace
-- Args: path, revision (optional), opts (optional)
-- opts can include: name, sparse_patterns
:lua require("jj-workspace").create_workspace("../feature-work", "@", {name = "feature", sparse_patterns = "copy"})

-- Switch to an existing workspace by path
:lua require("jj-workspace").switch_workspace("../feature-work")

-- Delete a workspace by name
:lua require("jj-workspace").delete_workspace("feature")

-- Rename the current workspace
:lua require("jj-workspace").rename_workspace("new-name")

-- List all workspaces (with callback)
:lua require("jj-workspace").list_workspaces(function(workspaces)
  for _, ws in ipairs(workspaces) do
    print(ws.name .. ": " .. ws.path)
  end
end)
```

## Telescope<a name="telescope"></a>

Add the following to your config to load the telescope extension:

```lua
require("telescope").load_extension("jj_workspace")
```

### Switch and Delete Workspaces

To bring up the telescope window listing your workspaces run the following:

```lua
:lua require('telescope').extensions.jj_workspace.jj_workspaces()
-- <Enter> - switches to that workspace
-- <c-d> - deletes that workspace
-- <c-f> - toggles forcing of the next deletion
```

### Create a Workspace

To bring up the prompt to create a new workspace run the following:

```lua
:lua require('telescope').extensions.jj_workspace.create_jj_workspace()
```

You will be prompted for:
1. Path to the new workspace
2. Revision (optional - leave empty for current working-copy parent)
3. Workspace name (optional - leave empty to use path basename)
4. Sparse patterns (optional - copy/full/empty, defaults to copy)

## Hooks<a name="hooks"></a>

jj-workspace emits events that you can hook into:

```lua
local Workspace = require("jj-workspace")

-- op = Operations.Switch, Operations.Create, Operations.Delete, Operations.Rename
-- metadata = table of useful values (structure dependent on op)
--      Switch
--          path = path you switched to
--          prev_path = previous workspace path
--      Create
--          path = path where workspace created
--          revision = revision used (may be nil)
--          name = workspace name (may be nil)
--          sparse_patterns = sparse pattern mode
--      Delete
--          workspace_name = name of workspace deleted
--      Rename
--          new_name = new workspace name

Workspace.on_tree_change(function(op, metadata)
  if op == Workspace.Operations.Switch then
    print("Switched from " .. metadata.prev_path .. " to " .. metadata.path)
  elseif op == Workspace.Operations.Create then
    print("Created workspace at " .. metadata.path)
  end
end)
```

This means that you can integrate with [harpoon](https://github.com/ThePrimeagen/harpoon)
or other plugins to perform follow-up operations and enhance your development workflow!

## JJ-Specific Features<a name="jj-specific-features"></a>

### Workspace Naming

Unlike git worktrees, jj workspaces can have names independent of their filesystem location:

```lua
-- Create a workspace with a custom name
require("jj-workspace").create_workspace("../work", "@", {name = "my-feature"})
```

### Sparse Workspaces

jj workspaces support sparse patterns out of the box:

```lua
-- Create an empty workspace (for large repos)
require("jj-workspace").create_workspace("../sparse-work", "@", {sparse_patterns = "empty"})

-- Create a full workspace
require("jj-workspace").create_workspace("../full-work", "@", {sparse_patterns = "full"})

-- Copy patterns from current workspace (default)
require("jj-workspace").create_workspace("../similar-work", "@", {sparse_patterns = "copy"})
```

### Revision-Based Workspaces

Create workspaces at any revision in your jj repository:

```lua
-- Create workspace at a specific commit
require("jj-workspace").create_workspace("../old-work", "abc123")

-- Create workspace at a bookmark
require("jj-workspace").create_workspace("../main-work", "main")

-- Create workspace at current working-copy parent (default)
require("jj-workspace").create_workspace("../new-work")
```

### Workspace Renaming

Rename workspaces as your work evolves:

```lua
-- Rename the current workspace
require("jj-workspace").rename_workspace("new-descriptive-name")
```

---

*This plugin is a fork of [git-worktree.nvim](https://github.com/ThePrimeagen/git-worktree.nvim) adapted for Jujutsu workspaces.*
