# Smart Speaker ESPHome Configuration

ESP32-S3 smart speaker that works as both a Music Assistant player and a Home
Assistant voice satellite.

* Audio in: INMP441 I2S microphone
* Audio out: MAX98357A I2S amplifier
* Wake word: micro_wake_word (Hey Jarvis)
* LEDs: WS2812 status LED and WS2812 light bar

## Build

```bash
./setup.sh                                  # compile
./setup.sh --upload smart-speaker.local     # compile + OTA
./setup.sh --upload /dev/cu.usbmodem1434101 # compile + serial
./setup.sh --clean                          # wipe venv and build artifacts
```

The script creates a virtualenv, installs the pinned ESPHome version, and runs
`esphome compile`. Nothing else is required.

### ESPHome version is pinned

`setup.sh` pins ESPHome to 2026.3.3. External I2S amplifiers on the ESP32-S3
regressed when the legacy I2S driver was removed in 2026.4.0
([esphome#16369](https://github.com/esphome/esphome/issues/16369), still open).
Do not bump this without testing audio output.

## Audio chain

```
media_pipeline       -> resampler -> mixer input (media)        \
                                                                 mixer -> MAX98357A
announcement_pipeline -> resampler -> mixer input (announcement) /
```

Things that matter here:

* Do not put LRCLK on GPIO46. It is a strapping pin with a weak internal
  pull-down, and it corrupts the word select clock badly enough that the
  MAX98357A amplifies garbage. The symptom is loud static that survives every
  software change, including muting the digital stream. LRCLK is on GPIO5.
* The mixer does not resample. Music Assistant streams arbitrary sample rates
  (44.1kHz is common) into a 48kHz chain, so each source needs a resampler in
  front of it. Removing them produces badly distorted audio.
* `timeout: never` on the speaker and both mixer inputs. A finite timeout
  releases the I2S bus between chunks, and reacquiring it clicks on every
  playback edge.

Music ducks 20dB while the assistant is speaking and is restored in `on_end`,
once the assistant has fully stopped.

## Volume

Volume is controlled through the `media_out` entity, which is what Home
Assistant, Music Assistant, voice intents and any physical buttons all talk to.
Use `media_player.volume_up`, `volume_down` and `volume_set` for buttons.

`volume_max` is a remap rather than a clamp. The reported volume still reads 0
to 100%, but it is rescaled into `volume_min..volume_max` before reaching the
speaker, so `volume_max` is the real output ceiling. It applies even to a volume
restored from flash, which is why setting `volume_initial` on its own does
nothing once the device has saved a volume.

The i2s speaker maps volume onto a 100 entry logarithmic table where index 0 is
silence and index 99 is 0dB. The bottom of the range is compressed, so small
percentages are much quieter than they look.

## LED driver split

Enabling audio on the ESP32-S3 leaves only one RMT TX channel free, which is not
enough to drive two WS2812 strips the usual way. So the two strips use different
drivers:

* Light bar (GPIO16): `esp32_rmt_led_strip` with DMA, using the one RMT channel.
* Status LED (GPIO48): `single_ws2812`, a bit-bang driver in `SRC/` that uses no
  RMT channel.

## Notes

Earlier versions of this project vendored esp-tflite-micro, esp-nn, esp-dsp,
mdns and multipart-parser into `my_components/`, with patches and a two-pass
PlatformIO build. None of that is needed now. Stock ESPHome declares those
dependencies itself, pinned, and resolves them through the IDF component
manager. If you disable `IDF_COMPONENT_MANAGER`, IDF ignores
`src/idf_component.yml` and the build fails on missing headers.
