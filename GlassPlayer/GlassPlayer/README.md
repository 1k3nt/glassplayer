# GlassPlayer

A Liquid Glass now-playing screen with synced lyrics, haptics and an animated cover.
Original code (not derived from any other project). Runs a built-in demo until you add a Spotify Client ID.

## Get the IPA (no Mac needed)

1. Create a new **private** GitHub repo and upload everything in this folder (keep `.github/` and `Sources/`).
2. (Spotify) Create an app at developer.spotify.com/dashboard, add the Redirect URI `glassplayer://callback`,
   and add your own Spotify account under User Management. In your repo go to
   Settings > Secrets and variables > Actions > Variables, and add `SPOTIFY_CLIENT_ID` with your Client ID.
   Skip this to build the demo version.
3. Open the **Actions** tab, run **Build IPA**, then download the `GlassPlayer-ipa` artifact (a zip containing `GlassPlayer.ipa`).
4. The IPA is unsigned. Sign and install it with your own Apple ID using SideStore, AltStore, Feather or Sideloadly.
   Change the bundle id in `project.yml` first if your signer needs a unique one.

## Using it

Open Spotify on your phone and start a song, then open GlassPlayer and tap Connect Spotify.
Playback controls need Spotify Premium and an active Spotify device.
Lyrics come from LRCLIB; haptics tick on every lyric line and on play/pause (toggle in the header).
