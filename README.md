# markit.nvim

A search panel for Neovim powered by ripgrep (`rg`), providing aligned inputs (Query, Filter, Flags, Path), file-based folding, and live line previews.

## Features

- **Aligned Inputs**: Query, Filter, Flags, and Path fields.
- **Layout Protection**: Recovers inputs if the user deletes prompts or merges lines.
- **Cross-Platform**: Spawns ripgrep using Neovim's process API and normalizes paths.
- **Folding**: Toggle folding/unfolding of search results by file.
- **Live Preview**: Highlights the match under the cursor in the adjacent window.
- **History**: Navigation of previous searches.

## Installation

Using lazy.nvim:

```lua
{
  "ginkohub/markit.nvim",
  dependencies = {
    "nvim-tree/nvim-web-devicons"
  },
  opts = {
    config = {
      max_results = 100, -- Maximum number of results to display
      width = 40,        -- Width of the search panel
      highlights = {
        -- You can link to standard groups or provide custom colors
        Title = { link = "Title" },
        Label = { link = "Keyword" },
        Success = { link = "DiagnosticOk" },
        Error = { link = "DiagnosticError" },
        File = { link = "Directory" },
        Ext = { link = "Type" },
        Sep = { link = "Comment" },
        Text = { link = "Normal" },
        Line = { link = "LineNr" },
        Match = { link = "Search" }, -- The highlighted search matches
      }
    }
  }
}
```

## Configuration

If not using a plugin manager's `opts`, you can call `setup` manually:

```lua
require("markit").setup({
  config = {
    max_results = 200,
    width = 50,
    highlights = {
      Match = { fg = "#1e1e2e", bg = "#f9e2af", bold = true }, -- Custom match color
    }
  }
})
```

## Usage

### Commands

- `:MarkIt` - Toggle the search panel.
- `:MarkItHealth` - View dependencies check status.

### Keymaps

#### Input Fields (Insert Mode)

- `<CR>` - Move to the next input line. On the last line (Path), runs the search and exits insert mode.
- `<C-p>` - Navigate backwards through search history.
- `<C-n>` - Navigate forwards through search history.

#### Results List (Normal Mode)

- `<CR>` - **Smart Jump**: 
  - On a Folder line: Toggles folding/unfolding.
  - On a Result line: Opens the file. If already open in another tab, jumps to it. Reuses current window to avoid layout shifts.
- `<TAB>` - Toggle folding/unfolding of file matches.
- `t` - Open the match explicitly in a **New Tab**.
- `q` - Close the search panel.
