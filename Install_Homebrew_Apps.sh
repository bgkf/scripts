#!/bin/bash
#
# dev tooling provisioning (Jamf policy script)
# ARM64 (Apple Silicon) only.
#
# Design notes:
#   - No `set -e`: we want every package attempted and every failure
#     recorded, not a hard stop on the first bad install.
#   - `-H` on every sudo -u call so $HOME resolves to the logged-in
#     user's home dir, not root's. brew/npm/nvm all cache under $HOME;
#     skipping -H is a classic source of PermissionError/path bugs.

LOGGED_IN_USER=$(stat -f%Su /dev/console)
BREW_PATH="/opt/homebrew/bin/brew"
VERSIONS_MANIFEST="/usr/local/etc/dev-tooling-versions.json"

FAILED=()

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

run_as_user() {
  sudo -u "$LOGGED_IN_USER" -H "$@"
}

install_formula() {
  local formula="$1"
  log "Installing formula: $formula"
  if ! run_as_user "$BREW_PATH" install "$formula"; then
    log "FAILED: $formula"
    FAILED+=("$formula")
  fi
}

install_cask() {
  local cask="$1"
  log "Installing cask: $cask"
  if ! run_as_user "$BREW_PATH" install --cask "$cask"; then
    log "FAILED (cask): $cask"
    FAILED+=("$cask")
  fi
}

# ---------------------------------------------------------------------------
# Floating packages — brew upgrade keeps these current, no version pin needed.
# ---------------------------------------------------------------------------
FLOATING_FORMULAE=(
  git
  awscli
  redis
  kubernetes-cli
  helm
  vim
  gh
  black
  gnupg
  dopplerhq/cli/doppler
  # docker-compose intentionally NOT installed here: engineers are on Docker
  # Desktop, which already bundles `docker compose` as a CLI plugin and
  # updates it on its own cadence. A standalone brew docker-compose formula
  # would be a second, independently-drifting binary that also wouldn't
  # show up in the same place as the one Desktop actually runs -- if you
  # ever need it back, confirm first whether anything still invokes the
  # legacy hyphenated `docker-compose` syntax specifically.
)

FLOATING_CASKS=(
  ngrok
  claude-code
)

for f in "${FLOATING_FORMULAE[@]}"; do
  install_formula "$f"
done

for c in "${FLOATING_CASKS[@]}"; do
  install_cask "$c"
done

# ---------------------------------------------------------------------------
# Version-locked packages.
#
# Homebrew doesn't support patch-level pins for node (only rolling majors
# like node@16, dropped entirely once EOL) — so pinning here goes through
# nvm instead, which keeps every historical release regardless of Homebrew's
# lifecycle. Do not add a floating `npm` brew formula anywhere above; it
# pulls in a second, different Node as a dependency and will silently
# fight with the pin below over what's on PATH.
#
# Any version change here should come with an updated reason/review_by in
# the manifest below, not a silent bump.
# ---------------------------------------------------------------------------
NODE_PIN_VERSION="16.9.1"
NPM_PIN_VERSION="7.24.0"

install_formula nvm

log "Installing pinned node ${NODE_PIN_VERSION} + npm ${NPM_PIN_VERSION} via nvm"
if ! run_as_user env \
      NODE_VERSION="$NODE_PIN_VERSION" \
      NPM_VERSION="$NPM_PIN_VERSION" \
      BREW_PATH="$BREW_PATH" \
      bash <<'SCRIPT'
set -e
export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"
NVM_PREFIX="$("$BREW_PATH" --prefix nvm)"
[ -s "$NVM_PREFIX/nvm.sh" ] && . "$NVM_PREFIX/nvm.sh"
nvm install "$NODE_VERSION"
nvm alias default "$NODE_VERSION"
npm install -g "npm@$NPM_VERSION"

# nvm never touches /opt/homebrew -- it keeps every version isolated under
# $NVM_DIR/versions/node/. That's correct behavior, but it also means node
# and npm aren't on PATH for anything that doesn't source nvm.sh (which the
# brew nvm formula does NOT set up in your shell profile automatically).
# Symlink into /opt/homebrew/bin instead of touching shell profiles: it's
# already proven to be on PATH (every other formula in this script resolves
# from there), and it works identically for interactive shells, scripts,
# and Self Service tooling without any per-shell (zsh/bash/fish) handling.
NODE_BIN_DIR="$NVM_DIR/versions/node/v$NODE_VERSION/bin"
ln -sf "$NODE_BIN_DIR/node" /opt/homebrew/bin/node
ln -sf "$NODE_BIN_DIR/npm" /opt/homebrew/bin/npm
ln -sf "$NODE_BIN_DIR/npx" /opt/homebrew/bin/npx
echo "Linked: $(/opt/homebrew/bin/node -v) / npm $(/opt/homebrew/bin/npm -v)"
SCRIPT
then
  log "FAILED: pinned node/npm install"
  FAILED+=("node@${NODE_PIN_VERSION}" "npm@${NPM_PIN_VERSION}")
fi

# claude-code via `npm install -g @anthropic-ai/claude-code` hits PATH
# issues when Node is nvm-managed rather than symlinked by brew; the
# claude-code cask above is the supported install path for now.
# sudo -u "$LOGGED_IN_USER" npm install -g @anthropic-ai/claude-code

# ---------------------------------------------------------------------------
# Manifest of intended pinned versions, for drift-check / CVE-watch tooling
# to diff against what's actually installed.
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$VERSIONS_MANIFEST")"
cat > "$VERSIONS_MANIFEST" <<EOF
{
  "node": {
    "approved_version": "${NODE_PIN_VERSION}",
    "reason": "TODO: document compatibility reason",
    "review_by": "TODO: set review date"
  },
  "npm": {
    "approved_version": "${NPM_PIN_VERSION}",
    "reason": "TODO: document compatibility reason",
    "review_by": "TODO: set review date"
  }
}
EOF

# ---------------------------------------------------------------------------
# Summary — surfaces in the Jamf policy log
# ---------------------------------------------------------------------------
if [ ${#FAILED[@]} -eq 0 ]; then
  log "All installs completed successfully."
  exit 0
else
  log "The following installs failed: ${FAILED[*]}"
  exit 1
fi