# Privacy Policy for Calendar Sync

**Effective date:** 2026-10-06

Calendar Sync ("the App") is a free, open-source, single-user command-line
tool for macOS that copies events from a calendar in your local macOS
Calendar app to a Google Calendar you choose. This policy explains what data
the App accesses and how it is used.

## Data the App Accesses

- **Your Google calendar list** (read-only) — used only so you can pick
  which Google Calendar to sync events into.
- **Events on calendars the App itself creates** — the App can create,
  update, and delete events only on a Google Calendar it created (or one you
  explicitly designated as the destination). It never reads or modifies any
  other events already on your Google account.
- **Events in the local macOS Calendar you select** — read via Apple's
  EventKit framework, to know what to copy to Google Calendar.

## How Your Data Is Used

- Event details (title, start/end time, and notes, if present) are copied
  from your chosen local calendar to your chosen Google Calendar, solely to
  keep that calendar in sync.
- The App does not run as a hosted service. There is no backend server
  operated by the developer. All communication happens directly between your
  Mac and Google's own servers, using your Google account.
- No data is sent to the developer or to any third party.

## Where Your Data Is Stored

- Your Google OAuth refresh token is stored only on your own Mac, in the
  macOS Keychain, gated by Touch ID / your device passcode.
- No calendar data, tokens, or other personal information is logged,
  collected, or transmitted anywhere other than your own device and Google's
  API endpoints.

## Data Sharing

The developer does not collect, view, sell, or share any of your data. The
App's full source code is public, so you can verify this yourself:
https://github.com/jondaley/calendar-sync

## Your Choices

- Revoke the App's access anytime from your Google Account's
  [Third-party apps & services](https://myaccount.google.com/permissions)
  settings.
- Run `calendar-sync --clear-all` to delete every event the App created on
  Google Calendar.
- Remove the stored refresh token from your Mac's Keychain (see the
  project's README/DOCS for the exact command).

## Changes to This Policy

Any changes to this policy will be made in this file in the public GitHub
repository, with the effective date above updated accordingly.
