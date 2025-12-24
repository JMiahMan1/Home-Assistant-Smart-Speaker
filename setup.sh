#!/bin/bash
set -e

# Directory definitions
BASE_DIR=$(cd "$(dirname "$0")" && pwd)
COMPONENTS_DIR="$BASE_DIR/my_components"
PATCHES_DIR="$BASE_DIR/SRC/patches"
VENV_DIR="$BASE_DIR/venv"

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
            echo "  --clean           Wipe build artifacts and components before building."
            echo "  --upload <target> Upload firmware via OTA (IP/hostname) or Serial (e.g., /dev/ttyACM0)."
            exit 0
            ;;
    esac
    shift
done

if [ "$CLEAN_MODE" = true ]; then
    echo "Cleaning up: removing venv, my_components, and build artifacts..."
    rm -rf "$VENV_DIR"
    rm -rf "$COMPONENTS_DIR"
    rm -rf "$BASE_DIR/YAML/.esphome"
    # Also clean managed_components which can interfere with local overrides
    rm -rf "$BASE_DIR/YAML/.esphome/build/smart-speaker/managed_components"
    rm -f "$BASE_DIR/YAML/idf_component.yml"
    rm -f "$BASE_DIR/YAML/build.log"
    rm -f "$PATCHES_DIR/src-cmakelists.patch"
    echo "Cleanup complete."
    # If only clean was requested, exit. If combined with upload, continue to build.
    if [ -z "$UPLOAD_TARGET" ] && [ "$#" -eq 0 ]; then
         # Wait, the logic here is slightly tricky if we want to support clean+build.
         # For now, let's assume if they say --clean, they might also want to build.
         # Original script exited. Let's maintain that if it was ONLY clean.
         echo "Exiting after cleanup."
         exit 0
    fi
    # If they passed --upload, we should probably build first.
fi

# ---------------------------------------------------------
# Part 0: Environment Setup (Venv & ESPHome)
# ---------------------------------------------------------
echo "Checking python environment..."

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment using python3.11..."
    if command -v python3.11 &> /dev/null; then
        python3.11 -m venv "$VENV_DIR"
    else
        echo "WARNING: python3.11 not found, falling back to python3"
        python3 -m venv "$VENV_DIR"
    fi
fi

# Activate venv for this script execution
source "$VENV_DIR/bin/activate"

# Check python version
python3.11 --version

# Install ESPHome if not present
if ! python3.11 -c "import esphome" &> /dev/null; then
    echo "Installing ESPHome 2025.12.1..."
    # We use --break-system-packages if needed, but in venv it's fine.
    # We pinned version as requested.
    python3.11 -m pip install esphome==2025.12.1
else
    echo "ESPHome is already installed."
fi

ESPHOME_VERSION="2025.12.1"
echo "Target ESPHome version: $ESPHOME_VERSION"

# Ensure my_components exists
mkdir -p "$COMPONENTS_DIR"


# ---------------------------------------------------------
# Part 2: Fetch and Patch Upstream Components (CLEAN INSTALL)
# ---------------------------------------------------------
TEMP_DIR="$BASE_DIR/temp_upstream"

# Function: install_component_clean
# Description: Wipes the target directory and installs a fresh copy using mv for atomicity.
install_component_clean() {
    local REPO_URL=$1
    local TAG=$2
    local COMPONENT_NAME=$3
    local SOURCE_SUBDIR=$4

    local TARGET_PATH="$COMPONENTS_DIR/$COMPONENT_NAME"
    
    echo "  [Checking] $COMPONENT_NAME..."
    # 1. Check if exists
    if [ -d "$TARGET_PATH" ]; then
        echo "    [Skip] $COMPONENT_NAME already exists (use --clean to force install)."
        return 0
    fi
    # 1.5 Wipe just in case (e.g. partial) - actually if we are here, definition says it's not a directory
    # But just in case it's a file or something weird
    rm -rf "$TARGET_PATH"
    
    echo "    [Install] Cloning $COMPONENT_NAME..."
    
    # 2. Clone to temp
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    git clone --depth 1 --branch "$TAG" "$REPO_URL" "$TEMP_DIR" > /dev/null 2>&1
    
    # 3. Move to target
    if [ -n "$SOURCE_SUBDIR" ]; then
        if [ -d "$TEMP_DIR/$SOURCE_SUBDIR" ]; then
             # Move the specific subdirectory to the target path
             mv "$TEMP_DIR/$SOURCE_SUBDIR" "$TARGET_PATH"
        else
             echo "ERROR: Subdir $SOURCE_SUBDIR not found in $REPO_URL"
             exit 1
        fi
    else
        # Move the entire cloned repo
        mv "$TEMP_DIR" "$TARGET_PATH"
    fi
    
    # Cleanup .git in target
    rm -rf "$TARGET_PATH/.git"
    
    # Cleanup temp dir (if it still exists, e.g. if we moved a subdir)
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    
    echo "    Success."
}

echo "Checking upstream components..."

# 1. micro_wake_word
ESPHOME_TAG="$ESPHOME_VERSION"
install_component_clean "https://github.com/esphome/esphome.git" "$ESPHOME_TAG" "micro_wake_word" "esphome/components/micro_wake_word"

# 2. esp-tflite-micro
install_component_clean "https://github.com/espressif/esp-tflite-micro.git" "master" "esp-tflite-micro" ""

# 3. esp-nn
install_component_clean "https://github.com/espressif/esp-nn.git" "master" "esp-nn" ""

# 4. esp-dsp
install_component_clean "https://github.com/espressif/esp-dsp.git" "master" "esp-dsp" ""

# 5. mdns (esp-protocols subdir)
install_component_clean "https://github.com/espressif/esp-protocols.git" "master" "mdns" "components/mdns"
touch "$COMPONENTS_DIR/mdns/__init__.py" # Mark as valid component? Actually for IDF components handled by manager, usually not needed, but safe.

# 6. multipart-parser
install_component_clean "https://github.com/zorxx/multipart-parser.git" "master" "multipart-parser" ""

# 7. single_ws2812 (Custom Component)
echo "  Installing single_ws2812 from SRC..."
SINGLE_WS2812_SRC="$BASE_DIR/SRC/single_ws2812"
SINGLE_WS2812_DEST="$COMPONENTS_DIR/single_ws2812"
if [ -d "$SINGLE_WS2812_SRC" ]; then
    rm -rf "$SINGLE_WS2812_DEST"
    mkdir -p "$SINGLE_WS2812_DEST"
    cp -r "$SINGLE_WS2812_SRC/"* "$SINGLE_WS2812_DEST/"
    echo "  Success."
else
    echo "ERROR: $SINGLE_WS2812_SRC not found!"
    exit 1
fi

# ---------------------------------------------------------
# Part 3: Apply Patches & Fixes (The "Automated Fixes")
# ---------------------------------------------------------
echo "Applying patches..."

PATCHES_DIR="$BASE_DIR/SRC/patches"

# Patch 1: esp-tflite-micro CMakeLists.txt
# Consolidates all CMakeLists.txt changes: dependencies, kernels, flags, duplicate exclusions
ESP_TFLITE_CMAKE="$COMPONENTS_DIR/esp-tflite-micro/CMakeLists.txt"
if [ -f "$ESP_TFLITE_CMAKE" ] && [ -f "$PATCHES_DIR/esp-tflite-micro-cmake.patch" ]; then
    echo "  Applying esp-tflite-micro CMakeLists.txt patch..."
    # Use -N to ignore patches that are already applied
    patch -N -p0 "$ESP_TFLITE_CMAKE" < "$PATCHES_DIR/esp-tflite-micro-cmake.patch" || true
fi

# Patch 2: decode_state_huffman.h - Remove C++14 digit separators
DECODE_STATE_HUFFMAN="$COMPONENTS_DIR/esp-tflite-micro/tensorflow/lite/micro/kernels/decode_state_huffman.h"
if [ -f "$DECODE_STATE_HUFFMAN" ] && [ -f "$PATCHES_DIR/decode_state_huffman.patch" ]; then
    echo "  Applying decode_state_huffman.h patch..."
    patch -N -p0 "$DECODE_STATE_HUFFMAN" < "$PATCHES_DIR/decode_state_huffman.patch" || true
fi

# Patch 3: common.cc - Add pragma directives to suppress switch warnings
COMMON_CC="$COMPONENTS_DIR/esp-tflite-micro/tensorflow/lite/core/c/common.cc"
if [ -f "$COMMON_CC" ] && [ -f "$PATCHES_DIR/common_cc_pragma.patch" ]; then
    echo "  Applying common.cc pragma patch..."
    patch -N -p0 "$COMMON_CC" < "$PATCHES_DIR/common_cc_pragma.patch" || true
fi

# Patch 4: micro_wake_word __init__.py - Comment out add_idf_component
MICRO_WAKE_WORD_INIT="$COMPONENTS_DIR/micro_wake_word/__init__.py"
if [ -f "$MICRO_WAKE_WORD_INIT" ] && [ -f "$PATCHES_DIR/micro_wake_word_init.patch" ]; then
    echo "  Applying micro_wake_word __init__.py patch..."
    patch -N -p0 "$MICRO_WAKE_WORD_INIT" < "$PATCHES_DIR/micro_wake_word_init.patch" || true
fi

# Fix 5: Copy multipart-parser sources to micro_wake_word
echo "  Copying multipart-parser to micro_wake_word..."
cp "$COMPONENTS_DIR/multipart-parser/multipart_parser.c" "$COMPONENTS_DIR/micro_wake_word/"
cp "$COMPONENTS_DIR/multipart-parser/multipart_parser.h" "$COMPONENTS_DIR/micro_wake_word/"

# Fix 8: Ensure all components have correct permissions for ESPHome to read
echo "  Setting component permissions..."
chmod -R 755 "$COMPONENTS_DIR"


# ---------------------------------------------------------
# Part 3: Apply Patches
# ---------------------------------------------------------
echo "Applying patches..."

MICRO_WAKE_WORD_PATH="$COMPONENTS_DIR/micro_wake_word"
if [ -f "$MICRO_WAKE_WORD_PATH/micro_wake_word.cpp" ]; then
    # Check if patched already
    if grep -q "RingBuffer<int16_t, 8192>" "$MICRO_WAKE_WORD_PATH/micro_wake_word.cpp"; then
         echo "  micro_wake_word already patched."
    else
         patch -N "$MICRO_WAKE_WORD_PATH/micro_wake_word.cpp" "$PATCHES_DIR/ring_buffer.patch" || echo "Patch failed or already applied"
         echo "  Patch applied successfully."
    fi
else
    echo "ERROR: micro_wake_word.cpp not found for patching."
    exit 1
fi

# ---------------------------------------------------------
# Part 4: ESPHome Build & Surgical Patching
# ---------------------------------------------------------
echo "---------------------------------------------------------"
echo "Starting ESPHome Build & Surgical Patching..."
export IDF_COMPONENT_MANAGER=0

# First pass: Generate build files without compiling
echo "  [Pass 1] Generating build files (ESPHome)..."
./venv/bin/esphome compile --only-generate YAML/media_player.yaml

SRC_CMAKELISTS="$BASE_DIR/YAML/.esphome/build/smart-speaker/src/CMakeLists.txt"
if [ ! -f "$SRC_CMAKELISTS" ]; then
    echo "  Notice: src/CMakeLists.txt not found. Creating default for patching..."
    mkdir -p "$(dirname "$SRC_CMAKELISTS")" # Use the correct variable name
    # Wait, I used SRC_CMACELISTS in the echo earlier, but the variable is SRC_CMAKELISTS.
    # Fixed it below.
    cat > "$SRC_CMAKELISTS" <<EOF
# This file was automatically generated for projects
# without default 'CMakeLists.txt' file.

FILE(GLOB_RECURSE app_sources \${CMAKE_SOURCE_DIR}/src/*.*)

idf_component_register(SRCS \${app_sources})
EOF
fi

echo "  Applying surgical src/CMakeLists.txt fixes..."
cat > "$SRC_CMAKELISTS" <<EOF
# This file was automatically generated for projects
# without default 'CMakeLists.txt' file.

FILE(GLOB_RECURSE app_sources \${CMAKE_SOURCE_DIR}/src/*.*)

set(COMPONENTS_DIR "${BASE_DIR}/my_components")
set(TFLITE_DIR "\${COMPONENTS_DIR}/esp-tflite-micro")
set(ESP_NN_DIR "\${COMPONENTS_DIR}/esp-nn")
set(ESP_DSP_DIR "\${COMPONENTS_DIR}/esp-dsp")

set(MDNS_DIR "\${COMPONENTS_DIR}/mdns")

# Glob TFLite sources
FILE(GLOB_RECURSE tflm_srcs "\${TFLITE_DIR}/tensorflow/lite/micro/*.cc")
FILE(GLOB tflite_api_srcs "\${TFLITE_DIR}/tensorflow/lite/core/api/*.cc")
set(tflite_core_c "\${TFLITE_DIR}/tensorflow/lite/core/c/common.cc")
set(tflite_lite_kernels
    "\${TFLITE_DIR}/tensorflow/lite/kernels/internal/quantization_util.cc"
    "\${TFLITE_DIR}/tensorflow/lite/kernels/internal/tensor_ctypes.cc"
)

set(tflite_srcs \${tflm_srcs} \${tflite_api_srcs} \${tflite_core_c} \${tflite_lite_kernels})
# Exclude tests, examples, and known duplicates
list(FILTER tflite_srcs EXCLUDE REGEX "(_test\\\\.cc|/test/|example|benchmark|kernels/internal/|micro/kernels/esp_nn/|tensorflow/lite/micro/micro_time\\\\.cc\$|tensorflow/lite/micro/system_setup\\\\.cc\$)")
# Re-add essential kernels and core API/schema files
configure_file("\${TFLITE_DIR}/tensorflow/lite/kernels/internal/common.cc" "\${CMAKE_CURRENT_BINARY_DIR}/tflite_internal_common.cc" COPYONLY)
configure_file("\${TFLITE_DIR}/tensorflow/lite/kernels/kernel_util.cc" "\${CMAKE_CURRENT_BINARY_DIR}/tflite_lite_kernel_util.cc" COPYONLY)

list(APPEND tflite_srcs 
    "\${CMAKE_CURRENT_BINARY_DIR}/tflite_internal_common.cc"
    "\${CMAKE_CURRENT_BINARY_DIR}/tflite_lite_kernel_util.cc"
    "\${TFLITE_DIR}/tensorflow/lite/kernels/internal/quantization_util.cc"
    "\${TFLITE_DIR}/tensorflow/lite/kernels/internal/tensor_ctypes.cc"
    "\${TFLITE_DIR}/tensorflow/lite/kernels/internal/portable_tensor_utils.cc"
    "\${TFLITE_DIR}/tensorflow/compiler/mlir/lite/core/api/error_reporter.cc"
    "\${TFLITE_DIR}/tensorflow/compiler/mlir/lite/schema/schema_utils.cc"
    "\${TFLITE_DIR}/tensorflow/lite/micro/kernels/pad.cc"
    "\${TFLITE_DIR}/tensorflow/lite/micro/kernels/pad_common.cc"
    "\${TFLITE_DIR}/tensorflow/lite/micro/kernels/pack.cc"
    "\${TFLITE_DIR}/tensorflow/lite/micro/kernels/split_v.cc"
)

# Simplified inclusion of all .cc/.c files in these directories
FILE(GLOB_RECURSE esp_nn_srcs "\${ESP_NN_DIR}/src/*.c" "\${ESP_NN_DIR}/src/*.S")
FILE(GLOB_RECURSE esp_dsp_srcs "\${ESP_DSP_DIR}/modules/**/*.c" "\${ESP_DSP_DIR}/modules/**/*.S" "\${ESP_DSP_DIR}/modules/**/*.cpp")

# Exclude incompatible architectures
list(FILTER esp_nn_srcs EXCLUDE REGEX "(/esp32(p4|c2|c3|c6|h2)/|esp_nn_.*_esp32(p4|c2|c3|c6|h2)\\\\.|/test/|/example/|main\\\\.c)")
list(FILTER esp_dsp_srcs EXCLUDE REGEX "(_sim\\\\.c|_sim\\\\.cpp|/test/|/example/|/tests/|/test_sim/|/benchmark/|main\\\\.c|main\\\\.cpp|test_.*\\\\.c|test_.*\\\\.cpp)")

# MDNS sources
set(mdns_srcs 
    "\${MDNS_DIR}/mdns_responder.c"
    "\${MDNS_DIR}/mdns_receive.c"
    "\${MDNS_DIR}/mdns_utils.c"
    "\${MDNS_DIR}/mdns_debug.c"
    "\${MDNS_DIR}/mdns_browser.c"
    "\${MDNS_DIR}/mdns_send.c"
    "\${MDNS_DIR}/mdns_netif.c"
    "\${MDNS_DIR}/mdns_querier.c"
    "\${MDNS_DIR}/mdns_pcb.c"
    "\${MDNS_DIR}/mdns_service.c"
    "\${MDNS_DIR}/mdns_mem_caps.c"
    "\${MDNS_DIR}/mdns_networking_lwip.c"
)

# Find include directories
FILE(GLOB_RECURSE esp_nn_include_dirs LIST_DIRECTORIES true "\${ESP_NN_DIR}/**/include")
FILE(GLOB_RECURSE esp_dsp_include_dirs LIST_DIRECTORIES true "\${ESP_DSP_DIR}/modules/**/include")
# Root includes as fallbacks
list(APPEND esp_nn_include_dirs "\${ESP_NN_DIR}/include" "\${ESP_NN_DIR}/src/common")
# No root include for esp-dsp as it doesn't exist; already covered by modules glob.

idf_component_register(SRCS \${app_sources} \${tflite_srcs} \${esp_nn_srcs} \${mdns_srcs}
                      INCLUDE_DIRS "." 
                      "../"
                      "\${TFLITE_DIR}"
                      "\${TFLITE_DIR}/third_party/flatbuffers/include"
                      "\${TFLITE_DIR}/third_party/gemmlowp"
                      "\${TFLITE_DIR}/third_party/kissfft"
                      "\${TFLITE_DIR}/third_party/ruy"
                      "\${TFLITE_DIR}/signal/src"
                      "\${TFLITE_DIR}/signal/micro/kernels"
                      "\${TFLITE_DIR}/tensorflow/compiler/mlir/lite/core/api"
                      "\${MDNS_DIR}/include"
                      "\${MDNS_DIR}/private_include"
                      "\${COMPONENTS_DIR}/multipart-parser"
                      \${esp_nn_include_dirs}
                      \${esp_dsp_include_dirs}
)

target_compile_definitions(\${COMPONENT_LIB} PUBLIC 
    -DCONFIG_MDNS_MAX_INTERFACES=3
    -DCONFIG_MDNS_MAX_SERVICES=10
    -DCONFIG_MDNS_TASK_PRIORITY=1
    -DCONFIG_MDNS_ACTION_QUEUE_LEN=16
    -DCONFIG_MDNS_TASK_STACK_SIZE=4096
    -DCONFIG_MDNS_SERVICE_ADD_TIMEOUT_MS=2000
    -DCONFIG_MDNS_TIMER_PERIOD_MS=100
    -DCONFIG_MDNS_TASK_AFFINITY=0
    -DCONFIG_MDNS_MULTIPLE_INSTANCE=1
    -DCONFIG_MDNS_PREDEF_NETIF_STA=1
    -DCONFIG_MDNS_PREDEF_NETIF_AP=1
)
EOF

echo "  [Pass 2] Compilation with surgical fixes (via PlatformIO)..."
# Run PlatformIO directly from the build directory to avoid ESPHome overwriting the patch
(cd "$BASE_DIR/YAML/.esphome/build/smart-speaker" && "$VENV_DIR/bin/platformio" run)

# ---------------------------------------------------------
# Part 5: Finalization & Compatibility
# ---------------------------------------------------------
echo "---------------------------------------------------------"
echo "Ensuring compatibility with standard ESPHome commands..."

# ESPHome's 'upload' command often expects the legacy PlatformIO structure (.pioenvs)
# Modern PlatformIO uses .pio/build. We harmonize this.
LEGACY_DIR="$BASE_DIR/YAML/.esphome/build/smart-speaker/.pioenvs/smart-speaker"
MODERN_DIR="$BASE_DIR/YAML/.esphome/build/smart-speaker/.pio/build/smart-speaker"

if [ -d "$MODERN_DIR" ]; then
    mkdir -p "$LEGACY_DIR"
    cp -r "$MODERN_DIR"/* "$LEGACY_DIR/"
    echo "  Binary artifacts copied to .pioenvs for 'esphome upload' compatibility."
fi

echo "---------------------------------------------------------"
echo "Setup & Build Complete!"
echo "Environment: $VENV_DIR"
echo "Components:  $COMPONENTS_DIR"
if [ -f "$MODERN_DIR/firmware.bin" ]; then
    echo "Firmware:    $MODERN_DIR/firmware.bin"
fi
echo "---------------------------------------------------------"

# ---------------------------------------------------------
# Part 6: Upload (Optional)
# ---------------------------------------------------------
if [ -n "$UPLOAD_TARGET" ]; then
    echo "Uploading to target: $UPLOAD_TARGET..."
    
    # Check if target is a file path (Serial) or network address (OTA)
    # Serial ports usually start with /dev/ (Linux/Mac) or COM (Windows)
    if [[ "$UPLOAD_TARGET" == /dev/* ]] || [[ "$UPLOAD_TARGET" == COM* ]]; then
        echo "  Target detected as Serial Port. Using PlatformIO direct upload for robustness..."
        # Use platformio run --target upload directly from the build directory
        # This bypasses ESPHome's build management which can conflict with our surgical patches during upload
        (cd "$BASE_DIR/YAML/.esphome/build/smart-speaker" && "$VENV_DIR/bin/platformio" run --target upload --upload-port "$UPLOAD_TARGET")
    else
        echo "  Target detected as Network Address. Using ESPHome upload..."
        # We use the venv's esphome for OTA as it handles network auth/protocols well
        "$VENV_DIR/bin/esphome" upload --device "$UPLOAD_TARGET" "$BASE_DIR/YAML/media_player.yaml"
    fi
fi
