# MDViewer

A featherweight native macOS markdown viewer. Double-click a `.md` file, read it, close it. Not an editor.

- Native Swift app (~300KB total), launches instantly
- GitHub-flavored rendering: tables, task lists, strikethrough, syntax-highlighted code
- Light/dark mode follows the system
- Auto-reloads when the file changes on disk (works with Vim-style save-via-rename)
- Embedded images render inline — `![caption](figures/plot.png)` — from anywhere on disk
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

Or without installing anything, via the `swift` interpreter that ships with the Command Line Tools:

```sh
cat > /tmp/setdefault.swift <<'EOF'
import AppKit
import UniformTypeIdentifiers
let sem = DispatchSemaphore(value: 0)
NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: "/Applications/MDViewer.app"), toOpen: UTType("net.daringfireball.markdown")!) { err in
    print(err.map { "error: \($0)" } ?? "ok")
    sem.signal()
}
_ = sem.wait(timeout: .now() + 10)
EOF
swift /tmp/setdefault.swift
```

The semaphore matters: `setDefaultApplication` completes asynchronously, and if the process exits first the change is silently dropped.

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
