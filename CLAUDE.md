# CLAUDE.md - MyTube Project Guide

## Project Overview

MyTube is a private iOS YouTube client with a Node.js serverless backend. The app's core feature is **background audio playback** of YouTube videos: it extracts audio via `yt-dlp`, caches it on Cloudflare R2, and streams it through `AVPlayer` with full lock-screen and Control Center integration.

**Current version**: 1.9.1

---

## Tech Stack

### iOS App
- **Language**: Swift 5+, SwiftUI
- **Target**: iOS 15.0+
- **Architecture**: MVVM with singleton services
- **State Management**: Combine (`@ObservableObject`, `@Published`, `@StateObject`)
- **Concurrency**: Swift async/await, `Task`, `TaskGroup`
- **Audio**: AVFoundation (`AVPlayer`, `AVAudioSession`)
- **Lock Screen**: MediaPlayer framework (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`)
- **Auth**: Google Sign-In SDK (`GIDSignIn`), YouTube Data API v3 scope `youtube.readonly`
- **Networking**: `URLSession`, `WKWebView` (fallback), `NWListener` (local proxy)
- **Persistence**: `UserDefaults` (encoded JSON)
- **Third-party**: `YouTubeKit` (Swift package for stream URL extraction)

### Backend (Netlify Functions)
- **Runtime**: Node.js >= 18
- **Hosting**: Netlify (serverless functions)
- **Bundler**: esbuild (via `node_bundler = "esbuild"`)
- **Storage**: Cloudflare R2 (S3-compatible, `@aws-sdk/client-s3` v3)
- **Audio Extraction**: `yt-dlp` binary (bundled for macOS + Linux)
- **Scheduled Jobs**: `@netlify/functions` `schedule()` (cron every 6 hours)
- **RSS**: `rss-parser` for YouTube channel feeds
- **Versioning**: `semantic-release` with conventional commits

---

## Repository Structure

```
.
├── MyTube/                          # iOS app source
│   ├── App/
│   │   ├── MyTubeApp.swift          # @main entry point, background tasks, Google OAuth URL handler
│   │   └── ContentView.swift        # Root view: splash/login/main + MiniPlayerView overlay
│   ├── Models/
│   │   └── YouTubeModels.swift      # All Codable structs for YouTube Data API v3
│   ├── Services/
│   │   ├── AuthManager.swift        # Google Sign-In, token refresh, auth state
│   │   ├── YouTubeService.swift     # YouTube Data API v3 REST calls (playlists, subs, channels, videos)
│   │   ├── AudioPlayerService.swift # Core audio engine (AVPlayer, NowPlaying, remote controls, interruptions)
│   │   ├── AudioDownloadManager.swift # Local audio cache (/Caches/AudioCache/, 7-day expiry)
│   │   ├── LocalStreamProxy.swift   # Local HTTP proxy on port 8765 (NWListener, range requests)
│   │   ├── WebViewDownloader.swift  # WKWebView-based download (TLS fingerprint bypass)
│   │   ├── YouTubeStreamService.swift # Client-side stream URL extraction via YouTubeKit
│   │   ├── CacheStatusService.swift # Batch R2 cache status checks (debounced, 50 IDs/batch)
│   │   ├── CookieStatusService.swift # YouTube cookie health monitoring + push notifications
│   │   └── BackgroundManager.swift  # BGAppRefreshTask: fetch new videos, send notifications
│   ├── ViewModels/
│   │   ├── HomeViewModel.swift      # Home feed: filtered subs, today's uploads, watched filtering
│   │   └── PlaylistsViewModel.swift # User's YouTube playlists
│   ├── Views/
│   │   ├── MainTabView.swift        # TabView: Home, Subscriptions, Playlists, Profile
│   │   ├── HomeView.swift           # Home feed with VideoCardView list, channel navigation
│   │   ├── SubscriptionsView.swift  # Subscription list with home-toggle, inline ViewModel
│   │   ├── ChannelDetailView.swift  # Channel uploads, new/watched badges, inline ViewModel
│   │   ├── MyPlaylistsView.swift    # User playlists list
│   │   ├── PlaylistDetailView.swift # Playlist items
│   │   ├── PlayerSheetView.swift    # Full-screen player (blur background, controls, speed selector)
│   │   ├── VideoCardView.swift      # Large card: thumbnail, title, duration, cache badge, channel button
│   │   ├── ProfileView.swift       # Account info, token status, cookie status (Italian UI strings)
│   │   ├── LoginView.swift          # Google Sign-In button
│   │   ├── SplashScreen.swift       # Loading screen during auth restore
│   │   └── YouTubeEmbedView.swift   # WKWebView YouTube player wrapper
│   ├── Utilities/
│   │   ├── VideoStatusManager.swift # Watch history, progress, channel visits, home prefs, cloud sync
│   │   ├── DateUtils.swift          # ISO 8601 parsing, "isToday", duration formatting
│   │   └── ShareSheet.swift         # UIActivityViewController wrapper
│   ├── Secrets.swift                # API secret (matches Netlify API_SECRET env var)
│   └── Info.plist                   # Google OAuth URL scheme, background modes, ATS config
│
├── MyTube.xcodeproj/                # Xcode project (project.pbxproj)
│
├── netlify/                         # Backend
│   └── functions/
│       ├── audio.js                 # Main: audio delivery, R2 cache, yt-dlp multi-strategy download
│       ├── check-cache.js           # Batch cache check (up to 50 video IDs via HeadObject)
│       ├── sync-history.js          # GET/POST watch history sync (last-write-wins merge)
│       ├── sync-preferences.js      # GET/POST home channel preferences sync
│       ├── cookie-status.js         # YouTube cookie health analysis
│       ├── cleanup.js               # R2 stale object cleanup
│       └── scheduled-prefetch-background.js  # Cron (every 6h): prefetch audio for home channels
│
├── .github/workflows/
│   └── release.yml                  # CI: semantic-release on push to main (runs on macos-latest)
│
├── netlify.toml                     # Build config, function bundling, catch-all redirect to audio.js
├── package.json                     # Backend deps: @aws-sdk/client-s3, @netlify/functions, rss-parser
├── .releaserc.json                  # semantic-release: changelog, npm version, xcrun agvtool, git commit
├── upload-cookies.js                # Utility: upload cookies to R2
├── debug_formats.js                 # Debug utility
├── yt-dlp                           # macOS yt-dlp binary
├── yt-dlp-linux                     # Linux yt-dlp binary
└── CHANGELOG.md                     # Auto-generated by semantic-release
```

---

## Architecture

### Navigation Flow

```
ContentView
├── SplashScreen                     (auth loading)
├── LoginView                        (unauthenticated)
└── MainTabView                      (authenticated)
    ├── Tab 1: HomeView
    │   └── NavigationLink → ChannelDetailView
    ├── Tab 2: SubscriptionsView
    │   └── NavigationLink → ChannelDetailView
    ├── Tab 3: MyPlaylistsView
    │   └── NavigationLink → PlaylistDetailView
    └── Tab 4: ProfileView

Global overlays (always on top of ContentView):
  - MiniPlayerView            (bottom bar, visible when audio is loaded)
  - PlayerSheetView           (fullScreenCover, triggered by isPlayerPresented)
```

### Singleton Services

All services use the singleton pattern (`ServiceName.shared`) and are `@MainActor`-annotated:

| Service | Purpose |
|---------|---------|
| `AuthManager` | Google OAuth lifecycle, token management |
| `AudioPlayerService` | AVPlayer playback, NowPlaying, remote controls |
| `YouTubeService` | YouTube Data API v3 calls |
| `VideoStatusManager` | Watch state, progress, cloud sync |
| `CacheStatusService` | R2 cache availability checks |
| `CookieStatusService` | Cookie health monitoring |
| `BackgroundManager` | Background refresh tasks |

### Audio Playback Pipeline

The audio acquisition has multiple fallback layers:

1. **R2 Cache hit** — backend returns HTTP 307 redirect to public CDN URL (fastest)
2. **yt-dlp backend download** — `audio.js` runs yt-dlp with up to 6 strategy combinations (player clients: `tv_embedded`, `web_creator`, `mweb`, `android`, `ios`, `web` x with/without cookies), uploads result to R2, returns 307
3. **Scheduled prefetch** — every 6 hours, proactively downloads audio for home channels via RSS feed scanning
4. **Client-side fallbacks** (legacy/experimental):
   - `YouTubeStreamService` — direct stream URL extraction via YouTubeKit
   - `AudioDownloadManager` — full file download to local cache
   - `LocalStreamProxy` — local HTTP proxy on port 8765
   - `WebViewDownloader` — WKWebView TLS fingerprint bypass

### Data Flow

```
iOS App ←→ Netlify Functions ←→ Cloudflare R2
  │                                    │
  │  x-api-key header auth             │  S3-compatible API
  │                                    │
  ├─ GET /audio?videoId=xxx            ├─ {videoId}_v2.m4a (audio files)
  ├─ GET/POST /check-cache             ├─ {videoId}.json (metadata)
  ├─ GET/POST /sync-history            ├─ system/history.json
  ├─ GET/POST /sync-preferences        ├─ system/home_channels.json
  └─ GET /cookie-status                └─ system/_cookies.json

iOS App ←→ YouTube Data API v3
  │
  ├─ Bearer token (Google OAuth)
  ├─ Subscriptions, Channels, Playlists, Videos
  └─ Scope: youtube.readonly
```

### Cloud Storage Layout (R2 bucket: `mytube-audio`)

```
mytube-audio/
├── {videoId}_v2.m4a                  # Audio files (versioned _v2 suffix)
├── {videoId}.json                    # yt-dlp metadata
└── system/
    ├── _cookies.json                 # YouTube cookies (browser extension JSON format)
    ├── history.json                  # Watch history/progress sync
    └── home_channels.json            # Home channel preferences
```

---

## Key Patterns and Conventions

### State Management
- Services publish state via `@Published` properties
- Views observe via `@ObservedObject` / `@StateObject`
- `VideoStatusManager` persists to `UserDefaults` (encoded JSON) and syncs bidirectionally with R2
- Cloud sync uses **last-write-wins** merge strategy by `lastUpdated` timestamp
- Sync is debounced with 10s minimum interval

### Environment Switching
Both iOS and backend URLs switch automatically:
- **Simulator**: `http://localhost:8888` (via `#if targetEnvironment(simulator)`)
- **Device**: `https://mytube-be.netlify.app`

### API Authentication
- All Netlify functions check `x-api-key` header against `API_SECRET` env var
- iOS embeds the secret in `Secrets.swift`
- YouTube API uses Google OAuth Bearer tokens with automatic 401 retry/refresh

### Video Status Tracking
- A video is marked **watched** at 90% completion
- Home feed shows only **today's unwatched** videos
- `ChannelDetailView` shows "new since last visit" badges based on `lastVisitDate`
- Progress is saved every 5 seconds during playback
- Resume from progress when re-opening a video (5%-95% threshold)

### Cookie Management
- YouTube cookies stored in R2 as `system/_cookies.json` (Chrome extension JSON format)
- Backend converts to Netscape format at runtime for yt-dlp
- App monitors cookie health and sends local push notifications when near expiry (3 days)
- Upload utility: `npm run upload-cookies` (runs `upload-cookies.js`)

---

## Development

### Prerequisites
- Xcode 14.0+
- Node.js >= 18
- Netlify CLI (`npx netlify`)

### Local Backend
```bash
npm install
npx netlify dev       # Starts local dev server on port 8888
```

### Environment Variables (Netlify)
| Variable | Purpose |
|----------|---------|
| `R2_ACCOUNT_ID` | Cloudflare account ID |
| `R2_ACCESS_KEY_ID` | R2 API access key |
| `R2_SECRET_ACCESS_KEY` | R2 API secret key |
| `R2_BUCKET_NAME` | R2 bucket name (default: `mytube-audio`) |
| `R2_PUBLIC_DOMAIN` | R2 public URL (default: `https://r2.mytube.app`) |
| `API_SECRET` | Shared secret for API auth |

### iOS Build
Open `MyTube.xcodeproj` in Xcode and build for simulator or device. The simulator automatically connects to `localhost:8888`.

---

## CI/CD

- **Trigger**: Push to `main` branch
- **Runner**: `macos-latest` (GitHub Actions)
- **Process**: `semantic-release` with conventional commits
  1. Analyzes commits to determine version bump (patch/minor/major)
  2. Generates changelog
  3. Updates `package.json` version
  4. Runs `xcrun agvtool` to update iOS marketing version + build number
  5. Commits `package.json`, `package-lock.json`, `CHANGELOG.md`, `project.pbxproj`, `Info.plist` with `[skip ci]`
  6. Creates GitHub release

### Commit Convention
Use [Conventional Commits](https://www.conventionalcommits.org/):
- `feat:` — new feature (minor bump)
- `fix:` — bug fix (patch bump)
- `chore:` — maintenance (no bump unless scoped)
- `BREAKING CHANGE:` — major bump

---

## Netlify Function Details

| Function | HTTP | Endpoint | Purpose |
|----------|------|----------|---------|
| `audio.js` | GET | `/?videoId=xxx` | Audio delivery with R2 cache + yt-dlp fallback |
| `check-cache.js` | GET/POST | `/.netlify/functions/check-cache` | Batch cache check (up to 50 IDs) |
| `sync-history.js` | GET/POST | `/.netlify/functions/sync-history` | Watch history cloud sync |
| `sync-preferences.js` | GET/POST | `/.netlify/functions/sync-preferences` | Home channel preferences sync |
| `cookie-status.js` | GET | `/.netlify/functions/cookie-status` | Cookie health status |
| `cleanup.js` | — | `/.netlify/functions/cleanup` | R2 stale object cleanup |
| `scheduled-prefetch-background.js` | Scheduled | Cron `0 */6 * * *` | Prefetch audio for home channels via RSS |

**Note**: `netlify.toml` has a catch-all redirect `/* → /.netlify/functions/audio` (status 200), so `audio.js` handles all unmatched paths. Other functions are accessed via their explicit `/.netlify/functions/{name}` paths.

---

## iOS App Info.plist Key Configuration

- **Google OAuth URL Scheme**: `com.googleusercontent.apps.47831350254-150v356l9c10oreprak310gm0qhb54sa`
- **Background Modes**: `audio`, `fetch`, `processing`
- **Background Task ID**: `com.mytube.refresh`
- **ATS**: `NSAllowsArbitraryLoads = true` (for localhost dev)

---

## Common Tasks

### Adding a new Netlify function
1. Create `netlify/functions/{name}.js`
2. Export an async `handler(event, context)` function
3. Add API key check at the top (copy from existing function)
4. If using external modules, add to `external_node_modules` in `netlify.toml`

### Adding a new view
1. Create `MyTube/Views/{Name}View.swift`
2. If complex state, create `MyTube/ViewModels/{Name}ViewModel.swift` as `@MainActor ObservableObject`
3. Wire navigation in parent view using `NavigationLink`

### Adding a new service
1. Create `MyTube/Services/{Name}Service.swift`
2. Use `@MainActor class {Name}Service: ObservableObject` with `static let shared` singleton
3. Add `@Published` properties for reactive state
