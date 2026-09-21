# Calendar Sync

A macOS command-line tool that syncs events from your local Calendar app to Google Calendar. Perfect for keeping your personal Google Calendar in sync with your corporate calendar.

## Features

- **One-way sync** from local macOS Calendar to Google Calendar
- **Smart deduplication** - no duplicate events on re-runs
- **Handles updates and deletions** - changes on the local calendar are reflected on Google
- **Periodic syncing** - runs every 5 minutes by default
- **Secure token storage** - refresh tokens stored in macOS Keychain
- **Token caching** - reduces keychain prompts to once per hour

## Prerequisites

- macOS (10.15+)
- Corporate calendar in macOS Calendar app
- Google account for destination calendar

## Getting Your Corporate Calendar into macOS Calendar

Before syncing, you need to add your corporate calendar to macOS Calendar:

1. Open **Calendar** app on your Mac
2. Go to **Calendar** > **Preferences** > **Accounts**
3. Click the **+** button to add an account
4. Select **Google**
5. Sign in with your corporate Gmail account
6. Check the box next to your corporate calendar to sync it
7. Click **Done**

Your corporate calendar events should now appear in macOS Calendar.

## Setup

### 1. Create Google OAuth Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or use existing)
3. Enable the Google Calendar API:
   - Click "APIs & Services" > "Library"
   - Search for "Google Calendar API"
   - Click "Enable"
4. Create OAuth 2.0 credentials:
   - Click "APIs & Services" > "Credentials"
   - Click "Create Credentials" > "OAuth 2.0 Client ID"
   - Choose "Desktop application"
   - Click "Create"
5. Copy your Client ID and Client Secret

### 2. Configure the App

Copy the example environment file:
```bash
cd ~/worksp/3rdparty/Calendar\ Sync
cp .env.example .env
```

Edit `.env` and add your credentials:
```bash
CALENDAR_SYNC_CLIENT_ID=your-client-id.apps.googleusercontent.com
CALENDAR_SYNC_CLIENT_SECRET=your-client-secret
```

**Important:** The `.env` file is git-ignored and will never be committed.

### 3. Build the App

```bash
cd ~/worksp/3rdparty/Calendar\ Sync
xcodebuild -scheme "Calendar Sync" -configuration Release build
```

The built app will be at:
```
~/Library/Developer/Xcode/DerivedData/calendar-sync-*/Build/Products/Release/calendar-sync.app/Contents/MacOS/calendar-sync
```

## Usage

### First Run (Setup)

```bash
export CALENDAR_SYNC_CLIENT_ID="your-client-id.apps.googleusercontent.com"
export CALENDAR_SYNC_CLIENT_SECRET="your-client-secret"

# Find and run the app
~/Library/Developer/Xcode/DerivedData/calendar-sync-*/Build/Products/Release/calendar-sync.app/Contents/MacOS/calendar-sync
```

The app will:
1. Ask you to select which local calendar to sync from
2. Open your browser for Google authentication (log in with your personal Google account)
3. Ask which Google Calendar to sync to (create new or use existing)
4. Start syncing events

### Normal Use (After Setup)

```bash
"/Users/jdaley/Library/Developer/Xcode/DerivedData/calendar-sync-ekoaqcfpglfqujchvfuacgbnmczy/Build/Products/Release/calendar-sync.app/Contents/MacOS/calendar-sync"
```

The app will run continuously, syncing every 5 minutes.

### Commands

```bash
# Start syncing (or resume if already configured)
./Calendar\ Sync

# Clear all synced events from Google Calendar
./Calendar\ Sync --clear-all

# Show help
./Calendar\ Sync --help
```

### Finding Your Google Calendar ID

If you want to sync to an existing calendar:

1. Go to [Google Calendar](https://calendar.google.com)
2. Find your calendar in the left sidebar
3. Click the three dots menu next to it
4. Select "Settings"
5. Look for "Calendar ID" (usually an email-like format: `your.email@gmail.com`)

## How It Works

### Syncing

- Events from your local calendar are copied to Google Calendar
- Each synced event is marked with a sync ID in its description
- On re-runs, the app:
  - Skips events already synced (no duplicates)
  - Updates events that have changed locally
  - Deletes events from Google Calendar if they no longer exist locally

### Personal Events

Events you create directly in Google Calendar are **never touched** by this app:
- They don't have the sync marker, so they're ignored
- You can freely create personal events alongside synced ones
- Use `--clear-all` to delete only synced events (personal events are safe)

### Authentication

- First run: Opens your browser for Google OAuth login
- Refresh token: Stored securely in macOS Keychain
- Access token: Cached in memory for 55 minutes (reduces keychain prompts)

## Troubleshooting

### "Refresh token not found in keychain"

The settings exist but the refresh token wasn't saved. Reset and re-authenticate:
```bash
defaults delete com.jondaley.calendar-sync
security delete-generic-password -s com.jondaley.calendar-sync -a google-refresh-token 2>/dev/null
```

Then run the app again for first-time setup.

### "Sync error: noData"

Same issue as above - run the reset commands above.

### Keychain keeps asking for password

This is normal on first run. Click "Always Allow" and it should only ask once per hour after that.

### Calendar wasn't created / synced

Check that:
- The local calendar events are within the next 90 days
- Google Calendar API is enabled in your Google Cloud project
- Your OAuth credentials are correct

## Customization

### Change sync interval

Edit `CalendarSyncApp.swift` and change:
```swift
let syncInterval: TimeInterval = 5 * 60  // 5 minutes
```

to desired interval in seconds (e.g., `60 * 60` for 1 hour).

### Change calendar name

When prompted to create a new calendar, you can manually enter a different name instead of "Corporate Calendar".

## Development

### Rebuild

```bash
cd ~/worksp/3rdparty/calendar-sync
xcodebuild -scheme "Calendar Sync" -configuration Release build
```

### Clean Build

```bash
xcodebuild -scheme "Calendar Sync" clean
xcodebuild -scheme "Calendar Sync" -configuration Release build
```

## Security Notes

⚠️ **Credentials:**
- `.env` file is git-ignored - never commit it
- OAuth credentials are only stored in environment variables at runtime
- Refresh token is stored securely in macOS Keychain
- Access token is cached in memory only

✅ **Safe Operations:**
- Personal events in Google Calendar are never deleted
- Only events created by this app (with sync markers) are modified
- All API calls use HTTPS
- Tokens are automatically refreshed as needed

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See the [LICENSE](LICENSE) file for details.
