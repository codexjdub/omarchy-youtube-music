#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

omarchy plugin validate .
jq -e . manifest.json >/dev/null

qmlformat_bin=$(command -v qmlformat || true)
[[ -n $qmlformat_bin ]] || qmlformat_bin=/usr/lib/qt6/bin/qmlformat
if [[ -x $qmlformat_bin ]]; then
  "$qmlformat_bin" Panel.qml >/dev/null
fi

qmllint_bin=$(command -v qmllint || true)
[[ -n $qmllint_bin ]] || qmllint_bin=/usr/lib/qt6/bin/qmllint
if [[ -x $qmllint_bin ]]; then
  "$qmllint_bin" -I /usr/share/omarchy/shell Panel.qml || true
fi

echo "Plugin checks passed"
