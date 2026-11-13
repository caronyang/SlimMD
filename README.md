# SlimMD

[English](README.md) | [繁體中文](README.zh-Hant.md)

A lightweight Markdown editor and viewer for Windows — built with .NET 9 WinForms
and WebView2, so it stays fast and light on CPU and memory (no Electron).

![SlimMD browse view](art/readme_browse_en.png)

## Features

- **Browse view by default** — clean rendered preview, distraction free.
- **Edit** — click the toolbar button (or press `Ctrl+E` / `F9`) to switch to a
  split view with the raw Markdown source on the left and the live preview on
  the right. Click **Hide Editor** to go back.

  ![SlimMD split view](art/readme_split_en.png)

- **Open / New / Save / Save As** — `Ctrl+O`, `Ctrl+N`, `Ctrl+S`, `Ctrl+Shift+S`.
  All shortcuts work in both browse and edit view. Drag & drop a `.md` file
  onto the window to open it. Files can also be passed on the command line:
  `SlimMD.exe notes.md`.
- **Encoding done right** — UTF-8 (with or without BOM) is detected
  automatically, with fallback to the system ANSI code page (Big5 / GBK /
  Windows-1252 …). The file's original line-ending style (CRLF / LF) and
  encoding are preserved on save.
- **English / 中文 interface** — switch any time from the **Language** toolbar
  menu; the choice is remembered.

  ![SlimMD 中文介面](art/readme_browse_zh.png)

- **Export** — the **Export** toolbar menu writes the document out as
  **PDF** (A4, print stylesheet, backgrounds kept, no header/footer) or as a
  self-contained **HTML** file (styles inlined, relative image/link paths
  rewritten so the page works from wherever you save it).
- **About dialog** — logo, version, feature list, repository and license links.

  ![About SlimMD](art/readme_about_en.png)

- **Light & dark themes** that follow the system setting.
- **Markdown support**: headings, paragraphs, emphasis, links, images, lists
  (ordered / task lists), blockquotes, fenced code blocks (with language
  label), tables, horizontal rules, inline code, strikethrough, HTML
  front-matter block, and raw HTML (sanitized whitelist).
- **Links open in your browser**, not inside the app.
- **Self-contained** — no .NET runtime installation needed.

## Requirements

- Windows 10 1809+ / Windows 11 (x64)
- Microsoft Edge WebView2 Runtime (preinstalled on Windows 11; the installer
  detects it and links to the download if missing)

## Install

Run `dist\SlimMD-1.0.0-Setup.exe` — a per-user install (no admin rights
required), to `%LOCALAPPDATA%\Programs\SlimMD`.

Optional tasks in the installer: desktop shortcut, `.md` file association.

To uninstall: *Settings → Apps → SlimMD*, or `unins000.exe` in the install
folder.

### Silent install

```
SlimMD-1.0.0-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

## Build from source

Prerequisites: .NET 9 SDK, Inno Setup 6, (optional) Node.js for renderer
tests, (optional) Python + Pillow to regenerate the logo.

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

This runs: icon generation → build → renderer tests → self-contained publish →
installer compile. Output lands in `dist\SlimMD-<version>-Setup.exe`.

Useful flags: `-SkipIcon`, `-SkipTests`, `-SkipInstaller`.

## Tests

| Command | What it covers |
|---|---|
| `node tests\render.test.js` | Markdown renderer — 58 unit tests |
| `powershell -File tools\e2e.ps1` | UI end-to-end — 34 checks (browse/split toggle, shortcuts from both views, selection, export menu, About dialog, EN/ZH switch, settings persistence) |
| `powershell -File tools\export-test.ps1` | Export flow (menu → Save dialog → PDF/HTML on disk) — 17 checks |
| `powershell -File tools\installer-test.ps1` | Shipped installer: silent install → run → Export menu → uninstall — 6 checks |

## Project layout

```
SlimMD.sln
src\SlimMD\            WinForms app
  MainForm.cs          toolbar, split view, file I/O, PDF/HTML export, settings
  AboutDialog.cs       About dialog
  AppInfo.cs           repository / license / copyright constants
  Strings.cs           EN/ZH UI strings
  MsgDialog.cs         localized dialogs
  AppSettings.cs       persisted settings (%LOCALAPPDATA%\SlimMD\settings.json)
  assets\              preview.html / preview.css / preview.js (renderer)
  SlimMD.ico           program logo
tests\render.test.js   renderer unit tests
tools\                 logo generator, E2E/export/installer test scripts, helpers
installer\SlimMD.iss    Inno Setup script
build.ps1              full build pipeline
```

## Debugging

Set `SLIMMD_DEBUG=1` in the environment before launching to append logs to
`%LOCALAPPDATA%\SlimMD\debug.log`.

## License

[MIT](LICENSE) © 2026 Caron Yang.
