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
4. Add the required scopes to the OAuth consent screen (a separate step from enabling the API above):
   - Click "APIs & Services" > "OAuth consent screen" > "Data Access"
   - Click "Add or Remove Scopes"
   - Add both of these (manually paste the scope if it's not in the filtered list):
     - `https://www.googleapis.com/auth/calendar.calendarlist.readonly` — lets the app list your calendars during setup
     - `https://www.googleapis.com/auth/calendar.app.created` — lets the app create its own destination calendar and manage events on it (it can't touch any calendar it didn't create itself)
   - Save
5. Create OAuth 2.0 credentials:
   - Click "APIs & Services" > "Credentials"
   - Click "Create Credentials" > "OAuth 2.0 Client ID"
   - Choose "Desktop application"
   - Click "Create"
6. Copy your Client ID and Client Secret
7. Move the app to production (see below) — otherwise Google expires your login after 7 days

### Moving the App to Production

While the OAuth consent screen's publishing status is **Testing**, Google expires refresh tokens after 7 days, so the app will keep asking you to re-authenticate. To avoid this:

1. Complete the branding: go to "APIs & Services" > "OAuth consent screen" > "Branding" and fill in:
   - **App homepage:** `https://github.limedaley.com/calendar-sync/`
   - **Privacy policy link:** `https://github.limedaley.com/calendar-sync/PRIVACY.html`
   - **Terms of service link:** `https://github.limedaley.com/calendar-sync/TERMS.html`
   - **Authorized domains:** `limedaley.com` (Google requires the homepage/policy links to be on an authorized domain)
   - **Do not upload an app logo.** Any branding logo has to be reviewed and approved by Google (which triggers the verification process); leaving it blank avoids that.

   You can use the GitHub Pages site above as-is, or publish the `docs/` folder on your own custom domain (this one is a CNAME to `jondaley.github.io`) (e.g. via a fork with GitHub Pages and a custom domain) and use that domain and its URLs instead.
2. Go to "Audience". Under "Publishing status", click "Publish app" and confirm. The status changes to **In production**
3. Delete the old refresh token and sign in again, since tokens issued while in Testing still expire after 7 days:
   ```bash
   defaults delete com.jondaley.calendar-sync
   security delete-generic-password -s com.jondaley.calendar-sync -a google-refresh-token
   ```
   Then run the app again; it walks you through setup and Google sign-in.

You do **not** need to submit the app for Google verification for personal use. Unverified apps in production work, but Google shows a "Google hasn't verified this app" warning at sign-in (click "Advanced" > "Go to <app name> (unsafe)") and caps the app at 100 users — fine for a single-user tool, since you own the project.

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
- Refresh token: Stored securely in macOS Keychain, gated by Touch ID (falls back to your device password if Touch ID fails or isn't available)
- Touch ID prompts once per app launch, not on every sync — the unlocked refresh token is held in memory for that process's lifetime, so it only needs to be re-confirmed after a restart or reboot, not every hour
- Subsequent runs: Uses the stored refresh token to obtain new access tokens
- Must be run as `./bin/calendar-sync.app/Contents/MacOS/calendar-sync` (inside its `.app` bundle) — a bare copied binary breaks Keychain access

## Customization

### Change sync interval and window

Set any of these in your `.env` file (see `.env.example`); defaults apply if omitted:
```
CALENDAR_SYNC_INTERVAL_MINUTES=5
CALENDAR_SYNC_DAYS_BACK=90
CALENDAR_SYNC_DAYS_AHEAD=180
```

The defaults live in the `// MARK: - Constants` block in `CalendarSyncApp.swift`, along with the other constants.

### Change calendar name

When prompted to create a new calendar, you can manually enter a different name instead of "Corporate Calendar".

## Choosing a Destination Calendar

During setup, the app only lets you pick a calendar it created itself (it lists these by probing which of your calendars it can actually read/write events on), or create a new one. You can't point it at a pre-existing calendar with personal events — the app's OAuth scope (`calendar.app.created`) is intentionally restricted to calendars the app created, so it can't read or write events anywhere else in your account.

## Troubleshooting

### "Refresh token not found in keychain"

The settings exist but the refresh token wasn't saved. Reset and re-authenticate:
```bash
defaults delete com.jondaley.calendar-sync
security delete-generic-password -s com.jondaley.calendar-sync -a google-refresh-token 
```

Then run the app again for first-time setup.

### "Sync error: noData"

Same issue as above - run the reset commands above.

### Destination calendar was deleted on Google

If the Google Calendar you were syncing to gets deleted (e.g. cleaning up test calendars), the app detects this automatically at the start of each sync pass, walks you through picking or creating a new destination calendar, and updates its saved settings — no manual reset needed.

### Asked to re-authenticate every week

Your OAuth consent screen is still in **Testing**, which expires tokens after 7 days. Publish it as described in [Moving the App to Production](#moving-the-app-to-production), then reset and sign in again.

### Calendar wasn't created / synced

Check that:
- The local calendar event is within the sync window (90 days back to 180 days ahead)
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
