#!/bin/bash
set -e

# Directory definitions
BASE_DIR=$(cd "$(dirname "$0")" && pwd)
VENV_DIR="$BASE_DIR/venv"
YAML_FILE="$BASE_DIR/YAML/media_player.yaml"

# Pinned because external I2S amps on ESP32-S3 regressed when the legacy I2S
# driver was removed in 2026.4.0 (esphome/esphome#16369, still open).
ESPHOME_VERSION="2026.3.3"

# ---------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------
UPLOAD_TARGET=""
CLEAN_MODE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --clean|clean)
            CLEAN_MODE=true
            ;;
        --upload)
            if [ -n "$2" ]; then
                UPLOAD_TARGET="$2"
                shift
            else
                echo "ERROR: --upload requires a target (IP or friendly name)."
                exit 1
            fi
            ;;
        -h|--help)
            echo "Usage: $0 [--clean] [--upload <target>]"
            echo "  --clean           Wipe venv and build artifacts before building."
            echo "  --upload <target> Upload via OTA (IP/hostname) or Serial (e.g. /dev/cu.usbmodem1434101)."
            exit 0
            ;;
    esac
    shift
done

if [ "$CLEAN_MODE" = true ]; then
    echo "Cleaning up: removing venv and build artifacts..."
    rm -rf "$VENV_DIR"
    rm -rf "$BASE_DIR/YAML/.esphome"
    echo "Cleanup complete."
    if [ -z "$UPLOAD_TARGET" ]; then
        echo "Exiting after cleanup."
        exit 0
    fi
fi

# ---------------------------------------------------------
# Part 0: Environment Setup (venv & ESPHome)
# ---------------------------------------------------------
echo "Checking python environment..."

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
python3 --version

INSTALLED_VERSION=$("$VENV_DIR/bin/python3" -c "import esphome.const; print(esphome.const.__version__)" 2>/dev/null || echo "none")
if [ "$INSTALLED_VERSION" != "$ESPHOME_VERSION" ]; then
    echo "Installing ESPHome $ESPHOME_VERSION (found: $INSTALLED_VERSION)..."
    python3 -m pip install "esphome==$ESPHOME_VERSION"
else
    echo "ESPHome $ESPHOME_VERSION already installed."
fi

# ---------------------------------------------------------
# Part 1: Build
# ---------------------------------------------------------
echo "---------------------------------------------------------"
echo "Building firmware..."

# ESPHome resolves esp-tflite-micro, esp-nn, esp-micro-speech-features, mdns,
# multipart-parser, arduinojson, esp-audio-libs and micro-flac itself through
# src/idf_component.yml. Disabling the component manager makes IDF ignore that
# manifest entirely, which breaks the build.
export IDF_COMPONENT_MANAGER=1

"$VENV_DIR/bin/esphome" compile "$YAML_FILE"

BUILD_DIR="$BASE_DIR/YAML/.esphome/build/smart-speaker"

echo "---------------------------------------------------------"
echo "Build complete."
echo "Environment: $VENV_DIR"
if [ -f "$BUILD_DIR/build/smart-speaker.bin" ]; then
    echo "Firmware:    $BUILD_DIR/build/smart-speaker.bin"
fi
echo "---------------------------------------------------------"

# ---------------------------------------------------------
# Part 2: Upload (optional)
# ---------------------------------------------------------
if [ -n "$UPLOAD_TARGET" ]; then
    echo "Uploading to target: $UPLOAD_TARGET..."
    "$VENV_DIR/bin/esphome" upload --device "$UPLOAD_TARGET" "$YAML_FILE"
fi
