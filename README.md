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
  opts = {}
}
```

## Usage

### Commands

- `:MarkIt` - Toggle the search panel.
- `:MarkItHealth` - View dependencies check status.
- `:checkhealth markit` - Run standard Neovim health check.

### Keymaps

#### Input Fields (Insert Mode)

- `<CR>` - Move to the next input line. On the last line, runs search and exits insert mode.
- `<C-p>` - Previous search history.
- `<C-n>` - Next search history.

#### Results List (Normal Mode)

- `<CR>` / `<TAB>` - Toggle folding/unfolding of file matches. If on a match line, opens it in the editor.
- `q` - Close the search panel.
