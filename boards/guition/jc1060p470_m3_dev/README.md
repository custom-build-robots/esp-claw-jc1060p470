# JC-ESP32P4-M3-DEV / Guition JC1060P470 — ESP-Claw board adaptation

This is a board adaptation for the Guition JC1060P470 (a.k.a.
JC-ESP32P4-M3-DEV): a 7-inch 1024×600 IPS HMI module with an ESP32-P4
main SoC, an ESP32-C6 for WiFi/BT via ESP-Hosted, 32 MB octal PSRAM and
16 MB flash, JD9165 MIPI-DSI LCD controller, ES8311 audio codec, and a
GT911 capacitive touch panel.

## Where to put these files

Place the folder under `application/edge_agent/boards/` in your
esp-claw clone:

```
esp-claw/
└── application/
    └── edge_agent/
        └── boards/
            └── guition/
                └── jc1060p470_m3_dev/
                    ├── board_info.yaml
                    ├── board_peripherals.yaml
                    ├── board_devices.yaml
                    ├── setup_device.c
                    ├── sdkconfig.defaults.board
                    └── README.md
```

Confirm the Board Manager sees it:

```
cd application/edge_agent
idf.py gen-bmgr-config -c ./boards -l
```

`jc1060p470_m3_dev` should appear in the Customer Boards list. Then
activate:

```
idf.py gen-bmgr-config -c ./boards -b jc1060p470_m3_dev
idf.py menuconfig                 # apply App Claw Config baseline
idf.py build
idf.py flash monitor
```

## Source attribution

Pin assignments are derived from `pingcfg.h` in
[Deep-start9527/guition_product_demo](https://github.com/Deep-start9527/guition_product_demo)
(variant `JC1060P470C_I_W_Y`). The JD9165 init sequence and MIPI DPI
video timings are lifted from `lcd/lcd.c` in the same repository.

The YAML schema and `setup_device.c` factory function shape mirror the
existing `esp32_p4_function_ev` adaptation in `esp-claw`, which is the
closest structural match (P4 + MIPI-DSI + ES8311 + GT911).

## Remaining items to verify

Most of the schema unknowns from the first draft have now been resolved
against `esp32_p4_function_ev`. What's left:

1. **SDMMC slot 0 default pins on ESP32-P4**
   The `fs_sdcard` device uses `slot: SDMMC_HOST_SLOT_0` with all-zero
   pins, which tells the driver to use slot 0's default IOMUX
   assignment. The JC1060P470 routes the SD card to GPIO 43/44/39-42.
   Confirm via the P4 Technical Reference Manual SDMMC chapter that
   those pins are slot 0's defaults on the P4 — if not, either switch
   to slot 1 or specify the pins explicitly.

2. **ESP-Hosted Kconfig symbol names**
   The Kconfig symbol names in `sdkconfig.defaults.board` for ESP-Hosted
   (`CONFIG_ESP_HOSTED_SDIO_CLK_GPIO` etc.) match the current
   `espressif/esp_hosted` component but may drift between versions.
   After `idf.py build` pulls in the component, run `idf.py menuconfig`
   and walk through the ESP-Hosted submenu to confirm.  If symbol names
   differ, update this file and re-run.

3. **C6 slave firmware**
   The ESP32-C6 on this board needs ESP-Hosted slave firmware flashed
   separately for WiFi to work. The flow is documented in
   espressif/esp-hosted-mcu — depending on the board, the C6 is either
   accessible via a USB↔UART bridge through the P4 or via dedicated
   test points. Check the JCZN documentation in `8-Burn operation/`.

4. **ES8311 I2C address polarity**
   The address `0x30` matches function_ev's convention (8-bit write
   address; 7-bit equivalent is `0x18`). JC1060P470 should use the
   same wiring, but worth confirming against the schematic in
   `5-Schematic/`.

5. **Audio PA gain and active level**
   The `gpio_pa_control` peripheral is set to `active_level: 1` and
   `gain: 6` matching function_ev.  If the speaker is too quiet or
   distorted on first boot, adjust these.

6. **Touch mirror flags**
   `mirror_x` and `mirror_y` are both `false`. If touch axes feel
   inverted at runtime, flip these.  The JC1060P470 may have a
   different physical orientation than function_ev.

## Suggested order of bring-up

1. **Flash factory firmware first** (from the JCZN `8-Burn operation/`
   folder) to confirm the hardware is healthy before fighting any of
   the above.

2. **Build the ESP-Claw image with WiFi/BT temporarily disabled** in
   menuconfig (so you can ignore ESP-Hosted entirely for the first
   pass) and verify the display lights up and touch works. That
   isolates the YAML/setup_device.c work from the C6 work.

3. **Then add WiFi**: enable ESP-Hosted in menuconfig, flash the C6
   slave firmware, and verify network connectivity.

4. **Finally configure** your LLM endpoint and IM transport
   (Telegram is simplest) in App Claw Config, and you should have a
   working agent.
