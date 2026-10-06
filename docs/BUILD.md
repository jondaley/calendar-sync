# Building Calendar Sync

## Prerequisites

- macOS (10.15+)
- Xcode with command-line tools installed
- Google Cloud OAuth credentials (see README Setup section)

## Configure the App

Copy the example environment file:
```bash
cp .env.example .env
```

Edit `.env` and add your credentials:
```bash
CALENDAR_SYNC_CLIENT_ID=your-client-id.apps.googleusercontent.com
CALENDAR_SYNC_CLIENT_SECRET=your-client-secret
```

## Build

```bash
./build.sh
```

The `build.sh` script compiles the project using Xcode and copies the built `.app` bundle to `./bin/calendar-sync.app`.

## Running the Binary

```bash
./bin/calendar-sync.app/Contents/MacOS/calendar-sync
```

**Important:** always run the executable from inside `./bin/calendar-sync.app`, not a copy of just the binary. A bare copied executable loses its Info.plist/sealed-resources binding, which macOS's code-identity checks need — Keychain calls (including the Touch ID-gated refresh token storage) fail with cryptic `errSecMissingEntitlement`/code-signing errors if run that way.

## Clean Build

```bash
xcodebuild -scheme "calendar-sync" clean
xcodebuild -scheme "calendar-sync" -configuration Release build
```

