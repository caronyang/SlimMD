# Changelog

All notable changes to SlimMD.

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
