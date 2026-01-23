# MyTube

MyTube is a custom iOS YouTube client designed to enhance the viewing experience with features like background audio playback and advanced subscription management.

## Features

- **Background Audio Playback**: distinct focus on allowing audio to continue playing when the app is in the background or the device is locked, addressing limitations in the standard YouTube app.
- **Advanced Subscription Management**:
    - Track "Unread" videos to easily see what you haven't watched yet.
    - specialized views for subscriptions and channel details.
- **Custom Player UI**: A refined player interface with full-screen support and intuitive controls.
- **Playlist Management**: Manage and view your YouTube playlists directly within the app.
- **Token Management**: Robust handling of OAuth tokens for seamless authentication with Google services.

## Requirements

- iOS 15.0+
- Xcode 14.0+
- A Google Cloud Console project with YouTube Data API v3 enabled (for API keys and OAuth functionality).

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/Liago/mytube.git
   ```
2. Open the project in Xcode:
   ```bash
   open MyTube.xcodeproj
   ```
3. Update specific configuration files (e.g., API Keys) if necessary (check `YouTubeService` or configuration files).
4. Build and run on your Simulator or Device.

## Architecture

The app is built using SwiftUI and follows a modern architecture pattern:
- **Views**: SwiftUI views for the UI layer.
- **Models**: Swift structures representing YouTube data (Channels, Videos, Playlists).
- **Services**: `YouTubeService` for API interactions, `VideoStatusManager` for local state persistence (watched status).

## License

Private repository. Copyright © 2026.
