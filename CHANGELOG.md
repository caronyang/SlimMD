# Changelog

All notable changes to SlimMD.

## Unreleased

### Scroll synchronisation
- Scroll sync is now **block-based** instead of proportional: the renderer
  tags every root-level block with the source line it came from, and each
  pane scrolls the other to the *matching block*. Editing at `## 4.` shows
  section 4 in the preview even though the two panes never carry the same
  amount of content per screen (headings, code, quotes and tables all have
  different rendered heights).
- Works in both directions: scrolling the editor moves the preview, and
  scrolling the preview (or re-showing the editor after browsing) moves the
  editor.
- Removed the 350 ms echo guard — it swallowed legitimate continuous wheel
  events and let the editor fall several sections behind; the JavaScript
  `syncing` flag already suppresses our own scroll echo.

### Multiple documents
- Multiple Markdown files can be open at once — each gets its own tab
  above the preview (the tab strip stays hidden while only one document
  is open).
- Tab headers now have an **✕** close button (hover highlight, hand
  cursor); closing a dirty tab still prompts to save.
- There is still a single editor pane; switching tabs switches it to that
  document. Save / Save As / Export always act on the active tab.
- Open dialog supports multi-select, drag & drop opens every dropped
  file, and multiple files can be passed on the command line
  (`SlimMD.exe a.md b.md`). Opening a file that is already open switches
  to its tab instead of duplicating it.
- Unsaved tabs are marked with `*` in the tab title and window title.

### Unsaved-changes prompt
- Closing a tab or the window while any document has unsaved edits asks
  to save first (Yes / No / Cancel). Cancel keeps the tab/window open;
  No discards. Every dirty tab is prompted when closing the window.
- Fixed the prompt dialog layout: the message text was laid out
  underneath the button panel and painted invisible (only the buttons
  showed). The dialog now sizes itself to its content, so the question
  and the Yes / No / Cancel buttons are all visible.

### Verification
- New tests: 15 multi-tab/close-prompt/✕ checks (`tools\tabs-test.ps1`),
  4 scroll-sync checks (`tools\scroll-test.ps1`), 6 block-alignment checks
  (`tools\blocksync-test.ps1`).

## 1.0.0 — 2026-11-12

First release.

### Editor & viewer
- Browse-first: opens any `.md` file as a clean rendered preview.
- **Edit** toggles a split view (source left, live preview right);
  toolbar button, `Ctrl+E` or `F9`. **Hide Editor** switches back.
- Open / New / Save / Save As (`Ctrl+O`, `Ctrl+N`, `Ctrl+S`,
  `Ctrl+Shift+S`), drag & drop, and command-line file arguments.
- UTF-8 (with/without BOM) detection with ANSI code-page fallback
  (Big5 / GBK / Windows-1252 …); original encoding and line endings
  (CRLF/LF) are preserved on save.
- Markdown: headings, emphasis, links, images, ordered/unordered/task
  lists, blockquotes, fenced code blocks with language label, tables,
  horizontal rules, inline code, strikethrough, front matter, and
  sanitized raw HTML.
- Light and dark themes following the system setting; links open in
  the system browser.

### Export
- **PDF** (A4, print stylesheet, backgrounds kept, no header/footer).
- **HTML** — self-contained file with inlined styles and rewritten
  relative image/link paths.

### Interface
- English (default) and Traditional Chinese UI, switchable at any time
  and persisted.
- Localized dialogs (message boxes, file dialogs don't follow the OS
  language only).
- About dialog with logo, version, feature list, repository and
  license links.

### Packaging
- Program logo (window, taskbar, installer).
- Inno Setup installer: per-user install (no admin), optional desktop
  shortcut and `.md` file association, silent-install supported.
- Self-contained .NET 9 build — no runtime installation required.

### Verification
- 58 renderer unit tests, 34 UI end-to-end checks, 17 export checks,
  6 installer checks.

### Fixes
- Showing the editor no longer selects all of its text on first focus.
- Keyboard shortcuts (`Ctrl+N/O/S/E`, `Ctrl+Shift+S`, `F9`) now work while
  the preview has focus (browse view), not just in the editor.
