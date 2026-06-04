#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_NAME="$(basename "$0")"

MX_PROJECT="$REPO_ROOT/Xcode/Mx.xcodeproj"
OUTPUT_XCFRAMEWORK="/tmp/Mx.xcframework"
INSTALL_PATH="$REPO_ROOT/../komp/Frameworks/FrameworksApple/Mx.xcframework"
CONFIGURATION="Release"
DERIVED_DATA=""
INSTALL_OUTPUT=0
INSTALL_ONLY=0
KEEP_ARCHIVES=0

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options]

Build a fresh Mx.xcframework from this mx Xcode project using xcodebuild
archive and xcodebuild -create-xcframework.

Options:
  --project PATH          Path to Mx.xcodeproj.
                          Default: $MX_PROJECT
  --output PATH           Output path for the generated xcframework.
                          Default: $OUTPUT_XCFRAMEWORK
  --install-path PATH     Path to install the xcframework when using --install.
                          Default: $INSTALL_PATH
  --configuration NAME    Xcode build configuration.
                          Default: $CONFIGURATION
  --derived-data PATH     Reuse a specific DerivedData directory.
  --install               Copy the built xcframework into --install-path after building.
  --install-only          Copy an existing xcframework at --output into --install-path
                          without rebuilding.
  --keep-archives         Keep the temporary archives directory.
  --help                  Show this message.

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME --configuration Debug --output /tmp/MxDebug.xcframework
  $SCRIPT_NAME --install
  $SCRIPT_NAME --output /tmp/Mx.xcframework --install-only
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            MX_PROJECT="$2"
            shift 2
            ;;
        --output)
            OUTPUT_XCFRAMEWORK="$2"
            shift 2
            ;;
        --install-path)
            INSTALL_PATH="$2"
            shift 2
            ;;
        --configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        --derived-data)
            DERIVED_DATA="$2"
            shift 2
            ;;
        --install)
            INSTALL_OUTPUT=1
            shift
            ;;
        --install-only)
            INSTALL_ONLY=1
            shift
            ;;
        --keep-archives)
            KEEP_ARCHIVES=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required tool not found: $tool" >&2
        exit 1
    fi
}

require_path() {
    local path="$1"
    local label="$2"
    if [[ ! -e "$path" ]]; then
        echo "$label not found: $path" >&2
        exit 1
    fi
}

install_xcframework() {
    local source_path="$1"
    echo "Installing xcframework into $INSTALL_PATH"
    rm -rf "$INSTALL_PATH"
    mkdir -p "$(dirname "$INSTALL_PATH")"
    rsync -a "$source_path/" "$INSTALL_PATH/"
}

require_tool xcodebuild
require_tool rsync

if [[ "$INSTALL_ONLY" -eq 1 ]]; then
    if [[ "$INSTALL_OUTPUT" -eq 1 ]]; then
        echo "Use either --install or --install-only, not both." >&2
        exit 1
    fi
    require_path "$OUTPUT_XCFRAMEWORK" "xcframework output"
    install_xcframework "$OUTPUT_XCFRAMEWORK"
    echo "Done"
    echo "Installed from: $OUTPUT_XCFRAMEWORK"
    echo "Installed to: $INSTALL_PATH"
    exit 0
fi

require_path "$MX_PROJECT" "mx project"

if [[ -z "$DERIVED_DATA" ]]; then
    DERIVED_DATA="$(mktemp -d /tmp/mx-derived-data.XXXXXX)"
    CREATED_DERIVED_DATA=1
else
    mkdir -p "$DERIVED_DATA"
    CREATED_DERIVED_DATA=0
fi

ARCHIVE_ROOT="$(mktemp -d /tmp/mx-archives.XXXXXX)"

cleanup() {
    if [[ "$CREATED_DERIVED_DATA" -eq 1 ]]; then
        rm -rf "$DERIVED_DATA"
    fi
    if [[ "$KEEP_ARCHIVES" -eq 0 ]]; then
        rm -rf "$ARCHIVE_ROOT"
    else
        echo "Keeping archives in $ARCHIVE_ROOT"
    fi
}
trap cleanup EXIT

archive_framework() {
    local scheme="$1"
    local destination="$2"
    local archive_path="$3"

    echo "Archiving $scheme for $destination"
    xcodebuild archive \
        -project "$MX_PROJECT" \
        -scheme "$scheme" \
        -configuration "$CONFIGURATION" \
        -destination "$destination" \
        -archivePath "$archive_path" \
        -derivedDataPath "$DERIVED_DATA" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        CODE_SIGNING_ALLOWED=NO
}

MACOS_ARCHIVE="$ARCHIVE_ROOT/Mx-macOS.xcarchive"
IOS_ARCHIVE="$ARCHIVE_ROOT/Mx-iOS.xcarchive"
IOS_SIM_ARCHIVE="$ARCHIVE_ROOT/Mx-iOS-Simulator.xcarchive"
CATALYST_ARCHIVE="$ARCHIVE_ROOT/Mx-Catalyst.xcarchive"

archive_framework "MxmacOS" "generic/platform=macOS" "$MACOS_ARCHIVE"
archive_framework "MxiOS" "generic/platform=iOS" "$IOS_ARCHIVE"
archive_framework "MxiOS" "generic/platform=iOS Simulator" "$IOS_SIM_ARCHIVE"
archive_framework "MxiOS" "generic/platform=macOS,variant=Mac Catalyst" "$CATALYST_ARCHIVE"

echo "Creating xcframework at $OUTPUT_XCFRAMEWORK"
rm -rf "$OUTPUT_XCFRAMEWORK"
xcodebuild -create-xcframework \
    -archive "$MACOS_ARCHIVE" -framework MxmacOS.framework \
    -archive "$IOS_ARCHIVE" -framework MxiOS.framework \
    -archive "$IOS_SIM_ARCHIVE" -framework MxiOS.framework \
    -archive "$CATALYST_ARCHIVE" -framework MxiOS.framework \
    -output "$OUTPUT_XCFRAMEWORK"

if [[ "$INSTALL_OUTPUT" -eq 1 ]]; then
    install_xcframework "$OUTPUT_XCFRAMEWORK"
fi

echo "Done"
echo "XCFramework: $OUTPUT_XCFRAMEWORK"
if [[ "$INSTALL_OUTPUT" -eq 1 ]]; then
    echo "Installed to: $INSTALL_PATH"
fi
