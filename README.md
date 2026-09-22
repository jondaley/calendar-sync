# Calendar Sync

A macOS command-line tool that syncs events from your local Calendar app to Google Calendar.

## Quick Start

**Prerequisites:** macOS 10.15+, corporate calendar in Calendar app, Google account

**1. Set up OAuth credentials** at [Google Cloud Console](https://console.cloud.google.com/) (see [DOCS.md](DOCS.md) for full steps):
   - Create a project and enable Google Calendar API
   - Add the `calendar.calendarlist.readonly` and `calendar.app.created` scopes on the OAuth consent screen
   - Create OAuth 2.0 Desktop credentials
   - Copy Client ID and Client Secret

**2. Build & run** (see [BUILD.md](BUILD.md)):
```bash
./bin/calendar-sync.app/Contents/MacOS/calendar-sync
```

On first run, the app will ask you to select a local calendar and authenticate with Google.

## Usage

```bash
./bin/calendar-sync.app/Contents/MacOS/calendar-sync              # Start syncing (every 5 minutes)
./bin/calendar-sync.app/Contents/MacOS/calendar-sync --clear-all  # Delete synced events from Google Calendar
./bin/calendar-sync.app/Contents/MacOS/calendar-sync --help       # Show help
```

## Features

- One-way sync from macOS Calendar → Google Calendar
- Smart deduplication (no duplicates on re-runs)
- Updates and deletes reflected on Google
- Personal Google Calendar events are never touched
- Secure token storage in macOS Keychain, gated by Touch ID

## More Info

- [BUILD.md](BUILD.md) — Build instructions, finding the binary, troubleshooting builds
- [DOCS.md](DOCS.md) — How it works, customization, authentication details, troubleshooting

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See the [LICENSE](LICENSE) file for details.
