# Clipboard Pattern Tracker

A native macOS status bar app that watches the clipboard for URLs and other configured regex matches, then saves them locally.

## Features

- Watches clipboard text while the app is running.
- Captures one or more matching values from each copied text value.
- Includes predefined patterns for URLs, email addresses, US phone numbers, UUIDs, IPv4 addresses, hex colors, and Git SHAs.
- Supports custom regex patterns from the status bar menu.
- Deduplicates repeated values and increments their copy count.
- Opens captured URLs from the menu and copies non-URL values back to the clipboard.

## Pattern Matching

Open the status bar menu and use the Patterns submenu to manage capture behavior.

Predefined patterns can be enabled or disabled individually:

- URLs
- Email Addresses
- US Phone Numbers
- UUIDs
- IPv4 Addresses
- Hex Colors
- Git SHAs

Custom regexes can be added with Patterns > Add Custom Regex. Each custom pattern has a display name and a regex pattern. If the regex contains capture groups, the app saves the first matched capture group. If it has no capture groups, the app saves the full match.

For example, this custom regex captures the numeric portion of ticket IDs like `APP-1234`:

```regex
\b[A-Z]+-(\d+)\b
```

Copied text:

```text
Fix APP-1234 before release.
```

Captured value:

```text
1234
```

Invalid custom regexes are rejected and shown as an error in the status bar menu.

## Using Captured Items

The status bar menu shows recent captured items with repeat counts when a value has been copied more than once.

Selecting a captured URL opens it in the default browser. Selecting any other captured value copies it back to the clipboard.

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

The app only reads clipboard text while it is running. It deduplicates copied URLs by a normalized URL and other copied values case-insensitively, then increments `copy_count` when a value is copied again.
