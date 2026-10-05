# MacIPTV

Native macOS IPTV viewer for personal provider subscriptions. The user wants a familiar TiviMate-style flow and explicitly authorizes autonomous design and implementation, with llamacpp/qwen3.8-flash-next as coding worker and this conversation as orchestrator.

## Scope
SwiftUI/AppKit desktop app, macOS 14+, Spanish interface, dark TV-centric layout. Sidebar with groups and favorites; searchable channel list; player with current programme; XMLTV schedule with channel rows and time columns. Resizable window, keyboard channel navigation, native fullscreen and playback controls.

Source setup supports remote M3U, local M3U file, optional XMLTV URL and Xtream server/user/password. Xtream can generate the provider M3U and XMLTV endpoints, requesting HLS for native playback. URLComponents must encode credentials. Source secrets and credential-bearing playlist content stay in Keychain; favorites and non-secret preferences can use UserDefaults. No credentials in logs or repository.

M3U parsing handles quoted EXTINF attributes, commas in channel names, CRLF/BOM, groups, logos, tvg-id, relative stream URLs, invalid entries and empty lists. Stable IDs keep favorites consistent across refreshes. XMLTV parsing handles timezones, missing stop values safely, entities and invalid dates. Index programmes by channel; avoid per-row full guide scans. Async networking rejects HTTP failures, supports cancellation and surfaces friendly errors without URLs containing credentials. Import errors preserve the last valid source and channels.

AVKit/AVPlayer supplies integrated HLS playback, state and failure UI, retry and native fullscreen. Installed VLC/IINA can be opened as explicit fallback for incompatible TS/codecs. Do not promise universal provider compatibility. No recording, catch-up, VOD, DRM or multi-screen in this version.

Demo mode contains synthetic channels/programmes clearly labeled, with Apple's public sample HLS stream; real providers are entered only in the UI. Demo must not overwrite a saved subscription. App launches without provider data.

## Deliverables and acceptance
Swift Package with independently testable core and native app executable. Tests cover parser/URL/guide edge cases. Release build packaged as dist/MacIPTV.app via repeatable script and ad-hoc local signature. Inspect running app and verify a public HLS playback smoke test. Document supported formats, installation, provider setup and unverified real-provider behavior. This is a local build, not a notarized distribution.
