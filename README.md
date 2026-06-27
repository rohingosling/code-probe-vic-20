# Code Probe (VIC-20)

![Assembly](https://img.shields.io/badge/Assembly-40318D?style=flat&logoColor=white)
![Machine Language](https://img.shields.io/badge/Machine_Language-AA7449?style=flat&logoColor=white)
![6502](https://img.shields.io/badge/6502-782922?style=flat&logoColor=white)
![Kick Assembler](https://img.shields.io/badge/Kick_Assembler-55A049?style=flat&logoColor=white)
![Commodore VIC-20](https://img.shields.io/badge/Commodore_VIC--20-1428A0?style=flat&logo=commodore&logoColor=white)
![Super Expander](https://img.shields.io/badge/VIC--1211A_Super_Expander-AA5FB6?style=flat&logoColor=white)

<p align="center">
  <img src="images/capture/Assemble/assemble.gif" width="48%" alt="Code Probe assembling machine code on the Commodore VIC-20">&emsp;
  <img src="images/capture/Save%20and%20Load/load-and-save.gif" width="48%" alt="Code Probe saving and loading a program on the Commodore VIC-20">
</p>

A machine language monitor for the **Commodore VIC-20** and **VIC-1211A Super Expander**.

- Inspect and modify memory with a hex dump and interactive alter mode.
- View the CPU registers and processor status flags captured at the end of the last executed routine.
- Save and load machine language programs to and from tape, in PRG and SEQ formats.
- Loads at `$0480` inside the **VIC-1211A Super Expander's** 3 KiB expansion RAM and is invoked from **BASIC** with `SYS 1152`.

<br>

> ***See also:** [**Code Probe** (**C64**)](https://github.com/rohingosling/code-probe-c64) — For the **Commodore 64** verison of **Code Probe**.*


## 📑 Contents

- [🔎 Overview](#-overview)
- [🚀 Quick Start](#-quick-start)
- [🕒 History](#-history)
- [💾 Loading and Starting](#-loading-and-starting)
- [📝 Command Reference](#-command-reference)
- [⚖️ Compared to Other **VIC-20** Monitors](#-compared-to-other-vic-20-monitors)
- [💻 Building From Source](#-building-from-source)
- [👪 **Code Probe** Family](#-code-probe-family)
- [🙋‍♂️ Acknowledgements](#-acknowledgements)
- [📄 License](#-license)

<br>

## 🔎 Overview 

**Code Probe** is a software-based machine language monitor that runs in the 3 KiB expansion RAM of the **VIC-1211A Super Expander** cartridge and produces machine language programs that run on a stock unexpanded **VIC-20** with no cartridge. The **Super Expander** must be inserted at boot; without it, there is no RAM at `$0480` for **Code Probe** to live in.

The design of **Code Probe** was inspired by the DOS `DEBUG` utility, and presents a similar terminal-style user interface and commands. All numeric input is hexadecimal. Addresses are 4 digits, byte values are 2 digits, file types are 2 digits.

### Features

- **Memory inspection** - Hex dump with PETSCII character display.
- **Memory editing** - Interactive alter mode with cursor navigation, auto-space between bytes, and auto-commit at five bytes per line.
- **Register display** - View A, X, Y, and P (with expanded flag bits) captured at the moment the most recent `G` command returned.
- **Program execution** - Run machine language programs via a JSR trampoline; the user routine returns to the monitor with `RTS`.
- **Tape I/O** - Save and load PRG and SEQ files to and from a Datasette. PRG files round-trip with the original load address; SEQ files carry raw bytes only.
- **Screen control** - Clear the display with a single command.
- **Exit to BASIC** - Return to **BASIC's** `READY.` prompt; re-enter **Code Probe** with `SYS 1152`.

<br>

## 🚀 Quick Start

Want to just run **Code Probe**? Download what you need from the v1.1 release:

| File                                  | Download                                                                                                               | Use case                                                          |
|---------------------------------------|------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------|
| `code-probe.prg`                      | [download](https://github.com/rohingosling/code-probe-vic-20/releases/download/v1.1/code-probe.prg)                    | Run on **VICE**, or load on a real **VIC-20** via **SD2IEC** / 1541 |
| `code-probe-vic20.tap`                | [download](https://github.com/rohingosling/code-probe-vic-20/releases/download/v1.1/code-probe-vic20.tap)              | Load on a real **VIC-20** via **TAPuino**, or record onto a cassette |
| `code-probe-user-manual-vic-20.pdf`   | [download](https://github.com/rohingosling/code-probe-vic-20/releases/download/v1.1/code-probe-user-manual-vic-20.pdf) | Read the manual                                                   |

You'll also need either a physical **VIC-1211A Super Expander** cartridge if you're using a physical **VIC-20**, or a **VIC-1211A Super Expander** ROM if you're using an emulator. In the case of a ROM for emulation, see [**Super Expander** ROM](#super-expander-rom) for the download link and setup.

### **Run on VICE**

```bash
xvic -memory 3k -cartA super-expander-a000.prg -autostart code-probe.prg
```

The `-memory 3k` flag in the command line enables the 3 KiB Block 0 RAM that **Code Probe** loads into. If you're configuring **VICE** through the GUI instead, enable **Block 0 (3 KiB)** in **VICE's** memory settings before launching — without it there's no RAM at `$0480` for **Code Probe** to land.

### **Run on real hardware**

Startup the **VIC-20** with a **VIC-1211A Super Expander** cartridge inserted. The load command depends on the device you're loading from:

| Loading device                                              | File                   | Load command             |
|-------------------------------------------------------------|------------------------|--------------------------|
| **TAPuino**, or `code-probe-vic20.tap` recorded onto a cassette | `code-probe-vic20.tap` | `LOAD "CODEPROBE",1,1`   |
| **SD2IEC** / **Pi1541** / 1541 Ultimate / real 1541 floppy  | `code-probe.prg`       | `LOAD "CODE-PROBE",8,1`  |

Then type `RUN` to start. See [Loading and Starting](#-loading-and-starting) for how to put `code-probe-vic20.tap` onto a real cassette, or `code-probe.prg` onto a real 1541 disk.

<br>

## 🕒 History

I originally wrote **Code Probe** in 1988 on a **Commodore VIC-20** with the **VIC-1211A Super Expander** cartridge. As a teenager I always wanted a cartridge with a monitor. I did end up getting a cartridge, the **Super Expander**, but it never came with a monitor. It *did*, however, have 3K of extra RAM, which at the time got me thinking, how hard could it be to make my own machine language monitor?

It turns out monitors aren't super complicated, especially a minimal one like **Code Probe**. You're basically just building a simple CLI that lets a user poke values into RAM, except using load and store (`LDA`, `STA`) instead of `POKE`. The monitor itself can be hand assembled on paper and poked in via a **BASIC** machine language loader, which is how I built the very first version of **Code Probe**, using [HEX-Loader](https://github.com/rohingosling/c64-hex-loader/tree/main).

The real challenge with building large machine language programs in the 80's without any decent tooling was not so much learning machine language as a kid, but rather, the painstaking workflow one had to perform to get anything into RAM. Debugging, as we know it today, was basically non-existent. So unless you had a commercial cartridge-based monitor with decent tooling and debugging features, the only way was to carefully build a library of small easy to test subroutines, which could be strung together with a fair degree of confidence that no bugs were there in the first place. An ideal that rarely panned out, but, that was the idea. My workflow involved designing isolated, highly modular, highly parameterised, machine language subroutines that I could painstakingly hand-assemble and poke into RAM with a **BASIC** loader one at a time, testing each one in isolation before being confident that they were bug free enough to brave using in larger programs.

My goal with **Code Probe** was simply to get a machine language monitor I could use to make games and other programs. However, by the time the 80's had come to a close, **Code Probe** had taken so long to write, that it was basically all I had to show for my efforts, aside from a few incomplete graphics demos. The [interactive 3D cube demo](https://github.com/rohingosling/3d-cube-commodore) being the most complete of them all worth showing off today.

I no longer have the original physical **VIC-20** today, but I did end up getting a **Commodore 64** in the early 1990s, which I used to copy **Code Probe's** PRG from tape to disk and make a **C64** version of **Code Probe**. From there, both the **VIC-20** and **C64** versions eventually made their way onto SD card in the early 2000s via **SD2IEC**. And then from SD card onto PC hard drive, where they remained dormant for many decades. ...Until now! 🎉

In 2026, just to see if it could be done, I fished out the PRG binaries and set about disassembling them into modern [Kick Assembler](http://www.theweb.dk/KickAssembler/) source listings for both. I'm pleased to report, it worked! Along the way I fixed a handful of long-standing bugs and made one or two small improvements.

Although the rebuilt versions aren't byte-for-byte identical to the originals, for the sake of nostalgia I kept the original attribution lines exactly as they appeared on the 1988 and 1990 builds: `ROHIN GOSLING (1988)` for the **VIC-20** version, and `ROHIN GOSLING (1990)` for the **C64** version. But they both do have a fresh coat of 2026 paint, courtesy of [Kick Assembler](http://www.theweb.dk/KickAssembler/).

<br>

## 💾 Loading and Starting

**Code Probe** loads at address `$0480` (1152 decimal) and occupies 2614 bytes of RAM in the `$0480`-`$0EB5` region of the **Super Expander's** expansion RAM. The full PRG file is 2743 bytes: a 13-byte **BASIC** stub at `$0401-$040D`, a zero-fill gap, the monitor body at `$0480-$0EB5`, plus the standard 2-byte PRG header. The native **VIC-20** RAM at `$1001-$1DFF` is left free for user machine language programs.

### **From the VICE Emulator**

There are several ways to launch **Code Probe** in **VICE**. Run all commands from the repository root so the relative paths to `roms/` and `build/` resolve. `xvic` must be on `PATH`, or substitute the full path to your **VICE** install.

#### **Launch with program file, `code-probe.prg`**

- To launch `xvic` with the **Super Expander** cartridge attached, the 3 KiB Block 0 RAM enabled, and `build/code-probe.prg` autostarted into the monitor:

  ```bash
  xvic -memory 3k -cartA roms/super-expander-a000.prg -autostart build/code-probe.prg
  ```

#### **Launch with tape image, `code-probe-vic20.tap`**

- **VICE** can autostart `build/code-probe-vic20.tap` the same way, in which case it drives the emulated Datasette through the load sequence and runs the program:

  ```bash
  xvic -memory 3k -cartA roms/super-expander-a000.prg -autostart build/code-probe-vic20.tap
  ```

#### **Launch bare VIC-20 + Super Expander, attach tape image and load from BASIC**

- To boot a bare Super-Expanded **VIC-20** and load **Code Probe** from tape by hand:

  ```bash
  xvic -memory 3k -cartA roms/super-expander-a000.prg
  ```

- Once **VICE** is running, attach the tape image via **File → Attach tape image → Attach to Datasette 1...** and select `build/code-probe-vic20.tap`. Then at the **BASIC** prompt:

  ```
  LOAD "CODEPROBE",1,1
  ```
  Then
  ```
  RUN
  ```
  or
  ```
  SYS 1152
  ```

- If the load does not begin automatically, press PLAY on the on-screen Datasette control panel in the status bar at the bottom of the **VICE** window.

### What happens at startup

1. The screen border and background are set to black via VIC-I register `$900F`.
2. The KERNAL text colour at `$0286` is set to white.
3. The screen is cleared via `CHROUT $93`.
4. The title banner is displayed:

   ```
   CODE PROBE      (v1.1)
   ROHIN GOSLING   (1988)
   ```

5. A blank line separates the banner from the first prompt.
6. The monitor prompt loop begins.

   ```
   CODE PROBE      (v1.1)
   ROHIN GOSLING   (1988)

   : █
   ```

### **From Real Hardware**

The published v1.1 release ships two prebuilt artefacts: `code-probe-vic20.tap` for tape-based loading and `code-probe.prg` for disk-based loading. Pick the path that matches the storage device attached to your **VIC-20**. All four paths assume the **VIC-1211A Super Expander** cartridge is inserted at boot.

#### TAPuino (SD-card tape emulator)

A [**TAPuino**](https://github.com/sweetlilmre/TAPuino) is an Arduino-based device that plugs into the **VIC-20's** cassette port and synthesises Datasette pulses from `.tap` files on an SD card. Stock Kernal, no patches required.

1. Copy `code-probe-vic20.tap` to the SD card.
2. Plug the **TAPuino** into the cassette port and select `code-probe-vic20.tap` in its file browser.
3. On the **VIC-20**, type `LOAD "CODEPROBE",1,1`, then press the **TAPuino's** PLAY button when prompted.
4. After the load completes, type `RUN`.

#### Real Cassette in a Datasette

The literal "physical tape" path. `.tap` is a PC-side container of pulse timings; a stock Datasette only reads cassette audio, so the file must first be rendered to audio and recorded onto a blank cassette.

1. Convert `code-probe-vic20.tap` to a `.wav` audio file using [Audiotap](http://wav-prg.sourceforge.net) (formerly WAV-PRG) or `prg2wav`.
2. Connect your PC's line-out (not headphone) to the line-in of a regular cassette deck. Set a clean, healthy recording level — loud enough to be unambiguous, not so loud the deck clips.
3. Insert a blank C-60 or C-90 ferric (Type I) cassette and record the `.wav` from the PC.
4. Rewind the cassette, insert it into the Datasette, and press PLAY.
5. On the **VIC-20**, type `LOAD "CODEPROBE",1,1`, then `RUN` once the load completes.

Tape head alignment varies between machines and the recording process compounds tolerances, so expect to retry a few loads. This is true to the 1981 user experience.

#### SD2IEC, Pi1541, or similar IEC-bus disk emulator

These devices plug into the **VIC-20's** IEC serial port (device 8) and serve files from an SD card as if a real 1541 drive were attached. The simplest modern path.

1. Copy `code-probe.prg` to the SD card.
2. Plug the device into the **VIC-20's** serial port and power it on.
3. Use the device's UI to navigate to the folder containing `code-probe.prg`.
4. On the **VIC-20**, type:

   ```
   LOAD "CODE-PROBE",8,1
   RUN
   ```

#### Real 1541 Floppy Disk

Writing `code-probe.prg` to a physical 5¼″ floppy requires bridging modern hardware to the IEC bus, since PCs cannot read or write GCR-encoded Commodore disks natively.

1. Connect a [ZoomFloppy](https://store.go4retro.com) USB adapter to a working 1541 / 1541-II drive via the IEC cable. Insert a blank floppy.
2. On the PC, install [OpenCBM](https://github.com/OpenCBM/OpenCBM) and run:

   ```bash
   cbmformat 8 "code probe,01"
   cbmwrite 8 code-probe.prg
   ```

3. Move the disk to the **VIC-20's** 1541, then on the **VIC-20**:

   ```
   LOAD "CODE-PROBE",8,1
   RUN
   ```

In every case the trailing `,1` is the secondary address — it tells the KERNAL to load the file at the address in its PRG header (`$0401`) rather than the default expanded-machine **BASIC** area. `RUN` invokes the embedded **BASIC** stub, which executes `SYS 1152` and transfers control to the monitor. `SYS 1152` typed by hand at the **BASIC** prompt has the same effect.

<br>

## 📝 Command Reference

All address and count values are hexadecimal. Addresses are 4 digits, byte values are 2 digits, file types are 2 digits. Command dispatch is single-character: `C`, `CLS`, and `CLEAR` all route to the clear-screen command; `E`, `EXIT`, and `END` all route to the exit-to-**BASIC** command.

| Command | Syntax                          | Description                                              |
|---------|---------------------------------|----------------------------------------------------------|
| `A`     | `A <address>`                   | Enter alter mode to write hex bytes to RAM.              |
| `D`     | `D <start> [<end>]`             | Hex dump memory from start to end (inclusive).           |
| `R`     | `R`                             | Display A, X, Y, and P (with expanded flag bits).        |
| `G`     | `G <address>`                   | Execute machine code at address; capture post-RTS regs.  |
| `S`     | `S <start> <end> <type>`        | Save tape file. `<type>` = `01` PRG, `00` SEQ.           |
| `L`     | `L <filename>`                  | Load PRG file (uses file's load address).                |
| `L`     | `L <filename> <address>`        | Load SEQ file to specified address.                      |
| `CLS`   | `CLS`                           | Clear the screen.                                        |
| `EXIT`  | `EXIT`                          | Exit to **BASIC**. Re-enter with `SYS 1152`.             |

The `S` command splits across two lines: the first line names the address range and the file type, and the second line is an auto-prompted `FILE:` entry for the filename (up to 16 characters, unquoted). Splitting the filename off the command line means long names do not have to fit alongside three other tokens on the 22-column screen.

See [`docs/code-probe-user-manual-vic-20.pdf`](docs/code-probe-user-manual-vic-20.pdf) for the full user manual, including worked tutorials, the memory map, error messages, a quick reference card, and an appendix on attaching the **Super Expander** cartridge under **VICE**.

<br>

## ⚖️ Compared to Other VIC-20 Monitors

The **VIC-20** has had several machine language monitors over the years, from full-featured commercial cartridges to minimal type-in listings published in magazines. **Code Probe** sits at the smaller, more focused end of that spectrum. Originally a type-in-style program that runs inside the **Super Expander's** existing 3 KiB RAM rather than requiring its own cartridge. Now converted into a modern open source assembly listing for [**Kick Assembler**](http://www.theweb.dk/KickAssembler/).

| Monitor | Year | Form & Size | Notable Features |
|---------|------|-------------|------------------|
| **Code Probe** <br>*(this project)* | 1988 | Tape PRG, ~2 KB at `$0480` (in **Super Expander** RAM) | Hex dump, alter mode, registers, JSR run, PRG and SEQ tape I/O. <br>MIT-licensed modern 2026 assembly rebuild from the original 1988 binaries. |
| **VICMON** <br>(VIC-1213) | 1982 | Cartridge, 4 KB ROM at `$6000` | Commodore's first-party monitor. Assembler, disassembler, breakpoints, single-step. The full-featured option. |
| **HESMON** <br>(HES C302) | 1982 | Cartridge, 4 KB ROM | Commercial cartridge from HES (Terry Peterson). Assembler and disassembler. |
| **Super VICMON** | early 1980s | Type-in PRG, ~3 KB | Jim Butterfield's SuperMon ported to **VIC-20** by David A. Hook. Hunt, transfer, mini-assembler, disassembler. |
| **TINYMON1** | 1982 | Type-in PRG, ~760 bytes | Jim Butterfield (COMPUTE! issue 20). `M`, `R`, `G`, `S`, `L`, `X` — the closest scope analogue to **Code Probe** in this list. |

<br>

## 💻 Building From Source

**Code Probe** is a single-file assembly project built with [Kick Assembler](http://www.theweb.dk/KickAssembler/). Java is required.

**Assemble:**

```bash
java -jar KickAss.jar src/code-probe-vic-20.asm -odir build
```

The build produces `build/code-probe.prg` — a 2743-byte PRG that loads at `$0401` (the **BASIC** start of an unexpanded **VIC-20**). The same PRG runs on a physical **VIC-20** with the **VIC-1211A Super Expander** cartridge inserted, and on the **VICE** emulator with the **Super Expander** ROM image attached.

### Running on a Physical VIC-20

Hardware required:

- A **Commodore VIC-20** (PAL or NTSC).
- A **VIC-1211A Super Expander** cartridge inserted at boot. **Code Probe** loads at `$0480`, inside the cartridge's 3 KiB expansion RAM, and will not run without it.
- A means of transferring `build/code-probe.prg` (or a `.tap` rendering) from the build host to the **VIC-20** — see [Loading and Starting](#-loading-and-starting) for the supported paths and the load command for each.

### Running in VICE

```bash
xvic -memory 3k -cartA roms/super-expander-a000.prg -autostart build/code-probe.prg
```

Run from the repository root so the relative paths resolve. `xvic` must be on `PATH`, or substitute the full path to your **VICE** install (e.g. `C:\Programs\GTK3VICE-3.10-win64\bin\xvic.exe` on Windows, `/usr/bin/xvic` on most Linux distributions).

#### Super Expander ROM

The **VIC-1211A Super Expander** cartridge image is not redistributed in this repository. Download it from the Zimmers archive and place it at `roms/super-expander-a000.prg`:

[http://www.zimmers.net/anonftp/pub/cbm/vic20/roms/tools/4k/](http://www.zimmers.net/anonftp/pub/cbm/vic20/roms/tools/4k/)

The expected file is a 4098-byte PRG with a `$A000` load-address header (4096 bytes of ROM plus a 2-byte header).

> **Note:**<br>Two versions of the **VIC-1211 Super Expander** are available on zimmers.net. The `VIC1211m`, originally targeting the Japanese market in the 1980s, and the standard **VIC-1211A**, listed as `Super Expander.prg` on the download page. For **Code Probe**, download the standard **VIC-1211A** (`Super Expander.prg`) and rename it to `super-expander-a000.prg` so the `xvic -cartA` argument resolves. The `-a000` filename suffix is a **VICE** smart-attach hint.

### Tape Images

`code-probe-vic20.tap` is the project's primary tape image — a Datasette-format archive containing the compiled `CODEPROBE` PRG (the v1.1 monitor binary).

Additional tape images live in `dist/examples/`: `hello.tap` / `hello2.tap` (minimal "hello world" greeters demonstrated in the user manual's tutorial chapter). These are round-trip test fixtures and tutorial subjects, not part of **Code Probe** itself.

<br>

## 👪 Code Probe Family

There are two main versions of **Code Probe**. The original 1988 **VIC-20** version, and then the 1990 port to **C64**. Both were rebuilt in 2026 from their original PRG binaries using [Kick Assembler](http://www.theweb.dk/KickAssembler/).

| Machine  | Repository | Original | Status |
|----------|------------|----------|--------|
| **Commodore VIC-20** | [code-probe-vic-20](https://github.com/rohingosling/code-probe-vic-20) | 1988 | v1.1 — This repo |
| **Commodore 64** | [code-probe-c64](https://github.com/rohingosling/code-probe-c64) | 1990 | v1.1 — **Commodore 64** version remo |

<br>

## 🙋‍♂️ Acknowledgements

| Tool                                                       | Author&nbsp;/&nbsp;Maintainer | Role in this project                                                                                          |
|------------------------------------------------------------|-------------------------------|---------------------------------------------------------------------------------------------------------------|
| [Kick&nbsp;Assembler](http://www.theweb.dk/KickAssembler/) | Mads&nbsp;Nielsen             | 6502 cross-assembler. Builds `codeprobe.prg` from `code-probe-vic-20.asm`.                                            |
| [**VICE**](https://vice-emu.sourceforge.io/)               | The&nbsp;**VICE**&nbsp;Team   | Commodore emulator suite. `xvic` and `x64sc` for development and testing.                                     |
| [**C64**&nbsp;TrueType](https://style64.org/c64-truetype)  | STYLE                         | TrueType **C64** font set. Used to typeset the user manual in an authentic Commodore style.                   |

<br>

## 📄 License

Released under the [MIT License](LICENSE) — Copyright © 1988 Rohin Gosling.
