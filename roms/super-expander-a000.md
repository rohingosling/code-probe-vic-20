# VIC-1211A Super Expander ROM

VICE does not ship the VIC-1211A Super Expander ROM. You must source it yourself before Code Probe will run in VICE. Once downloaded, change the name of the ROM image file to `super-expander-a000.prg` and place in the `roms/` folder. The `-a000` filename suffix is a VICE smart-attach hint.

## Source:

- **URL:** http://www.zimmers.net/anonftp/pub/cbm/vic20/roms/tools/4k/

- **Note:**
  
  Two versions of the VIC-1211 Super Expander are available on zimmers.net.
  - The `VIC1211m`, originally targeting the Japanese market in the 1980s.
  - The standard VIC-1211A, listed as `Super Expander.prg` on the download page.
  
  For Code Probe, download the standard VIC-1211A (`Super Expander.prg`) and rename it to `super-expander-a000.prg` so the `xvic -cartA` argument resolves. The `-a000` filename suffix is a VICE smart-attach hint.

## Usage

1. Once the file is in place (`roms/super-expander-a000.prg`), launch VICE with the ROM attached at block 5

2. Enable `Block 0 (3KiB at $0400-$0FFF)`, via `VICE -> Preferences -> Settings -> Machine -> Model`

3. From the `v1/` directory:

    `xvic -memory 3k -cartA roms/super-expander-a000.prg -autostart build/code-probe.prg`

<br>

> *See `README.md` for the full setup procedure, including the GUI alternative for attaching the cartridge from VICE's File menu.*
