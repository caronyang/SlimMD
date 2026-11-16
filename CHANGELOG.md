# Changelog

All notable changes to SlimMD.

## Unreleased

### Scroll synchronisation
- The editor and the preview now follow each other's scroll position in
  both directions: scrolling the editor moves the preview, and scrolling
  the preview (or re-showing the editor after browsing) moves the editor,
  so the rendered result of what you are editing is always in view.

### Multiple documents
- Multiple Markdown files can be open at once — each gets its own tab
  above the preview (the tab strip stays hidden while only one document
  is open).
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

### Verification
- New tests: 11 multi-tab/close-prompt checks (`tools\tabs-test.ps1`),
  4 scroll-sync checks (`tools\scroll-test.ps1`).

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
