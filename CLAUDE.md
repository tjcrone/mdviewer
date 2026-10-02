# MDViewer development notes

Lightweight native macOS markdown viewer. Not an editor — keep it that way.
See README.md for user-facing docs.

## Build & run

- `./build.sh` builds `build/MDViewer.app`; `./build.sh install` also copies to
  `/Applications` and runs `lsregister`. Finder double-click launches the
  `/Applications` copy, so changes are invisible until you run `install`.
- No Xcode project, no SPM, no node. Only `swiftc` (Command Line Tools).
  The whole app is `Sources/main.swift`.
- Ad-hoc codesign (`codesign --force --sign -`) is required on Apple Silicon.

## Architecture

- `main.swift`: AppDelegate (one window controller per open file, app quits on
  last window close) + DocumentWindowController (window, WKWebView, file
  watcher, menu actions via responder chain).
- Rendering happens in `Resources/viewer.html` inside the WKWebView:
  marked.js parses, highlight.js colors code, CSS in the same file.
  Swift passes the markdown text in via `renderMarkdown(text, baseHref)`
  (both arguments JSON-encoded strings).
- `viewer.html` is loaded once per window at creation. ⌘R only re-renders the
  markdown — CSS/JS changes need the window closed and reopened.
- The document's own directory is served to the webview over a custom `mdfile://` scheme (`LocalFileSchemeHandler`), and the base href points there, so relative images and links resolve. Swift reads the bytes itself, so WebKit's file-URL sandbox is not involved at all. `loadFileURL` now grants read access only to the app's own `Resources`, which is all the viewer page's own CSS/JS needs.
- Navigation policy: only viewer.html (+ fragments) loads in the webview. Links arrive as `mdfile://` and get mapped back to file URLs — `.md` opens a new viewer window, everything else goes to `NSWorkspace.shared.open` (browser, Finder, etc.).
- File watching uses a DispatchSource on an `O_EVTONLY` fd. On delete/rename it
  re-attaches after 200ms — this is what makes Vim-style save-via-rename work.

## Vendored dependencies (Resources/)

All fetched from jsdelivr, committed so builds are offline:

- `marked.min.js` — marked v15, GFM (tables, task lists, strikethrough)
- `highlight.min.js` — highlight.js v11 "common" build (~40 languages)
- `atom-one-light.min.css` / `atom-one-dark.min.css` — code themes, selected by
  `media="(prefers-color-scheme: ...)"` link attributes
- `zig.js` — hand-rolled Zig grammar; Zig is not in the common build

## Gotchas learned the hard way

- `allowingReadAccessTo:` does not grant access across a mount point, and the grant must be an ancestor of the page being loaded or WebKit refuses the load outright. So `URL(fileURLWithPath: "/")` does *not* mean "the whole filesystem": with the app on the system volume and documents on `/Volumes/Macintosh HD CS`, every relative image silently failed — `naturalWidth` 0, no error raised anywhere. This is why figures go through `mdfile://` instead. Established 2026-10-02 over a matrix of page locations and grants; the same page loading from the CS volume did resolve its images, which is how the bug stayed hidden.
- The `mdfile://` handler serves whole files synchronously and ignores Range requests, so `<video>`/`<audio>` seeking is not supported. Images, the case it exists for, are unaffected.
- highlight.js silently skips code fences tagged with an unknown language —
  no fallback to auto-detect. Untagged fences DO auto-detect. If a language
  renders all-black, it needs a grammar registered (see zig.js pattern).
- The GitHub highlight theme looks nearly monochrome (strings are #032f62,
  basically black). That's why we use the Atom One pair. Themes are drop-in
  single CSS files if a swap is ever wanted.
- In an NSWindowController subclass, bare `close(fd)` resolves to
  `NSWindowController.close` — use `Darwin.close(fd)`.
- `Info.plist` `CFBundleDocumentTypes` + `UTImportedTypeDeclarations` are what
  make double-click work. Default-handler status is user-set (Get Info →
  Change All, or `duti -s com.tjcrone.mdviewer net.daringfireball.markdown all`).
- `NSWorkspace.setDefaultApplication(at:toOpen:)` is async; a `swift -e` one-liner that doesn't wait for the completion handler exits before the change lands and reports nothing. README has a working version with a semaphore.

## Deliberate design decisions

- Content wraps at window width (no max-width column) — owner's preference.
- No editing features, no tabs, no preferences window. Resist scope creep.
- Markdown is rendered unsanitized (raw HTML in md executes) — acceptable for
  a local viewer of the owner's own files; don't point it at hostile input.
