#!/usr/bin/env bash
set -euo pipefail

mode=${1:---isolated}
case "$mode" in
  --isolated | --shared) ;;
  *) echo "Usage: bash launch.sh [--isolated|--shared] [--prepare]" >&2; exit 2 ;;
esac
prepare=${2:-}
if [[ $# -gt 2 || ( -n $prepare && $prepare != --prepare ) ]]; then
  echo "Usage: bash launch.sh [--isolated|--shared] [--prepare]" >&2
  exit 2
fi

if ! command -v omarchy >/dev/null; then
  echo "Omarchy's web-app launcher is required to open YouTube Music." >&2
  exit 1
fi

url=https://music.youtube.com
command=(omarchy launch webapp "$url")

focus_window() {
  # Hyprland 0.55 uses Lua dispatchers; retain compatibility with older hosts.
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null 2>&1 ||
    hyprctl dispatch focuswindow "address:$1" >/dev/null 2>&1
}

if [[ $mode == --isolated ]]; then
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

  # App classes are identical for normal and isolated profiles. Only reuse
  # a window when its browser process explicitly uses the intended directory.
  # Unreadable process information is never evidence that a profile matches.
  if command -v hyprctl >/dev/null && command -v jq >/dev/null; then
    clients=$(hyprctl clients -j 2>/dev/null || true)
    while IFS=$'\t' read -r pid address; do
      [[ $pid =~ ^[1-9][0-9]*$ && $address =~ ^0x[0-9a-fA-F]+$ ]] || continue
      [[ -r /proc/$pid/cmdline ]] || continue
      args=()
      mapfile -d '' -t args < "/proc/$pid/cmdline" 2>/dev/null || continue
      actual_profile=
      for ((i = 0; i < ${#args[@]}; i++)); do
        case "${args[i]}" in
          --user-data-dir=*) actual_profile=${args[i]#--user-data-dir=} ;;
          --user-data-dir) actual_profile=${args[i+1]:-}; ((i+=1)) ;;
        esac
      done
      profile_matches=false
      if [[ $actual_profile == "$profile" ]]; then
        profile_matches=true
      elif [[ ${#args[@]} == 1 &&
          ( ${args[0]} == *" --user-data-dir=$profile "* ||
            ${args[0]} == *" --user-data-dir=$profile" ) ]]; then
        # Brave can rewrite argv as one display string, losing token boundaries.
        # Chromium's profile lock records the actual owning host/browser PID;
        # require it as well, rather than guessing where a spaced path ends.
        lock=$(readlink -- "$profile/SingletonLock" 2>/dev/null || true)
        [[ $lock != "$(uname -n)-$pid" ]] || profile_matches=true
      fi
      if [[ $profile_matches == true ]] &&
          focus_window "$address"; then
        [[ $prepare != --prepare ]] || printf '[]\n'
        exit 0
      fi
    done < <(printf '%s' "$clients" | jq -r '
      .[] | select([.class, .initialClass] | any(. != null and
        test("(^|-)music\\.youtube\\.com__(?:-|$)"; "i"))) |
      [.pid, .address] | @tsv' 2>/dev/null || true)
  fi
  command+=("--user-data-dir=$profile" --no-first-run --no-default-browser-check)
fi

# The managed QML process only prepares/focuses. The returned argv is launched
# with Quickshell.execDetached, so widget destruction cannot kill the browser.
if [[ $prepare == --prepare ]]; then
  jq -cn --args '$ARGS.positional' -- "${command[@]}"
else
  exec "${command[@]}"
fi
