# Changelog

All notable changes to SlimMD.

## 1.0.3 — 2026-11-18

Faster startup and file opening, with a visible loading state.

### Performance
- The WebView2 browser process is started as soon as SlimMD launches and the
  preview page begins loading while the window is still being laid out, so the
  first document appears noticeably sooner.
- Opening a file no longer waits for the preview engine before reading it, and
  the preview is rendered immediately instead of after the 250 ms typing
  debounce. Opening a second document is now effectively instant.
- The status-bar line/column readout uses native caret lookups instead of
  scanning the whole document, so it stays smooth on large files.

### Loading indicator
- While a document is being read and rendered, the status bar shows
  `Loading <file>...` with an indeterminate progress bar, and the preview pane
  shows the same message centred instead of a blank white area. Both disappear
  as soon as the rendered document is on screen.
- The message follows the interface language (English / Traditional Chinese).

## 1.0.2 — 2026-11-16

Scroll synchronisation fix — both panes now reach the end of the document.

### Scroll synchronisation
- Reaching the end of the document now reaches the end of the preview. Block
  alignment alone left the preview short of the bottom (the last few blocks are
  shorter than the viewport), so both panes now snap to the very end, in both
  directions: scrolling the editor to its last line scrolls the preview to the
  bottom, and scrolling the preview to the bottom scrolls the editor to its
  last page.
- Positions inside a block are interpolated by source-line count instead of
  snapping to the block start, so mid-paragraph scrolling moves smoothly.
- The echo guard is now position-based (the host records the offset it scrolled
  to and ignores exactly that one scroll event) instead of a timed flag, which
  could swallow continuous wheel scrolling.

## 1.0.1 — 2026-11-16

Second release: user-feedback round, block-based scroll sync and toolbar icons.

### Interface
- Every toolbar item (New, Open, Save, Save As, Export, Edit, Language,
  About) now shows a small icon next to its label. The glyphs are drawn
  with GDI+ at runtime (`ToolbarIcons.cs`) and scaled to the system DPI,
  so no image assets are shipped and they stay crisp on high-DPI screens.
- All glyphs share the same 13x13 footprint inside the 16x16 grid so the
  row reads uniformly; Save As uses two overlapping floppies rather than
  a pencil overlay, which looked lopsided at 16px.

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
- `tools\tabs-test.ps1` now re-resolves the main-window handle through a
  live UIA check — `Start-Process -PassThru` can hand back a stale handle
  after the window is recreated during startup, which made every UIA
  lookup silently return nothing.

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
