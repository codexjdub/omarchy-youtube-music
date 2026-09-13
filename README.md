# Omarchy YouTube Music

A native Omarchy Quattro bar plugin for controlling YouTube Music through
MPRIS. It controls the existing browser player, so it does not start a second
player, automate the browser, or store Google account data.

## Features

- Previous, play/pause, and next controls directly in the bar
- Current track title in the bar (optional)
- Artwork, artist, album, playback position, and seeking in a popup
- Keyboard controls in the popup
- YouTube Music detection for Chromium, Chrome, Brave, Firefox, Zen, Vivaldi,
  and Edge
- Horizontal and vertical bar support
- Theme-aware colors and sizing
- No dependencies beyond Omarchy/Quickshell and a browser with MPRIS support

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

- Music icon: open or close the popup
- Music icon right-click: open `music.youtube.com`
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

- `showTitle`: show the track title in a horizontal bar
- `maxTitleWidth`: cap the title width between 80 and 320 pixels
- `showWhenIdle`: keep the launcher visible when there is no detected player
- `browserFallback`: detect Chromium-family players when the browser omits the
  current tab URL

## Validate

```bash
./tests/check.sh
```

The check runs Omarchy's manifest validator and Qt's QML parser. It also runs
`qmllint` when available; framework import-path warnings are expected when
linting a dynamically loaded third-party plugin outside the shell host.

## How detection works

The plugin prefers explicit MPRIS identities, desktop entries, or metadata
URLs containing YouTube Music. Chromium sometimes omits the media tab URL, so
the optional fallback also recognizes browser players with album metadata or
YouTube/Google-hosted artwork. Turn `browserFallback` off if another browser
media tab is incorrectly selected.

## Credits

The interaction model and MPRIS detection were informed by:

- <https://github.com/levyvix/omarchy-youtube-music>
- <https://github.com/itsdotdev/omarchy-youtube-music>

## License

MIT — see [LICENSE](LICENSE).
