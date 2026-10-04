#!/usr/bin/env bash
set -euo pipefail

mode=${1:---isolated}
case "$mode" in
  --isolated | --shared) ;;
  *) echo "Usage: bash launch.sh [--isolated|--shared]" >&2; exit 2 ;;
esac

if ! command -v omarchy >/dev/null; then
  echo "Omarchy's web-app launcher is required to open YouTube Music." >&2
  exit 1
fi

url=https://music.youtube.com
if [[ $mode == --shared ]]; then
  exec omarchy launch webapp "$url"
fi

# Match the browser selection in omarchy-launch-webapp. Separate directories
# prevent different browser vendors/channels from reusing each other's data.
browser=$(xdg-settings get default-web-browser 2>/dev/null || true)
case "$browser" in
  google-chrome* | brave* | microsoft-edge* | opera* | vivaldi* | helium*) ;;
  *) browser=chromium.desktop ;;
esac
browser=${browser//[^a-zA-Z0-9._-]/_}

# XDG paths must be absolute. Never launch without an explicit data directory
# when isolation was requested, even if creating the directory fails.
data_home=${XDG_DATA_HOME:-}
if [[ $data_home != /* ]]; then
  if [[ ${HOME:-} != /* ]]; then
    echo "Cannot determine an absolute directory for the YouTube Music profile." >&2
    exit 1
  fi
  data_home="$HOME/.local/share"
fi
profile="$data_home/dj.youtube-music/browser/$browser"
umask 077
mkdir -p -- "$profile"

exec omarchy launch webapp "$url" \
  "--user-data-dir=$profile" \
  --no-first-run --no-default-browser-check
