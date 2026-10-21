# emacs-mode.nvim

A little Emacs for your Insert mode.

emacs-mode is an Insert mode with Emacs keys, entered from Normal mode with a key of your choice.
Plain Insert mode (`i`, `a`, `o`, ...) stays as it is.

It is meant for writing prose: small moves, deletions and kills without going back to Normal mode,
and Normal mode again with `Esc` when you are done.

- Character, word, line, sentence and paragraph moves, kills and a kill ring with `M-y`
- A region from a mark, without Visual mode, killed with `C-w` or copied with `M-w`
- Every edit is one undo step, apart from the text typed around it
- Works with wide characters, combining characters and emoji, and ends sentences at `。！？` as well as `.!?`
- No registers and no clipboard are touched
- No dependencies; uses [neoscroll.nvim](https://github.com/karb94/neoscroll.nvim) for `C-v` / `M-v` / `C-l` when it is loaded,
  and closes the [blink.cmp](https://github.com/saghen/blink.cmp) menu without accepting an item

Requires Neovim 0.12 or later.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "riii111/emacs-mode.nvim",
  opts = { start_key = "e" },
}
```

Without a plugin manager, put the repository on `'runtimepath'` and call `require("emacs-mode").setup({ start_key = "e" })`.

## Configuration

```lua
require("emacs-mode").setup({
  -- the Normal mode key that starts the mode; none is mapped when it is false
  start_key = false,
  -- the keys that set the mark; terminals send C-SPC as C-@, and macOS may use C-SPC for the input source
  set_mark = { "<C-Space>", "<C-@>" },
  -- milliseconds of neoscroll's animation for C-v, M-v and C-l, when neoscroll is loaded
  scroll_duration = 100,
})
```

`start_key = "e"` replaces the `e` motion in Normal mode of editable buffers; `e` in Visual and
Operator-pending mode (`de`, `ye`) is unchanged, and buffers that are not for editing text (help, terminal,
pickers, file explorers) keep the motion.
To start the mode from a key of your own instead:

```lua
vim.keymap.set("n", "<leader>e", function() require("emacs-mode").start() end)
```

### Statusline

`require("emacs-mode").is_active()` tells whether the mode is on. With lualine:

```lua
sections = {
  lualine_a = {
    {
      "mode",
      fmt = function(str)
        return require("emacs-mode").is_active() and "EMACS" or str
      end,
      color = function()
        if require("emacs-mode").is_active() then
          return { fg = "#1a1e29", bg = "#c065db", gui = "bold" }
        end
      end,
    },
  },
},
```

The cursor is a block while the mode is on, as in Normal mode and Emacs.

## Starting and ending

- The mode starts at the cursor like `i`, without moving or changing anything.
- `Esc` or `C-c` ends it and puts back the mappings the buffer had.
- `i_CTRL-O` runs a Normal mode command and comes back to the mode.
- Going to another buffer or window, or deleting the buffer, ends it; coming back does not start it again.
- It works in buffers with an empty `'buftype'` that are `'modifiable'`.
- Lua: `require("emacs-mode").start()`, `stop()`, `is_active()`, `teardown()`.

## Keys

`C-` is Ctrl and `M-` is Alt (Meta).

| Key | Action |
|---|---|
| `C-f` / `C-b` | Next / previous character, across lines |
| `C-n` / `C-p` | Next / previous screen line (as `gj` / `gk`), keeping the column while pressed in a row |
| `C-a` / `C-e` | Start / end of the line |
| `M-f` / `M-b` | After the end of the next word / start of the word |
| `M-<` / `M->` | Start / end of the buffer |
| `M-{` / `M-}` | Previous / next paragraph separator |
| `M-a` / `M-e` | Start / end of the sentence |
| `C-v` / `M-v` | Scroll down / up a screen (with neoscroll when it is loaded) |
| `C-l` | Current line to the middle, top and bottom of the window, in turn when pressed in a row |
| `M-r` | Cursor to the middle, top and bottom line of the window, in turn |
| `C-d` / `Delete` | Delete the next character; at the end of a line, join the next line |
| `Backspace` / `C-h` | Delete the previous character; at the start of a line, join the previous line |
| `C-k` | Kill to the end of the line, or the line break when only blanks are left |
| `C-u` | Kill to the start of the line (as in Readline, not Emacs' universal-argument) |
| `M-d` / `M-Backspace` | Kill to where `M-f` / `M-b` go |
| `M-k` | Kill to the end of the sentence |
| `M-z` then a character | Kill up to and with the next occurrence of the character |
| `C-y` | Put back the kill at the yank pointer (usually the latest) |
| `M-y` | Right after `C-y` or `M-y`, replace what was put with the next older kill |
| `C-SPC` (`C-@`) | Set the mark; moves stretch the highlighted region from it |
| `C-w` | Kill the region, or the word before the cursor when there is none |
| `M-w` | Copy the region into the kill ring |
| `C-g` | Drop the region; the mode goes on |
| `M-h` | Mark the paragraph |
| `M-t` | Swap the word at or before the cursor with the next one |
| `M-u` / `M-l` / `M-c` | Upcase / downcase / capitalize the rest of the word |
| `M-\` / `M-SPC` | Delete the blanks around the cursor / collapse them to one space |
| `C-s` / `C-r` | Search forward / backward with Vim's `/` / `?` |
| `C-/` / `C-_` | Undo |

With the kitty keyboard protocol Option+Shift+`,` arrives as `<M-S-,>`, so `M-<` `M->` `M-{` `M-}` are
also mapped in that form. Other keys (`C-o`, `C-x`, ...) do what they do in Insert mode.

While the mode is on, its keys take the place of Vim's `C-v` (use `C-q`), `C-r` (insert a register),
`C-w`, `C-u`, `C-k`, `C-g` and others, and of other plugins' Insert mode mappings on the same keys,
such as blink.cmp's `C-SPC`. They all come back when the mode ends.

## How it differs from Emacs and plain Insert mode

- A character is what Normal mode's `l` and `h` move over: a base character with its composing characters,
  and emoji sequences (ZWJ, flags, skin tones) as one. `'delcombine'` is not used.
- A word is a run of characters that `'iskeyword'` makes word characters. Every Japanese character is one,
  so kana, kanji and Latin letters next to each other make one word, separated by `、`, `。` or blanks.
- A sentence ends at `。！？．`, or at `.!?` before a blank (a full-width space too) or the end of the line,
  with the terminators and closing brackets and quotes after it (`！？」`). A paragraph ends its last
  sentence, and a line break inside a paragraph counts as a blank. Abbreviations such as `Mr.` end a
  sentence too, as with Emacs' `sentence-end-double-space` off.
- The kill ring keeps 60 kills, shared by all buffers, for the Neovim session. Kills in a row join in the
  order of the text; any other key in between starts a new kill.
- Each command is one undo step. Like the arrow keys, its moves also split the text typed before and after.
- With a completion menu open, the mode's keys close it without accepting an item and then do their own
  work. For blink.cmp this calls blink.cmp internals, so check the mode after updating blink.cmp.
- Typing does not replace the region (Emacs' default without delete-selection-mode).
- `C-s` / `C-r` use Vim's search from `i_CTRL-O`: matches show while typing with `'incsearch'`, `C-g` /
  `C-t` go to the next / previous match, an empty search repeats the last one, `Esc` goes back. The cursor
  lands at the start of the match, and a match at the cursor is skipped, as with `/`.
- `C-v` / `C-l` follow Vim's `<C-f>` / `zz` without neoscroll; `M-r` follows `H` / `M` / `L`
  (inside `'scrolloff'`).

## Not included

- Keys starting with `C-x`, such as `C-x C-x`: `C-x` starts Insert mode completion, and a mapping there
  would wait for the next key.
- `C-t`, `C-o` (open-line), rectangles, registers, keyboard macros.
- Saving the kill ring across sessions.
- Input method control: text being composed belongs to the input method.

## Tests

```sh
make test          # needs nvim on PATH
make check-format  # needs stylua
```

The tests feed keys through the real mappings and check the text, the cursor, the kill ring, the mode and
the mappings put back. Run inside a configuration with blink.cmp or neoscroll loaded, with
`dofile("tests/emacs_spec.lua")()`, they also check the mode together with those.

Terminal and input method behavior is not covered: check by hand that the Alt keys reach Neovim
(`:lua vim.on_key(function(_, k) if k ~= "" then print(vim.fn.keytrans(k)) end end)` shows what arrives),
that `Esc` followed by a key is not taken for `M-` that key, and that `C-SPC` is not used by the OS.

## License

MIT
