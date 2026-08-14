#!/bin/bash
set -euo pipefail

# ── Desktop App Review ──────────────────────────────────────────────
# Inspects a macOS .app, .dmg, .zip, .pkg, or standalone binary for
# signing, notarization, hardened runtime, entitlements, frameworks,
# helpers, and Electron fuses.
#
# Usage:
#   app-review.sh <path> [flags]
#
# Flags:
#   --name <name>         App name (inferred from filename if omitted)
#   --txt                 Write review to a .txt file (default)
#   --gdoc                Upload to Google Drive via GAM as a Google Doc
#   --linear              Create a Linear issue (requires --linear-api-key or LINEAR_API_KEY env)
#   --linear-api-key <k>  Linear API key
#   --linear-team-id <id> Linear team ID (default: from LINEAR_TEAM_ID env)
#   --linear-project <id> Linear project ID (default: from LINEAR_PROJECT_ID env)
#   --gam-user <email>    GAM user for Drive upload (default: from GAM_USER env)
#   --gdoc-folder-id <id> Google Drive folder ID (default: from GDOC_FOLDER_ID env)
#   --source <src>        Installer source: "appstore", "internet", or a URL/description.
#                         If omitted, auto-detected from MAS receipt and quarantine xattr.
#   --output-dir <dir>    Directory for .txt output (default: current directory)
#   -h, --help            Show this help
# ────────────────────────────────────────────────────────────────────

GAM_CMD="${GAM_CMD:-gam}"
GDOC_FOLDER_ID="${GDOC_FOLDER_ID:-1uiJLMq_eyM-dFk7xD_0e20GQIny2YMU4}"
GAM_USER="${GAM_USER:-}"
LINEAR_API_KEY="${LINEAR_API_KEY:-}"
LINEAR_TEAM_ID="${LINEAR_TEAM_ID:-}"
LINEAR_PROJECT_ID="${LINEAR_PROJECT_ID:-}"
OUTPUT_DIR="."
APP_NAME=""
SOURCE_OVERRIDE=""
DO_TXT=false
DO_GDOC=false
DO_LINEAR=false
CLEANUP_PATHS=()

usage() {
    sed -n '/^# Usage:/,/^# ─/p' "$0" | sed 's/^# \?//'
    exit 0
}

cleanup() {
    for p in "${CLEANUP_PATHS[@]}"; do
        if [[ "$p" == /Volumes/* ]]; then
            hdiutil detach "$p" -quiet 2>/dev/null || true
        elif [[ -d "$p" ]]; then
            rm -rf "$p"
        fi
    done
}
trap cleanup EXIT

die() { echo "ERROR: $*" >&2; exit 1; }

# ── Parse arguments ────────────────────────────────────────────────

[[ $# -eq 0 ]] && usage

INPUT_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)       APP_NAME="$2"; shift 2 ;;
        --source)     SOURCE_OVERRIDE="$2"; shift 2 ;;
        --txt)        DO_TXT=true; shift ;;
        --gdoc)       DO_GDOC=true; shift ;;
        --linear)     DO_LINEAR=true; shift ;;
        --linear-api-key)  LINEAR_API_KEY="$2"; shift 2 ;;
        --linear-team-id)  LINEAR_TEAM_ID="$2"; shift 2 ;;
        --linear-project)  LINEAR_PROJECT_ID="$2"; shift 2 ;;
        --gam-user)        GAM_USER="$2"; shift 2 ;;
        --gdoc-folder-id)  GDOC_FOLDER_ID="$2"; shift 2 ;;
        --output-dir)      OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)    usage ;;
        -*)           die "Unknown flag: $1" ;;
        *)            INPUT_PATH="$1"; shift ;;
    esac
done

[[ -z "$INPUT_PATH" ]] && die "No input path provided."
[[ -e "$INPUT_PATH" ]] || die "Path does not exist: $INPUT_PATH"

if ! $DO_TXT && ! $DO_GDOC && ! $DO_LINEAR; then
    DO_TXT=true
fi

if $DO_GDOC && [[ -z "$GAM_USER" ]]; then
    die "--gdoc requires --gam-user <email> or GAM_USER env var."
fi

if $DO_LINEAR && [[ -z "$LINEAR_API_KEY" ]]; then
    die "--linear requires --linear-api-key <key> or LINEAR_API_KEY env var."
fi

if $DO_LINEAR && [[ -z "$LINEAR_TEAM_ID" ]]; then
    die "--linear requires --linear-team-id <id> or LINEAR_TEAM_ID env var."
fi

# ── Step 1: Prepare the target ─────────────────────────────────────

APP_PATH=""
IS_STANDALONE=false
PKG_BUNDLE_ID=""
PKG_VERSION=""
PKG_SIGNED_INFO=""
PKG_NOTARIZED_INFO=""
PKG_STAPLER_INFO=""
PKG_INSTALL_LOCATION=""
PKG_PAYLOAD_FILES=""

resolve_app_name() {
    if [[ -n "$APP_NAME" ]]; then return; fi
    if [[ -n "$APP_PATH" ]]; then
        APP_NAME=$(basename "$APP_PATH" .app)
    else
        APP_NAME=$(basename "$INPUT_PATH" | sed -E 's/\.(dmg|zip|pkg|app)$//' | sed -E 's/-[0-9].*//')
    fi
}

EXT="${INPUT_PATH##*.}"
case "$EXT" in
    app)
        APP_PATH="$INPUT_PATH"
        ;;
    dmg)
        echo "Mounting DMG..."
        MOUNT_OUTPUT=$(hdiutil attach "$INPUT_PATH" -nobrowse -readonly 2>&1)
        MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep -o '/Volumes/.*' | head -1)
        [[ -z "$MOUNT_POINT" ]] && die "Failed to mount DMG."
        CLEANUP_PATHS+=("$MOUNT_POINT")
        APP_PATH=$(find "$MOUNT_POINT" -maxdepth 3 -name "*.app" -type d 2>/dev/null | head -1)
        [[ -z "$APP_PATH" ]] && die "No .app found in DMG."
        ;;
    zip)
        echo "Extracting ZIP..."
        TMPDIR_ZIP=$(mktemp -d)
        CLEANUP_PATHS+=("$TMPDIR_ZIP")
        unzip -q "$INPUT_PATH" -d "$TMPDIR_ZIP"
        APP_PATH=$(find "$TMPDIR_ZIP" -maxdepth 3 -name "*.app" -type d -not -path "*/__MACOSX/*" 2>/dev/null | head -1)
        if [[ -z "$APP_PATH" ]]; then
            STANDALONE_BIN=$(find "$TMPDIR_ZIP" -maxdepth 3 -type f -perm +111 -not -path "*/__MACOSX/*" 2>/dev/null | head -1)
            if [[ -n "$STANDALONE_BIN" ]]; then
                APP_PATH=""
                IS_STANDALONE=true
                BINARY="$STANDALONE_BIN"
            else
                die "No .app or executable found in ZIP."
            fi
        fi
        ;;
    pkg)
        echo "Expanding PKG..."
        TMPDIR_PKG=$(mktemp -d)
        CLEANUP_PATHS+=("$TMPDIR_PKG")
        pkgutil --expand "$INPUT_PATH" "$TMPDIR_PKG/pkg_expanded" 2>/dev/null || die "Failed to expand PKG."

        if [[ -f "$TMPDIR_PKG/pkg_expanded/PackageInfo" ]]; then
            PKG_BUNDLE_ID=$(sed -n 's/.*identifier="\([^"]*\)".*/\1/p' "$TMPDIR_PKG/pkg_expanded/PackageInfo")
            PKG_VERSION=$(sed -n 's/.*<pkg-info.*[[:space:]]version="\([^"]*\)".*/\1/p' "$TMPDIR_PKG/pkg_expanded/PackageInfo" | head -1)
            PKG_INSTALL_LOCATION=$(sed -n 's/.*install-location="\([^"]*\)".*/\1/p' "$TMPDIR_PKG/pkg_expanded/PackageInfo")
        fi

        if [[ -f "$TMPDIR_PKG/pkg_expanded/Bom" ]]; then
            PKG_PAYLOAD_FILES=$(lsbom "$TMPDIR_PKG/pkg_expanded/Bom" 2>/dev/null | awk '{print $1}')
        fi

        PKG_SIGNED_INFO=$(pkgutil --check-signature "$INPUT_PATH" 2>&1 || true)
        PKG_NOTARIZED_INFO=$(spctl --assess --type install -vv "$INPUT_PATH" 2>&1 || true)
        PKG_STAPLER_INFO=$(stapler validate "$INPUT_PATH" 2>&1 || true)

        if [[ -f "$TMPDIR_PKG/pkg_expanded/Payload" ]]; then
            EXTRACT_DIR=$(mktemp -d)
            CLEANUP_PATHS+=("$EXTRACT_DIR")
            (cd "$EXTRACT_DIR" && cat "$TMPDIR_PKG/pkg_expanded/Payload" | cpio -id 2>/dev/null)

            APP_PATH=$(find "$EXTRACT_DIR" -maxdepth 4 -name "*.app" -type d 2>/dev/null | head -1)
            if [[ -z "$APP_PATH" ]]; then
                STANDALONE_BIN=$(find "$EXTRACT_DIR" -maxdepth 5 -type f -perm +111 ! -name ".*" 2>/dev/null | head -1)
                if [[ -n "$STANDALONE_BIN" ]]; then
                    IS_STANDALONE=true
                    BINARY="$STANDALONE_BIN"
                else
                    die "No .app or executable found in PKG payload."
                fi
            fi
        else
            die "No Payload found in PKG."
        fi
        ;;
    *)
        if file "$INPUT_PATH" | grep -q "Mach-O"; then
            IS_STANDALONE=true
            BINARY="$INPUT_PATH"
        else
            die "Unsupported file type: $EXT"
        fi
        ;;
esac

resolve_app_name

# ── Bootstrapper detection ─────────────────────────────────────────

detect_bootstrapper() {
    if $IS_STANDALONE; then return 1; fi
    [[ -z "$APP_PATH" ]] && return 1

    local bid
    bid=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true)
    local app_name_lower
    app_name_lower=$(basename "$APP_PATH" .app | tr '[:upper:]' '[:lower:]')

    local is_bootstrapper=false

    if echo "$bid" | grep -qiE '\.installer$|\.bootstrap$|\.updater$|\.setup$'; then
        is_bootstrapper=true
    fi
    if echo "$app_name_lower" | grep -qiE 'installer|setup|bootstrap'; then
        is_bootstrapper=true
    fi

    # Check if the app has no frameworks and a very small binary — typical of stub installers
    if $is_bootstrapper; then
        local fw_count=0
        if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
            fw_count=$(ls "$APP_PATH/Contents/Frameworks/" 2>/dev/null | wc -l | tr -d ' ')
        fi
        local has_resources=false
        if [[ -d "$APP_PATH/Contents/Resources" ]]; then
            local res_count
            res_count=$(find "$APP_PATH/Contents/Resources" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
            if [[ "$res_count" -gt 5 ]]; then
                has_resources=true
            fi
        fi

        echo ""
        echo "WARNING: This appears to be a bootstrapper/installer app, not the actual application."
        echo "  App:      $(basename "$APP_PATH")"
        echo "  BundleID: ${bid:-unknown}"
        echo "  Frameworks: ${fw_count}"
        echo ""
        echo "This installer downloads and installs the real application at runtime."
        echo "To review the actual app, install it first, then run this script against"
        echo "the installed .app bundle (likely in /Applications/)."
        echo ""
        return 0
    fi

    return 1
}

if detect_bootstrapper; then
    exit 0
fi

# ── Step 2: Collect data ───────────────────────────────────────────

QUARANTINE_SOURCE_URL=""
QUARANTINE_RAW=""

detect_installer_source() {
    # 1. Explicit override wins
    if [[ -n "$SOURCE_OVERRIDE" ]]; then
        local source_lower
        source_lower=$(echo "$SOURCE_OVERRIDE" | tr '[:upper:]' '[:lower:]')
        case "$source_lower" in
            appstore|"app store"|mas)
                INSTALLER_SOURCE="App Store"
                return ;;
            internet)
                INSTALLER_SOURCE="Internet"
                return ;;
            *)
                INSTALLER_SOURCE="Internet"
                INSTALLER_SOURCE_NOTES="Source: ${SOURCE_OVERRIDE}"
                return ;;
        esac
    fi

    # 2. Check MAS receipt (only for .app bundles)
    if [[ -n "$APP_PATH" ]] && ! $IS_STANDALONE; then
        if [[ -d "$APP_PATH/Contents/_MASReceipt" ]]; then
            INSTALLER_SOURCE="App Store"
            return
        fi
    fi

    # 3. Check quarantine extended attribute on the original input file
    QUARANTINE_RAW=$(xattr -p com.apple.quarantine "$INPUT_PATH" 2>/dev/null || true)
    if [[ -n "$QUARANTINE_RAW" ]]; then
        # Format: flags;timestamp;agent_name;UUID
        # or:    flags;timestamp;agent_name;UUID|source_url
        local agent_name
        agent_name=$(echo "$QUARANTINE_RAW" | cut -d';' -f3 | cut -d'|' -f1)
        QUARANTINE_SOURCE_URL=$(echo "$QUARANTINE_RAW" | grep -oE 'https?://[^ ;]+' || true)

        if [[ "$agent_name" == "com.apple.appstore" || "$agent_name" == "com.apple.AppStore" ]]; then
            INSTALLER_SOURCE="App Store"
            return
        fi

        INSTALLER_SOURCE="Internet"
        if [[ -n "$QUARANTINE_SOURCE_URL" ]]; then
            INSTALLER_SOURCE_NOTES="Downloaded from: ${QUARANTINE_SOURCE_URL}"
        elif [[ -n "$agent_name" ]]; then
            INSTALLER_SOURCE_NOTES="Downloaded via: ${agent_name}"
        fi
        return
    fi

    # 4. Also check quarantine on the .app if we extracted from a container
    if [[ -n "$APP_PATH" ]] && [[ "$APP_PATH" != "$INPUT_PATH" ]]; then
        local app_quarantine
        app_quarantine=$(xattr -p com.apple.quarantine "$APP_PATH" 2>/dev/null || true)
        if [[ -n "$app_quarantine" ]]; then
            local agent_name
            agent_name=$(echo "$app_quarantine" | cut -d';' -f3 | cut -d'|' -f1)
            QUARANTINE_SOURCE_URL=$(echo "$app_quarantine" | grep -oE 'https?://[^ ;]+' || true)

            if [[ "$agent_name" == "com.apple.appstore" || "$agent_name" == "com.apple.AppStore" ]]; then
                INSTALLER_SOURCE="App Store"
                return
            fi

            if [[ -n "$QUARANTINE_SOURCE_URL" ]]; then
                INSTALLER_SOURCE_NOTES="Downloaded from: ${QUARANTINE_SOURCE_URL}"
            elif [[ -n "$agent_name" ]]; then
                INSTALLER_SOURCE_NOTES="Downloaded via: ${agent_name}"
            fi
        fi
    fi

    INSTALLER_SOURCE="Internet"
}

INSTALLER_SOURCE_NOTES=""

detect_installer_source

BUNDLE_ID=""
VERSION=""
TEAM_ID=""
BINARY_PATH=""
IS_SIGNED=""
IS_NOTARIZED=""
HAS_HARDENED_RUNTIME=""
IS_SANDBOXED=""
ENTITLEMENTS_LIST=""
FRAMEWORKS_LIST=""
HELPERS_LIST=""
ELECTRON_FUSES=""
FILE_TYPE_INFO=""

declare -a HELPER_NAMES=()
declare -a HELPER_SIGNED=()
declare -a HELPER_NOTARIZED=()
declare -a HELPER_HARDENED=()
declare -a HELPER_SANDBOXED=()
declare -a HELPER_ENTITLEMENTS=()

check_binary() {
    local bin="$1"
    local signed notarized hardened sandboxed ents

    if codesign -v "$bin" 2>/dev/null; then
        signed="Yes"
    else
        signed="No"
    fi

    local spctl_out
    spctl_out=$(spctl --assess --type exec -vv "$bin" 2>&1 || true)
    if echo "$spctl_out" | grep -q "accepted"; then
        notarized="Yes"
    else
        notarized="No"
    fi

    local flags
    flags=$(codesign -d --verbose=2 "$bin" 2>&1 | grep "flags=" || true)
    if echo "$flags" | grep -q "runtime"; then
        hardened="Yes"
    else
        hardened="No"
    fi

    local ents_raw
    ents_raw=$(codesign --display --entitlements :- "$bin" 2>&1 || true)
    if echo "$ents_raw" | grep -q "com.apple.security.app-sandbox"; then
        sandboxed="Yes"
    else
        sandboxed="No"
    fi

    ents=""
    if echo "$ents_raw" | grep -q "com.apple.security"; then
        ents=$(echo "$ents_raw" | grep -oE 'com\.apple\.security\.[a-zA-Z0-9._-]+' | sort -u)
    fi

    echo "$signed|$notarized|$hardened|$sandboxed|$ents"
}

if $IS_STANDALONE; then
    BINARY_PATH="$BINARY"
    FILE_TYPE_INFO=$(file "$BINARY" 2>/dev/null | head -1)

    if [[ -n "$PKG_BUNDLE_ID" ]]; then
        BUNDLE_ID="$PKG_BUNDLE_ID"
    fi
    if [[ -n "$PKG_VERSION" ]]; then
        VERSION="$PKG_VERSION"
    fi

    CODESIGN_VERBOSE=$(codesign -dv --verbose=4 "$BINARY" 2>&1 || true)
    TEAM_ID=$(echo "$CODESIGN_VERBOSE" | grep "TeamIdentifier=" | sed 's/TeamIdentifier=//')

    IFS='|' read -r IS_SIGNED IS_NOTARIZED HAS_HARDENED_RUNTIME IS_SANDBOXED ENTITLEMENTS_LIST <<< "$(check_binary "$BINARY")"

    if [[ "$IS_NOTARIZED" == "No" && "$EXT" == "pkg" ]]; then
        if echo "$PKG_NOTARIZED_INFO" | grep -q "accepted"; then
            IS_NOTARIZED="Yes (pkg installer is notarized; spctl does not assess standalone binaries)"
        fi
    fi
else
    BUNDLE_ID=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "unknown")
    VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || \
              defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "unknown")
    CODESIGN_VERBOSE=$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)
    TEAM_ID=$(echo "$CODESIGN_VERBOSE" | grep "TeamIdentifier=" | sed 's/TeamIdentifier=//')

    EXEC_NAME=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleExecutable 2>/dev/null || echo "")
    if [[ -n "$EXEC_NAME" ]]; then
        BINARY="$APP_PATH/Contents/MacOS/$EXEC_NAME"
    else
        BINARY=$(find "$APP_PATH/Contents/MacOS" -maxdepth 1 -type f -perm +111 2>/dev/null | head -1)
    fi
    BINARY_PATH="$BINARY"
    FILE_TYPE_INFO=$(file "$BINARY" 2>/dev/null | head -1)

    IFS='|' read -r IS_SIGNED IS_NOTARIZED HAS_HARDENED_RUNTIME IS_SANDBOXED ENTITLEMENTS_LIST <<< "$(check_binary "$BINARY")"

    # Frameworks
    if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
        FRAMEWORKS_LIST=$(ls "$APP_PATH/Contents/Frameworks/" 2>/dev/null | sort)
    fi

    # Electron fuses
    if echo "$FRAMEWORKS_LIST" | grep -q "Electron Framework"; then
        echo "Checking Electron fuses..."
        ELECTRON_FUSES=$(npx --yes @electron/fuses read --app "$APP_PATH" 2>/dev/null || echo "Could not read Electron fuses.")
    fi

    # Helper apps
    HELPERS_RAW=$(find "$APP_PATH/Contents" -name "*.app" -maxdepth 4 -not -samefile "$APP_PATH" 2>/dev/null | sort || true)
    if [[ -n "$HELPERS_RAW" ]]; then
        while IFS= read -r helper_app; do
            helper_name=$(basename "$helper_app" .app)
            helper_exec=$(defaults read "$helper_app/Contents/Info.plist" CFBundleExecutable 2>/dev/null || echo "")
            if [[ -z "$helper_exec" ]]; then
                helper_exec=$(find "$helper_app/Contents/MacOS" -maxdepth 1 -type f -perm +111 2>/dev/null | head -1)
                helper_exec=$(basename "$helper_exec")
            fi
            helper_binary="$helper_app/Contents/MacOS/$helper_exec"

            if [[ -f "$helper_binary" ]]; then
                IFS='|' read -r h_signed h_notarized h_hardened h_sandboxed h_ents <<< "$(check_binary "$helper_binary")"
                HELPER_NAMES+=("$helper_name")
                HELPER_SIGNED+=("$h_signed")
                HELPER_NOTARIZED+=("$h_notarized")
                HELPER_HARDENED+=("$h_hardened")
                HELPER_SANDBOXED+=("$h_sandboxed")
                HELPER_ENTITLEMENTS+=("$h_ents")
            fi
        done <<< "$HELPERS_RAW"
    fi
fi

echo "Data collection complete."

# ── Step 3: Generate the review ────────────────────────────────────

generate_review() {
    local NL=$'\n'

    echo "# ${APP_NAME} Desktop App Review"
    echo ""
    echo "#### **SUMMARY**"
    echo ""

    # Build a factual summary
    local summary="${APP_NAME}"
    if [[ "$TEAM_ID" != "not set" && -n "$TEAM_ID" ]]; then
        summary+=" (TeamIdentifier: ${TEAM_ID})"
    fi
    if $IS_STANDALONE; then
        summary+=" is a standalone binary"
        if [[ -n "$PKG_INSTALL_LOCATION" && -n "$PKG_PAYLOAD_FILES" ]]; then
            local install_path
            install_path=$(echo "$PKG_PAYLOAD_FILES" | grep -v "^\.$" | grep -v "^$" | grep -v "/$" | tail -1)
            install_path="${install_path#.}"
            if [[ "$PKG_INSTALL_LOCATION" == "/" ]]; then
                summary+=" installed to ${install_path}"
            else
                summary+=" installed to ${PKG_INSTALL_LOCATION%/}${install_path}"
            fi
        fi
    else
        summary+=" is a macOS application"
    fi
    summary+="."

    if [[ "$IS_SIGNED" == "Yes" ]]; then
        summary+=" The binary is signed"
        if [[ "$IS_NOTARIZED" == *"Yes"* ]]; then
            summary+=" and notarized"
        else
            summary+=", but NOT notarized"
        fi
    else
        summary+=" The binary is NOT signed"
    fi
    if [[ "$HAS_HARDENED_RUNTIME" == "Yes" ]]; then
        summary+=", with a hardened runtime"
    fi
    if [[ -n "$ENTITLEMENTS_LIST" ]]; then
        local ent_count
        ent_count=$(echo "$ENTITLEMENTS_LIST" | wc -l | tr -d ' ')
        summary+=" and ${ent_count} entitlement(s)"
    else
        summary+=" and no entitlements"
    fi
    summary+="."

    if [[ -n "$ELECTRON_FUSES" ]] && echo "$ELECTRON_FUSES" | grep -q "Disabled"; then
        summary+=" This is an Electron app with some fuses disabled."
    fi

    echo "$summary"
    echo ""
    echo "#### **GENERAL INFO**"
    echo ""

    if [[ -n "$BUNDLE_ID" ]]; then
        echo "BundleID = ${BUNDLE_ID}"
    else
        echo "BundleID = N/A"
    fi
    echo "TeamIdentifier = ${TEAM_ID:-N/A}"
    echo ""
    echo "Where is the installer sourced from?"
    echo ""
    if [[ "$INSTALLER_SOURCE" == "App Store" ]]; then
        echo "1. Appstore"
        echo "2. ~~Internet~~"
    else
        echo "1. ~~Appstore~~"
        echo "2. Internet"
        local sub=1
        if [[ "$EXT" == "pkg" ]]; then
            echo "   ${sub}. Distributed as a .pkg installer."
            sub=$((sub + 1))
        elif [[ "$EXT" == "dmg" ]]; then
            echo "   ${sub}. Distributed as a .dmg disk image."
            sub=$((sub + 1))
        elif [[ "$EXT" == "zip" ]]; then
            echo "   ${sub}. Distributed as a .zip archive."
            sub=$((sub + 1))
        fi
        if [[ -n "$INSTALLER_SOURCE_NOTES" ]]; then
            echo "   ${sub}. ${INSTALLER_SOURCE_NOTES}"
            sub=$((sub + 1))
        fi
        if [[ -n "$QUARANTINE_RAW" && -z "$INSTALLER_SOURCE_NOTES" ]]; then
            local agent_name
            agent_name=$(echo "$QUARANTINE_RAW" | cut -d';' -f3 | cut -d'|' -f1)
            if [[ -n "$agent_name" ]]; then
                echo "   ${sub}. Downloaded via: ${agent_name}"
            fi
        fi
    fi
    echo ""
    echo "Version Reviewed: ${VERSION:-N/A}"
    echo ""
    echo "#### **PRIMARY BINARY**"
    echo ""
    echo "Path to binary."

    if $IS_STANDALONE && [[ -n "$PKG_INSTALL_LOCATION" ]]; then
        local real_path
        real_path=$(echo "$PKG_PAYLOAD_FILES" | grep -v "^\.$" | grep -v "^$" | grep -v "/$" | tail -1)
        real_path="${real_path#.}"
        if [[ "$PKG_INSTALL_LOCATION" == "/" ]]; then
            echo "${real_path}"
        else
            echo "${PKG_INSTALL_LOCATION%/}${real_path}"
        fi
    else
        echo "$BINARY_PATH"
    fi
    echo ""

    if echo "$FILE_TYPE_INFO" | grep -q "universal"; then
        echo "Universal binary: x86_64 + arm64"
        echo ""
    elif echo "$FILE_TYPE_INFO" | grep -q "arm64"; then
        echo "Architecture: arm64"
        echo ""
    elif echo "$FILE_TYPE_INFO" | grep -q "x86_64"; then
        echo "Architecture: x86_64"
        echo ""
    fi

    echo "Is it sandboxed? ${IS_SANDBOXED}"
    echo ""

    local signed_nota="${IS_SIGNED}"
    if [[ "$IS_SIGNED" == "Yes" && "$IS_NOTARIZED" == *"Yes"* ]]; then
        signed_nota="Yes"
    elif [[ "$IS_SIGNED" == "Yes" ]]; then
        signed_nota="Signed but not notarized"
    else
        signed_nota="No"
    fi
    echo "Is it signed and notarized? ${signed_nota}"

    if [[ "$EXT" == "pkg" ]]; then
        local pkg_sign_status=""
        if echo "$PKG_SIGNED_INFO" | grep -q "signed by a developer certificate"; then
            pkg_sign_status="signed"
        fi
        if echo "$PKG_NOTARIZED_INFO" | grep -q "accepted"; then
            pkg_sign_status+=" and notarized"
        fi
        if echo "$PKG_STAPLER_INFO" | grep -q "worked"; then
            pkg_sign_status+=", staple validated"
        fi
        if [[ -n "$pkg_sign_status" ]]; then
            echo "- PKG installer is ${pkg_sign_status}."
        fi
        local signer
        signer=$(echo "$PKG_SIGNED_INFO" | grep "Developer ID" | head -1 | sed 's/^[[:space:]]*//' | sed 's/^[0-9]*\. //')
        if [[ -n "$signer" ]]; then
            echo "- Signed by: ${signer}"
        fi
    fi
    echo ""

    echo "Does it have a hardened runtime? ${HAS_HARDENED_RUNTIME}"
    if [[ -n "$ENTITLEMENTS_LIST" ]]; then
        echo "Are there exceptions/entitlements? Yes"
        echo "$ENTITLEMENTS_LIST" | while IFS= read -r ent; do
            [[ -n "$ent" ]] && echo "$ent"
        done
    else
        echo "Are there exceptions/entitlements? No"
    fi
    echo ""
    echo "#### **WHAT ELSE IS INSTALLED**"
    echo ""

    if $IS_STANDALONE; then
        echo "N/A — standalone binary."
        if [[ -n "$PKG_PAYLOAD_FILES" ]]; then
            echo ""
            echo "PKG payload files:"
            echo "$PKG_PAYLOAD_FILES" | grep -v "^\.$" | while IFS= read -r f; do
                [[ -n "$f" ]] && echo "- ${f}"
            done
        fi
    else
        echo "Frameworks"
        echo ""
        if [[ -n "$FRAMEWORKS_LIST" ]]; then
            local i=1
            echo "$FRAMEWORKS_LIST" | while IFS= read -r fw; do
                if [[ -n "$fw" ]]; then
                    echo "${i}. ${fw}"
                    if [[ "$fw" == "Electron Framework.framework" && -n "$ELECTRON_FUSES" ]]; then
                        echo "$ELECTRON_FUSES" | grep -E "Enabled|Disabled" | while IFS= read -r fuse_line; do
                            echo "   - ${fuse_line}"
                        done
                    fi
                    i=$((i + 1))
                fi
            done
        else
            echo "None"
        fi
    fi
    echo ""
    echo "#### **ADDITIONAL BINARIES**"
    echo ""

    if $IS_STANDALONE; then
        echo "N/A — standalone binary."
    elif [[ ${#HELPER_NAMES[@]} -eq 0 ]]; then
        echo "None"
    else
        for idx in "${!HELPER_NAMES[@]}"; do
            echo "${HELPER_NAMES[$idx]}"
            echo ""
            echo "1. Is it sandboxed? ${HELPER_SANDBOXED[$idx]}"
            echo "2. Signed and notarized? ${HELPER_SIGNED[$idx]}"
            echo "3. Hardened runtime? ${HELPER_HARDENED[$idx]}"
            if [[ -n "${HELPER_ENTITLEMENTS[$idx]}" ]]; then
                echo "4. Are there exceptions/entitlements? Yes"
                echo "${HELPER_ENTITLEMENTS[$idx]}" | while IFS= read -r ent; do
                    [[ -n "$ent" ]] && echo "   1. ${ent}"
                done
            else
                echo "4. Are there exceptions/entitlements? No"
            fi
            echo ""
        done
    fi
}

REVIEW_CONTENT=$(generate_review)

echo ""
echo "========================================="
echo "$REVIEW_CONTENT"
echo "========================================="
echo ""

# ── Step 4: Output ─────────────────────────────────────────────────

GDOC_URL=""

if $DO_TXT; then
    OUTFILE="${OUTPUT_DIR}/${APP_NAME} Desktop App Review.txt"
    echo "$REVIEW_CONTENT" > "$OUTFILE"
    echo "TXT saved to: $OUTFILE"
fi

if $DO_GDOC; then
    echo "Uploading to Google Drive via GAM..."
    TMPFILE=$(mktemp /tmp/app-review-XXXXXX.md)
    echo "$REVIEW_CONTENT" > "$TMPFILE"
    GAM_OUTPUT=$($GAM_CMD user "$GAM_USER" create drivefile \
        localfile "$TMPFILE" \
        drivefilename "${APP_NAME} Desktop App Review" \
        mimetype "application/vnd.google-apps.document" \
        parentid "$GDOC_FOLDER_ID" \
        returnlinkonly 2>&1)
    rm -f "$TMPFILE"
    GDOC_URL=$(echo "$GAM_OUTPUT" | grep -oE 'https://[^ ]+' | head -1)
    if [[ -n "$GDOC_URL" ]]; then
        echo "Google Doc created: $GDOC_URL"
    else
        echo "GAM output: $GAM_OUTPUT"
        echo "WARNING: Could not parse Google Doc URL from GAM output."
    fi
fi

if $DO_LINEAR; then
    echo "Creating Linear issue..."
    DESC="$REVIEW_CONTENT"
    if [[ -n "$GDOC_URL" ]]; then
        DESC="[Google Doc](${GDOC_URL})"$'\n\n'"${REVIEW_CONTENT}"
    fi

    ESCAPED_TITLE=$(echo "Desktop App Review: ${APP_NAME}" | sed 's/"/\\"/g')
    ESCAPED_DESC=$(echo "$DESC" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

    MUTATION="{\"query\":\"mutation { issueCreate(input: { title: \\\"${ESCAPED_TITLE}\\\", teamId: \\\"${LINEAR_TEAM_ID}\\\""

    if [[ -n "$LINEAR_PROJECT_ID" ]]; then
        MUTATION+=", projectId: \\\"${LINEAR_PROJECT_ID}\\\""
    fi

    MUTATION+=", description: ${ESCAPED_DESC}"
    MUTATION+=" }) { success issue { id identifier url } } }\"}"

    LINEAR_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: ${LINEAR_API_KEY}" \
        -d "$MUTATION" \
        https://api.linear.app/graphql)

    LINEAR_URL=$(echo "$LINEAR_RESPONSE" | python3 -c 'import sys,json; data=json.load(sys.stdin); print(data.get("data",{}).get("issueCreate",{}).get("issue",{}).get("url",""))' 2>/dev/null || true)
    LINEAR_ID=$(echo "$LINEAR_RESPONSE" | python3 -c 'import sys,json; data=json.load(sys.stdin); print(data.get("data",{}).get("issueCreate",{}).get("issue",{}).get("identifier",""))' 2>/dev/null || true)

    if [[ -n "$LINEAR_URL" ]]; then
        echo "Linear issue created: ${LINEAR_ID} — ${LINEAR_URL}"
    else
        echo "WARNING: Linear issue creation may have failed."
        echo "Response: $LINEAR_RESPONSE"
    fi
fi

echo ""
echo "Done."
