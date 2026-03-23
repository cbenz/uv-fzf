#!/usr/bin/env bash

set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd uv
require_cmd fzf
require_cmd jq

UV_PYTHON_DIR="$(uv python dir)"

python_versions_build_rows() {
  uv python list --managed-python --output-format json | jq -r '
    sort_by(.key)
    | group_by(.key)
    | map({
        key: .[0].key,
        implementation: .[0].implementation,
        version: .[0].version,
        version_parts: .[0].version_parts,
        installed: (any(.[]; .path != null)),
        path: ([.[] | select(.path != null) | .path][0] // "")
      })
    | map(.display_key = ((if .installed then "* " else "  " end) + .key))
    | sort_by(.implementation)
    | group_by(.implementation)
    | sort_by(.[0].implementation)
    | map(
        sort_by([
          .version_parts.major,
          .version_parts.minor,
          .version_parts.patch,
          .version
        ])
        | reverse
      )
    | add
    | .[]
    | [
        .display_key,
        (if .installed then "installed" else "available" end),
        .key,
        .version,
        .path
      ]
    | @tsv
  '
}

python_versions_preview() {
  local row="$1"
  local display_key status key version path
  IFS=$'\t' read -r display_key status key version path <<<"$row"

  local dir
  if [[ "$status" == "installed" && -n "$path" ]]; then
    dir="${path%/bin/*}"
  else
    dir="${UV_PYTHON_DIR}/${key}"
  fi

  local size="not installed"
  if [[ -d "$dir" ]]; then
    size="$(du -shL "$dir" 2>/dev/null | awk '{print $1}')"
  fi

  printf 'Status: %s\n' "$status"
  printf 'Version: %s\n' "$version"
  printf 'Key: %s\n' "$key"
  printf 'Size: %s\n\n' "$size"

  # Terminal hyperlink (OSC 8), when supported.
  local display_dir="${dir/#$HOME/\~}"
  printf 'Directory: \e]8;;file://%s\e\\%s\e]8;;\e\\\n' "$dir" "$display_dir"
}

if [[ "${1-}" == "--preview" ]]; then
  python_versions_preview "${2-}"
  exit 0
fi

confirm() {
  local header="$1"
  local picked key

  picked="$(printf 'Yes\nNo\n' | fzf \
    --height=10% \
    --layout=reverse \
    --border \
    --no-sort \
    --expect=esc,ctrl-c \
    --header="$header" \
    --prompt='Confirm> ')"

  keypress="$(printf '%s\n' "$picked" | sed -n '1p')"
  if [[ "$keypress" == "ctrl-c" ]]; then
    exit 1
  fi
  if [[ "$keypress" == "esc" ]]; then
    return 1
  fi

  picked="$(printf '%s\n' "$picked" | sed -n '2p')"
  [[ "$picked" == "Yes" ]]
}

python_versions_picker() {
  local rows
  rows="$(python_versions_build_rows)"

  if [[ -z "$rows" ]]; then
    echo "No Python versions returned by uv." >&2
    return 1
  fi

  local selected keypress
  selected="$(
    printf '%s\n' "$rows" | fzf \
      --height=100% \
      --layout=reverse \
      --border \
      --tabstop=1 \
      --delimiter=$'\t' \
      --expect=esc,ctrl-c \
      --with-nth=1 \
      --bind='focus:transform-header:case {2} in installed) echo "Enter: uninstall | Esc: back | Ctrl-C: quit" ;; *) echo "Enter: install | Esc: back | Ctrl-C: quit" ;; esac' \
      --footer='Filters: installed available clear' \
      --footer-border \
      --bind='click-footer:transform:case "$FZF_CLICK_FOOTER_WORD" in installed|available) echo "change-query($FZF_CLICK_FOOTER_WORD)+first" ;; clear) echo "clear-query+first" ;; esac' \
      --preview="$0 --preview {}" \
      --preview-window='right,60%,border-left'
  )"

  keypress="$(printf '%s\n' "$selected" | sed -n '1p')"
  if [[ "$keypress" == "ctrl-c" ]]; then
    exit 1
  fi
  if [[ "$keypress" == "esc" ]]; then
    return 1
  fi
  selected="$(printf '%s\n' "$selected" | sed -n '2p')"

  local _display_key status key version _path
  IFS=$'\t' read -r _display_key status key version _path <<<"$selected"

  local action
  if [[ "$status" == "installed" ]]; then
    action="Uninstall"
  else
    action="Install"
  fi

  if ! confirm "${action} ${key}?"; then
    return 0
  fi

  echo
  if [[ "$status" == "installed" ]]; then
    uv python uninstall --managed-python "$key"
  else
    uv python install --managed-python "$key"
  fi
  echo
  read -r -s -p "Press Enter to continue..."
  echo

  return 0
}

run_python_versions() {
  local rc
  while true; do
    set +e
    python_versions_picker
    rc=$?
    set -e
    case $rc in
      0)
        ;;
      1)
        return 0
        ;;
      *)
        return "$rc"
        ;;
    esac
  done
}

run_uv_cache() {
  echo "TODO: uv cache (inspect, clean)"
}

run_uv_tools() {
  echo "TODO: uv tool (install, uninstall, upgrade)"
}

main_menu() {
  local MENU keypress rc
  MENU="$(printf '%s\n' \
    $'Manage Python versions\trun_python_versions' \
    $'Manage uv cache\trun_uv_cache' \
    $'Manage uv tools\trun_uv_tools' \
  | fzf \
      --height=40% \
      --layout=reverse \
      --border \
      --delimiter=$'\t' \
      --expect=esc,ctrl-c \
      --with-nth=1 \
      --header='uv-fzf | Enter: select | Esc: quit | Ctrl-C: quit'
  )"

  keypress="$(printf '%s\n' "$MENU" | sed -n '1p')"
  if [[ "$keypress" == "ctrl-c" ]]; then
    exit 1
  fi
  if [[ "$keypress" == "esc" ]]; then
    return 1
  fi
  MENU="$(printf '%s\n' "$MENU" | sed -n '2p')"

  local _label action
  IFS=$'\t' read -r _label action <<<"$MENU"
  set +e
  "$action"
  rc=$?
  set -e
  case $rc in
    0)
      return 0
      ;;
    1)
      return 0
      ;;
    *)
      return "$rc"
      ;;
  esac
}

while true; do
  set +e
  main_menu
  rc=$?
  set -e
  case $rc in
    0)
      echo
      ;;
    1)
      break
      ;;
    *)
      exit "$rc"
      ;;
  esac
done
