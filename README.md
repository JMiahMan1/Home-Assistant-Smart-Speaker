
# Smart Speaker ESPHome Configuration

## Overview
This configuration is for an ESP32-S3 Smart Speaker, featuring:
*   **Audio**: I2S Microphone (INMP441), I2S Speaker (MAX98357A)
*   **Voice Assistant**: Micro Wake Word, Voice Assistant pipeline
*   **LEDs**: WS2812 Status LED and WS2812 LED Bar

## Fix for LED Regression (ESP-IDF + Audio)
**Problem:** Enabling audio components on ESP32-S3 with ESP-IDF consumes resources that leave only **one RMT TX channel** available. This prevents driving two separate LED strips using the standard RMT driver.

**Solution:** A **Hybrid Driver Strategy** is used:
1.  **Status LED Bar (GPIO16)**: Uses the standard `esp32_rmt_led_strip` with DMA (`use_dma: true`). This consumes the single available RMT channel.
2.  **Status LED (GPIO48)**: Uses a custom **Bit-Bang Driver** (`single_ws2812`). This uses direct GPIO manipulation (zero RMT channels).

## Development Workflow

### Prerequisite: `setup.sh`
This project relies on a custom `setup.sh` script to manage the complex build environment. **Do not run `esphome run` directly.**

### 1. Initial Setup & Clean Build
To set up the environment (virtualenv, components) and perform a clean build:
```bash
./setup.sh --clean && ./setup.sh
```

### 2. Standard Build
To compile the firmware:
```bash
./setup.sh
```

### 3. Uploading to Device
The script automatically handles the upload method based on the target:
*   **OTA (Over-the-Air):** Uses `esphome upload` for standard network updates.
*   **Serial (USB):** Uses `platformio run --target upload` for robust flashing over USB, bypassing build system conflicts.

```bash
# Upload via Network (OTA)
./setup.sh --upload smart-speaker.lan

# Upload via Serial (USB)
./setup.sh --upload /dev/ttyACM0
```

## Why is this so complex?
The complexity of this setup—custom scripts, surgical CMake injection, and two-pass builds—is the direct result of fixing a critical regression: **The Light Bar (LEDs) ceased to function when Audio/AI features were enabled.**

1.  **Resource Conflict (The Root Cause):** Empowering the ESP32-S3 with Voice Assistant capabilities (I2S Audio + Wakeword detection) consumed nearly all hardware RMT channels. This left insufficient resources for the standard LED drivers to control both the Status LED and the Light Bar, breaking the Light Bar.
2.  **The Fix (Custom Drivers):** To solve this without sacrificing Audio/AI, we had to implement a hybrid driver strategy (Bit-Bang + DMA), forcing us to carefully manage how components are compiled and linked.
3.  **Dependency Hell (The Consequence):** Bringing in these custom configurations while maintaining the delicate TFLite Micro + ESP-NN + ESP-DSP integration triggered a cascade of linker errors and missing symbols. The standard ESPHome build system could not handle this specific combination of custom drivers and AI libraries.

### The Solution: Surgical Build Control
We ultimately had to take full control of the build process:
*   **Custom CMake Injection:** We replace the generated `src/CMakeLists.txt` to properly handle the custom dependency graph.
*   **Explicit Source Globbing:** We manually register TFLite/ESP-NN sources to prevent "undefined reference" errors that standard builds missed.
*   **Two-Pass Build:** `setup.sh` orchestrates the generation and compilation phases separately to apply these patches reliably.

This rigorous approach ensures a **Zero-Compromise** firmware: 
*   ✅ Working Audio & Voice Assistant
*   ✅ Working Light Bar & Status LEDs
*   ✅ Fully reproducible build environment
