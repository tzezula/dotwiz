# DotWiz

A small native macOS viewer for Graphviz `.dot` / `.gv` files. It renders the graph and
re-renders it automatically whenever the file changes on disk, so you can keep it open
next to your editor.

## Requirements

- macOS 13+
- Graphviz: `brew install graphviz`

DotWiz looks for `dot` in `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`,
`/usr/bin`, then asks your login shell. To use a different binary:

```bash
defaults write com.tzezula.dotwiz DotPath /path/to/dot
```

## Build

```bash
./build-app.sh            # produces build/DotWiz.app
./build-app.sh --install  # also copies it to /Applications
```

Then open a file with `open -a DotWiz graph.dot`, File ▸ Open…, or Finder's *Open With*.

## Features

- Vector rendering (`dot -Tpdf` shown in PDFKit), so it stays sharp at any zoom.
- Live reload: works with in-place writes, atomic saves (rename over the original) and
  vim-style backup renames. Zoom and scroll position are kept across reloads.
- Syntax errors and warnings appear in a bar under the graph; the last good rendering
  stays visible until the file is fixed.
- View ▸ Layout Engine: Automatic (honours the graph's `layout` attribute), dot, neato,
  fdp, sfdp, circo, twopi, osage, patchwork.
- File ▸ Export ▸ PNG / JPEG / PDF / SVG (⇧⌘E for PNG). Bitmap exports offer
  96, 192 (2×) or 300 dpi.
- File ▸ Print… (⌘P) prints the graph as shown, scaled to fit the page and rotated to
  match its orientation; Page Setup… (⇧⌘P) picks paper size.
- Multiple windows/tabs, Open Recent, ⌘R to force a reload.

## Debugging

Render and file-change events are logged:

```bash
log stream --level info --predicate 'subsystem == "com.tzezula.dotwiz"'
```
