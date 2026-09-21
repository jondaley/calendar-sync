# Building Calendar Sync

## Prerequisites

- macOS (10.15+)
- Xcode with command-line tools installed
- Google Cloud OAuth credentials (see README Setup section)

## Configure the App

Copy the example environment file:
```bash
cd ~/worksp/3rdparty/calendar-sync
cp .env.example .env
```

Edit `.env` and add your credentials:
```bash
CALENDAR_SYNC_CLIENT_ID=your-client-id.apps.googleusercontent.com
CALENDAR_SYNC_CLIENT_SECRET=your-client-secret
```

**Important:** The `.env` file is git-ignored and will never be committed.

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
xcodebuild -scheme "Calendar Sync" clean
xcodebuild -scheme "calendar-sync" -configuration Release build
```

## Troubleshooting Builds

- **Build fails**: Ensure you have the latest Xcode tools: `xcode-select --install`
- **Binary not found**: Run the `find` command above to verify the path with Xcode's random hash
- **Permission denied**: The binary may not be executable. Check permissions and rebuild
