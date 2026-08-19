# MDViewer

A featherweight native macOS markdown viewer. Double-click a `.md` file, read it, close it. Not an editor.

- Native Swift app (~300KB total), launches instantly
- GitHub-flavored rendering: tables, task lists, strikethrough, syntax-highlighted code
- Light/dark mode follows the system
- Auto-reloads when the file changes on disk (works with Vim-style save-via-rename)
- Relative links to other `.md` files open in a new viewer window; web links open in your browser
- Quits when the last window closes

## Build

```sh
./build.sh            # build into build/MDViewer.app
./build.sh install    # build and install to /Applications
```

Requires only the Xcode Command Line Tools (`swiftc`). No Xcode project, no SPM, no node.

## Make it the default for .md files

After installing, right-click any `.md` file → Get Info → Open with: MDViewer → **Change All…**

Or with [duti](https://github.com/moretension/duti):

```sh
duti -s com.tjcrone.mdviewer net.daringfireball.markdown all
```

## Keys

| Key | Action |
|-----|--------|
| ⌘O | Open file |
| ⌘W / ⌘Q | Close / quit |
| ⌘R | Re-render |
| ⌘+ / ⌘− / ⌘0 | Zoom |

## Layout

- `Sources/main.swift` — the entire app: window, file watching, menu
- `Resources/viewer.html` — rendering page and CSS
- `Resources/marked.min.js`, `highlight.min.js`, `atom-one-*.css` — vendored deps (marked v15, highlight.js v11)
- `Resources/zig.js` — hand-rolled Zig grammar (not in highlight.js's common build)
- `Info.plist` — declares the app as a viewer for markdown UTIs/extensions
