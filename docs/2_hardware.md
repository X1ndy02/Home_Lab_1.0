Hardware

Core system

- Raspberry Pi 5 Model B (16GB RAM)
- 52Pi Ultra Thin ICE Tower Cooler
  
- Raspberry pizero2W
- Raspberry pizero2WH

Primary storage (boot drive)

- Kingston 500GB NVMe SSD
- Connected via Geekworm X1001 PCIe to M.2 adapter
- Linked using 50mm PCIe FFC cable
- Mounted in elevated position using M2.5 hex brass spacers

The elevated mounting was done to improve airflow and prevents heat buildup
around the NVMe module.

NVMe is used as the primary boot device instead of microSD
for improved I/O performance and endurance.


Secondary storage
- Geekworm X1100 2.5" SATA shield
- Kingston 240GB SATA SSD
The SATA SSD is dedicated to backup storage
and any otehr ,,cold,, storage functions 


Power backup
- Geekworm X1201 2-Cell 5.1V 5A UPS shield
- 2 × Molicel M35A 18650 batteries (3500mAh, 10A)
The UPS provides short-term backup power during outages.

It integrates with system services to:
- Send power loss notifications
- Trigger safe shutdown on low battery


System monitoring display
- RP2350 1.47" display development board (172×320, 262K color)
- RP2350 dual-core, dual-architecture microcontroller
- Connected via USB A

The display outputs real-time system information including:
- Current IP addresses
- Running processes
- CPU usage
- RAM usage
- Temperature
- UPS battery status
- Network ping
- Throttling state

This allows immediate physical inspection of system state
without remote login

Pi zero2W / Pi zero2WH
- Booted from 32gb SanDik Micro SD card 
- Aluminium Heatsink
- 52Pi USB Dongle Expansion Breakout Module Kit (Which makes them plug and play via USB A only)

