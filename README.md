# esp-claw-jc1060p470

Board adaptation for the **Guition JC1060P470** (ESP32-P4 HMI development board) and a PowerShell-based update toolkit for the [ESP-Claw](https://github.com/espressif/esp-claw) on-device AI agent framework from Espressif.

This repository is a companion to my blog series on [ai-box.eu](https://ai-box.eu/) about running sovereign AI agents on microcontroller hardware, talking to a local Ollama server instead of relying on any cloud service.

## What's in here

```
boards/guition/jc1060p470_m3_dev/   # Drop-in board adaptation for ESP-Claw
scripts/update-esp-claw.ps1         # Automated update / rebuild / re-flash workflow
```

### Board adaptation

The folder `boards/guition/jc1060p470_m3_dev/` contains everything ESP-Claw's Board Manager needs to build the `edge_agent` firmware for the Guition JC1060P470:

- `board_info.yaml`, `board_peripherals.yaml`, `board_devices.yaml` &mdash; declarative description of the board, its peripherals (I2C, I2S, LDO, MIPI-DSI, LEDC) and its devices (display, touch, codec, etc.)
- `setup_device.c` &mdash; custom initialisation, including the **JD9165 LCD init sequence** for the 1024&times;600 MIPI-DSI panel that the JC1060P470 ships with
- `sdkconfig.defaults.board` &mdash; board-specific Kconfig defaults, including the chip-revision range so the firmware boots on older ESP32-P4 silicon (v1.3)

### Update script

`scripts/update-esp-claw.ps1` automates the full update workflow described in [Part 5 of my ESP-Claw series](https://ai-box.eu/) on ai-box.eu:

1. ZIP backup of the board adaptation with a timestamp
2. `git stash`, `fetch`, `pull --rebase`, recursive submodule update
3. Restore of the board adaptation from the ZIP backup
4. `pip install --upgrade esp-bmgr-assist`
5. `idf.py reconfigure` &amp; `gen-bmgr-config`
6. `idf.py build`
7. **`idf.py -p COM<n> app-flash monitor`** &mdash; the `app-flash` command (not `flash`!) is the critical piece: it leaves the `storage.bin` on the device untouched, so WiFi credentials, the LLM configuration and the memory files survive the update.

## Prerequisites

- A Guition JC1060P470 with an ESP32-P4 + ESP32-C6 combo
- ESP-IDF v5.5.4 (parallel installation, not over an existing IDF tree)
- ESP-Claw cloned with `--recursive`
- Windows + PowerShell (the script is PowerShell, but the board adaptation itself is platform-independent)

## How to use the board adaptation

1. Clone ESP-Claw with submodules:
   ```
   git clone --recursive https://github.com/espressif/esp-claw.git
   ```
2. Copy the `boards/guition/` folder from this repository into `esp-claw/application/edge_agent/boards/`.
3. Generate the Board Manager config:
   ```
   cd esp-claw/application/edge_agent
   idf.py gen-bmgr-config -c ./boards -b jc1060p470_m3_dev
   ```
4. Build &amp; flash:
   ```
   idf.py build
   idf.py -p COM<n> flash monitor     # only on the very first flash
   ```
   For every subsequent update use the script from `scripts/` &mdash; or `idf.py -p COM<n> app-flash monitor` manually.

A more detailed step-by-step guide lives in `boards/guition/jc1060p470_m3_dev/README.md`.

## How to use the update script

From the **ESP-IDF 5.5 PowerShell** (not a regular Windows PowerShell):

```powershell
.\scripts\update-esp-claw.ps1                       # default run
.\scripts\update-esp-claw.ps1 -ComPort COM5         # custom COM port
.\scripts\update-esp-claw.ps1 -SkipFlash            # build only, no flash
.\scripts\update-esp-claw.ps1 -NonInteractive       # no confirmation prompts
```

The script writes a full transcript to `D:\esp32-claw\backups\update_log_<timestamp>.txt` and creates a timestamped ZIP backup of your board adaptation before doing anything destructive.

## Tested setup

- **Board:** Guition JC1060P470 with ESP32-P4 v1.3 and ESP32-C6 co-processor
- **Display:** 1024&times;600 MIPI-DSI with JD9165 controller
- **PSRAM:** 32&nbsp;MB at 200&nbsp;MHz octal mode
- **Flash:** 16&nbsp;MB
- **Audio:** Dual ES8311 codec (one DAC, one ADC)
- **Toolchain:** ESP-IDF v5.5.4 on Windows 11
- **LLM backend:** Local Ollama server with Qwen 3.6 35B on RTX A6000 GPUs

## Related blog posts on ai-box.eu

- Part 1 &mdash; Vision: a sovereign AI agent on HMI hardware
- Part 2 &mdash; Setting up ESP-IDF v5.5.4 and building ESP-Claw step by step
- Part 3 &mdash; Adding a new board to ESP-Claw: my board adaptation for the JC1060P470
- Part 4 &mdash; Connecting ESP-Claw to a local Ollama server
- Part 5 &mdash; Keeping ESP-Claw up to date: update, rebuild and re-flash

## License

This repository is licensed under the [MIT License](LICENSE).

Files that originate from or are derived from [ESP-Claw](https://github.com/espressif/esp-claw) by Espressif Systems retain their original Apache 2.0 license &mdash; please consult the upstream repository for the authoritative license of those files. The board adaptation and the update script in this repository are original work, released under MIT to make reuse as friction-free as possible.

## Contributions

Pull requests with improvements to the board adaptation, support for related Guition boards, or extensions to the update script are very welcome. Please open an issue first if you want to discuss a larger change.

## Disclaimer

This is a personal maker project, not an official Espressif or Guition product. The board adaptation has been tested on my own hardware and is shared in the hope that it is useful, but without any warranty of fitness for a particular purpose.
