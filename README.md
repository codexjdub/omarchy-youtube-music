# Omarchy YouTube Music

A native Omarchy Quattro bar plugin that opens the full YouTube Music site in
a dedicated browser app window and controls playback through MPRIS.
By default, the app uses its own persistent browser profile, separate from
your normal browser login, cookies, and history.

## Features

- Full YouTube Music app window with an isolated browser profile by default
- Previous, play/pause, and next controls directly in the bar
- Current song title and artist in the bar (optional)
- Artwork, artist, album, playback position, and seeking in a popup
- Keyboard controls in the popup
- YouTube Music detection for Chromium, Chrome, Brave, Firefox, Zen, Vivaldi,
  and Edge
- Horizontal and vertical bar support
- Theme-aware colors and sizing
- App launching through Omarchy and a supported Chromium-based browser;
  playback controls work with browsers that expose MPRIS

## App window and privacy

Left-click the music icon or track title to open YouTube Music in a separate
app window. The site provides search, playlists, your library, and Google
sign-in. Right-click opens the plugin's playback popup.
The popup includes an **Open app** button and shows whether the app uses a
separate or shared browser profile.

The default launch uses a dedicated `--user-data-dir`, so your normal browser
sessions are not reused. Sign into Google once in the app; the profile persists
across launches. Browser data is stored under
`${XDG_DATA_HOME:-$HOME/.local/share}/dj.youtube-music/browser/<browser-desktop-id>/`.
Each browser/channel has a separate profile, so changing the default browser
may require signing in again. This is browser-profile separation; activity
associated with a Google account can still be stored by Google.

Turn off `isolatedProfile` explicitly to use the normal browser profile instead.
Launch failures never automatically switch to the shared profile.

App windows use Omarchy's supported default browser (Chrome, Brave, Edge,
Opera, Vivaldi, or Helium), falling back to Chromium for other defaults.
The selected browser must be installed. This launches the site in browser app
mode; it does not install a browser-managed PWA or a desktop launcher.

## Install

```bash
omarchy plugin add https://github.com/codexjdub/omarchy-youtube-music.git --enable
omarchy bar move dj.youtube-music --section left
```

For development from a local checkout, commit your changes first and replace
the GitHub URL with `.`. The Omarchy installer clones the repository, so it
installs committed content rather than uncommitted working-tree changes.

The shell hot-reloads plugin changes. If it ever needs a manual rescan:

```bash
omarchy-shell shell rescanPlugins
```

## Bar controls

- Music icon or title: open the YouTube Music app window
- Music icon or title right-click: open or close the playback popup
- Previous/play/next icons: control playback
- Scroll over the music icon or title: previous/next track
- Middle-click the music icon or title: play/pause

## Popup keyboard controls

- `Space` or `Enter`: play/pause
- `n` or Right arrow: next track
- `p` or Left arrow: previous track
- `o`: open `music.youtube.com`
- `Escape`: close

## Settings

The plugin exposes these bar-widget settings through Omarchy:

- `showTitle`: show the song title and artist in a horizontal bar
- `isolatedProfile`: use a dedicated browser profile (on by default); disable
  only if you want to share normal browser logins, cookies, and history
- `maxTitleWidth`: cap the combined song title and artist width between 80 and
  320 pixels; the artist gets reserved space so a long title cannot hide it.
  Hover to see the full text when it is truncated.
- `showWhenIdle`: keep the launcher visible when there is no detected player
- `browserFallback`: detect Chromium-family players when the browser omits the
  current tab URL

## Validate

```bash
./tests/check.sh
```

The check tests isolated/shared launching without starting a browser, and runs
Omarchy's manifest validator and Qt's QML parser. It also runs
`qmllint` when available; framework import-path warnings are expected when
linting a dynamically loaded third-party plugin outside the shell host.

## How detection works

The plugin first matches the dedicated app window's process ID to its MPRIS
instance, so missing song URLs or artwork do not prevent app detection.
It then checks explicit MPRIS identities, desktop entries, or metadata URLs.
Chromium sometimes omits the media tab URL, so
the optional fallback also recognizes browser players with album metadata or
YouTube/Google-hosted artwork. Turn `browserFallback` off if another browser
media tab is incorrectly selected.

Start a track in the app before using playback controls: browsers publish their
MPRIS player when a media session starts. Controls follow the capabilities the
browser exposes, including whether seeking is supported.

For troubleshooting or keyboard bindings, the plugin exposes these IPC calls:

```bash
omarchy-shell dj.youtube-music.controls status
omarchy-shell dj.youtube-music.controls playPause
omarchy-shell dj.youtube-music.controls previous
omarchy-shell dj.youtube-music.controls next
```

`status` reports detected app process IDs, available players, the selected
player, and its playback capabilities. Development checks require Python 3
and Node.js; neither is required to run the installed plugin.

## Credits

The interaction model and MPRIS detection were informed by:

- <https://github.com/levyvix/omarchy-youtube-music>
- <https://github.com/itsdotdev/omarchy-youtube-music>

## License

MIT — see [LICENSE](LICENSE).
