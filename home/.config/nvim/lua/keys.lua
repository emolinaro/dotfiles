-- save by pressing Escape
vim.keymap.set('n', '<Esc>', ':w<CR>', { desc = 'Save' })
-- select all
vim.keymap.set('n', '<C-a>', 'ggVG', { desc = 'Select All' })
-- pasting over a selection no longer clobbers your clipboard
vim.cmd([[ xnoremap <expr> p 'pgv"'.v:register.'y' ]])
-- CMD+C copies the visual selection (incl. mouse drags) to the system clipboard.
-- WezTerm forwards the key only when it has no selection of its own (see wezterm.lua);
-- nvim receives it via the kitty keyboard protocol. Paste needs no mapping:
-- WezTerm's CMD+V arrives as a bracketed paste that nvim handles in every mode.
vim.keymap.set('v', '<D-c>', '"+y', { desc = 'Copy selection to system clipboard' })

