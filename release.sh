#!/usr/bin/env bash
#
# release.sh - Create per-service GitHub releases based on version.json
#
# Each service gets its own release/tag, formatted as: <service>-v<version>
# e.g. backend-v1.1.0, worker-v1.1.1, etc.
#
# Usage:
#   ./release.sh <service>                # release one service, artifacts taken from ./dist
#   ./release.sh all                      # release every service listed in version.json
#   ./release.sh backend ./build          # use a custom artifact directory
#   ./release.sh backend -- file1 file2   # explicitly specify which files to upload
#
# Optional env vars:
#   VERSION_FILE    default: version.json
#   DIST_DIR        default: dist  (folder to search for artifacts when files aren't given explicitly)
#   CHANGELOG_FILE  default: CHANGELOG.md (release notes are pulled from here, matched by version + component)
#   NOTES_FILE      default: notes.md (fallback if no matching section is found in CHANGELOG)
#   DRY_RUN=1       print commands without executing them
#
# Supported CHANGELOG.md heading formats (the "##" prefix is optional):
#   ## [1.1.1] - Webui
#   [1.2.0] - Updater
# Each section ends at the next heading or at a separator line of "====...".
#
# Requirements: gh CLI (already authenticated), jq

set -euo pipefail

VERSION_FILE="${VERSION_FILE:-version.json}"
DIST_DIR="${DIST_DIR:-build}"
CHANGELOG_FILE="${CHANGELOG_FILE:-CHANGELOG.md}"
DRY_RUN="${DRY_RUN:-0}"

# ---------- helpers ----------
log()  { echo -e "\033[1;34m[release]\033[0m $*"; }
err()  { echo -e "\033[1;31m[error]\033[0m $*" >&2; }
die()  { err "$*"; exit 1; }

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "+ $*"
  else
    "$@"
  fi
}

usage() {
  grep '^#' "$0" | sed -e '1d' -e 's/^# \{0,1\}//'
  exit 1
}

command -v gh >/dev/null 2>&1 || die "gh CLI not found. Install it: https://cli.github.com"
command -v jq >/dev/null 2>&1 || die "jq not found. Install it: apt install jq"
[[ -f "$VERSION_FILE" ]] || die "File $VERSION_FILE not found"

[[ $# -ge 1 ]] || usage

SERVICE_ARG="$1"; shift || true
SERVICE_ARG="${SERVICE_ARG%$'\r'}"   # defend against CRLF line endings (e.g. file edited on Windows)

# ---------- get the list of services from version.json ----------
ALL_SERVICES=$(jq -r 'keys[]' "$VERSION_FILE")

if [[ "$SERVICE_ARG" == "all" ]]; then
  SERVICES="$ALL_SERVICES"
else
  echo "$ALL_SERVICES" | grep -qx "$SERVICE_ARG" || die "Service '$SERVICE_ARG' not found in $VERSION_FILE"
  SERVICES="$SERVICE_ARG"
fi

# ---------- parse remaining args (custom dir / explicit files) ----------
EXPLICIT_FILES=()
CUSTOM_DIR=""

if [[ "${1:-}" == "--" ]]; then
  shift
  EXPLICIT_FILES=("$@")
  EXPLICIT_FILES=("${EXPLICIT_FILES[@]%$'\r'}")
elif [[ $# -ge 1 ]]; then
  CUSTOM_DIR="${1%$'\r'}"
fi

# ---------- extract release notes from CHANGELOG.md by version + component ----------
# Supported headings:
#   ## [1.1.1] - Webui
#   [1.2.0] - Updater
# A section ends at the next heading or at a "====..." separator line.
# Writes the result to $outfile; returns 0 if a non-empty match was found.
extract_changelog_notes() {
  local service="$1" version="$2" outfile="$3"

  [[ -f "$CHANGELOG_FILE" ]] || return 1

  local boundaries
  boundaries=$(grep -nE '^(##[[:space:]]*)?\[[0-9]+\.[0-9]+\.[0-9]+\][[:space:]]*-|^=+$' "$CHANGELOG_FILE") || true
  [[ -n "$boundaries" ]] || return 1

  local -a barr=()
  while IFS= read -r line; do
    barr+=("$line")
  done <<< "$boundaries"

  local total_lines
  total_lines=$(wc -l < "$CHANGELOG_FILE")

  local n=${#barr[@]} i start_line="" end_line=""
  for ((i = 0; i < n; i++)); do
    local entry="${barr[$i]}"
    local lnum="${entry%%:*}"
    local content="${entry#*:}"

    # a "====" separator line is a boundary but not a version heading, skip matching it
    if [[ "$content" =~ ^=+$ ]]; then
      continue
    fi

    if [[ "$content" =~ ^(##[[:space:]]*)?\[([0-9]+\.[0-9]+\.[0-9]+)\][[:space:]]*-[[:space:]]*(.+)$ ]]; then
      local lver="${BASH_REMATCH[2]}"
      local lcomp="${BASH_REMATCH[3]}"
      lcomp="${lcomp%%[[:space:]]}"  # trim one trailing space (good enough for common cases)

      if [[ "$lver" == "$version" && "${lcomp,,}" == "${service,,}" ]]; then
        start_line=$((lnum + 1))
        if ((i + 1 < n)); then
          local next_lnum="${barr[$((i + 1))]%%:*}"
          end_line=$((next_lnum - 1))
        else
          end_line="$total_lines"
        fi
        break
      fi
    fi
  done

  [[ -n "$start_line" ]] || return 1
  ((start_line <= end_line)) || return 1

  # extract the section, then trim leading/trailing blank lines
  sed -n "${start_line},${end_line}p" "$CHANGELOG_FILE" | \
    awk 'NF{lines[++n]=$0; if(first=="")first=NR} {raw[NR]=$0}
         {if($0!="") last=NR}
         END{
           for(j=1;j<=NR;j++){
             if(j<first) continue
             if(j>last) break
             print raw[j]
           }
         }' > "$outfile"

  [[ -s "$outfile" ]]
}

# ---------- process a single service ----------
release_one() {
  local service="$1"
  local version download_url tag

  version=$(jq -r --arg s "$service" '.[$s].version' "$VERSION_FILE")
  download_url=$(jq -r --arg s "$service" '.[$s].download_url // empty' "$VERSION_FILE")

  [[ -n "$version" && "$version" != "null" ]] || die "Version for '$service' not found in $VERSION_FILE"

  tag="${service}-v${version}"

  log "=== $service -> tag: $tag ==="

  # ---- determine which files to upload ----
  local files=()
  if [[ ${#EXPLICIT_FILES[@]} -gt 0 ]]; then
    files=("${EXPLICIT_FILES[@]}")
  else
    local dir="${CUSTOM_DIR:-$DIST_DIR}"
    if [[ -d "$dir" ]]; then
      # look for files matching both service name & version, fall back to just the service name
      while IFS= read -r f; do
        files+=("$f")
      done < <(find "$dir" -maxdepth 1 -type f -iname "*${service}*${version}*" | sort)

      if [[ ${#files[@]} -eq 0 ]]; then
        while IFS= read -r f; do
          files+=("$f")
        done < <(find "$dir" -maxdepth 1 -type f -iname "*${service}*" | sort)
      fi
    fi
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    err "No artifact files found for '$service' (check folder '${CUSTOM_DIR:-$DIST_DIR}' or use '-- file1 file2')"
    if [[ -n "$download_url" ]]; then
      err "Hint: expected filename similar to -> $(basename "$download_url")"
    fi
    return 1
  fi

  log "Files to be uploaded:"
  printf '  - %s\n' "${files[@]}"

  # ---- release notes ----
  local notes_arg=() generated_notes=""
  generated_notes=$(mktemp)

  if extract_changelog_notes "$service" "$version" "$generated_notes"; then
    log "Notes pulled from $CHANGELOG_FILE (section [$version] - $service)"
    notes_arg=(-F "$generated_notes")
  elif [[ -f "$NOTES_FILE" ]]; then
    log "No matching section in $CHANGELOG_FILE, falling back to $NOTES_FILE"
    rm -f "$generated_notes"
    notes_arg=(-F "$NOTES_FILE")
  else
    err "Section [$version] - $service not found in $CHANGELOG_FILE, and $NOTES_FILE doesn't exist either. Using default notes."
    rm -f "$generated_notes"
    notes_arg=(--notes "Release ${service} v${version}")
  fi

  # ---- skip if the tag already exists ----
  if gh release view "$tag" >/dev/null 2>&1; then
    err "Release '$tag' already exists, skipping. Delete it first to replace: gh release delete $tag"
    [[ -f "$generated_notes" ]] && rm -f "$generated_notes"
    return 1
  fi

  run gh release create "$tag" "${files[@]}" --title "$tag" "${notes_arg[@]}"

  [[ -f "$generated_notes" ]] && rm -f "$generated_notes"
  log "Done: $tag"
}

FAILED=0
for s in $SERVICES; do
  if ! release_one "$s"; then
    FAILED=1
  fi
  echo
done

[[ "$FAILED" -eq 0 ]] || die "Some releases failed, check the log above."
log "All releases created successfully 🎉"