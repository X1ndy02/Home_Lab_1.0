RP2350 LCD Stats Dashboard Implementation

**Status: retired.** This hardware/service was taken out of service when the Pi 5 (rootnode) was
retired in favour of a VM on the UGREEN DXP2800GT NAS (x86_64). It has no home on the new VM —
there is no physical USB port to a VM guest, so this display and its service were not migrated.
This folder exists purely so the working setup can be revived on a future small host (e.g. a
Pi Zero 2W) if wanted.

System view

- Waveshare RP2350-LCD-1.47-A board, connected to the Pi 5 via USB-A (not GPIO)
- Board runs MicroPython (`WAVESHARE-RP2350-LCD-1.47-A.uf2`), flashed with `board_main.py` as `main.py`
- Host side: `pi_sender.py` polls Pi system stats and UPS state, and streams them to the board over
  USB serial as newline-delimited `key=value;key=value` lines
- Was run as a systemd service (`rp2350-stats.service`) — see note below, unit file no longer present
  on the system at time of archiving, likely removed/disabled before retirement

What interacts with what

- `pi_sender.py` reads `/proc/stat`, `/proc/meminfo`, `/sys/class/thermal/thermal_zone0/temp`,
  `vcgencmd get_throttled`, pings a host (default 1.1.1.1), and reads UPS charge via NUT (`upsc`)
  or apcupsd (`apcaccess`) — falls back to `--` if neither UPS source is present
- Payload is written to the serial device at `/dev/serial/by-id/usb-MicroPython_Board_in_FS_mode_...`
  (device-specific path, will differ per board)
- `board_main.py` reads lines from stdin (the serial connection) and redraws the 172x320 SPI display
  each time a line arrives

Why this design

- USB-serial link keeps the board's firmware simple (just a renderer) and puts all the system-reading
  logic on the Pi side, where it's easy to change without reflashing the board
- Polling + full-redraw each interval is simpler than partial updates, acceptable at the ~1s refresh rate

Display layout (final agreed state, locked)

- Top: centered hostname
- "STATS:" label
- CPU%/RAM%, UPS%/Ping(ms), Temp/Throttle status
- Separator line
- "CPU LOAD:" label
- 5 top-process lines (name left, % right-aligned)
- Separator line
- Up to 3 IP lines pinned to bottom (ETH/WRL/ZT tags, right-aligned IP)
- Date/time at the very bottom

Colors

- Day (06:00–21:00): white/green text (`col` field sent from `pi_sender.py`, default `lcd.TEXT` if absent)
- Night: dimmer shade
- Display orientation locked via `MADCTL 0xC0` — do not change without confirming, took several
  sessions to get right (see [[lcd_display_setup]] memory)

What is here

- `scripts/board_main.py` — on-device MicroPython script (flash to board as `main.py`)
- `scripts/pi_sender.py` — host-side Python script (needs `pyserial`)
- `SETUP_POINT1.txt` — original locked setup notes (service name, exact ExecStart command, payload
  field reference)

To revive on a new small host

1. Flash `WAVESHARE-RP2350-LCD-1.47-A.uf2` MicroPython firmware to the RP2350 board
2. Copy `scripts/board_main.py` to the board as `main.py`
3. Install `pyserial` on the new host, copy `scripts/pi_sender.py` over
4. Find the board's serial device path (`ls /dev/serial/by-id/`) and recreate a systemd service per
   `SETUP_POINT1.txt`'s `ExecStart` line (adjust the device path — it's per-board)
