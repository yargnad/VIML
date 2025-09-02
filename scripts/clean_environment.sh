#!/usr/bin/env bash
set -euo pipefail

# Safe environment cleanup script
# Removes common local build and venv artefacts under $HOME
# Logs actions to ~/.cleanup_logs/clean_env_YYYYMMDD_HHMMSS.log

LOG_DIR="$HOME/.cleanup_logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/clean_env_${TIMESTAMP}.log"

DRY_RUN=0
ASSUME_YES=0

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [--yes]

Options:
  --dry-run   Show what would be removed but do not delete anything.
  --yes       Proceed without interactive confirmation.
  --help      Show this help message.

This script only removes files and directories under your home directory.
It will refuse to run if a target is outside of HOME for safety.
EOF
}

log() {
    mkdir -p "$LOG_DIR"
    echo "$(date -Is) $*" | tee -a "$LOG_FILE"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            --yes) ASSUME_YES=1; shift ;;
            --help) usage; exit 0 ;;
            *) echo "Unknown arg: $1"; usage; exit 2 ;;
        esac
    done
}

ensure_under_home() {
    # Ensure absolute path and is under $HOME
    local p="$1"
    case "$p" in
        "$HOME"/*) return 0 ;;
        "$HOME") return 0 ;;
        *) return 1 ;;
    esac
}

confirm() {
    if [ "$ASSUME_YES" -eq 1 ]; then
        return 0
    fi
    read -r -p "$1 [y/N]: " ans
    case "$ans" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

main() {
    parse_args "$@"

    log "Starting cleanup (dry-run=$DRY_RUN)."

    # Candidate targets (safe defaults under HOME)
    TARGETS=(
        "$HOME/source_builds"
        "$HOME/.venv"
        "$HOME/venv"
        "$HOME/VIML/venv"
        "$HOME/VIML/.venv"
        "$HOME/.cache/pip"
        "$HOME/.cache/torch"
        "$HOME/.cache/huggingface"
        "$HOME/.cache/viml_build"
    )

    # Extra patterns (backups, build dirs inside repo)
    EXTRA_PATTERNS=(
        "$HOME/VIML"/Python-* 
        "$HOME/VIML"/ffmpeg-* 
        "$HOME/VIML"/*.egg-info
        "$HOME/VIML"/*.pyc
        "$HOME/VIML"/*.bak
        "$HOME/VIML"/*~
    )

    # Flatten list and dedupe
    TO_REMOVE=()
    for t in "${TARGETS[@]}"; do
        TO_REMOVE+=("$t")
    done
    for p in "${EXTRA_PATTERNS[@]}"; do
        for match in $p; do
            [ -e "$match" ] || continue
            TO_REMOVE+=("$match")
        done
    done

    if [ ${#TO_REMOVE[@]} -eq 0 ]; then
        log "No targets found to remove. Exiting."
        return 0
    fi

    log "Planned removals:" 
    for item in "${TO_REMOVE[@]}"; do
        log "  $item"
    done

    if [ "$DRY_RUN" -eq 1 ]; then
        log "Dry run complete. No files were removed."
        return 0
    fi

    if ! confirm "Proceed to remove the above items permanently?"; then
        log "User cancelled. No changes made."
        return 0
    fi

    # Perform removals, escalate to sudo for root-owned files if needed
    for item in "${TO_REMOVE[@]}"; do
        if [ -z "$item" ]; then
            continue
        fi
        if ! ensure_under_home "$item"; then
            log "Refusing to remove '$item' because it's outside HOME"
            continue
        fi
        if [ ! -e "$item" ]; then
            log "Not found: $item"
            continue
        fi
        # If the file is owned by root or not writable, use sudo after prompting
        owner_uid=$(stat -c %u "$item")
        if [ "$owner_uid" -ne "$(id -u)" ]; then
            log "Item $item is not owned by current user (uid=$owner_uid). Will use sudo to remove."
            if confirm "Use sudo to remove $item?"; then
                log "Running: sudo rm -rf -- '$item'"
                sudo rm -rf -- "$item" 2>&1 | tee -a "$LOG_FILE"
                log "Removed (sudo): $item"
            else
                log "Skipped (no sudo): $item"
            fi
        else
            log "Removing: $item"
            rm -rf -- "$item" 2>&1 | tee -a "$LOG_FILE" || log "Failed to remove: $item"
            log "Removed: $item"
        fi
    done

    log "Cleanup finished."
}

main "$@"
#!/usr/bin/env bash
set -euo pipefail

# clean_environment.sh
# Interactive helper to remove project virtualenvs and build artifacts so you can start fresh.
# Usage: ./scripts/clean_environment.sh [--yes] [--dry-run] [--project DIR] [--build DIR]

DRY_RUN=0
AUTO_YES=0
PROJECT_DIR="${HOME}/VIML"
BUILD_DIR="${HOME}/source_builds"

# Logging setup: timestamped logfile under the project
LOG_DIR="${PROJECT_DIR}/.cleanup_logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/clean_env_$(date +%Y%m%d_%H%M%S).log"

log() {
  # Timestamped log line to stdout and logfile
  printf "%s %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

usage() {
  cat <<EOF
Usage: $0 [--yes] [--dry-run] [--project DIR] [--build DIR]

Options:
  --yes        Don't prompt, proceed with destructive actions where safe.
  --dry-run    Show what would be removed but don't delete anything.
  --project    Project root (default: ${HOME}/VIML)
  --build      Build directory to clean (default: ${HOME}/source_builds)
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes) AUTO_YES=1; shift ;;
    --project) PROJECT_DIR="$2"; shift 2 ;;
    --build) BUILD_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

# Safety checks: require paths to be under $HOME to avoid accidental system deletes
is_under_home() {
  local p
  p="$(realpath -s "$1")"
  case "${p}" in
    "${HOME}"/*) return 0 ;;
    "${HOME}") return 0 ;;
    *) return 1 ;;
  esac
}

if ! is_under_home "$PROJECT_DIR"; then
  echo "Refusing to operate on project dir outside HOME: $PROJECT_DIR"
  exit 2
fi
if ! is_under_home "$BUILD_DIR"; then
  echo "Refusing to operate on build dir outside HOME: $BUILD_DIR"
  exit 2
fi

log "Project: $PROJECT_DIR"
log "Build dir: $BUILD_DIR"

# Items planned for removal
declare -a TO_REMOVE
TO_REMOVE+=("$PROJECT_DIR/venv" "$PROJECT_DIR/.venv" "$PROJECT_DIR/uploads" "$PROJECT_DIR/generated")

log ""
log "Planned destructive actions (safe):"
for p in "${TO_REMOVE[@]}"; do
  if [ -e "$p" ]; then
  du -sh "$p" 2>/dev/null | tee -a "$LOG_FILE" || true
  log "  -> $p"
  else
  log "  (not present) $p"
  fi
done

echo
if [ -d "$BUILD_DIR" ]; then
  log "Will remove user-owned items under: $BUILD_DIR"
  log "Example listing (maxdepth 2):"
  find "$BUILD_DIR" -maxdepth 2 -user "$USER" -ls | sed -n '1,10p' | tee -a "$LOG_FILE" || true
else
  log "Build dir not present: $BUILD_DIR"
fi

if [ $DRY_RUN -eq 1 ]; then
  log "Dry-run enabled: no changes will be made. Exiting."
  log "Log file created: $LOG_FILE"
  exit 0
fi

confirm() {
  if [ $AUTO_YES -eq 1 ]; then
    return 0
  fi
  read -r -p "$1 [y/N]: " ans
  case "${ans}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# 1) Remove project venvs and generated dirs (no sudo)
if confirm "Remove project venvs and generated/upload dirs?"; then
  for p in "${TO_REMOVE[@]}"; do
    if [ -e "$p" ]; then
      log "Removing $p"
      if rm -rf "$p" 2>&1 | tee -a "$LOG_FILE"; then
        log "Removed $p"
      else
        log "Failed to remove $p (will continue)"
      fi
    fi
  done
else
  log "Skipping project cleanup"
fi

# 2) Remove user-owned items inside build dir (no sudo)
if [ -d "$BUILD_DIR" ]; then
  if confirm "Remove user-owned items under $BUILD_DIR? (safe, no sudo)"; then
    log "Finding and removing user-owned items under $BUILD_DIR (depth 3)"
    # Capture list then remove each, logging output
    find "$BUILD_DIR" -maxdepth 3 -user "$USER" -print | tee -a "$LOG_FILE" || true
    while IFS= read -r p; do
      log "Removing: $p"
      if rm -rf "$p" 2>&1 | tee -a "$LOG_FILE"; then
        log "Removed: $p"
      else
        log "Failed to remove: $p"
      fi
    done < <(find "$BUILD_DIR" -maxdepth 3 -user "$USER" -print)
    log "Done removing user-owned items."
  else
    echo "Skipping user-owned removals under $BUILD_DIR"
  fi
fi

# 3) Check for remaining items that may require sudo
if [ -d "$BUILD_DIR" ]; then
  log ""
  log "Remaining items in $BUILD_DIR (owner summary):"
  find "$BUILD_DIR" -maxdepth 1 -ls | tee -a "$LOG_FILE" || true
  log ""
  find "$BUILD_DIR" -maxdepth 2 -printf "%u %p\n" | sort | uniq -c | tee -a "$LOG_FILE" || true

  if confirm "Attempt sudo removal of $BUILD_DIR (will remove entire directory)?"; then
    log "You will be prompted for your password by sudo. Proceeding..."
    if [ $AUTO_YES -eq 1 ]; then
      log "Running with --yes: sudo removal will run non-interactively"
    fi
    # Remove immutable flags if present then remove
    log "Running: sudo chattr -R -i $BUILD_DIR"
    sudo chattr -R -i "$BUILD_DIR" 2>&1 | tee -a "$LOG_FILE" || true
    log "Running: sudo rm -rf $BUILD_DIR"
    sudo rm -rf "$BUILD_DIR" 2>&1 | tee -a "$LOG_FILE" || true
    log "Sudo removal complete."
  else
    log "Skipping sudo removal. You can remove remaining files manually or re-run this script with --yes to automate."
  fi
else
  log "No build dir to check: $BUILD_DIR"
fi

# Final summary
log ""
log "Final state check:"
if [ -d "$BUILD_DIR" ]; then
  log "$BUILD_DIR exists:"
  find "$BUILD_DIR" -maxdepth 1 -ls | tee -a "$LOG_FILE" || true
else
  log "$BUILD_DIR removed or not present"
fi

log "Cleanup finished. If you want to completely reset, re-run any build scripts from your project to recreate needed files."
log "Log file saved: $LOG_FILE"

exit 0
