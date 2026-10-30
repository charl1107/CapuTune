# Changelog

Notable changes for each release, written so users can understand what
changed and why it matters. The newest release comes first.

When you cut a release (`git tag vX.Y.Z && git push origin vX.Y.Z`), add
its section here first, then paste the same text into the GitHub release
(`gh release edit vX.Y.Z --notes-file <file>`).

Releases before 2.0.0 were auto-generated from commit history; see their
GitHub release pages for details.

## [2.0.0] — 2026-10-30

**The headline: CapuTune now finds music and keeps it playing on its
own.** Search results are ranked by actual relevance, every song can
grow into an endless radio, and streams heal themselves when the network
drops.

### ✨ New

- **Smart Search** — results are ranked by relevance: exact title
  matches come first, then artist and album matches, with popularity
  breaking ties. The right song is now the first result instead of page
  two.
- **Smart Radio** — start a radio from any song and CapuTune builds an
  endless queue of similar tracks straight from YouTube Music's own
  radio stations.
- **Smarter recommendations** — home suggestions are now built from the
  radio of what you play (with a search fallback when a song has no
  radio), and songs you've already heard are skipped.
- **Albums & Artists view** — a new Collections screen groups your whole
  library (favorites, downloads, most played, playlists) by album or
  artist. Find it in the Library toolbar.
- **Playlist reorder & sort** — drag songs to rearrange, or sort any
  playlist by title or artist from the toolbar.
- **Sleep timer** — Off / 15 / 30 / 60 minutes from the player's ⋮ menu.
  It pauses instead of stopping, so you can resume where you dozed off.
  The menu shows the exact time playback will pause.
- **Playback speed** — 0.5×–2× from the ⋮ menu. Your chosen speed sticks
  across streams, downloads and imported files, and the notification now
  shows the real speed.
- **Share** — the Share entry in the player menu now actually shares the
  song (title, artist and link).

### 🚀 Improved

- **The Audio Quality setting now really works** — 128/192/320 kbps was
  saved but never used; the resolver always grabbed the highest bitrate.
  It now picks a stream (and download) matching your choice, with 320
  keeping the highest available.
- **Self-healing streams** — if the connection to YouTube's servers dies
  mid-song, CapuTune quietly retries on a fresh URL — usually a
  different, healthy server — and resumes exactly where you left off (up
  to 2 attempts before telling you plainly).
- **Honest error messages** — when there's no usable internet, the app
  now says "No usable internet on this network. Streaming is unavailable
  — downloaded songs still play." instead of wrongly blaming YouTube.
- **Stronger retry logic** — stream retries now use exponential backoff
  with jitter instead of fixed delays, and diagnostics log only the
  server host and failure stage — your signed URLs are never logged.

### 📥 Downloads

- **Network-resilient downloads**: strict timeouts (15s to connect, 45s
  waiting for the server to respond, 45s stall guard mid-transfer), and
  one bounded retry on a freshly resolved URL — but only for transient
  failures. Cancelling always wins over retrying.
- **Self-cleanup**: staging files left behind by killed downloads are
  swept at startup (only after 24h, never touching completed downloads).
- **Quality-aware**: downloads resolve at your Audio Quality setting.

### 🛠 For the curious

- Releases are now **tag-driven**: a pushed `vX.Y.Z` tag releases
  exactly that version, and pushes to `main` never auto-release. Version
  numbers finally mean what they say.

[2.0.0]: https://github.com/charl1107/CapuTune/compare/v1.0.24...v2.0.0
