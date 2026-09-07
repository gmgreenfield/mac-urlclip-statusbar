# URL Clipboard Tracker

A native macOS status bar app that watches the clipboard for URLs and saves them locally.

## Run From Source

```sh
swift run UrlClipStatusBar
```

## Build The App

```sh
chmod +x Scripts/build-app.sh
Scripts/build-app.sh
```

The app bundle is created at:

```text
build/URL Clipboard Tracker.app
```

Open it with:

```sh
open "build/URL Clipboard Tracker.app"
```

## Data

The SQLite database is stored at:

```text
~/Library/Application Support/urlclip-statusbar/links.sqlite3
```

The app only reads clipboard text while it is running. It deduplicates copied URLs by a normalized URL and increments `copy_count` when a URL is copied again.
