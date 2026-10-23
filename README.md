# emacs-mode.nvim

A little Emacs for your Insert mode.

Move, select, and edit text with familiar Emacs keys without leaving Insert mode.
Enter emacs-mode with a key of your choice and return to Normal mode with `Esc`.
Regular Insert mode (`i`, `a`, `o`, ...) stays unchanged.

Includes a kill ring, region selection, and word, sentence, and paragraph editing.
Your registers and clipboard stay untouched.

Requires **Neovim 0.12+**. No dependencies.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "riii111/emacs-mode.nvim",
  opts = { start_key = "<leader>e" },
}
```

Press `<leader>e` in Normal mode to start at the cursor, then `Esc` or `C-c` to leave.
Switching buffers or windows also ends the mode.

Choose any `start_key` you like. For example, `"e"` replaces the Normal mode `e`
motion in editable buffers.

For other plugin managers, call `require("emacs-mode").setup({ start_key = "<leader>e" })`.

## Everyday keys

`C-` means Ctrl; `M-` means Alt (Meta). “Kill” saves text to the plugin's kill ring.

| Key | Action |
| --- | --- |
| `C-f` / `C-b` | Move forward / backward one character |
| `C-n` / `C-p` | Move down / up one screen line |
| `C-a` / `C-e` | Move to the start / end of the line |
| `M-f` / `M-b` | Move forward / backward by word |
| `C-k` / `C-u` | Kill to the end / start of the line |
| `M-d` / `M-Backspace` | Kill forward / backward by word |
| `C-y` | Yank from the kill ring |
| `M-y` | After a yank, cycle through older kills |
| `C-SPC` (`C-@`) | Set a mark, then move to select a region |
| `C-w` / `M-w` | Kill / copy the region (`C-w` kills the previous word if none) |
| `C-g` | Clear the selection |
| `C-s` / `C-r` | Search forward / backward using Vim search |
| `C-/` / `C-_` | Undo |

## Good to know

- While active, emacs-mode takes over its keys, including any completion-plugin mappings
  on those keys. Your previous mappings return when the mode ends.
- Your terminal must send Alt keys to Neovim. If the OS uses `C-SPC`, configure another
  mark key with `set_mark` (see the help below).
- `C-x` and `M-g` are Emacs prefixes while active, so Insert mode's `C-x` completion is not available in the mode.
- `C-u` kills to the start of the line, as in Readline; it is not Emacs' universal argument.

For all keys, configuration options, statusline integration via `is_active()` and the
`EmacsModeEnter` / `EmacsModeLeave` events, hooks for scrolling and completion plugins,
and behavior details, see **`:help emacs-mode`** or the [reference](doc/emacs-mode.txt).

## License

[MIT](LICENSE)
