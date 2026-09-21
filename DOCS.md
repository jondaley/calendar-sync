# Calendar Sync Documentation

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

## Setting Up Google OAuth Credentials

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
- Subsequent runs: Uses the stored refresh token to obtain new access tokens

## Customization

### Change sync interval

Edit `CalendarSyncApp.swift` and change:
```swift
let syncInterval: TimeInterval = 5 * 60  // 5 minutes
```

to desired interval in seconds (e.g., `60 * 60` for 1 hour).

### Change calendar name

When prompted to create a new calendar, you can manually enter a different name instead of "Corporate Calendar".

## Finding Your Google Calendar ID

If you want to sync to an existing calendar:

1. Go to [Google Calendar](https://calendar.google.com)
2. Find your calendar in the left sidebar
3. Click the three dots menu next to it
4. Select "Settings"
5. Look for "Calendar ID" (usually an email-like format: `your.email@gmail.com`)

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

If the system Keychain prompts for your password, click "Always Allow" to prevent repeated prompts.

### Calendar wasn't created / synced

Check that:
- The local calendar events are within the next 90 days
- Google Calendar API is enabled in your Google Cloud project
- Your OAuth credentials are correct

## Security

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
