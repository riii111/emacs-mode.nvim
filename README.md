# emacs-mode.nvim

A little Emacs for your Insert mode.

emacs-mode is an Insert mode with Emacs keys, entered from Normal mode with a key of your choice.
Plain Insert mode (`i`, `a`, `o`, ...) stays as it is.

It is meant for writing prose: small moves, deletions and kills without going back to Normal mode,
and Normal mode again with `Esc` when you are done.

- Character, word, line, sentence and paragraph moves, goto line, character and column, kills and a kill ring with `M-y`
- A mark and a selection that are separate, as in Emacs: `C-SPC`, `M-@`, `C-x h`, `C-x C-x` and selecting with Shift
- Transposing, case conversion, whitespace and blank line commands, paragraph filling that leaves Markdown structure alone
- Every edit is one undo step, apart from the text typed around it; undo and redo are Neovim's own
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
  -- more keys for a command, by the name it has in `:help emacs-mode-commands`
  aliases = {},
})
```

`start_key = "e"` replaces the `e` motion in Normal mode of editable buffers; `e` in Visual and
Operator-pending mode (`de`, `ye`) is unchanged, and buffers that are not for editing text (help, terminal,
pickers, file explorers) keep the motion.
To start the mode from a key of your own instead, still call `setup()` (with lazy.nvim, `opts = {}` does),
since it sets up what ends the mode and counts the keys:

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
- `Esc` or `C-c` ends it and puts back the mappings the buffer had, and the mark goes with it.
- `i_CTRL-O` runs a Normal mode command and comes back to the mode.
- Going to another buffer or window, or deleting the buffer, ends it; coming back does not start it again.
- It works in buffers with an empty `'buftype'` that are `'modifiable'`.
- Lua: `require("emacs-mode").start()`, `stop()`, `is_active()`, `teardown()`.

## Keys

`C-` is Ctrl, `M-` is Alt (Meta) and `S-` is Shift. The keys after a slash do the same.

### Moving

| Key | Action |
|---|---|
| `C-f` / `C-b`, `Right` / `Left` | Next / previous character, across lines |
| `C-n` / `C-p`, `Down` / `Up` | Next / previous screen line (as `gj` / `gk`), keeping the column while pressed in a row |
| `C-a` / `C-e`, `Home` / `End` | Start / end of the line |
| `M-m` | First character of the line that is not a blank |
| `M-f` / `M-b`, `C-Right` / `C-Left`, `M-Right` / `M-Left` | After the end of the next word / start of the word |
| `M-<` / `M->`, `C-Home` / `C-End` | Start / end of the buffer |
| `M-{` / `M-}`, `C-Up` / `C-Down` | Previous / next paragraph separator |
| `M-a` / `M-e` | Start / end of the sentence |
| `M-g g`, `M-g M-g` | Go to a line number that is asked for |
| `M-g c` | Go to a character position (`1` is the start of the buffer; code points, line breaks counted) |
| `M-g TAB` | Go to a column of the line, counted in cells; inside a tab or a wide character, after it |
| `C-x C-n` | Keep the column of `C-n`, `C-p` and the page scrolls (the goal column); pressed again where it is, release it |

### Scrolling

| Key | Action |
|---|---|
| `C-v` / `M-v`, `PageDown` / `PageUp` | Scroll down / up a screen (with neoscroll when it is loaded) |
| `C-l` | Current line to the middle, top and bottom of the window, in turn when pressed in a row |
| `M-r` | Cursor to the middle, top and bottom line of the window, in turn |
| `C-x <` / `C-x >`, `C-PageDown` / `C-PageUp` | Scroll the text left (showing the right of the lines) / right by the width of the window less 2 |

Lines that wrap cannot scroll sideways, so `C-x <` turns `'wrap'` off in the window until the text is back at the
left or the mode ends.

### Deleting and killing

| Key | Action |
|---|---|
| `C-d` | Delete the next character, also when a selection is on; at the end of a line, join the next line |
| `Delete` | Delete the selection, or the next character |
| `Backspace` / `C-h` | Delete the selection, or the previous character |
| `C-k` | Kill to the end of the line, or the line break when only blanks are left |
| `C-S-Backspace` | Kill the whole line with its line break |
| `C-u` | Kill to the start of the line (as in Readline, not Emacs' universal-argument) |
| `M-d` / `M-Backspace`, `C-Delete` / `C-Backspace` | Kill to where `M-f` / `M-b` go |
| `M-k` / `C-x Backspace` | Kill to the end / back to the start of the sentence |
| `M-z` then a character | Kill up to and with the next occurrence of the character |

Deleting does not touch the kill ring. Kills in a row join into one entry, and so do two kills with `C-M-w` between.

### Mark and selection

| Key | Action |
|---|---|
| `C-SPC` (`C-@`) | Set the mark and start a selection; again right after, drop it and bring it back |
| `S-Right` `S-Left` `S-Down` `S-Up` `S-Home` `S-End` `S-PageDown` `S-PageUp`, `C-S-Right` `C-S-Left` `C-S-Up` `C-S-Down` `C-S-Home` `C-S-End`, `M-S-Right` `M-S-Left` | Move as the key without Shift does and select from where the move started; a move without Shift ends such a selection |
| `M-@` | Mark the next word; again, one word further |
| `M-h` | Mark the paragraph; again, the next one too |
| `C-x h` | Select the buffer |
| `C-x C-x` | Swap the cursor and the mark, and bring the selection back |
| `C-g` | Drop the selection; the mark stays |
| `C-w` / `S-Delete` | Kill the selection, or the word before the cursor when there is none |
| `M-w` / `C-Insert` | Copy the selection into the kill ring |

The selection is highlighted. Moves stretch it, and typed text and edits end it without replacing it.
The mark stays until the mode ends: `C-x C-x`, `C-x C-u` and `C-x C-l` use it after `C-g` too.

### Kill ring

| Key | Action |
|---|---|
| `C-y` / `S-Insert` | Put back the kill at the yank pointer (usually the latest), and set the mark at its start without a selection |
| `M-y` | Right after `C-y`, or after an `M-y` that replaced, replace what was put with the next older kill; otherwise, also after a kill chosen from the list, choose a kill from a list (`vim.ui.select()`) and put it |
| `C-M-w` | Make the next kill join the previous one |

### Transposing, case, blanks and lines

| Key | Action |
|---|---|
| `C-t` | Swap the characters around the cursor, or the last two at the end of a line; a line break is a character |
| `M-t` | Swap the word at or before the cursor with the next |
| `C-x C-t` | Swap the line with the one before it (the first line, with the next) |
| `M-u` / `M-l` / `M-c` | Upcase / downcase / capitalize the rest of the word |
| `C-x C-u` / `C-x C-l` | Upcase / downcase the text between the mark and the cursor |
| `M-\` | Delete the blanks around the cursor |
| `M-SPC` | Leave one space around the cursor; pressed in a row, none, and then the blanks that were there |
| `M-^` | Join the line to the one before it, leaving one space or none; with a selection, join its lines |
| `C-M-o` | Split the line at the cursor and put the rest in the column it had |
| `C-x C-o` | On a blank line, delete the blank lines around it but one (or it, when alone); else those after |

### Filling

| Key | Action |
|---|---|
| `M-q` | Fill the paragraph at or after the cursor, or the paragraphs the selection touches |
| `C-x f` | Set the fill width of the buffer, asked for with the cursor column as the default |
| `C-x .` | Use the text from the start of the line to the cursor as the fill prefix of the buffer; at the start of a line, remove it |

Without `C-x f` the width is `'textwidth'`, or 70 when that is 0; `'textwidth'` itself is left alone.
Lines are joined with no space next to CJK characters and broken between them, with kinsoku (no `。` or `」`
at the start of a line, no `「` at the end). Code blocks, front matter, headings, tables, HTML, link definitions,
indented code, list items and quotes with blocks inside, quotes of different depth, and paragraphs with a hard line break
(two trailing spaces or `\`) are not filled, and neither is a line that would turn into a list, heading or quote
by starting a line. List items keep their marker and indentation (a task box stays together), quotes their marks;
the fill prefix is for plain paragraphs.

### Undo and redo

| Key | Action |
|---|---|
| `C-/` / `C-_` / `C-x u` | Undo |
| `C-?` / `C-M-_` | Redo |

Both are Neovim's own undo tree; there is no selective undo, and undo is not itself undone.

### Search

| Key | Action |
|---|---|
| `C-s` / `C-r` | Search forward / backward with Vim's `/` / `?` |

The search is Vim's: matches show while typing with `'incsearch'`, `C-g` / `C-t` go to the next / previous
match, an empty search repeats the last one, `Esc` goes back. The cursor lands at the start of the match, and a
match at the cursor is skipped, as with `/`.

### Keys that need a second key

`C-x` and `M-g` wait for the next key as long as it takes, with no timeout; `Esc` or `C-g` gives up, and a key
that follows them but means nothing is dropped, as in Emacs. Prompts (`M-g g`, `M-g c`, `M-g TAB`, `C-x f`,
`M-y`) are Vim's `input()` and `vim.ui.select()`; `Esc` cancels them.

While the mode is on, `C-x` is the Emacs prefix, so Neovim's `i_CTRL-X` completion keys are not available in
it (`C-x C-f`, `C-x C-l` and the others); plain Insert mode keeps them. Its keys also take the place of Vim's
`C-v` (use `C-q`), `C-r` (insert a register), `C-w`, `C-u`, `C-k`, `C-g`, `C-t` and others, and of other plugins'
Insert mode mappings on the same keys, such as blink.cmp's `C-SPC`. They all come back when the mode ends.
`Up`, `Down`, `PageUp` and `PageDown` keep working on a completion menu while one is open.

## Terminals

Whether a key reaches Neovim, and as what, depends on the terminal. A terminal that cannot tell two keys apart
sends them as one, and one input gets one action here.

| Key | What a terminal without the kitty keyboard protocol sends | Here |
|---|---|---|
| `C-?` | DEL, as for Backspace | `Backspace`; with the protocol, `C-?` (also as `C-S-/`) is redo |
| `C-S-Backspace` | the same as Backspace | `Backspace`; with the protocol, `C-S-Backspace` kills the line |
| `C-Backspace` | some send `C-h` | `Backspace`; with the protocol, `C-Backspace` kills the word before |
| `C-M-_` | `Esc` and `C-_`, the same as `C-M-/` | Redo, when the terminal sends it as `<C-M-_>` |
| `M-<` `M->` `M-{` `M-}` `M-@` `M-^` | `Esc` and the character | With the protocol, `<M-S-,>` and the like; these are mapped too |
| `C-SPC` | `C-@` | Both set the mark |
| `Alt+Arrow` | varies (`Esc b`, or `Esc` and the arrow) | Check that `Esc` followed by a key is not taken for `M-` that key |

Neovim's reading of these sequences was checked with synthetic input; no physical keyboard or terminal emulator was.
The forms above with the protocol assume a US layout. For anything else, give the key you can send to the
command with `aliases`; for example, to kill a line and redo with function keys:

```lua
require("emacs-mode").setup({
  start_key = "e",
  aliases = {
    kill_whole_line = { "<F7>" },
    redo = { "<F8>" },
  },
})
```

`:lua vim.on_key(function(_, k) if k ~= "" then print(vim.fn.keytrans(k)) end end)` shows what arrives.
Command names are in `:help emacs-mode-commands`.

## Status of Emacs' keys

Standard keys of GNU Emacs 30 are sorted into four statuses. [docs/emacs-30-key-audit.md](docs/emacs-30-key-audit.md)
lists them key by key with the Emacs source.

**Supported**: the ten categories above, with every standard key and alias of the category.

| Category | Keys |
|---|---|
| Moving and positions | `C-f` `C-b` `C-n` `C-p` `C-a` `C-e` `M-f` `M-b` `M-<` `M->` `M-{` `M-}` `M-a` `M-e` `M-m` `M-g g` `M-g M-g` `M-g c` `M-g TAB` `C-x C-n`, the arrow, `Home`, `End`, `C-Left/Right/Up/Down`, `M-Left/Right`, `C-Home`, `C-End` |
| Scrolling | `C-v` `M-v` `C-l` `M-r` `C-x <` `C-x >`, `PageUp`, `PageDown`, `C-PageUp`, `C-PageDown` |
| Deleting and killing | `C-d` `Delete` `Backspace` `C-k` `M-d` `M-Backspace` `C-Delete` `C-Backspace` `M-k` `M-z` `C-x Backspace` `C-S-Backspace` |
| Mark and selection | `C-SPC` `M-@` `M-h` `C-x h` `C-x C-x` `C-g` `C-w` `M-w` `S-Delete` `C-Insert`, selecting with Shift |
| Kill ring and yanking | `C-y` `M-y` `C-M-w` `S-Insert` |
| Transposing | `C-t` `M-t` `C-x C-t` |
| Case | `M-u` `M-l` `M-c` `C-x C-u` `C-x C-l` |
| Blanks and lines | `M-\` `M-SPC` `M-^` `C-M-o` `C-x C-o` |
| Filling | `M-q` `C-x f` `C-x .` |
| Undo and redo | `C-/` `C-_` `C-x u` `C-?` `C-M-_` |

**Delegated to Neovim**: what Neovim already does. The mode implements none of these operations and gives their Emacs keys no new meaning: `C-s` / `C-r` run Vim's search, `C-o`, `C-j` and the other keys of Insert mode keep their Insert mode meaning, and `C-x` followed by a key the mode does not use is dropped.

| Category | Examples |
|---|---|
| Files and buffers | `C-x C-f` `C-x b` `C-x C-s` |
| Windows and frames | `C-x 2` `C-x 3` `C-x o` `C-M-v` |
| Search and replace | `C-s` `C-r` (Vim's `/` and `?`), `C-M-s` `C-M-r` `M-%` |
| Editing by syntax | `C-M-f` `C-M-b` `C-M-k` `C-M-t` `C-M-@` `C-M-h` (Neovim and Treesitter) |
| Indentation by language | `M-i` `C-M-\` `C-x TAB` |
| Macros and registers | `C-x (` `C-x )`, register commands |
| Special newlines | `C-o` (the Insert mode one, as `i_CTRL-O`), `C-j` |
| Commands, help and completion | `M-x` `C-h` `M-/` |
| Undo history | undo itself, which Neovim's history does |

**Unsupported**: these Emacs operations are left out on purpose. A key of Emacs that the mode uses for something else is listed under the intentional differences.

| Category | Examples |
|---|---|
| Rectangles | `C-x SPC`, `C-x r` |
| Numeric arguments and repetition | `C-u`, `M-0` ... `M-9`, `M--`, `C-x z` |
| Mark ring and position history | `C-u C-SPC`, `C-x C-SPC` |
| Pages | `C-x [` `C-x ]` `C-x C-p` |
| Selective undo | undo of a region |
| Auto Fill mode | |
| Input methods | switching the input source, text being composed |

**Intentional differences**: what is chosen to differ from Emacs.

- `C-u` kills to the start of the line; it is not the numeric argument. `C-w` kills the word before the cursor when
  no selection is on. `C-o` stays the Insert mode one.
- The kill ring, the mark and the selection are the mode's own: no register and no clipboard is read or written.
- Typing does not replace the selection (Emacs' default without delete-selection-mode), and ends it.
- `C-x C-n` is released by pressing it again at the goal column, since `C-u` is not an argument. The goal column
  is for `C-n`, `C-p`, `Down`, `Up` and the page scrolls (`C-v`, `M-v`, `PageDown`, `PageUp`); a page scroll
  with a goal column set is not animated by neoscroll, which scrolls later from a timer.
- `C-x f` asks for the width with the cursor column as the default, and the width and the fill prefix belong
  to the buffer; `'textwidth'` is used when none was set. Filling never adds a second space after a sentence.
- The mark does not move to where `M-<`, `M->` or `M-g g` came from, and there is no mark ring.
- `M-g g`, `M-g c`, `M-g TAB` and `M-r` end a selection that Shift started, like the other moves; Emacs keeps it.
- `M-y` without a yank before it uses `vim.ui.select()`, and an interface that answers later inserts the kill
  only if the buffer did not change.
- `M-^` joins CJK text with no space, as filling does. `C-x C-t` on the last line adds no empty line.
- Sideways scrolling turns `'wrap'` off while text is scrolled; the cursor moves into view rather than freezing
  at the edge. Emacs asks for confirmation before it runs `C-x <`, `C-x C-n`; the mode does not.
- Case conversion follows Vim's `toupper()` and `tolower()`, which map each character to one character: `ß` becomes `ẞ`, not `SS`.

## How it differs from plain Insert mode

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
  work, except the keys named above. For blink.cmp this calls blink.cmp internals, so check the mode after
  updating blink.cmp.
- `C-v` / `C-l` follow Vim's `<C-f>` / `zz` without neoscroll; `M-r` follows `H` / `M` / `L`
  (inside `'scrolloff'`).

## Not included

- Saving the kill ring across sessions.
- Everything listed as unsupported above.

## Tests

```sh
make test          # needs nvim on PATH
make check-format  # needs stylua
```

The tests feed keys through the real mappings and check the text, the cursor, the mark, the selection, the kill
ring, the mode and the mappings put back; one case runs a second Neovim to wait between keys. Run inside a
configuration with blink.cmp or neoscroll loaded, with `dofile("tests/emacs_spec.lua")()`, they also check the mode
together with those.

Terminal and input method behavior is not covered: check by hand that the keys of the table above reach Neovim,
that `Esc` followed by a key is not taken for `M-` that key, and that `C-SPC` is not used by the OS.

## License

MIT
