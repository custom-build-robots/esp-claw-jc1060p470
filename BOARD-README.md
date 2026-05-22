# Guition JC1060P470 &mdash; ESP-Claw board adaptation

This folder contains a complete drop-in board adaptation for the [Espressif ESP-Claw](https://github.com/espressif/esp-claw) on-device AI agent framework, targeting the **Guition JC1060P470** development board (ESP32-P4 + ESP32-C6).

## About the board

The Guition JC1060P470 is a 7-inch HMI development board built around the ESP32-P4. Key specs as targeted by this adaptation:

| Component         | Detail                                            |
| ----------------- | ------------------------------------------------- |
| MCU               | ESP32-P4 (in my unit: revision **v1.3**)           |
| Co-processor      | ESP32-C6 (WiFi 6 + BLE 5) via ESP-Hosted over SDIO |
| PSRAM             | 32&nbsp;MB, 200&nbsp;MHz, octal mode               |
| Flash             | 16&nbsp;MB                                         |
| Display           | 7&Prime; 1024&times;600 MIPI-DSI, **JD9165** controller |
| Touch             | Capacitive touch panel                             |
| Audio             | Dual ES8311 codec (DAC and ADC on separate I2S)    |
| Storage expansion | microSD card slot (SDMMC, 4-bit)                   |

## Files in this folder

| File                          | Purpose                                                                  |
| ----------------------------- | ------------------------------------------------------------------------ |
| `board_info.yaml`             | Top-level board metadata for the ESP Board Manager                       |
| `board_peripherals.yaml`      | Declarative peripheral description (I2C, I2S, LDO, MIPI-DSI, LEDC, etc.) |
| `board_devices.yaml`          | Devices that sit on those peripherals (display, touch, audio codecs)     |
| `setup_device.c`              | Custom C code, including the **JD9165 init command sequence**            |
| `sdkconfig.defaults.board`    | Board-specific Kconfig defaults (incl. chip-revision range)              |

## Using the adaptation

1. Clone ESP-Claw with submodules:
   ```
   git clone --recursive https://github.com/espressif/esp-claw.git
   ```
2. Copy the `guition/` folder (including this `jc1060p470_m3_dev/` directory) into:
   ```
   esp-claw/application/edge_agent/boards/guition/
   ```
3. Generate the Board Manager config from the YAMLs:
   ```
   cd esp-claw/application/edge_agent
   idf.py gen-bmgr-config -c ./boards -b jc1060p470_m3_dev
   ```
   Expected output ends with something like
   `Successfully validated 7 peripherals` and `Successfully validated 6 devices`.
4. Build the firmware:
   ```
   idf.py build
   ```
5. Flash &mdash; only on the very first flash:
   ```
   idf.py -p COM<n> flash monitor
   ```
   For every subsequent update, use **`app-flash`** instead of `flash` to keep the on-device storage (WiFi credentials, LLM config, memory files) intact:
   ```
   idf.py -p COM<n> app-flash monitor
   ```

## Important note about the chip revision

If your ESP32-P4 silicon is older than v3.0 (mine is v1.3), the default ESP-IDF chip-revision range will refuse to boot the firmware. This adaptation pins the range explicitly in `sdkconfig.defaults.board`:

```
CONFIG_ESP32P4_REV_MIN_FULL=0
CONFIG_ESP32P4_REV_MAX_FULL_NUM=199
```

Newer boards (ESP32-P4 Function EV Board, M5Stack Tab5 with P4 v3.0+) do not need this, but the setting is harmless on those boards too.

## Tested ESP-IDF version

- ESP-IDF **v5.5.4** on Windows 11
- ESP-Claw `master` branch

## Background

The full development story of this adaptation lives in [Part 3 of my ESP-Claw series](https://ai-box.eu/) on ai-box.eu. The update / rebuild / re-flash workflow that this adaptation is designed to survive cleanly is described in Part 5.

## License

MIT &mdash; see the [LICENSE](../../../LICENSE) file at the root of the repository.

Files that originate from or are derived from ESP-Claw retain their original Apache 2.0 license. Please consult the upstream repository for the authoritative license of those parts.
