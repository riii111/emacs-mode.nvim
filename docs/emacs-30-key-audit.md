# Emacs 30 key audit

The keys of the ten supported categories, checked against GNU Emacs 30.2, with what the mode does for each.
Statuses are *supported*, *unsupported*, *delegated to Neovim* and *intentional difference*.

Sources, all at the tag `emacs-30.2`:

- `bindings.el`: [lisp/bindings.el](https://github.com/emacs-mirror/emacs/blob/emacs-30.2/lisp/bindings.el)
- `simple.el`: [lisp/simple.el](https://github.com/emacs-mirror/emacs/blob/emacs-30.2/lisp/simple.el)
- `fill.el`: [lisp/textmodes/fill.el](https://github.com/emacs-mirror/emacs/blob/emacs-30.2/lisp/textmodes/fill.el)
- `paragraphs.el`: [lisp/textmodes/paragraphs.el](https://github.com/emacs-mirror/emacs/blob/emacs-30.2/lisp/textmodes/paragraphs.el)
- `casefiddle.c`: [src/casefiddle.c](https://github.com/emacs-mirror/emacs/blob/emacs-30.2/src/casefiddle.c)
- The GNU Emacs manual: [Moving Point](https://www.gnu.org/software/emacs/manual/html_node/emacs/Moving-Point.html),
  [Scrolling](https://www.gnu.org/software/emacs/manual/html_node/emacs/Scrolling.html),
  [Horizontal Scrolling](https://www.gnu.org/software/emacs/manual/html_node/emacs/Horizontal-Scrolling.html),
  [Killing](https://www.gnu.org/software/emacs/manual/html_node/emacs/Killing.html),
  [Yanking](https://www.gnu.org/software/emacs/manual/html_node/emacs/Yanking.html),
  [Setting the Mark](https://www.gnu.org/software/emacs/manual/html_node/emacs/Setting-Mark.html),
  [Shift Selection](https://www.gnu.org/software/emacs/manual/html_node/emacs/Shift-Selection.html),
  [Transposing](https://www.gnu.org/software/emacs/manual/html_node/emacs/Transposition.html),
  [Case](https://www.gnu.org/software/emacs/manual/html_node/emacs/Case.html),
  [Blank Lines](https://www.gnu.org/software/emacs/manual/html_node/emacs/Blank-Lines.html),
  [Filling](https://www.gnu.org/software/emacs/manual/html_node/emacs/Fill-Commands.html),
  [Undo](https://www.gnu.org/software/emacs/manual/html_node/emacs/Undo.html)

The default keys of the basic commands (`C-f`, `C-b`, `C-v`, `M-v`, `C-l`, `M-r`, `M-u`, `M-l`, `M-c`, `C-x <`,
`C-x C-u`, `C-x C-l`) are not in `bindings.el` of 30.2; they are taken from the manual and the functions' own
documentation. The Emacs installed locally while this was written is 31.1 and is no evidence for 30.

Line numbers below are those of the files above. "Here" is the key or behavior of the mode; every key can be
changed or added with `aliases` (see `:help emacs-mode-commands`).

## 1. Moving and positions

| Emacs key | Command | Status | Here | Source |
|---|---|---|---|---|
| `C-f` `C-b` `<right>` `<left>` | `forward-char` `backward-char` | supported | `C-f` `C-b` `Right` `Left`, `kRight` `kLeft` | `bindings.el` L1289-1291, L1411-1429 (keypad) |
| `C-n` `C-p` `<down>` `<up>` | `next-line` `previous-line` | supported | screen lines, as `gj` `gk` | `bindings.el` L1220-1221, L1290-1292 |
| `C-a` `C-e` `<home>` `<end>` | `move-beginning-of-line` `move-end-of-line` | supported | `C-a` `C-e` `Home` `End` | `bindings.el` L1223-1224, L1285, L1305 |
| `M-f` `M-b` `C-<right>` `C-<left>` `M-<right>` `M-<left>` | `forward-word` `backward-word` | supported | all six keys | `bindings.el` L1487-1488, L1502-1508 |
| `M-<` `M->` `C-<home>` `C-<end>` `<begin>` | `beginning-of-buffer` `end-of-buffer` | supported | the four keys and `kOrigin` | `bindings.el` L1286, L1306, L1309, L1492-1493 |
| `M-{` `M-}` `C-<up>` `C-<down>` | `backward-paragraph` `forward-paragraph` | supported | all four keys | `bindings.el` L1295-1296, L1583-1584 |
| `M-a` `M-e` | `backward-sentence` `forward-sentence` | supported | `M-a` `M-e` | `bindings.el` L1586-1587 |
| `M-m` | `back-to-indentation` | supported | `M-m`, blanks are space, tab and U+3000 | `bindings.el` L1110, `simple.el` L1075 |
| `M-g g` `M-g M-g` | `goto-line` | supported | asks for a line; empty or `Esc` cancels | `bindings.el` L1239-1240, `simple.el` L1609 |
| `M-g c` | `goto-char` | supported | asks for a character position | `bindings.el` L1238 |
| `M-g TAB` | `move-to-column` | supported | asks for a column; within a character, after it | `bindings.el` L1245 |
| `C-x C-n` | `set-goal-column` | supported, released by pressing it again at the column | goal column for `C-n` `C-p` and the page scrolls | `bindings.el` L1222, `simple.el` L8420 |
| `M-g n` `M-g p` `M-g i` `` C-x ` `` | `next-error` `imenu` | delegated | no key | `bindings.el` L1226, L1241-1246 |
| `<M-home>` `<M-end>` | `beginning-of-buffer-other-window` | delegated (windows) | no key | `bindings.el` L1287-1311 |
| `C-M-<left>` `C-M-<right>` `C-M-<up>` `C-M-<down>` `C-M-<home>` | `backward-sexp`, `down-list`, ... | delegated (syntax) | no key | `bindings.el` L1515-1524 |

## 2. Scrolling

| Emacs key | Command | Status | Here | Source |
|---|---|---|---|---|
| `C-v` `<next>` `<kp-next>` | `scroll-up-command` | supported | `C-v` `PageDown` `kPageDown` | `bindings.el` L1294; manual *Scrolling* |
| `M-v` `<prior>` `<kp-prior>` | `scroll-down-command` | supported | `M-v` `PageUp` `kPageUp` | `bindings.el` L1293; manual *Scrolling* |
| `C-l` | `recenter-top-bottom` | supported | middle, top, bottom in turn | manual *Recentering* |
| `M-r` | `move-to-window-line-top-bottom` | supported | middle, top, bottom line in turn | manual *Moving Point* |
| `C-x <` `C-<next>` | `scroll-left` | supported | `C-x <` `C-PageDown`; text moves left by width - 2 | `bindings.el` L1298-1299; manual *Horizontal Scrolling* |
| `C-x >` `C-<prior>` | `scroll-right` | supported | `C-x >` `C-PageUp` | `bindings.el` L1297; manual *Horizontal Scrolling* |
| `C-M-v` `M-<next>` `M-<prior>` | `scroll-other-window` | delegated (windows) | no key | `bindings.el` L1300-1304 |

The manual says that text scrolled horizontally is truncated, not continued. With `'wrap'` on, `C-x <` turns it off
in the window until the text is back at the left or the mode ends.

## 3. Deleting and killing

| Emacs key | Command | Status | Here | Source |
|---|---|---|---|---|
| `C-d` | `delete-char` | supported; ignores a selection, as in Emacs | `C-d` | `bindings.el` L1196-1201 |
| `DEL` (`<backspace>`) | `delete-backward-char` | supported; a selection is deleted, not killed | `Backspace` `C-h` | `bindings.el` L1195, `simple.el` L1438 |
| `<deletechar>`, the Delete key under `normal-erase-is-backspace-mode` | `delete-forward-char` | supported; a selection is deleted | `Delete` `kDel` | `bindings.el` L1337, `simple.el` L1480, L10785 |
| `C-k` | `kill-line` | supported | `C-k` | `bindings.el` L1203 |
| `C-S-<backspace>` | `kill-whole-line` | supported; needs a terminal that tells it from Backspace | `C-S-Backspace` | `bindings.el` L1284, `simple.el` L6693 |
| `M-d` `C-<delete>` | `kill-word` | supported | both | `bindings.el` L1489, L1510 |
| `M-DEL` `C-<backspace>` | `backward-kill-word` | supported | both | `bindings.el` L1490, L1511 |
| `M-k` | `kill-sentence` | supported | `M-k` | `bindings.el` L1588 |
| `C-x DEL` | `backward-kill-sentence` | supported | `C-x Backspace`, `C-x C-h` | `bindings.el` L1589, `paragraphs.el` L585 |
| `M-z` | `zap-to-char` | supported | `M-z` | `bindings.el` L1113 |
| `<deleteline>` `<insertline>` | `kill-line` `open-line` | not mapped: keys of old Sun keyboards | none | `bindings.el` L1335-1336 |
| `C-u` | `universal-argument` | unsupported; **intentional difference**: kills to the start of the line | `C-u` | `bindings.el` L1175 |

Deleting never goes to the kill ring (`delete-active-region` is `t` in Emacs, and the command deletes). A kill
joins the previous one when it comes right after it, and after `C-M-w`.

## 4. Mark and selection

| Emacs key | Command | Status | Here | Source |
|---|---|---|---|---|
| `C-SPC` `C-@` | `set-mark-command` | supported; again right after, it toggles the selection | `set_mark` keys | `bindings.el` L1210-1212, `simple.el` L7325 |
| `M-@` | `mark-word` | supported; again, or with a selection, one more word | `M-@` | `bindings.el` L1486, `simple.el` L8814 |
| `M-h` | `mark-paragraph` | supported; again, or with a selection, the next paragraph | `M-h` | `bindings.el` L1585, `paragraphs.el` L382 |
| `C-x h` | `mark-whole-buffer` | supported; cursor at the start, mark at the end | `C-x h` | `bindings.el` L1494, `simple.el` L1543 |
| `C-x C-x` | `exchange-point-and-mark` | supported; works with an inactive mark and brings the selection back | `C-x C-x` | `bindings.el` L1215, `simple.el` L7429 |
| `C-g` | `keyboard-quit` | supported; drops the selection, the mark stays | `C-g` | `bindings.el` L1098 |
| `C-w` | `kill-region` | supported; **intentional difference**: kills the word before when no selection is on | `C-w` `S-Delete` | `bindings.el` L1204, L1513, `simple.el` L5821 |
| `M-w` | `kill-ring-save` | supported | `M-w` `C-Insert` | `bindings.el` L1205, L1316 |
| `S-<arrow>` `S-<home>` `S-<end>` `S-<prior>` `S-<next>`, with `C-` or `M-` | shift selection | supported for the keys the mode maps (see `keys.lua`) | `S-` of Right Left Down Up Home End PageDown PageUp; `C-S-` of Right Left Up Down Home End; `M-S-` of Right Left | `simple.el` L7451-7504 |
| `C-x C-SPC` `C-u C-SPC` | `pop-global-mark`, `pop-to-mark-command` | unsupported (mark ring) | no key | `bindings.el` L1216-1218 |
| `C-x SPC` | `rectangle-mark-mode` | unsupported (rectangles) | no key | `bindings.el` L1217 |

Behaviors checked in `simple.el`: a shifted move starts a selection unless a selection of Shift is on already (L7493-7499);
an unshifted move ends only a selection that Shift started (L7500-7504); `use-region-p` is false for an empty
selection, so `Backspace` then deletes a character. The mark is kept when the selection is dropped, as
`mark-even-if-inactive` is `t`; `C-w` and `M-w` still act on an active selection only, as in the existing mode.

## 5. Kill ring and yanking

| Emacs key | Command | Status | Here | Source |
|---|---|---|---|---|
| `C-y` `S-<insert>` | `yank` | supported; sets an inactive mark at the start | `C-y` `S-Insert` | `bindings.el` L1207, L1317, `simple.el` L6278 |
| `M-y` after a yank | `yank-pop` | supported | replaces with the next older kill | `bindings.el` L1208, `simple.el` L6230 |
| `M-y` alone | `yank-from-kill-ring` | supported; asks with `vim.ui.select()` | list of the 60 kills | `simple.el` L6501 |
| `C-M-w` | `append-next-kill` | supported; for the next command only | `C-M-w` | `bindings.el` L1206, `simple.el` L6020 |
| `C-<insert>` | `kill-ring-save` | supported | `C-Insert` | `bindings.el` L1316 |

A region kill goes in front of the previous kill when the cursor is before the mark (`kill-region` passes
`(< end beg)` with the mark first, `simple.el` L5865); other kills are in front when they go backward.
`yank-from-kill-ring` moves the yank pointer to the chosen kill and sets the mark, and the next `M-y` asks again
because the last command is not `yank` (L6527-6531).

## 6. Transposing

| Emacs key | Command | Status | Here | Source |
|---|---|---|---|---|
| `C-t` | `transpose-chars` | supported; a line break is a character, as in Emacs | `C-t` | `bindings.el` L1473, `simple.el` L8639 |
| `M-t` | `transpose-words` | supported | `M-t` | `bindings.el` L1474 |
| `C-x C-t` | `transpose-lines` | supported; on the first line, with the next | `C-x C-t` | `bindings.el` L1476, `simple.el` L8716 |
| `C-M-t` | `transpose-sexps` | delegated (syntax) | no key | `bindings.el` L1475 |

## 7. Case

| Emacs key | Command | Status | Here | Source |
|---|---|---|---|---|
| `M-u` `M-l` `M-c` | `upcase-word` `downcase-word` `capitalize-word` | supported | the same | manual *Case*; `casefiddle.c` L662 |
| `C-x C-u` | `upcase-region` | supported; the mark is used when the selection was dropped, no mark does nothing | `C-x C-u` | `casefiddle.c` L600 |
| `C-x C-l` | `downcase-region` | supported | `C-x C-l` | `casefiddle.c` L612 |

`upcase-region` takes `(region-beginning)` and `(region-end)`, which need a mark but not an active one.

## 8. Blanks, joining and blank lines

| Emacs key | Command | Status | Here | Source |
|---|---|---|---|---|
| `M-\` | `delete-horizontal-space` | supported | `M-\` | `bindings.el` L1109, `simple.el` L1095 |
| `M-SPC` | `cycle-spacing` | supported; one space, none, the original blanks | `M-SPC` | `bindings.el` L1112, `simple.el` L1152-1346 |
| `M-^` | `delete-indentation` | supported; a selection joins its lines | `M-^` | `bindings.el` L1108, `simple.el` L753 |
| `C-M-o` | `split-line` | supported; the rest keeps its display column | `C-M-o` | `bindings.el` L1106, `simple.el` L702 |
| `C-x C-o` | `delete-blank-lines` | supported | `C-x C-o` | `bindings.el` L1111, `simple.el` L793 |
| `C-o` `C-j` | `open-line`, newline with indentation | delegated (Insert mode keeps them) | unchanged | `bindings.el` L1105 |

## 9. Filling

| Emacs key | Command | Status | Here | Source |
|---|---|---|---|---|
| `M-q` | `fill-paragraph` | supported; with a selection, its paragraphs | `M-q` | `bindings.el` L1580, `fill.el` L824 |
| `C-x f` | `set-fill-column` | supported; asks, the cursor column is the default | `C-x f` | `bindings.el` L1483, `simple.el` L9094 |
| `C-x .` | `set-fill-prefix` | supported; at the start of a line it cancels | `C-x .` | `bindings.el` L1581, `fill.el` L81 |
| `M-j` `C-M-j` | `default-indent-new-line` | delegated (special newline) | no key | `bindings.el` L1479-1480 |
| auto-fill | `auto-fill-mode` | unsupported | none | |

Lines are joined as `fill-delete-newlines` does with the default `fill-separate-heterogeneous-words-with-space`:
no space where a line break stands next to a CJK character (`fill.el` L505-527). Lines are broken between CJK
characters with kinsoku (`fill.el` L420-436). The double space after a sentence of `sentence-end-double-space`
is kept where it was and never added.

## 10. Undo and redo

| Emacs key | Command | Status | Here | Source |
|---|---|---|---|---|
| `C-/` `C-_` | `undo` | supported | the same | `bindings.el` L1126-1127 |
| `C-x u` | `undo` | supported | `C-x u` | `bindings.el` L1123 |
| `C-?` `C-M-_` | `undo-redo` | supported; see the table of terminals below | `redo` | `bindings.el` L1136-1137, `simple.el` L3567 |
| `C-x r`... | selective undo | unsupported | none | |

## Excluded categories

| Category | Status | Keys that are not given a meaning |
|---|---|---|
| Files and buffers | delegated | `C-x C-f` `C-x b` `C-x C-s` |
| Windows and frames | delegated | `C-x 2` `C-x 3` `C-x o` `C-M-v` |
| Search and replace | delegated | `C-s` `C-r` run Vim's `/` `?`; `C-M-s` `C-M-r` `M-%` |
| Editing by syntax | delegated | `C-M-f` `C-M-b` `C-M-k` `C-M-t` `C-M-@` `C-M-h` |
| Indentation by language | delegated | `M-i` `C-M-\` `C-x TAB` |
| Macros and registers | delegated | `C-x (` `C-x )` |
| Special newlines | delegated | `C-o` `C-j` |
| Commands, help and completion | delegated | `M-x` `C-h` `M-/` |
| Undo history | delegated | Neovim's own |
| Rectangles | unsupported | `C-x SPC` `C-x r` |
| Numeric arguments | unsupported | `C-u` `M-0` ... `M-9` `M--` `C-x z` |
| Mark ring | unsupported | `C-u C-SPC` `C-x C-SPC` |
| Pages | unsupported | `C-x [` `C-x ]` `C-x C-p` |
| Auto Fill mode | unsupported | |
| Input methods | unsupported | |

## Terminals

What each way of sending a key does in the mode. "Neovim reads it as" was checked by sending the bytes to
Neovim's terminal UI in a pseudo-terminal; which terminal sends which bytes was not.

| Key | Bytes | Neovim reads it as | Action |
|---|---|---|---|
| Backspace | `7f` | `<BS>` | delete backward |
| `C-h` | `08` | `<C-H>` | delete backward |
| `C-?` (protocol) | `CSI 63;5u` | `<C-?>`, which is not `<BS>` | redo |
| `C-S-/` (protocol) | `CSI 47;6u` | `<C-S-/>` | redo |
| `C-M-S--` (protocol) | `CSI 45;8u` | `<M-C-S-->` | redo |
| `C-S-Backspace` (protocol) | `CSI 127;6u` | `<C-S-BS>` | kill the line |
| `C-Backspace` (protocol) | `CSI 127;5u` | `<C-BS>` | kill the word before |
| `C-Delete` `S-Delete` `C-Insert` `S-Insert` | `CSI 3;5~` `3;2~` `2;5~` `2;2~` | `<C-Del>` `<S-Del>` `<C-Insert>` `<S-Insert>` | as in Emacs |
| `C-S-Left` `S-Left` `C-Up` `C-Home` `C-S-End` | `CSI 1;6D` `1;2D` `1;5A` `1;5H` `1;6F` | the same names | moves and selection |
| `C-PageUp` `C-PageDown` `S-PageUp` | `CSI 5;5~` `6;5~` `5;2~` | the same names | sideways scroll, selection |
| `M-@` `M-^` (protocol, US layout) | `CSI 50;4u` `54;4u` | `<M-S-2>` `<M-S-6>` | mark word, join lines |
| `Alt+key` without the protocol | `Esc` and the key | `<M-key>`, or `<Esc>` and the key when they arrive apart | timing of the terminal decides |

A terminal without the protocol sends `C-?`, `C-S-Backspace` and Backspace as the same byte, so they are the same key
here. A key that cannot be told apart gets one action only, and `aliases` gives a command another key.

## Verification

| What | How | Result |
|---|---|---|
| Behavior of the keys, through the real mappings | `make test` (headless Neovim 0.12, no plugin), run in CI | passes |
| Coexistence with blink.cmp, neoscroll.nvim and nvim-autopairs | the same spec with the three loaded, from a configuration of lazy.nvim | passes |
| Waiting for the second key of `C-x` and `M-g` | a second Neovim started by the spec, with a wait beyond `'timeoutlen'` between keys | passes |
| How Neovim reads terminal sequences | bytes written to Neovim's terminal UI in a pseudo-terminal | the table above |
| Real terminal emulators, physical keyboards, the OS taking keys, input methods | not checked | unverified |
