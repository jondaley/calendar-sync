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

The `build.sh` script compiles the project using Xcode and automatically creates a symlink `./calendar-sync` in the project root that points to the built binary.

## Running the Binary

```bash
./bin/calendar-sync
```

## Clean Build

```bash
xcodebuild -scheme "calendar-sync" clean
xcodebuild -scheme "calendar-sync" -configuration Release build
```

