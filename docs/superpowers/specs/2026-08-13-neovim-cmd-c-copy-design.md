# Neovim Cmd+C System Clipboard Design

## Goal

Make Cmd+C copy a Neovim visual selection to the macOS system clipboard so it
can be pasted into any terminal pane or other application. Preserve Cmd+C as
the normal copy shortcut for WezTerm-owned selections outside Neovim.

## Behavior

- When WezTerm owns a text selection, Cmd+C copies that selection to the system
  clipboard.
- When WezTerm has no selection, it forwards Cmd+C to the foreground terminal
  application.
- In Neovim visual mode, Cmd+C yanks the visual selection into the `+` register.
- Cmd+V remains handled by WezTerm and pastes the system clipboard into the
  foreground terminal application.
- Cmd+C with no WezTerm selection outside Neovim is forwarded and otherwise
  left to the foreground application.

## Design

WezTerm is the dispatch layer because it sees Cmd+C before terminal
applications do and knows whether it currently owns a selection. Its Cmd+C
binding will inspect the active pane's selection. A non-empty selection uses
WezTerm's clipboard action. An empty selection sends the original Cmd+C key to
the pane.

Neovim is the application layer. A visual-mode `<D-c>` mapping yanks to the
system clipboard register. The existing `clipboard=unnamedplus` setting remains
unchanged, while the explicit `+` register makes this shortcut's intent clear.

This division keeps terminal-native copying independent of Neovim and avoids
changing Cmd+C behavior when WezTerm already has selected text.

## Error Handling

- Empty WezTerm selections are never written to the clipboard.
- Neovim receives Cmd+C only when WezTerm has nothing to copy itself.
- Clipboard-provider failures remain visible through Neovim's standard error
  reporting rather than being silently swallowed.

## Validation

- Parse the WezTerm configuration with the configured WezTerm CLI.
- Start Neovim headlessly with the repository configuration and assert that
  visual mode has a `<D-c>` mapping targeting the system clipboard register.
- Add a static regression check for both branches of the WezTerm dispatch:
  copy a non-empty terminal selection and forward Cmd+C for an empty selection.
- Run formatting, linting, and the repository-wide flake validation.
- Manually verify both user paths in WezTerm: a native terminal selection and a
  Neovim visual selection can each be pasted into another terminal pane.

## Scope

This change targets macOS Cmd+C in WezTerm and Neovim. It does not introduce a
new clipboard protocol, change Linux shortcuts, or alter tmux copy mode.
