//*******************************************************************************
//
// Project:      Code Probe (VIC-20)
// Version:      1.1
// Release Date: 1988
// Last Updated: 2026-04-23
// Author:       Rohin Gosling
//
// DESCRIPTION:
//
//   Code Probe is a minimal machine-language monitor for the Commodore
//   VIC-20 with the VIC-1211A Super Expander cartridge attached. It
//   lives in the cartridge's 3 KiB expansion RAM at $0480 and provides
//   five commands for authoring ML programs that target an unexpanded,
//   cartridge-less VIC-20:
//
//     A  Alter   Enter bytes into memory.
//     D  Dump    Hex + PETSCII dump of a memory range.
//     G  Go      JSR to a user routine and return to the monitor.
//     L  Load    Tape load.
//     S  Save    Tape save.
//
//   This is the 2026 reconstruction of the lost 1988 original, which
//   was written in VIC-20 BASIC with hand-assembled ML entered as
//   decimal DATA / POKE statements. See docs/requirements.md for the
//   command-level specification and docs/architecture.md for the memory
//   map, zero-page allocations, KERNAL dependencies, and dispatch.
//
// USAGE:
//
//   LOAD "CODE-PROBE", 1, 1
//   SYS 1152
//
// BUILD (run from the v1 / project-root directory):
//
//   java -jar KickAss.jar src/code-probe-vic-20.asm -odir ../build
//
// NOTE: KickAssembler resolves -odir relative to the SOURCE file's
// directory, not the current working directory. code-probe-vic-20.asm
// lives in src/, so "../build" resolves to v1/build/. The VS Code
// Kick Assembler extension uses a different resolver and correctly
// lands output in v1/build/ when outputDirectory is set to "build".
//
// RUN IN VICE (VIC-20 with VIC-1211A Super Expander):
//
//   run-code-probe.bat
//
// DEVELOPMENT PHASES:
//
//   1. Toolchain stub:     print 'A' from $0480, verify build + run.    (done)
//   2. Echo terminal:      banner + read-print main loop.                (done)
//   3. Parsing utilities:  hex parsers, tokeniser, printers, errors.     (done)
//   4. D (Dump):           hex + PETSCII sidebar.                        (done)
//   5. A (Alter):          inline multi-byte editor.                     (done)
//   6. G (Go):             JSR trampoline to user ML.                    (done)
//   7. S (Save):           tape SAVE via KERNAL.                         (done)
//   8. L (Load):           tape LOAD via KERNAL (SA = 1).                <-- CURRENT
//   9. Polish + round-trip: size check + 3D Cube end-to-end test.
//
//*******************************************************************************


//==============================================================================
// Text Encoding
//==============================================================================
//
// petscii_upper is the standard upper / graphics encoding used by the
// KERNAL character I/O routines. Any character or string literals below
// are assembled in this encoding, so #'A' becomes $41 at assembly time.

.encoding "petscii_upper"


//==============================================================================
// Output PRG Filename
//==============================================================================
//
// Kick Assembler names the output .prg after the source file stem by
// default, which would produce build/code-probe-vic-20.prg. This
// project's run-code-probe.bat and the GitHub release manifest both
// reference build/code-probe.prg, so override the output filename here
// so both the CLI and the VS Code Kick Assembler extension produce the
// same, short name regardless of how the build is invoked.

.file     [ name = "code-probe.prg", segments = "CodeProbe" ]
.segmentdef CodeProbe
.segment    CodeProbe


//==============================================================================
// Constants
//==============================================================================

// KERNAL routines (VIC-20 jump table; see docs/architecture.md section 5).

.const KERNAL_CHROUT            = $FFD2         // Output a PETSCII byte to the current output device.
.const KERNAL_CHRIN             = $FFCF         // Read a PETSCII byte from the current input device (line-buffered, blocking).
.const KERNAL_GETIN             = $FFE4         // Poll the keyboard buffer non-blocking (used by cmd_a's key loop).
.const KERNAL_SETLFS            = $FFBA         // Set logical file, device, secondary address.
.const KERNAL_SETNAM            = $FFBD         // Set filename pointer and length.
.const KERNAL_SAVE              = $FFD8         // SAVE: write memory range as PRG (2-byte load-address header prepended).
.const KERNAL_LOAD              = $FFD5         // LOAD: read a file, either to its header address or to a caller-supplied one.
.const KERNAL_OPEN              = $FFC0         // Open the logical file configured by SETLFS / SETNAM.
.const KERNAL_CLOSE             = $FFC3         // Close a logical file.
.const KERNAL_CHKIN             = $FFC6         // Redirect CHRIN input from a logical file.
.const KERNAL_CHKOUT            = $FFC9         // Redirect CHROUT output to a logical file.
.const KERNAL_CLRCHN            = $FFCC         // Restore default CHROUT / CHRIN device.

// VIC-I and KERNAL-managed system addresses.

.const VIC_SCREEN_BORDER        = $900F         // Border / background / reverse-mode byte.
.const CURRENT_TEXT_COLOR       = $0286         // Colour CHROUT uses for subsequent characters.
.const BASIC_WARM_START         = $C002         // BASIC ROM warm-start vector (indirect). jmp ($C002) restarts BASIC with program + vars intact.

// Zero-page allocations (see docs/architecture.md section 4).

.const ZP_SCRATCH               = $02           // Temporary scratch byte (parser nibble stash, commit byte assembly).
.const KERNAL_STATUS_BYTE       = $90           // KERNAL I/O status byte (ST). Bit 6 set = end-of-file on tape read; non-zero-non-$40 = I/O error.
.const KEYBOARD_BUFFER_COUNT    = $C6           // KERNAL keyboard-buffer fill count. Zero drains pending keystrokes.
.const CURSOR_BLINK_ENABLE      = $CC           // Screen-editor blink flag. 0 = on, non-zero = off.
.const CURSOR_CHAR_UNDER        = $CE           // Original PETSCII code of the character under the cursor.
.const CURSOR_BLINK_PHASE       = $CF           // 0 = original char shown, non-zero = reverse-video phase shown.
.const CURSOR_LINE_POINTER      = $D1           // Pointer to start of current logical line in screen RAM (lo/hi = $D1/$D2).
.const CURSOR_COLUMN            = $D3           // Current cursor column within the logical line.
.const ZP_PTR_1                 = $FB           // 16-bit pointer, primary / destination. Lo at $FB, hi at $FC.

// PETSCII control codes and special keys.

.const CLEAR_SCREEN             = $93           // Clear screen.
.const CARRIAGE_RETURN          = $0D           // Move cursor to start of next line.
.const SPACE                    = $20           // ASCII / PETSCII space.
.const REVERSE_ON               = $12           // Subsequent CHROUT chars render reverse-video (glyph + background inverted).
.const REVERSE_OFF              = $92           // End reverse-video run; subsequent chars render normally again.
.const PETSCII_COLOR_WHITE      = $05           // CHROUT control: set text colour to white (writes $0286).
.const PETSCII_COLOR_BLUE       = $1F           // CHROUT control: set text colour to blue.

// Banner border characters. Three rows of solid graphic glyphs —
// one above the program-title line, one between the two title
// lines, and one below the author line — framing the banner on
// 22-column width. Each row is filled with a single PETSCII byte
// via .fill below.

.const BANNER_TOP_BAR_CHAR      = $AF
.const BANNER_MID_BAR_CHAR      = $A3
.const BANNER_BOTTOM_BAR_CHAR   = $64

// Banner width in columns. Fills the full VIC-20 text width.

.const BANNER_BAR_WIDTH         = 22
.const CURSOR_LEFT_KEY          = $9D           // Cursor-left key (also emittable via CHROUT).
.const CURSOR_RIGHT_KEY         = $1D           // Cursor-right key (also emittable via CHROUT).
.const CURSOR_UP_KEY            = $91           // Cursor-up key. Ignored by every Code Probe input mode.
.const CURSOR_DOWN_KEY          = $11           // Cursor-down key. Ignored by every Code Probe input mode.
.const DELETE_KEY               = $14           // INST / DEL without SHIFT.

// Colour palette (VIC-I colour nibble values).

.const COLOR_BLACK              = $00           // Black.
.const COLOR_WHITE              = $01           // White.

// Startup composite VIC_SCREEN_BORDER value ($900F):
//
//   bits 4-7  background colour (0-15). Black = 0 -> $00.
//   bit  3    reverse-mode flag. Set to 1 for normal (non-inverted) rendering.
//   bits 0-2  border colour (0-7). Black = 0 -> $00.
//
// Net value: $08 = black background, black border, normal display.
// VIC-20 has no per-cell background colour, so a coloured banner
// "bar" (e.g. blue) can only be rendered via reverse-video +
// per-cell colour-RAM (see the banner data below) — the text inside
// the bar ends up as the *global* background colour (black),
// because reverse inverts which pixel areas are foreground vs
// background and the background is what every cell shares.

.const SCREEN_BORDER_INIT       = $08

// Input buffer width. The physical screen is 22 columns, but KERNAL
// CHRIN can return a line up to the full logical width, so the buffer
// is generously sized at 40 bytes. The null terminator consumes one
// slot, leaving 39 printable characters.

.const INPUT_BUFFER_SIZE        = 40

// Token table capacity. Command lines have at most 4 tokens (e.g.
// "S 1001 1DD4 01") and Alter-mode lines at most 5 byte tokens plus
// the address prompt, so 8 slots is a roomy ceiling.

.const MAX_TOKENS               = 8

// D (Dump) row layout. Each row shows up to DUMP_BYTES_PER_ROW bytes
// so that the combined "AAAA: XX XX XX XX CCCC" line fills the 22-col
// screen exactly.

.const DUMP_BYTES_PER_ROW       = 4

// D (Dump) default range when the user omits <end>. DUMP_DEFAULT_SPAN
// is one less than the desired byte count: span + 1 = 64 = 16 rows.

.const DUMP_DEFAULT_SPAN        = $3F

// PETSCII printable range for the D-command sidebar. Bytes outside
// [DUMP_PRINTABLE_MIN, DUMP_PRINTABLE_MAX] are rendered as '.'.

.const DUMP_PRINTABLE_MIN       = $20
.const DUMP_PRINTABLE_MAX       = $7E

// A (Alter) auto-commit threshold. One "AAAA: " prompt (6 cols) plus
// 5 bytes formatted as "XX XX XX XX XX" (14 cols) fits the 22-col
// VIC-20 screen with 2 cols of margin; after the tenth nibble the
// line auto-commits instead of emitting a trailing separator space.

.const A_MAX_NIBBLES_PER_LINE   = 10

// Monitor-prompt input length cap. The ": " prompt occupies cols 0-1
// (0-indexed); user input starts at col 2 and must not advance the
// cursor past col 21 (the rightmost visible column on the 22-col
// VIC-20 screen) because that would trigger a CBM auto-wrap onto
// the next line. 22 - 2 - 1 = 19 characters fit in cols 2..20,
// leaving the cursor parked at col 21 after the 19th char.

.const MONITOR_PROMPT_MAX_CHARS = 19

// R (Register display) shadow-register offsets. cmd_g captures the
// user routine's final A / X / Y / P into these slots on the `G`
// command's post-RTS fall-through; cmd_r reads them for display.
// The write-side of R (setting registers for the next G) is out of
// scope — see docs/development-phases.md "Out of Scope".

.const REG_OFFSET_A             = 0
.const REG_OFFSET_X             = 1
.const REG_OFFSET_Y             = 2
.const REG_OFFSET_P             = 3
.const SHADOW_REGISTER_COUNT    = 4

// S (Save) / L (Load) filename buffer. CBM filenames are max 16 chars
// for both tape and disk. Longer input is rejected with
// ERROR: ILLEGAL VALUE.

.const FILENAME_BUFFER_SIZE     = 16

// Tape device number for SETLFS. Device 1 is the datasette.

.const TAPE_DEVICE              = 1

// Secondary addresses used by the S command.
//   PRG — KERNAL_SAVE with SA = 0. SAVE itself prepends the 2-byte
//         load-address header that BASIC's LOAD ",1,1" reads back.
//   SEQ — KERNAL_OPEN with SA = 1. Raw per-byte CHROUT writes
//         follow; no load-address header is emitted.

.const SAVE_SECONDARY_ADDRESS   = 0
.const SEQ_SECONDARY_ADDRESS    = 1

// L command PRG-mode secondary address. SA = 1 tells KERNAL_LOAD to
// read the load address from the file's PRG header block. The
// forced-address variant (SA = 0) was removed after Phase 8 testing
// because the L command now picks the mode from the token count —
// if an address is supplied the SEQ path (OPEN + CHRIN loop) is
// used instead of KERNAL_LOAD.

.const LOAD_SA_HEADER           = 1

// SEQ read OPEN uses SA = 0 on tape (tape's SA encoding: 0 = read).

.const TAPE_READ_SECONDARY_ADDRESS = 0

// KERNAL ST byte mask for end-of-file on tape/serial. Any other
// non-zero ST value during a CHRIN read is treated as an error.

.const KERNAL_ST_EOF_MASK       = $40

// S-command file-type flag values (parsed from the <type> token).

.const FILE_TYPE_SEQ            = $00
.const FILE_TYPE_PRG            = $01


//==============================================================================
// BASIC Upstart Stub
//==============================================================================
//
// Tokenised BASIC program "10 SYS 1152" at $0401. This is the BASIC
// program area under 3K RAM expansion, and is where VICE's -autostart
// RAM-injection places the PRG contents and then types RUN. The stub
// dispatches to the monitor at $0480 (1152 decimal), so -autostart
// loads the PRG, RUNs the stub, and the stub SYSes into entry.
//
// Without this stub, -autostart injects the monitor opcodes at $0401,
// RUN mis-parses them as BASIC, and ?SYNTAX ERROR blocks launch.
//
// The stub clobbers the Super Expander's $0401-$047F workspace, which
// is acceptable here: Code Probe never calls into the Super Expander
// BASIC extension ROM, so the SE's runtime state becoming stale has
// no functional impact on the monitor.
//
// Byte layout:
//
//     $0401-$0402: link pointer to next line (-> basic_end at $040D)
//     $0403-$0404: line number 10
//     $0405:       SYS token ($9E)
//     $0406-$040A: " 1152" in PETSCII (space + four digits)
//     $040B:       end-of-line null terminator
//     $040C-$040D: end-of-program marker ($0000)
//
// Bytes $040E-$047F are filled with zero by the $0480 origin jump
// below; the Super Expander no longer reads them after reset.
//
//==============================================================================

*= $0401 "BASIC Stub"

    .word basic_end, 10                         // Link pointer to next line, line number 10.
    .byte $9E                                   // SYS token.
    .text " 1152"                               // SYS target in decimal ($0480 = 1152).
    .byte $00                                   // End of line.
basic_end:
    .word $0000                                 // End of BASIC program marker.


//==============================================================================
// Program Entry Point
//==============================================================================
//
// Origin is $0480, inside the VIC-1211A Super Expander's 3 KiB RAM
// block at $0400-$0FFF. Reached from the BASIC upstart above via
// SYS 1152 after -autostart RUNs the injected PRG. The invoking SYS
// pushes its own return address onto the 6502 stack, so the eventual
// RTS out of main_loop (via RUN/STOP + RESTORE, on later phases)
// returns cleanly to BASIC's ready prompt.
//
//==============================================================================

*= $0480 "Code Probe"

entry:

    //--------------------------------------------------------------------------
    // Startup: set colours, clear the screen, print the banner, then
    // fall through to the monitor prompt loop.
    //--------------------------------------------------------------------------

    // Background = black, border = black, reverse mode off.

    lda #SCREEN_BORDER_INIT
    sta VIC_SCREEN_BORDER

    // CHROUT text colour = white.

    lda #COLOR_WHITE
    sta CURRENT_TEXT_COLOR

    // Clear the screen and home the cursor.

    lda #CLEAR_SCREEN
    jsr KERNAL_CHROUT

    // Print the startup banner.

    lda #<banner
    ldx #>banner
    jsr print_string

    // Fall through to main_loop.


//------------------------------------------------------------------------------
//
// Subroutine: main_loop
//
// Description:
//
//   The monitor's read-dispatch loop. Reads a line, tokenises it,
//   dispatches on the first character of token 0, and emits a blank
//   separator before the next prompt.
//
//   Per-iteration sequence:
//
//     1. Print ": " prompt.
//     2. Read a line from the keyboard into input_buffer (null-
//        terminated, up to INPUT_BUFFER_SIZE - 1 characters).
//     3. Print a newline so any output starts on its own line.
//     4. Tokenise the buffer in-place (spaces become nulls).
//     5. Dispatch on the first character of token 0.
//     6. Print a blank separator line.
//     7. Repeat.
//
//   Commands leave the cursor on the final line of their output with
//   no trailing newline; print_blank_line (two CRs) then produces
//   exactly one visible blank line before the next prompt.
//
// Parameters: None.
// Returns:    Never — loops until RUN/STOP + RESTORE breaks to BASIC.
// Clobbers:   A, X, Y, ZP_PTR_1, ZP_SCRATCH.
//
//------------------------------------------------------------------------------

main_loop:

    // Restore the screen palette before every prompt. A user routine
    // run via `G` (or any external code that touched VIC_SCREEN_BORDER /
    // CURRENT_TEXT_COLOR — e.g. POKEs from BASIC before SYS 1152) may
    // have changed border, background, or CHROUT colour. Re-setting
    // here guarantees the prompt and any subsequent command output
    // print white-on-black. Only future CHROUT picks up the new text
    // colour; cells the user's program already painted retain their
    // per-cell colour in colour RAM ($9600+) until the user issues
    // CLS.

    lda #SCREEN_BORDER_INIT
    sta VIC_SCREEN_BORDER
    lda #COLOR_WHITE
    sta CURRENT_TEXT_COLOR

    // Print the prompt ": ".

    lda #<prompt
    ldx #>prompt
    jsr print_string

    // Read a line from the keyboard via the bounded editor. The cap
    // is MONITOR_PROMPT_MAX_CHARS so the cursor never advances past
    // column 21 (the rightmost visible column); the editor's RETURN
    // handler emits its own trailing CR to park the cursor at col 0
    // of the next line before command dispatch.

    lda #MONITOR_PROMPT_MAX_CHARS
    sta input_line_max
    jsr read_bounded_line

    // Split the line into tokens.

    jsr tokenize

    // Empty input: skip dispatch and fall straight to the blank line.

    lda token_count
    beq main_loop_next_iteration

    // Fetch the first character of token 0 and dispatch.

    lda #$00
    jsr get_token_address
    ldy #$00
    lda ( ZP_PTR_1 ), y

    cmp #'A'
    beq main_loop_dispatch_a
    cmp #'C'
    beq main_loop_dispatch_c
    cmp #'D'
    beq main_loop_dispatch_d
    cmp #'E'
    beq main_loop_dispatch_e
    cmp #'G'
    beq main_loop_dispatch_g
    cmp #'L'
    beq main_loop_dispatch_l
    cmp #'R'
    beq main_loop_dispatch_r
    cmp #'S'
    beq main_loop_dispatch_s
    jmp main_loop_unknown_command

main_loop_dispatch_a:

    jsr cmd_a
    jmp main_loop_next_iteration

main_loop_dispatch_c:

    // CLS is special — after cmd_cls emits the CLEAR_SCREEN control
    // code, the cursor is parked at (0, 0). main_loop_next_iteration
    // would then run print_blank_line (2 CRs) and leave the next
    // prompt on row 2, with two blank rows above it. Skip that step
    // by re-entering main_loop directly so the ": " prompt lands on
    // row 0 of the freshly cleared screen.

    jsr cmd_cls
    jmp main_loop

main_loop_dispatch_d:

    jsr cmd_d
    jmp main_loop_next_iteration

main_loop_dispatch_e:

    jmp cmd_exit                                // Tail call — cmd_exit never returns.

main_loop_dispatch_g:

    jsr cmd_g
    jmp main_loop_next_iteration

main_loop_dispatch_l:

    jsr cmd_l
    jmp main_loop_next_iteration

main_loop_dispatch_r:

    jsr cmd_r
    jmp main_loop_next_iteration

main_loop_dispatch_s:

    jsr cmd_s
    jmp main_loop_next_iteration

main_loop_unknown_command:

    lda #<error_unknown_command
    ldx #>error_unknown_command
    jsr print_error

main_loop_next_iteration:

    // Blank separator before the next prompt.

    jsr print_blank_line
    jmp main_loop


//------------------------------------------------------------------------------
//
// Subroutine: cmd_d
//
// Description:
//
//   Dump memory as hex + PETSCII, four bytes per row in 22-column
//   width. Syntax:
//
//     D <start>             — dump 64 bytes starting at <start>.
//     D <start> <end>       — dump the inclusive range [start, end].
//
//   Each row is formatted as
//
//     AAAA: XX XX XX XX CCCC      (full row, 22 columns)
//     AAAA: XX XX XX    CCC       (partial row; missing hex slots are
//                                  three spaces; sidebar shows only
//                                  present bytes — no right pad)
//
//   The sidebar prints each byte as its PETSCII glyph when in the
//   printable range [DUMP_PRINTABLE_MIN, DUMP_PRINTABLE_MAX], else as
//   '.'. A trailing summary row "XXXX (Y)" shows the byte count in
//   hex and decimal.
//
//   When <end> is omitted, the default end is clamped to $FFFF so
//   "D FFF8" dumps the last 8 bytes of memory without wrapping. The
//   row loop also breaks on wrap-past-$FFFF so ranges that end on
//   high memory terminate cleanly.
//
// Parameters: None (reads token_offsets / token_count).
// Returns:    None.
// Clobbers:   A, X, Y, ZP_PTR_1, ZP_SCRATCH, d_start_address,
//             d_current_address, d_end_address, d_scratch_address,
//             d_byte_count, hex_parse_result.
//
//------------------------------------------------------------------------------

cmd_d:

    // Require at least the command letter + a start-address argument.
    // Every carry-based error check below inverts its sense and uses
    // an unconditional JMP so cmd_d_error_illegal stays at its natural
    // spot at the end of the function, out of range of a direct
    // relative branch.

    lda token_count
    cmp #$02
    bcs cmd_d_token_count_ok
    jmp cmd_d_error_illegal

cmd_d_token_count_ok:

    // Parse token 1 (start address) into d_start_address and seed
    // d_current_address from the same value.

    lda #$01
    jsr get_token_address
    ldy #$00
    jsr parse_hex_word
    bcs cmd_d_start_parsed
    jmp cmd_d_error_illegal

cmd_d_start_parsed:

    lda hex_parse_result + 0
    sta d_start_address + 0
    sta d_current_address + 0
    lda hex_parse_result + 1
    sta d_start_address + 1
    sta d_current_address + 1

    // Token 2 (end address) is optional.

    lda token_count
    cmp #$03
    bcs cmd_d_parse_end_token

    // No end token: default to start + DUMP_DEFAULT_SPAN, clamping
    // to $FFFF on overflow so "D FFF8" dumps the last 8 bytes.

    clc
    lda d_current_address + 0
    adc #DUMP_DEFAULT_SPAN
    sta d_end_address + 0
    lda d_current_address + 1
    adc #$00
    sta d_end_address + 1
    bcc cmd_d_validate_range
    lda #$FF
    sta d_end_address + 0
    sta d_end_address + 1
    jmp cmd_d_validate_range

cmd_d_parse_end_token:

    lda #$02
    jsr get_token_address
    ldy #$00
    jsr parse_hex_word
    bcs cmd_d_end_parsed
    jmp cmd_d_error_illegal

cmd_d_end_parsed:

    lda hex_parse_result + 0
    sta d_end_address + 0
    lda hex_parse_result + 1
    sta d_end_address + 1

cmd_d_validate_range:

    // Reject end < start.

    lda d_end_address + 1
    cmp d_current_address + 1
    bcs cmd_d_validate_hi_ok
    jmp cmd_d_error_illegal

cmd_d_validate_hi_ok:

    bne cmd_d_row_loop
    lda d_end_address + 0
    cmp d_current_address + 0
    bcs cmd_d_row_loop
    jmp cmd_d_error_illegal

cmd_d_row_loop:

    jsr cmd_d_print_row

    // Advance d_current_address by DUMP_BYTES_PER_ROW. A carry out of
    // the high byte means we wrapped past $FFFF — exit the loop.

    clc
    lda d_current_address + 0
    adc #DUMP_BYTES_PER_ROW
    sta d_current_address + 0
    lda d_current_address + 1
    adc #$00
    sta d_current_address + 1
    bcs cmd_d_summary

    // If d_current_address > d_end_address, the range is exhausted.

    lda d_end_address + 1
    cmp d_current_address + 1
    bcc cmd_d_summary
    bne cmd_d_row_loop
    lda d_end_address + 0
    cmp d_current_address + 0
    bcc cmd_d_summary
    jmp cmd_d_row_loop

cmd_d_summary:

    // Byte count = ( end - start ) + 1.

    sec
    lda d_end_address + 0
    sbc d_start_address + 0
    sta d_byte_count + 0
    lda d_end_address + 1
    sbc d_start_address + 1
    sta d_byte_count + 1

    clc
    lda d_byte_count + 0
    adc #$01
    sta d_byte_count + 0
    lda d_byte_count + 1
    adc #$00
    sta d_byte_count + 1

    // Hex count "XXXX".

    lda d_byte_count + 0
    ldx d_byte_count + 1
    jsr print_hex_word

    // " (".

    lda #SPACE
    jsr KERNAL_CHROUT
    lda #'('
    jsr KERNAL_CHROUT

    // Decimal count.

    lda d_byte_count + 0
    ldx d_byte_count + 1
    jsr print_decimal_word

    // ")". Last character on the line — main_loop's print_blank_line
    // terminates the row and supplies the separator to the next prompt.

    lda #')'
    jmp KERNAL_CHROUT                           // Tail call.

cmd_d_error_illegal:

    lda #<error_illegal_value
    ldx #>error_illegal_value
    jmp print_error                             // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: cmd_d_print_row
//
// Description:
//
//   Prints one dump row starting at d_current_address: the address
//   prefix "AAAA: ", up to DUMP_BYTES_PER_ROW hex byte slots (padded
//   with "   " where the slot is past d_end_address), a separator
//   space, and a PETSCII sidebar covering only the present bytes.
//   Terminates the row with a newline.
//
//   ZP_PTR_1 is loaded with d_current_address so slot reads use
//   ( ZP_PTR_1 ), Y with Y being the slot index 0..3.
//
// Parameters: d_current_address, d_end_address.
// Returns:    None.
// Clobbers:   A, Y, ZP_PTR_1, d_scratch_address.
//
//------------------------------------------------------------------------------

cmd_d_print_row:

    // Set ZP_PTR_1 = d_current_address.

    lda d_current_address + 0
    sta ZP_PTR_1 + 0
    lda d_current_address + 1
    sta ZP_PTR_1 + 1

    // "AAAA: ".

    lda d_current_address + 0
    ldx d_current_address + 1
    jsr print_hex_word
    lda #':'
    jsr KERNAL_CHROUT
    lda #SPACE
    jsr KERNAL_CHROUT

    // Slot 0 is always present — the loop precondition guarantees
    // d_current_address <= d_end_address.

    ldy #$00
    lda ( ZP_PTR_1 ), y
    jsr print_hex_byte

    // Slots 1..DUMP_BYTES_PER_ROW - 1: leading space then "XX", or
    // three spaces if the slot is past d_end_address.

    ldy #$01

cmd_d_print_row_slot:

    cpy #DUMP_BYTES_PER_ROW
    beq cmd_d_print_row_hex_done

    jsr cmd_d_is_offset_in_range
    bcc cmd_d_print_row_slot_pad

    // In range: " XX".

    lda #SPACE
    jsr KERNAL_CHROUT
    lda ( ZP_PTR_1 ), y
    jsr print_hex_byte
    jmp cmd_d_print_row_slot_next

cmd_d_print_row_slot_pad:

    // Out of range: "   " (three spaces, same width as " XX").

    lda #SPACE
    jsr KERNAL_CHROUT
    jsr KERNAL_CHROUT
    jsr KERNAL_CHROUT

cmd_d_print_row_slot_next:

    iny
    jmp cmd_d_print_row_slot

cmd_d_print_row_hex_done:

    // Separator space before the sidebar.

    lda #SPACE
    jsr KERNAL_CHROUT

    // Sidebar: one PETSCII glyph per present byte; stop at the first
    // out-of-range slot so partial rows do not right-pad the sidebar.

    ldy #$00

cmd_d_print_row_sidebar:

    cpy #DUMP_BYTES_PER_ROW
    beq cmd_d_print_row_done

    jsr cmd_d_is_offset_in_range
    bcc cmd_d_print_row_done

    lda ( ZP_PTR_1 ), y

    cmp #DUMP_PRINTABLE_MIN
    bcc cmd_d_print_row_sidebar_dot
    cmp #DUMP_PRINTABLE_MAX + 1
    bcs cmd_d_print_row_sidebar_dot
    jmp cmd_d_print_row_sidebar_emit

cmd_d_print_row_sidebar_dot:

    lda #'.'

cmd_d_print_row_sidebar_emit:

    jsr KERNAL_CHROUT
    iny
    jmp cmd_d_print_row_sidebar

cmd_d_print_row_done:

    // A full 22-column row has already wrapped the cursor to column 0
    // of the next line — emitting another CR there would leave a
    // visible blank between rows. Partial rows end mid-line and do
    // need an explicit CR. Y is the sidebar byte count (= slots
    // present), so Y == DUMP_BYTES_PER_ROW iff this was a full row.

    cpy #DUMP_BYTES_PER_ROW
    beq cmd_d_print_row_full
    jmp print_newline                           // Tail call (partial row).

cmd_d_print_row_full:

    rts


//------------------------------------------------------------------------------
//
// Subroutine: cmd_d_is_offset_in_range
//
// Description:
//
//   Tests whether d_current_address + Y is within [d_current_address,
//   d_end_address]. Used by cmd_d_print_row to decide whether each
//   slot 0..3 has a byte behind it.
//
// Parameters:
//
//   Y - Slot offset from d_current_address (0..3).
//
// Returns:  Carry = 1 if the offset is in range, Carry = 0 otherwise.
//           Y preserved.
// Clobbers: A, d_scratch_address.
//
//------------------------------------------------------------------------------

cmd_d_is_offset_in_range:

    // d_scratch_address = d_current_address + Y.

    tya
    clc
    adc d_current_address + 0
    sta d_scratch_address + 0
    lda d_current_address + 1
    adc #$00
    sta d_scratch_address + 1

    // Compare against d_end_address. Carry set means end >= scratch.

    lda d_end_address + 1
    cmp d_scratch_address + 1
    bcc cmd_d_is_offset_out
    bne cmd_d_is_offset_in
    lda d_end_address + 0
    cmp d_scratch_address + 0
    bcc cmd_d_is_offset_out

cmd_d_is_offset_in:

    sec
    rts

cmd_d_is_offset_out:

    clc
    rts


//------------------------------------------------------------------------------
//
// Subroutine: cmd_a
//
// Description:
//
//   Interactive hex-digit editor. Syntax:
//
//     A <address>           — enter alter mode at <address>.
//
//   Each line prompts with "AAAA: " (flush left, matching the D
//   command's dump rows) and reads keystrokes one at a time via
//   KERNAL_GETIN. Hex digits are stored in a_nibble_buffer and echoed
//   on screen; a separator space is auto-inserted after every
//   completed byte. CURSOR_LEFT / CURSOR_RIGHT move between hex slots
//   hopping the separator spaces; DELETE erases the most recently
//   entered nibble at the frontier. The line auto-commits after
//   A_MAX_NIBBLES_PER_LINE (10 nibbles = 5 bytes on 22-col VIC-20)
//   or when the user presses RETURN. RETURN on an empty line exits.
//
//   Example:
//
//     : A 1000
//     1000: 00 1F E0 00 FF
//     1005: 2A 00 F0 00
//     1009:
//     0009 (9)
//
//   The first line auto-commits at the tenth nibble; the second is
//   committed by RETURN; the third is exited by an empty RETURN.
//
//   Port of the Phase-5 Alter mode in the C64 v2.1 reference at
//   X:\Commodore\C64\Projects\Code Probe\v1\src\codeprobe.asm, with
//   the screen layout adapted to 22 columns.
//
// Parameters: None (reads token_offsets / token_count from the A-line
//             that started the session).
// Returns:    None.
// Clobbers:   A, X, Y, ZP_PTR_1, ZP_SCRATCH, hex_parse_result, KERNAL
//             cursor zero-page state, a_line_address, a_total_bytes,
//             a_nibble_buffer, a_nibble_count, a_cursor_pos,
//             a_commit_byte_count.
//
//------------------------------------------------------------------------------

cmd_a:

    // Require at least the command letter + a start-address argument.

    lda token_count
    cmp #$02
    bcs cmd_a_have_start_token
    jmp cmd_a_error_illegal

cmd_a_have_start_token:

    // Parse token 1 (start address) into a_line_address.

    lda #$01
    jsr get_token_address
    ldy #$00
    jsr parse_hex_word
    bcs cmd_a_start_parsed
    jmp cmd_a_error_illegal

cmd_a_start_parsed:

    lda hex_parse_result + 0
    sta a_line_address + 0
    lda hex_parse_result + 1
    sta a_line_address + 1

    // Reset per-session state.

    lda #$00
    sta a_nibble_count
    sta a_cursor_pos
    sta a_total_bytes + 0
    sta a_total_bytes + 1

    // Drain the KERNAL keyboard buffer so no leftover keystrokes
    // from the A-line leak into the first GETIN poll.

    sta KEYBOARD_BUFFER_COUNT

    // Print the first line prompt and enter the key loop.

    jsr cmd_a_print_prompt

cmd_a_enable_cursor:

    // Re-enable the KERNAL cursor blink so the user can see where
    // the next hex digit will land while we wait on GETIN. The flag
    // is inverted: 0 = blink on, non-zero = blink off.

    lda #$00
    sta CURSOR_BLINK_ENABLE

cmd_a_key_loop:

    jsr KERNAL_GETIN
    beq cmd_a_key_loop                          // No key pending — keep polling.

    // Dispatch on the key code.

    cmp #CARRIAGE_RETURN
    bne cmd_a_not_return

    // RETURN: remove the blink from the screen, then commit or exit.

    jsr a_cursor_off
    lda a_nibble_count
    beq cmd_a_exit
    jsr a_commit_line
    jsr print_newline
    jsr cmd_a_print_prompt
    jmp cmd_a_enable_cursor

cmd_a_not_return:

    cmp #CURSOR_LEFT_KEY
    beq cmd_a_do_left
    cmp #CURSOR_RIGHT_KEY
    beq cmd_a_do_right
    cmp #DELETE_KEY
    beq cmd_a_do_delete

    // Hex digit? is_hex_digit preserves A so we can pass it through
    // to a_handle_hex_digit on success.

    jsr is_hex_digit
    bcc cmd_a_enable_cursor                     // Non-hex, non-command: ignore.

    jsr a_handle_hex_digit
    jmp cmd_a_enable_cursor

cmd_a_do_left:

    jsr a_handle_cursor_left
    jmp cmd_a_enable_cursor

cmd_a_do_right:

    jsr a_handle_cursor_right
    jmp cmd_a_enable_cursor

cmd_a_do_delete:

    jsr a_handle_delete
    jmp cmd_a_enable_cursor

cmd_a_exit:

    // Restore the cursor blink for the main_loop prompt that follows.

    lda #$00
    sta CURSOR_BLINK_ENABLE

    // Drop below the final empty prompt line and print the summary.

    jsr print_newline

    lda a_total_bytes + 0
    ldx a_total_bytes + 1
    jsr print_hex_word

    lda #SPACE
    jsr KERNAL_CHROUT
    lda #'('
    jsr KERNAL_CHROUT

    lda a_total_bytes + 0
    ldx a_total_bytes + 1
    jsr print_decimal_word

    lda #')'
    jmp KERNAL_CHROUT                           // Tail call.

cmd_a_error_illegal:

    // Pre-session validation failure (bad A-line tokens). Print the
    // error without entering the key loop.

    lda #<error_illegal_value
    ldx #>error_illegal_value
    jmp print_error                             // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: cmd_a_print_prompt
//
// Description:
//
//   Prints "AAAA: " (six columns, flush left, no indent) where AAAA
//   is a_line_address. Called before the key loop starts and after
//   every commit to open the next line's prompt.
//
// Parameters: a_line_address.
// Returns:    None.
// Clobbers:   A.
//
//------------------------------------------------------------------------------

cmd_a_print_prompt:

    lda a_line_address + 0
    ldx a_line_address + 1
    jsr print_hex_word

    lda #':'
    jsr KERNAL_CHROUT
    lda #SPACE
    jmp KERNAL_CHROUT                           // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: a_cursor_off
//
// Description:
//
//   Suppresses the KERNAL cursor blink and, if the blink is currently
//   in its reverse-video phase, restores the original character from
//   CURSOR_CHAR_UNDER to screen RAM so the reversed glyph doesn't get
//   left behind when we CHROUT over the cursor slot. Must be called
//   before any CHROUT that moves or overwrites the cursor position
//   while a_handle_hex_digit / a_handle_cursor_* / a_handle_delete
//   are running.
//
// Parameters: None.
// Returns:    None.
// Clobbers:   A, Y.
//
//------------------------------------------------------------------------------

a_cursor_off:

    // Disable the IRQ blink toggle.

    inc CURSOR_BLINK_ENABLE

    // If the blink is on its reverse-video phase, restore the stored
    // original character to the cursor slot in screen RAM.

    lda CURSOR_BLINK_PHASE
    beq a_cursor_off_done

    ldy CURSOR_COLUMN
    lda CURSOR_CHAR_UNDER
    sta ( CURSOR_LINE_POINTER ), y

    lda #$00
    sta CURSOR_BLINK_PHASE

a_cursor_off_done:

    rts


//------------------------------------------------------------------------------
//
// Subroutine: a_handle_hex_digit
//
// Description:
//
//   Handles a hex-digit keypress in Alter mode. Echoes the digit to
//   screen, stores its nibble value in a_nibble_buffer at
//   a_cursor_pos, advances the cursor, and (when a byte is completed
//   at the frontier and the line isn't yet full) emits a separator
//   space so the next byte lands on a clean slot. If the line just
//   hit A_MAX_NIBBLES_PER_LINE, auto-commits instead of the trailing
//   space and opens the next line's prompt.
//
// Parameters:
//
//   A - PETSCII hex digit (validated by caller via is_hex_digit).
//
// Returns:  None.
// Clobbers: A, X, Y, ZP_PTR_1, ZP_SCRATCH.
//
//------------------------------------------------------------------------------

a_handle_hex_digit:

    // Kill the blink before overwriting the cursor slot.

    pha
    jsr a_cursor_off
    pla

    // Echo the digit to screen.

    pha
    jsr KERNAL_CHROUT
    pla

    // Store the nibble value in the buffer.

    jsr char_to_nibble
    ldx a_cursor_pos
    sta a_nibble_buffer, x

    // Advance the cursor.

    inc a_cursor_pos

    // Extend the frontier if the cursor moved past it.

    lda a_cursor_pos
    cmp a_nibble_count
    bcc a_hex_byte_check
    beq a_hex_byte_check
    sta a_nibble_count

a_hex_byte_check:

    // Byte complete when cursor is even (finished a low nibble).

    lda a_cursor_pos
    and #$01
    bne a_hex_done                              // Odd: high nibble only.

    // Byte complete. Only auto-advance (space or commit) when we're
    // at the frontier — editing in the middle leaves the existing
    // layout alone.

    lda a_cursor_pos
    cmp a_nibble_count
    bne a_hex_advance

    // At the frontier: auto-commit if the line is now full, else
    // emit a separator space.

    lda a_nibble_count
    cmp #A_MAX_NIBBLES_PER_LINE
    beq a_hex_auto_commit

a_hex_advance:

    lda #SPACE
    jmp KERNAL_CHROUT                           // Tail call.

a_hex_auto_commit:

    jsr a_commit_line
    jsr print_newline
    jmp cmd_a_print_prompt                      // Tail call; prompt's
                                                //   RTS returns to cmd_a's
                                                //   key loop.

a_hex_done:

    rts


//------------------------------------------------------------------------------
//
// Subroutine: a_handle_cursor_left
//
// Description:
//
//   Moves the alter-mode cursor one hex-digit slot to the left,
//   hopping the separator space when crossing a byte boundary.
//   Clamped at the first hex-digit slot of the current line
//   (a_cursor_pos == 0).
//
// Parameters: None.
// Returns:    None.
// Clobbers:   A, Y.
//
//------------------------------------------------------------------------------

a_handle_cursor_left:

    lda a_cursor_pos
    beq a_cursor_left_done                      // Already at slot 0.

    jsr a_cursor_off

    dec a_cursor_pos

    // One screen-column left lands us on the slot we came from; a
    // second move is needed when we just crossed a byte boundary
    // (new cursor_pos is odd = low-nibble slot of the previous byte,
    // so the separator space sits between us and our target).

    lda #CURSOR_LEFT_KEY
    jsr KERNAL_CHROUT

    lda a_cursor_pos
    and #$01
    beq a_cursor_left_done

    lda #CURSOR_LEFT_KEY
    jsr KERNAL_CHROUT

a_cursor_left_done:

    rts


//------------------------------------------------------------------------------
//
// Subroutine: a_handle_cursor_right
//
// Description:
//
//   Moves the alter-mode cursor one hex-digit slot to the right,
//   hopping the separator space when crossing a byte boundary.
//   Clamped at the frontier — cursor cannot advance past
//   a_nibble_count, so the user can't park on an uninitialised slot.
//
// Parameters: None.
// Returns:    None.
// Clobbers:   A, Y.
//
//------------------------------------------------------------------------------

a_handle_cursor_right:

    lda a_cursor_pos
    cmp a_nibble_count
    bcs a_cursor_right_done                     // At frontier — can't advance.

    jsr a_cursor_off

    inc a_cursor_pos

    lda #CURSOR_RIGHT_KEY
    jsr KERNAL_CHROUT

    // If the new cursor_pos is even, we just crossed a byte boundary
    // and the separator space is one more column to the right.

    lda a_cursor_pos
    and #$01
    bne a_cursor_right_done

    lda #CURSOR_RIGHT_KEY
    jsr KERNAL_CHROUT

a_cursor_right_done:

    rts


//------------------------------------------------------------------------------
//
// Subroutine: a_handle_delete
//
// Description:
//
//   Deletes the most recent nibble entered in Alter mode. Only
//   operates at the frontier (a_cursor_pos == a_nibble_count); with
//   the cursor moved back into already-entered data, DEL is a no-op
//   so existing bytes don't get accidentally shifted.
//
//   When deleting a low nibble (a_nibble_count was even pre-delete,
//   odd after), the trailing separator space is also erased so the
//   cursor lands back on the low-nibble slot of the previous byte.
//   When deleting a high nibble, only the digit itself is erased.
//
// Parameters: None.
// Returns:    None.
// Clobbers:   A, Y.
//
//------------------------------------------------------------------------------

a_handle_delete:

    // Nothing to delete at slot 0.

    lda a_cursor_pos
    beq a_delete_done

    // Only at the frontier.

    cmp a_nibble_count
    bne a_delete_done

    jsr a_cursor_off

    dec a_nibble_count
    dec a_cursor_pos

    // After the decrement, a_nibble_count odd means we just deleted
    // a low nibble (both the digit and the trailing space must be
    // erased, two columns). Even means we deleted a high nibble.

    lda a_nibble_count
    and #$01
    bne a_delete_two

    // Erase one column (high nibble).

    lda #CURSOR_LEFT_KEY
    jsr KERNAL_CHROUT
    lda #SPACE
    jsr KERNAL_CHROUT
    lda #CURSOR_LEFT_KEY
    jmp KERNAL_CHROUT                           // Tail call.

a_delete_two:

    // Erase two columns (low nibble + trailing separator space).

    lda #CURSOR_LEFT_KEY
    jsr KERNAL_CHROUT
    lda #CURSOR_LEFT_KEY
    jsr KERNAL_CHROUT
    lda #SPACE
    jsr KERNAL_CHROUT
    lda #SPACE
    jsr KERNAL_CHROUT
    lda #CURSOR_LEFT_KEY
    jsr KERNAL_CHROUT
    lda #CURSOR_LEFT_KEY
    jmp KERNAL_CHROUT                           // Tail call.

a_delete_done:

    rts


//------------------------------------------------------------------------------
//
// Subroutine: a_commit_line
//
// Description:
//
//   Walks a_nibble_buffer, packs nibble pairs into bytes, writes them
//   to RAM at a_line_address, then:
//
//     - adds the byte count to a_total_bytes (the summary total),
//     - advances a_line_address by the byte count,
//     - resets a_nibble_count and a_cursor_pos to 0.
//
//   A trailing high-only nibble (a_nibble_count odd) is discarded —
//   incomplete bytes never get committed.
//
// Parameters: a_nibble_buffer, a_nibble_count, a_line_address.
// Returns:    None.
// Clobbers:   A, X, Y, ZP_PTR_1, ZP_SCRATCH.
//
//------------------------------------------------------------------------------

a_commit_line:

    // Number of complete bytes = nibble_count / 2.

    lda a_nibble_count
    lsr
    beq a_commit_reset                          // No complete bytes.
    sta a_commit_byte_count

    // Destination pointer = a_line_address.

    lda a_line_address + 0
    sta ZP_PTR_1 + 0
    lda a_line_address + 1
    sta ZP_PTR_1 + 1

    ldx #$00                                    // Nibble buffer index.
    ldy #$00                                    // Destination byte offset.

a_commit_write_loop:

    cpy a_commit_byte_count
    beq a_commit_update

    // High nibble → upper 4 bits.

    lda a_nibble_buffer, x
    asl
    asl
    asl
    asl
    sta ZP_SCRATCH
    inx

    // Low nibble → OR into upper.

    lda a_nibble_buffer, x
    ora ZP_SCRATCH
    sta ( ZP_PTR_1 ), y
    inx
    iny
    jmp a_commit_write_loop

a_commit_update:

    // a_total_bytes += byte count.

    lda a_commit_byte_count
    clc
    adc a_total_bytes + 0
    sta a_total_bytes + 0
    lda #$00
    adc a_total_bytes + 1
    sta a_total_bytes + 1

    // a_line_address += byte count.

    lda a_commit_byte_count
    clc
    adc a_line_address + 0
    sta a_line_address + 0
    lda #$00
    adc a_line_address + 1
    sta a_line_address + 1

a_commit_reset:

    // Reset nibble state so the next prompt starts fresh.

    lda #$00
    sta a_nibble_count
    sta a_cursor_pos
    rts


//------------------------------------------------------------------------------
//
// Subroutine: cmd_g
//
// Description:
//
//   Execute the user's ML routine at <address> via a self-modified
//   JMP trampoline, then return to the monitor prompt when the user
//   code RTSs. Syntax:
//
//     G <address>           — JSR to <address>.
//
//   Flow:
//
//     1. Parse the 4-digit hex address into hex_parse_result.
//     2. Patch the two operand bytes of the JMP at cmd_g_trampoline.
//     3. JSR cmd_g_trampoline — the trampoline's JMP lands at the
//        user address; the user's RTS pops back to the instruction
//        after our JSR.
//     4. RTS to main_loop, which emits the blank separator and the
//        next prompt.
//
//   No register or memory state is saved or restored around the
//   JSR — if the user's code corrupts zero page or clobbers KERNAL
//   workspace, that's on them. This matches the intentional SYS-style
//   semantics called out in docs/development-phases.md as out of scope
//   for this 1988-compatible reconstruction.
//
//   The user's code is responsible for terminating with RTS; a
//   runaway routine (no RTS, infinite loop, stack underflow) requires
//   a VIC-20 hard reset to recover.
//
// Parameters: None (reads token_offsets / token_count from the G-line).
// Returns:    None.
// Clobbers:   Whatever the user's code clobbers; the monitor itself
//             touches A, X, Y, ZP_PTR_1, ZP_SCRATCH, hex_parse_result,
//             and the two operand bytes at cmd_g_trampoline + 1.
//
//------------------------------------------------------------------------------

cmd_g:

    // Require at least the command letter + an address argument.

    lda token_count
    cmp #$02
    bcs cmd_g_have_address
    jmp cmd_g_error_illegal

cmd_g_have_address:

    // Parse token 1 into hex_parse_result.

    lda #$01
    jsr get_token_address
    ldy #$00
    jsr parse_hex_word
    bcs cmd_g_address_parsed
    jmp cmd_g_error_illegal

cmd_g_address_parsed:

    // Patch the trampoline's JMP operand (little-endian: lo then hi,
    // into the two bytes following the $4C opcode).

    lda hex_parse_result + 0
    sta cmd_g_trampoline + 1
    lda hex_parse_result + 1
    sta cmd_g_trampoline + 2

    // Jump into the user's code. The user's RTS returns here; we
    // immediately capture A / X / Y / P into shadow_registers so
    // the R command can display what the user's routine left behind.
    //
    // A is stored first (before PHP/PLA clobber it); P is fetched
    // from the stack via PHP + PLA. The crucial step is the CLD
    // *after* PHP — the user's routine may have executed SED, which
    // leaves the 6502 in decimal mode, which then turns every
    // subsequent ADC / SBC in Code Probe into BCD arithmetic. Left
    // unchecked that breaks get_token_address (its `adc #<input_buffer`
    // yields a BCD sum that lands the pointer in the wrong place),
    // and every command after the G silently falls through to
    // ERROR: UNKNOWN COMMAND. PHP captures the user's real P
    // (including the D bit the routine left set) so R can still
    // display it; CLD then clears D on the live processor so the
    // monitor's own arithmetic behaves again.

    jsr cmd_g_trampoline

    sta shadow_registers + REG_OFFSET_A
    stx shadow_registers + REG_OFFSET_X
    sty shadow_registers + REG_OFFSET_Y
    php
    cld
    pla
    sta shadow_registers + REG_OFFSET_P

    rts

cmd_g_trampoline:

    jmp $0000                                   // Operand self-modified above.

cmd_g_error_illegal:

    lda #<error_illegal_value
    ldx #>error_illegal_value
    jmp print_error                             // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: cmd_s
//
// Description:
//
//   Save a memory range to tape. Syntax:
//
//     S <start> <end> <type>
//     FILE: <name>
//
//   After the S-line parses cleanly, the monitor prints "FILE: " on
//   a new line and reads the filename as a second input step (up to
//   16 PETSCII chars). Splitting the filename off the command line
//   lets the user type long names without having to predict where
//   they'll wrap on the 22-col screen.
//
//   <type> is a two-digit hex byte selecting the on-tape file
//   format:
//
//     00 = SEQ  raw bytes [start, end], no load-address header.
//               Written via KERNAL_OPEN + CHKOUT + per-byte CHROUT
//               + CLRCHN + CLOSE. Useful for data blobs.
//     01 = PRG  2-byte little-endian load-address header (= <start>)
//               + the bytes [start, end]. Written via KERNAL_SAVE.
//               Loadable from BASIC with `LOAD "name",1,1` and
//               launchable with `SYS <decimal-start>`.
//
//   The KERNAL itself displays "PRESS RECORD & PLAY ON TAPE" and
//   "SAVING <name>" during either path.
//
//   Error paths (all print and exit without writing anything):
//
//     - fewer than 4 arguments (S, <start>, <end>, <type>)
//     - non-hex <start> or <end>
//     - end < start
//     - <type> is not exactly "00" or "01" (wrong width, non-hex,
//       or out-of-range byte)
//     - filename empty
//     - filename > 16 chars
//       -> ERROR: ILLEGAL VALUE
//     - KERNAL SAVE/OPEN/CHKOUT returns carry set (RUN/STOP mid-I/O,
//       tape error)
//       -> ERROR: FILE ERROR (plus CLOSE to release the logical file)
//
// Parameters: None (reads token_offsets / token_count for the S-line,
//             then read_line for the FILE prompt).
// Returns:    None.
// Clobbers:   A, X, Y, ZP_PTR_1, ZP_SCRATCH, hex_parse_result,
//             s_start_address, s_end_address, s_end_plus_one,
//             s_file_type, filename_buffer, filename_length,
//             input_buffer.
//
//------------------------------------------------------------------------------

cmd_s:

    // Require command letter + start + end + type = 4 tokens.

    lda token_count
    cmp #$04
    bcs cmd_s_parse_start
    jmp cmd_s_error_illegal

cmd_s_parse_start:

    // Parse token 1 (start address).

    lda #$01
    jsr get_token_address
    ldy #$00
    jsr parse_hex_word
    bcs cmd_s_start_ok
    jmp cmd_s_error_illegal

cmd_s_start_ok:

    lda hex_parse_result + 0
    sta s_start_address + 0
    lda hex_parse_result + 1
    sta s_start_address + 1

    // Parse token 2 (end address).

    lda #$02
    jsr get_token_address
    ldy #$00
    jsr parse_hex_word
    bcs cmd_s_end_ok
    jmp cmd_s_error_illegal

cmd_s_end_ok:

    lda hex_parse_result + 0
    sta s_end_address + 0
    lda hex_parse_result + 1
    sta s_end_address + 1

    // Reject end < start.

    lda s_end_address + 1
    cmp s_start_address + 1
    bcc cmd_s_range_bad
    bne cmd_s_parse_type
    lda s_end_address + 0
    cmp s_start_address + 0
    bcs cmd_s_parse_type

cmd_s_range_bad:

    jmp cmd_s_error_illegal

cmd_s_parse_type:

    // Token 3 must be exactly two hex digits parsing to either
    // FILE_TYPE_SEQ ($00) or FILE_TYPE_PRG ($01). Any other width,
    // non-hex character, or out-of-range byte is rejected as illegal.

    lda #$03
    jsr get_token_address

    ldy #$00
    jsr parse_hex_byte
    bcc cmd_s_range_bad
    sta s_file_type

    // Width check: parse_hex_byte left Y just past the second hex
    // digit, so ( ZP_PTR_1 ), y must now be the token's null
    // terminator. Anything else (e.g. "001", "01X") is wrong-width.

    lda ( ZP_PTR_1 ), y
    bne cmd_s_range_bad

    // Range check: only $00 and $01 are valid file-type values.

    lda s_file_type
    cmp #$02
    bcs cmd_s_range_bad

    //--------------------------------------------------------------------------
    // Filename entry mode. Print "FILE: " on the line main_loop's
    // read_bounded_line already landed us on, then run the bounded
    // editor with a 16-char cap so the user can't overflow
    // filename_buffer (and can DEL back from the wrap line when
    // they type the 16th character).
    //--------------------------------------------------------------------------

    lda #<file_prompt
    ldx #>file_prompt
    jsr print_string

    lda #FILENAME_BUFFER_SIZE
    sta input_line_max
    jsr read_bounded_line

    // Reject empty filename.

    lda input_buffer
    beq cmd_s_range_bad

    // Copy input_buffer into filename_buffer, capped at
    // FILENAME_BUFFER_SIZE. Empty was rejected above; over-long
    // falls through to error.

    ldy #$00

cmd_s_filename_copy_loop:

    lda input_buffer, y
    beq cmd_s_filename_copy_done
    cpy #FILENAME_BUFFER_SIZE
    bcs cmd_s_range_bad                         // > 16 characters.
    sta filename_buffer, y
    iny
    jmp cmd_s_filename_copy_loop

cmd_s_filename_copy_done:

    sty filename_length

    // Pre-compute end+1 for the PRG path's KERNAL_SAVE.

    clc
    lda s_end_address + 0
    adc #$01
    sta s_end_plus_one + 0
    lda s_end_address + 1
    adc #$00
    sta s_end_plus_one + 1

    // Dispatch on the file-type flag.

    lda s_file_type
    beq cmd_s_save_seq                          // 0 = SEQ
    jmp cmd_s_save_prg                          // 1 = PRG

cmd_s_save_seq:

    //--------------------------------------------------------------------------
    // SEQ write: OPEN + CHKOUT + per-byte CHROUT + CLRCHN + CLOSE.
    // No load-address header is written — the tape gets exactly the
    // bytes from [s_start_address, s_end_address].
    //--------------------------------------------------------------------------

    // SETLFS( logical = 1, device = tape, SA = 1 ). SA = 1 selects
    // "write" for tape OPEN.

    lda #$01
    ldx #TAPE_DEVICE
    ldy #SEQ_SECONDARY_ADDRESS
    jsr KERNAL_SETLFS

    // SETNAM( length, ptr_lo, ptr_hi ).

    lda filename_length
    ldx #<filename_buffer
    ldy #>filename_buffer
    jsr KERNAL_SETNAM

    // OPEN — shows "PRESS RECORD & PLAY ON TAPE" and waits.

    jsr KERNAL_OPEN
    bcs cmd_s_seq_open_failed

    // Redirect CHROUT to logical file 1.

    ldx #$01
    jsr KERNAL_CHKOUT
    bcs cmd_s_seq_chkout_failed

    // Byte loop: walk ZP_PTR_1 from s_start_address through
    // s_end_address inclusive, CHROUT each byte. Wrap-past-$FFFF is
    // detected via inc ZP_PTR_1+1 producing zero.

    lda s_start_address + 0
    sta ZP_PTR_1 + 0
    lda s_start_address + 1
    sta ZP_PTR_1 + 1

cmd_s_seq_write_loop:

    // If ZP_PTR_1 > s_end_address, we're done.

    lda ZP_PTR_1 + 1
    cmp s_end_address + 1
    bcc cmd_s_seq_write_byte
    bne cmd_s_seq_write_done
    lda ZP_PTR_1 + 0
    cmp s_end_address + 0
    bcc cmd_s_seq_write_byte
    beq cmd_s_seq_write_byte
    jmp cmd_s_seq_write_done

cmd_s_seq_write_byte:

    ldy #$00
    lda ( ZP_PTR_1 ), y
    jsr KERNAL_CHROUT

    // Advance ZP_PTR_1 by 1, detect wrap past $FFFF.

    inc ZP_PTR_1 + 0
    bne cmd_s_seq_write_loop
    inc ZP_PTR_1 + 1
    bne cmd_s_seq_write_loop
    // Wrapped — fall through to done.

cmd_s_seq_write_done:

    jsr KERNAL_CLRCHN
    lda #$01
    jsr KERNAL_CLOSE
    rts

cmd_s_seq_chkout_failed:

    // CHKOUT failed — still clear the channel and close the file.

    jsr KERNAL_CLRCHN
    lda #$01
    jsr KERNAL_CLOSE
    jmp cmd_s_file_error

cmd_s_seq_open_failed:

    // OPEN failed — no CHKOUT was done, but CLOSE the logical file
    // anyway so the KERNAL file table entry is released.

    lda #$01
    jsr KERNAL_CLOSE
    jmp cmd_s_file_error

cmd_s_save_prg:

    //--------------------------------------------------------------------------
    // PRG write: KERNAL_SAVE. The KERNAL prepends a 2-byte
    // little-endian load-address header derived from the start
    // pointer in ZP_PTR_1.
    //--------------------------------------------------------------------------

    // ZP_PTR_1 = start address (SAVE reads the source pointer from
    // this zero-page word).

    lda s_start_address + 0
    sta ZP_PTR_1 + 0
    lda s_start_address + 1
    sta ZP_PTR_1 + 1

    // SETLFS( logical = 1, device = tape, SA = 0 ).

    lda #$01
    ldx #TAPE_DEVICE
    ldy #SAVE_SECONDARY_ADDRESS
    jsr KERNAL_SETLFS

    // SETNAM( length, ptr_lo, ptr_hi ).

    lda filename_length
    ldx #<filename_buffer
    ldy #>filename_buffer
    jsr KERNAL_SETNAM

    // SAVE( zp_addr_of_start_pointer, end+1_lo, end+1_hi ).

    lda #<ZP_PTR_1
    ldx s_end_plus_one + 0
    ldy s_end_plus_one + 1
    jsr KERNAL_SAVE
    bcs cmd_s_file_error
    rts

cmd_s_file_error:

    lda #<error_file_error
    ldx #>error_file_error
    jmp print_error                             // Tail call.

cmd_s_error_illegal:

    lda #<error_illegal_value
    ldx #>error_illegal_value
    jmp print_error                             // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: cmd_l
//
// Description:
//
//   Load a file from tape. The presence of a destination address
//   picks the mode — no explicit type flag is needed.
//
//     L <filename>              PRG: KERNAL_LOAD with SA = 1. The
//                                file's header-embedded load address
//                                is honoured, so files saved with
//                                `S <start> <end> 01 ...` return to
//                                their original location.
//     L <filename> <address>    SEQ: OPEN + CHKIN + per-byte CHRIN
//                                loop + CLRCHN + CLOSE. Writes the
//                                bytes verbatim into memory starting
//                                at <address>. Required for files
//                                saved with `S <start> <end> 00 ...`
//                                because SEQ tape files have no
//                                PRG-style load-address header.
//
//   Error paths (all print and return without a load):
//
//     - missing filename (token_count < 2)                  -> ILLEGAL VALUE
//     - more than 3 tokens total                            -> ILLEGAL VALUE
//     - filename > FILENAME_BUFFER_SIZE (16) chars          -> ILLEGAL VALUE
//     - <address> not a 4-hex-digit word                    -> ILLEGAL VALUE
//     - KERNAL returns carry set (tape not found, I/O
//       error, RUN/STOP pressed mid-load), or KERNAL_ST_BYTE
//       reports a non-EOF error during SEQ read
//                                                           -> FILE ERROR
//
//   Note: there is no "force a PRG to a specific address" mode.
//   KERNAL_LOAD with SA = 1 is reliable for PRG files in this
//   environment; if a file's header is ever wrong, re-save rather
//   than trying to override on load. Keeps the L syntax symmetric
//   with the user's mental model: "address given = raw bytes,
//   no address = structured file".
//
// Parameters: None (reads token_offsets / token_count).
// Returns:    None.
// Clobbers:   A, X, Y, ZP_PTR_1, ZP_SCRATCH, hex_parse_result,
//             filename_buffer, filename_length, l_load_address,
//             plus whatever memory the loaded payload overwrites.
//
//------------------------------------------------------------------------------

cmd_l:

    // Require command letter + filename = 2 tokens minimum.

    lda token_count
    cmp #$02
    bcs cmd_l_copy_filename
    jmp cmd_l_error_illegal

cmd_l_copy_filename:

    // Copy token 1 into filename_buffer, capped at
    // FILENAME_BUFFER_SIZE. Empty tokens can't appear here —
    // tokenize only commits non-space runs to the offsets table.

    lda #$01
    jsr get_token_address

    ldy #$00

cmd_l_filename_copy_loop:

    lda ( ZP_PTR_1 ), y
    beq cmd_l_filename_copy_done
    cpy #FILENAME_BUFFER_SIZE
    bcc cmd_l_filename_copy_store               // Y < 16, OK to store.
    jmp cmd_l_error_illegal                     // > 16 characters.

cmd_l_filename_copy_store:

    sta filename_buffer, y
    iny
    jmp cmd_l_filename_copy_loop

cmd_l_filename_copy_done:

    sty filename_length

    // Dispatch on token count:
    //   2 → PRG (header address).
    //   3 → SEQ (address given).
    //   other → illegal.

    lda token_count
    cmp #$02
    beq cmd_l_load_prg
    cmp #$03
    beq cmd_l_parse_address
    jmp cmd_l_error_illegal

cmd_l_parse_address:

    lda #$02
    jsr get_token_address
    ldy #$00
    jsr parse_hex_word
    bcs cmd_l_address_parsed
    jmp cmd_l_error_illegal

cmd_l_address_parsed:

    lda hex_parse_result + 0
    sta l_load_address + 0
    lda hex_parse_result + 1
    sta l_load_address + 1
    jmp cmd_l_load_seq

cmd_l_load_prg:

    //--------------------------------------------------------------------------
    // PRG load via KERNAL_LOAD with SA = 1 (header address).
    //--------------------------------------------------------------------------

    lda #$01
    ldx #TAPE_DEVICE
    ldy #LOAD_SA_HEADER
    jsr KERNAL_SETLFS

    lda filename_length
    ldx #<filename_buffer
    ldy #>filename_buffer
    jsr KERNAL_SETNAM

    // X / Y are ignored by LOAD when SA = 1 but we zero them for
    // deterministic register state.

    lda #$00
    ldx #$00
    ldy #$00
    jsr KERNAL_LOAD
    bcs cmd_l_file_error
    rts

cmd_l_load_seq:

    //--------------------------------------------------------------------------
    // SEQ load via OPEN + CHKIN + per-byte CHRIN loop + CLRCHN +
    // CLOSE. Writes bytes from the tape into memory starting at
    // l_load_address; the file's header-embedded address is ignored.
    // The loop stops on KERNAL_STATUS_BYTE going non-zero — bit 6
    // ($40) = clean EOF, anything else = error.
    //--------------------------------------------------------------------------

    // SETLFS( logical = 1, device = tape, SA = 0 = read ).

    lda #$01
    ldx #TAPE_DEVICE
    ldy #TAPE_READ_SECONDARY_ADDRESS
    jsr KERNAL_SETLFS

    // SETNAM( length, ptr_lo, ptr_hi ).

    lda filename_length
    ldx #<filename_buffer
    ldy #>filename_buffer
    jsr KERNAL_SETNAM

    // OPEN — shows "PRESS PLAY ON TAPE", searches for the file.

    jsr KERNAL_OPEN
    bcs cmd_l_seq_open_failed

    // Redirect CHRIN source to logical file 1.

    ldx #$01
    jsr KERNAL_CHKIN
    bcs cmd_l_seq_chkin_failed

    // Point ZP_PTR_1 at the destination.

    lda l_load_address + 0
    sta ZP_PTR_1 + 0
    lda l_load_address + 1
    sta ZP_PTR_1 + 1

cmd_l_seq_read_loop:

    // Peek ST before each read. Non-zero ST means no more data;
    // either clean EOF (bit 6 set) or an error.

    lda KERNAL_STATUS_BYTE
    bne cmd_l_seq_check_status

    jsr KERNAL_CHRIN
    ldy #$00
    sta ( ZP_PTR_1 ), y

    // Advance the destination pointer; stop if it wraps past $FFFF.

    inc ZP_PTR_1 + 0
    bne cmd_l_seq_read_loop
    inc ZP_PTR_1 + 1
    bne cmd_l_seq_read_loop
    jmp cmd_l_seq_read_done

cmd_l_seq_check_status:

    and #KERNAL_ST_EOF_MASK
    bne cmd_l_seq_read_done                     // EOF bit set = clean end.

    // Any other ST value = tape error; fall through to error path.

    jsr KERNAL_CLRCHN
    lda #$01
    jsr KERNAL_CLOSE
    jmp cmd_l_file_error

cmd_l_seq_read_done:

    jsr KERNAL_CLRCHN
    lda #$01
    jsr KERNAL_CLOSE
    rts

cmd_l_seq_chkin_failed:

    jsr KERNAL_CLRCHN
    lda #$01
    jsr KERNAL_CLOSE
    jmp cmd_l_file_error

cmd_l_seq_open_failed:

    lda #$01
    jsr KERNAL_CLOSE
    jmp cmd_l_file_error

cmd_l_file_error:

    lda #<error_file_error
    ldx #>error_file_error
    jmp print_error                             // Tail call.

cmd_l_error_illegal:

    lda #<error_illegal_value
    ldx #>error_illegal_value
    jmp print_error                             // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: cmd_r
//
// Description:
//
//   Display the CPU register state captured at the end of the most
//   recent G command. Read-only — the C64 version's `R <reg> <val>`
//   write form is explicitly out of scope for this port (would
//   require an RTI-based G trampoline and shadow-register-to-CPU
//   reload path that the 1988 original didn't have).
//
//   Output (three lines, 22-column-safe):
//
//     A:XX X:XX Y:XX P:XX          19 chars — four regs, space-separated
//     NV-BDIZC                      8 chars — flag header
//     XXXXXXXX                      8 chars — flag bits, MSB (N) left
//
//   Before any G has run the shadows are all zero, so a bare `R`
//   right after startup shows all zeros — not useful, but harmless
//   and self-explanatory.
//
// Parameters: None.
// Returns:    None.
// Clobbers:   A, X, Y, ZP_PTR_1, ZP_SCRATCH.
//
//------------------------------------------------------------------------------

cmd_r:

    // Line 1: "A:XX X:XX Y:XX P:XX".
    // reg_name_chars is a 4-char string "AXYP" indexed by X in the
    // loop; shadow_registers holds the 4 captured values in the
    // same order (A, X, Y, P).

    ldx #$00

cmd_r_register_loop:

    // Space separator between registers, skipped before the first one.

    cpx #$00
    beq cmd_r_no_separator
    lda #SPACE
    jsr KERNAL_CHROUT

cmd_r_no_separator:

    lda reg_name_chars, x
    jsr KERNAL_CHROUT
    lda #':'
    jsr KERNAL_CHROUT
    lda shadow_registers, x
    jsr print_hex_byte

    inx
    cpx #SHADOW_REGISTER_COUNT
    bne cmd_r_register_loop

    jsr print_newline

    // Line 2: "NV-BDIZC".

    lda #<flag_header_string
    ldx #>flag_header_string
    jsr print_string
    jsr print_newline

    // Line 3: shadow_p unpacked MSB-first into 8 '0'/'1' chars.
    // Each iteration ASLs ZP_SCRATCH and uses the carry (old bit 7)
    // to turn '0' into '1' via ADC #0.

    lda shadow_registers + REG_OFFSET_P
    sta ZP_SCRATCH

    ldx #$08

cmd_r_flag_bit_loop:

    asl ZP_SCRATCH
    lda #'0'
    adc #$00
    jsr KERNAL_CHROUT
    dex
    bne cmd_r_flag_bit_loop

    // No trailing newline — main_loop's print_blank_line supplies
    // the separator before the next prompt, matching every other
    // command's contract.

    rts


//------------------------------------------------------------------------------
//
// Subroutine: cmd_cls
//
// Description:
//
//   Clear-screen command. Emits a single PETSCII CLEAR_SCREEN ($93)
//   control code via CHROUT — the KERNAL resets all screen RAM to
//   the space character, clears colour RAM to the current text
//   colour, and homes the cursor to column 0 of line 0. main_loop's
//   subsequent print_blank_line leaves the fresh screen with a
//   blank row above the next `:` prompt, matching the visual that
//   would follow any other command.
//
//   Mirrors cmd_cls in the C64 v2.1 reference at
//   `X:\Commodore\C64\Projects\Code Probe\v1\src\codeprobe.asm`.
//
// Parameters: None (extra tokens on the CLS line are ignored).
// Returns:    None.
// Clobbers:   A.
//
//------------------------------------------------------------------------------

cmd_cls:

    lda #CLEAR_SCREEN
    jmp KERNAL_CHROUT                           // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: cmd_exit
//
// Description:
//
//   Exit command. Restarts BASIC via its warm-start vector at
//   `$C002` (indirect) — the same mechanism the C64 reference at
//   `X:\Commodore\C64\Projects\Code Probe\v1\src\codeprobe.asm`
//   uses via the analogous `$A002` vector. Code Probe stays
//   resident in the Super Expander's 3 KiB RAM; the user can
//   re-enter the monitor with `SYS 1152` at the BASIC prompt.
//
//   Unlike the C64 version there is no BRK-vector dance here —
//   Code Probe's G command uses a JSR trampoline rather than
//   BRK-RTI, so there's no original BRK handler to restore.
//
//   Never returns. Stack discipline is irrelevant because the
//   warm-start routine reinitialises BASIC's stack pointer during
//   its own prologue.
//
// Parameters: None (extra tokens on the EXIT line are ignored).
// Returns:    Never.
// Clobbers:   Whatever BASIC's warm-start routine clobbers.
//
//------------------------------------------------------------------------------

cmd_exit:

    jmp ( BASIC_WARM_START )


//------------------------------------------------------------------------------
//
// Subroutine: read_bounded_line
//
// Description:
//
//   Line editor shared by the monitor prompt and the S-command
//   filename entry prompt. Polls KERNAL_GETIN one keystroke at a
//   time and enforces a length cap the caller sets in
//   input_line_max before the call. On RETURN the buffer is
//   null-terminated, the KERNAL cursor blink is re-enabled, and a
//   carriage return is emitted so the next CHROUT lands at column
//   0 of the following line.
//
//   Accepted keys:
//
//     RETURN            — commit; null-terminate; emit CR; return.
//     CURSOR_LEFT ($9D) — move cursor one slot left; clamped at
//                         the start of user input (buffer offset 0
//                         = col 2 in the ": " prompt, col 6 in the
//                         "FILE: " prompt).
//     CURSOR_RIGHT ($1D)— move cursor one slot right; clamped at
//                         the frontier (input_line_length).
//     DELETE ($14)      — erase the most recent character; only
//                         active at the frontier to match the C64
//                         alter-mode convention. Visual redraw is
//                         delegated to CBM CHROUT.
//     Printable chars   — at the frontier, appended while length <
//                         input_line_max; once the cap is reached
//                         further printable keys are silently
//                         discarded. Inside existing content
//                         (cursor moved back via CURSOR_LEFT) a
//                         printable key overwrites that slot in
//                         place and advances the cursor; length is
//                         unchanged.
//
//   Explicitly ignored keys: CURSOR_UP ($91), CURSOR_DOWN ($11).
//   Any other PETSCII value the KERNAL returns falls into the
//   "printable char" path and is subject to the same length gate.
//
//   Cursor blink is disabled with a_cursor_off before every CHROUT
//   that moves or overwrites the cursor slot (mirrors the pattern
//   used by cmd_a's hex editor), and re-enabled on every loop
//   iteration so the user can see where the next character will
//   land.
//
// Parameters:
//
//   input_line_max  - caller-set maximum length (0..INPUT_BUFFER_SIZE
//                     - 1). 19 for the monitor prompt (cap at col
//                     21 of the 22-col screen after the ": " prefix),
//                     FILENAME_BUFFER_SIZE (16) for the FILE: prompt.
//
// Returns:
//
//   input_buffer    - populated with the typed characters, $00 terminated.
//   input_line_length - final length (0..input_line_max).
//   Cursor          - parked at column 0 of the line after the user's
//                     input line.
//
// Clobbers: A, X, Y, KERNAL cursor zero-page state, input_line_cursor,
//           input_line_length.
//
//------------------------------------------------------------------------------

read_bounded_line:

    lda #$00
    sta input_line_cursor
    sta input_line_length

read_bounded_line_loop:

    lda #$00
    sta CURSOR_BLINK_ENABLE

read_bounded_line_poll:

    jsr KERNAL_GETIN
    beq read_bounded_line_poll

    // Kill the blink before any screen work.

    pha
    jsr a_cursor_off
    pla

    // RETURN is handled inline so the BEQ to its path stays in
    // short-branch range even as the char-dispatch tail grows.

    cmp #CARRIAGE_RETURN
    bne read_bounded_line_not_return

    // Null-terminate the buffer at the frontier.

    ldy input_line_length
    lda #$00
    sta input_buffer, y

    // Emit a CR so the cursor ends up at column 0 of the line
    // after the user's input — the contract the old CHRIN-based
    // read_line offered that every caller relies on. Cursor blink
    // stays disabled here (a_cursor_off above already cleared it);
    // any caller that wants the blink back on re-enables before
    // its own input loop, the way main_loop and cmd_a already do.

    lda #CARRIAGE_RETURN
    jmp KERNAL_CHROUT                           // Tail call.

read_bounded_line_not_return:

    cmp #CURSOR_LEFT_KEY
    beq read_bounded_line_left
    cmp #CURSOR_RIGHT_KEY
    beq read_bounded_line_right
    cmp #DELETE_KEY
    beq read_bounded_line_delete
    cmp #CURSOR_UP_KEY
    beq read_bounded_line_loop
    cmp #CURSOR_DOWN_KEY
    beq read_bounded_line_loop

    jmp read_bounded_line_char

read_bounded_line_left:

    ldy input_line_cursor
    beq read_bounded_line_loop                  // At left bound.
    dey
    sty input_line_cursor
    lda #CURSOR_LEFT_KEY
    jsr KERNAL_CHROUT
    jmp read_bounded_line_loop

read_bounded_line_right:

    ldy input_line_cursor
    cpy input_line_length
    bcs read_bounded_line_loop                  // At frontier.
    iny
    sty input_line_cursor
    lda #CURSOR_RIGHT_KEY
    jsr KERNAL_CHROUT
    jmp read_bounded_line_loop

read_bounded_line_delete:

    ldy input_line_cursor
    beq read_bounded_line_loop                  // Nothing to delete.
    cpy input_line_length
    bne read_bounded_line_loop                  // Only at the frontier.
    dec input_line_cursor
    dec input_line_length
    lda #DELETE_KEY
    jsr KERNAL_CHROUT
    jmp read_bounded_line_loop

read_bounded_line_char:

    // A holds the PETSCII keystroke. Decide append vs overwrite vs
    // reject based on cursor position relative to the frontier and
    // length cap.

    pha
    ldy input_line_cursor
    cpy input_line_length
    bcc read_bounded_line_char_overwrite        // Cursor < length: overwrite in place.
    beq read_bounded_line_char_at_frontier      // Cursor == length: append if room.
    pla                                         // Cursor > length is impossible but fail closed.
    jmp read_bounded_line_loop

read_bounded_line_char_at_frontier:

    cpy input_line_max
    bcs read_bounded_line_char_reject
    pla
    ldy input_line_cursor
    sta input_buffer, y
    iny
    sty input_line_cursor
    sty input_line_length
    jsr KERNAL_CHROUT
    jmp read_bounded_line_loop

read_bounded_line_char_overwrite:

    pla
    ldy input_line_cursor
    sta input_buffer, y
    iny
    sty input_line_cursor
    jsr KERNAL_CHROUT
    jmp read_bounded_line_loop

read_bounded_line_char_reject:

    pla
    jmp read_bounded_line_loop


//------------------------------------------------------------------------------
//
// Subroutine: tokenize
//
// Description:
//
//   Splits input_buffer in place into at most MAX_TOKENS tokens
//   separated by spaces. Every space between tokens is overwritten
//   with $00 so each token is an independently null-terminated
//   PETSCII string that parse_hex_byte / parse_hex_word can walk
//   without knowing its length.
//
//   Leading, trailing, and runs of interior spaces are all handled.
//   If the input contains more than MAX_TOKENS tokens, the overflow
//   is silently ignored and token_count is clamped to MAX_TOKENS.
//
// Parameters: input_buffer (null-terminated).
// Returns:    token_count        - number of tokens found (0..MAX_TOKENS).
//             token_offsets[0..N] - byte offset of each token within
//                                   input_buffer.
//             input_buffer       - interior spaces replaced with $00.
// Clobbers:   A, X, Y.
//
//------------------------------------------------------------------------------

tokenize:

    ldy #$00                                    // Input cursor.
    ldx #$00                                    // Token count accumulator.

tokenize_skip_spaces:

    lda input_buffer, y
    beq tokenize_finished                       // Null terminator ends the scan.
    cmp #SPACE
    bne tokenize_start_token
    iny
    jmp tokenize_skip_spaces

tokenize_start_token:

    // Overflow: stop recording tokens but still return a valid count.

    cpx #MAX_TOKENS
    bcs tokenize_finished

    // Record this token's start offset.

    tya
    sta token_offsets, x
    inx

tokenize_consume_token:

    lda input_buffer, y
    beq tokenize_finished                       // Token ended at end of input.
    cmp #SPACE
    beq tokenize_end_of_token
    iny
    jmp tokenize_consume_token

tokenize_end_of_token:

    // Replace the separating space with a null so the token becomes
    // independently null-terminated, then look for the next token.

    lda #$00
    sta input_buffer, y
    iny
    jmp tokenize_skip_spaces

tokenize_finished:

    stx token_count
    rts


//------------------------------------------------------------------------------
//
// Subroutine: get_token_address
//
// Description:
//
//   Loads the address of token N's first character into ZP_PTR_1 so
//   parse_hex_byte / parse_hex_word can walk it. The caller is
//   responsible for checking token_count first.
//
// Parameters:
//
//   A - Token index (0-based).
//
// Returns:  ZP_PTR_1 holds &input_buffer[ token_offsets[ A ] ].
// Clobbers: A, X.
//
//------------------------------------------------------------------------------

get_token_address:

    tax
    lda token_offsets, x
    clc
    adc #<input_buffer
    sta ZP_PTR_1 + 0
    lda #>input_buffer
    adc #$00                                    // Absorb carry from the low byte.
    sta ZP_PTR_1 + 1
    rts


//------------------------------------------------------------------------------
//
// Subroutine: is_hex_digit
//
// Description:
//
//   Tests whether A holds a PETSCII hex digit ('0'..'9' or 'A'..'F').
//   A is preserved so callers can chain into char_to_nibble without
//   reloading.
//
// Parameters:
//
//   A - Candidate PETSCII character.
//
// Returns:  Carry = 1 if A is a hex digit, Carry = 0 otherwise.
// Clobbers: Flags only (A unchanged).
//
//------------------------------------------------------------------------------

is_hex_digit:

    cmp #'0'
    bcc is_hex_digit_no                         // A < '0'
    cmp #'9' + 1
    bcc is_hex_digit_yes                        // '0' <= A <= '9'
    cmp #'A'
    bcc is_hex_digit_no                         // ':'..'@' gap
    cmp #'F' + 1
    bcc is_hex_digit_yes                        // 'A' <= A <= 'F'

is_hex_digit_no:

    clc
    rts

is_hex_digit_yes:

    sec
    rts


//------------------------------------------------------------------------------
//
// Subroutine: char_to_nibble
//
// Description:
//
//   Converts a PETSCII hex digit to its numeric value 0..15. Assumes
//   the caller has already validated A via is_hex_digit.
//
// Parameters:
//
//   A - PETSCII hex digit ('0'..'9' or 'A'..'F').
//
// Returns:  A = 0..15.
// Clobbers: A, flags.
//
//------------------------------------------------------------------------------

char_to_nibble:

    cmp #'A'
    bcs char_to_nibble_letter                   // 'A'..'F' branch.

    // '0'..'9' → 0..9

    sec
    sbc #'0'
    rts

char_to_nibble_letter:

    // 'A'..'F' → 10..15

    sec
    sbc #'A' - 10
    rts


//------------------------------------------------------------------------------
//
// Subroutine: parse_hex_byte
//
// Description:
//
//   Reads exactly two hex characters starting at ( ZP_PTR_1 ), Y and
//   returns the decoded byte in A. Y advances by two on success so
//   callers (notably parse_hex_word) can chain reads without extra
//   arithmetic. On any non-hex character Y is left part-way into the
//   token and carry is cleared.
//
// Parameters:
//
//   ZP_PTR_1 - Base address of the input string.
//   Y        - Offset into the string.
//
// Returns:  Carry = 1 on success with A = parsed byte and Y advanced by 2.
//           Carry = 0 on failure (caller treats Y as indeterminate).
// Clobbers: A, Y, ZP_SCRATCH.
//
//------------------------------------------------------------------------------

parse_hex_byte:

    // High nibble.

    lda ( ZP_PTR_1 ), y
    jsr is_hex_digit
    bcc parse_hex_byte_fail
    jsr char_to_nibble
    asl
    asl
    asl
    asl
    sta ZP_SCRATCH
    iny

    // Low nibble.

    lda ( ZP_PTR_1 ), y
    jsr is_hex_digit
    bcc parse_hex_byte_fail
    jsr char_to_nibble
    ora ZP_SCRATCH
    iny
    sec
    rts

parse_hex_byte_fail:

    clc
    rts


//------------------------------------------------------------------------------
//
// Subroutine: parse_hex_word
//
// Description:
//
//   Reads exactly four hex characters starting at ( ZP_PTR_1 ), Y and
//   writes the decoded 16-bit value into hex_parse_result (little-
//   endian). The character immediately after the fourth hex digit
//   must be a null terminator; trailing garbage ("12345") is rejected
//   as wrong-width.
//
// Parameters:
//
//   ZP_PTR_1 - Base address of the input string.
//   Y        - Offset into the string.
//
// Returns:  Carry = 1 on success with hex_parse_result populated.
//           Carry = 0 on failure (non-hex, too few digits, or trailing garbage).
// Clobbers: A, Y, ZP_SCRATCH, hex_parse_result.
//
//------------------------------------------------------------------------------

parse_hex_word:

    jsr parse_hex_byte
    bcc parse_hex_word_fail
    sta hex_parse_result + 1                    // High byte.

    jsr parse_hex_byte
    bcc parse_hex_word_fail
    sta hex_parse_result + 0                    // Low byte.

    // Width check: the next character must be the token's null terminator.

    lda ( ZP_PTR_1 ), y
    bne parse_hex_word_fail

    sec
    rts

parse_hex_word_fail:

    clc
    rts


//------------------------------------------------------------------------------
//
// Subroutine: print_hex_byte
//
// Description:
//
//   Prints A as two PETSCII hex characters via CHROUT (high nibble
//   first).
//
// Parameters:
//
//   A - Byte to print.
//
// Returns:  None.
// Clobbers: A.
//
//------------------------------------------------------------------------------

print_hex_byte:

    pha                                         // Save the low nibble for later.
    lsr
    lsr
    lsr
    lsr
    jsr print_nibble
    pla
    and #$0F
    jmp print_nibble                            // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: print_hex_word
//
// Description:
//
//   Prints a 16-bit value as four PETSCII hex characters via CHROUT
//   (high byte first, then low byte).
//
// Parameters:
//
//   A - Low byte.
//   X - High byte.
//
// Returns:  None.
// Clobbers: A.
//
//------------------------------------------------------------------------------

print_hex_word:

    pha                                         // Save the low byte.
    txa                                         // A = high byte.
    jsr print_hex_byte
    pla                                         // Restore low byte.
    jmp print_hex_byte                          // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: print_nibble
//
// Description:
//
//   Prints a 4-bit value (0..15) as a single PETSCII hex character
//   via CHROUT. Shared helper for print_hex_byte.
//
// Parameters:
//
//   A - Nibble, 0..15 (high bits assumed clear).
//
// Returns:  None.
// Clobbers: A.
//
//------------------------------------------------------------------------------

print_nibble:

    cmp #$0A
    bcc print_nibble_digit                      // 0..9 branch.

    // 10..15 → 'A'..'F'

    clc
    adc #'A' - 10
    jmp KERNAL_CHROUT                           // Tail call.

print_nibble_digit:

    // 0..9 → '0'..'9'

    clc
    adc #'0'
    jmp KERNAL_CHROUT                           // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: print_decimal_word
//
// Description:
//
//   Prints a 16-bit unsigned value as 1..5 decimal digits via CHROUT,
//   suppressing leading zeros (the value 0 still prints as "0"). Uses
//   repeated subtraction of the powers 10000, 1000, 100, 10.
//
// Parameters:
//
//   A - Value, low byte.
//   X - Value, high byte.
//
// Returns:  None.
// Clobbers: A, X, Y, decimal_value, decimal_digit, decimal_leading_done.
//
//------------------------------------------------------------------------------

print_decimal_word:

    sta decimal_value + 0
    stx decimal_value + 1

    // Track whether a non-zero digit has already been emitted; until
    // one has, further zeros stay suppressed.

    lda #$00
    sta decimal_leading_done

    ldx #$00                                    // Power-of-10 table index.

print_decimal_word_power_loop:

    cpx #$04
    beq print_decimal_word_ones_digit

    // Count how many times powers_of_10[ X ] fits into decimal_value.

    lda #$00
    sta decimal_digit

print_decimal_word_subtract:

    sec
    lda decimal_value + 0
    sbc powers_of_10_lo, x
    tay
    lda decimal_value + 1
    sbc powers_of_10_hi, x
    bcc print_decimal_word_subtract_done

    // Commit the subtraction and bump the digit count.

    sta decimal_value + 1
    sty decimal_value + 0
    inc decimal_digit
    jmp print_decimal_word_subtract

print_decimal_word_subtract_done:

    // Emit the digit unless it's a leading zero that should be suppressed.

    lda decimal_digit
    bne print_decimal_word_emit
    ldy decimal_leading_done
    beq print_decimal_word_next_power

print_decimal_word_emit:

    clc
    adc #'0'
    jsr KERNAL_CHROUT
    lda #$01
    sta decimal_leading_done

print_decimal_word_next_power:

    inx
    jmp print_decimal_word_power_loop

print_decimal_word_ones_digit:

    // The remainder in decimal_value + 0 is always 0..9 here and is
    // always printed, covering both the final digit of non-zero
    // values and the single '0' case.

    lda decimal_value + 0
    clc
    adc #'0'
    jmp KERNAL_CHROUT                           // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: print_string
//
// Description:
//
//   Prints a null-terminated PETSCII string via CHROUT, up to 256 bytes.
//
// Parameters:
//
//   A - String address, low byte.
//   X - String address, high byte.
//
// Returns:  None.
// Clobbers: A, Y, ZP_PTR_1.
//
//------------------------------------------------------------------------------

print_string:

    sta ZP_PTR_1 + 0
    stx ZP_PTR_1 + 1

    ldy #$00

print_string_next_character:

    lda ( ZP_PTR_1 ), y
    beq print_string_done
    jsr KERNAL_CHROUT
    iny
    bne print_string_next_character             // Safety cap at 256 bytes per string.

print_string_done:

    rts


//------------------------------------------------------------------------------
//
// Subroutine: print_newline
//
// Description:
//
//   Emits a single PETSCII carriage return, which moves the cursor to
//   the start of the next line.
//
// Parameters: None.
// Returns:    None.
// Clobbers:   A.
//
//------------------------------------------------------------------------------

print_newline:

    lda #CARRIAGE_RETURN
    jmp KERNAL_CHROUT                           // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: print_blank_line
//
// Description:
//
//   Emits two PETSCII carriage returns, leaving one visible blank line
//   between the previous output and the cursor's new position.
//
// Parameters: None.
// Returns:    None.
// Clobbers:   A.
//
//------------------------------------------------------------------------------

print_blank_line:

    jsr print_newline
    jmp print_newline                           // Tail call.


//------------------------------------------------------------------------------
//
// Subroutine: print_error
//
// Description:
//
//   Prints a null-terminated error string. Kept as a distinct entry
//   point from print_string so call sites self-document as error
//   output, but behaviourally identical — main_loop's print_blank_line
//   supplies the blank separator before the next prompt, so adding a
//   trailing newline here would produce a double-blank gap.
//
// Parameters:
//
//   A - Error string address, low byte.
//   X - Error string address, high byte.
//
// Returns:  None.
// Clobbers: A, Y, ZP_PTR_1.
//
//------------------------------------------------------------------------------

print_error:

    jmp print_string                            // Tail call.


//==============================================================================
// Data
//==============================================================================

banner:

    // Each banner line is wrapped in REVERSE_ON / REVERSE_OFF so the
    // cells render as reverse-video — glyph pixels take the global
    // background colour (black), non-glyph pixels take the cell's
    // text colour (white, Code Probe's default). Net effect: white
    // bar with black glyph cutouts.
    //
    // No per-cell colour manipulation — the cells use whatever text
    // colour CHROUT is currently on (white). This is the simplest
    // and highest-contrast banner highlight standard VIC-20 text
    // mode can produce; a coloured bar (e.g. blue background) would
    // require a raster-interrupt trick that's out of scope for the
    // monitor (see the discussion note in session memory).

    .fill BANNER_BAR_WIDTH, BANNER_TOP_BAR_CHAR
    .byte REVERSE_ON
    .text "CODE PROBE      (V1.1)"
    .byte REVERSE_OFF
    .fill BANNER_BAR_WIDTH, BANNER_MID_BAR_CHAR
    .text "ROHIN GOSLING   (1988)"
    .byte REVERSE_OFF
    .fill BANNER_BAR_WIDTH, BANNER_BOTTOM_BAR_CHAR
    .byte CARRIAGE_RETURN                       // Blank line between banner and first prompt.
    .byte $00

prompt:

    .text ": "
    .byte $00

error_illegal_value:

    .text "ERROR: ILLEGAL VALUE"
    .byte $00

error_unknown_command:

    .text "ERROR: UNKNOWN COMMAND"
    .byte $00

error_file_error:

    .text "ERROR: FILE ERROR"
    .byte $00

file_prompt:

    .text "FILE: "
    .byte $00

reg_name_chars:

    .text "AXYP"                                // Indexed 0..3 in cmd_r's register-print loop; same order as shadow_registers.

flag_header_string:

    .text "NV-BDIZC"
    .byte $00

powers_of_10_lo:

    .byte <10000, <1000, <100, <10

powers_of_10_hi:

    .byte >10000, >1000, >100, >10

input_buffer:

    .fill INPUT_BUFFER_SIZE, $00

input_line_cursor:

    .byte $00                                   // read_bounded_line: cursor slot within input_buffer (0..input_line_length).

input_line_length:

    .byte $00                                   // read_bounded_line: frontier — number of characters committed so far.

input_line_max:

    .byte $00                                   // read_bounded_line: per-call cap the caller must set before the call.

token_offsets:

    .fill MAX_TOKENS, $00

token_count:

    .byte $00

hex_parse_result:

    .word $0000                                 // Low byte at +0, high byte at +1.

d_start_address:

    .word $0000                                 // Dump range lower bound (remembered for the byte-count summary).

d_current_address:

    .word $0000                                 // Rolling row-start pointer.

d_end_address:

    .word $0000                                 // Dump range upper bound, inclusive.

d_scratch_address:

    .word $0000                                 // Scratch for d_current_address + Y during slot-in-range tests.

d_byte_count:

    .word $0000                                 // ( d_end_address - d_start_address ) + 1.

a_line_address:

    .word $0000                                 // Start address of the current alter-mode line (advanced on each commit).

a_total_bytes:

    .word $0000                                 // Running total of bytes committed across the session (for the summary).

a_nibble_buffer:

    .fill A_MAX_NIBBLES_PER_LINE, $00           // One nibble (0..15) per slot; packed to bytes at commit.

a_nibble_count:

    .byte $00                                   // Frontier: number of nibbles actually entered on the current line.

a_cursor_pos:

    .byte $00                                   // Cursor slot within a_nibble_buffer (0..a_nibble_count).

a_commit_byte_count:

    .byte $00                                   // Bytes written by the most recent a_commit_line call.

s_start_address:

    .word $0000                                 // S command: inclusive lower bound of the byte range to save.

s_end_address:

    .word $0000                                 // S command: inclusive upper bound.

s_end_plus_one:

    .word $0000                                 // s_end_address + 1, passed as KERNAL_SAVE's exclusive limit.

filename_buffer:

    .fill FILENAME_BUFFER_SIZE, $00             // Up to 16 chars of the current S / L filename.

filename_length:

    .byte $00                                   // Actual length of filename_buffer contents (0..16).

s_file_type:

    .byte $00                                   // 0 = SEQ (OPEN + CHROUT loop), 1 = PRG (KERNAL_SAVE).

l_load_address:

    .word $0000                                 // L command: destination address for the SEQ path (PRG uses the file header instead).

shadow_registers:

    .fill SHADOW_REGISTER_COUNT, $00            // [A, X, Y, P] captured at the end of the most recent G command; read by cmd_r.

decimal_value:

    .word $0000                                 // Running remainder during power-of-10 subtraction.

decimal_digit:

    .byte $00                                   // Subtraction count for the current power of 10.

decimal_leading_done:

    .byte $00                                   // 0 while leading zeros are still being suppressed.


//==============================================================================
// Build Metadata
//==============================================================================
//
// Print the assembled code size at build time. The design contract
// is that Code Probe must fit entirely within the Super Expander's
// free expansion RAM at $0480-$0FFF — 2944 bytes of monitor code.
// If this size ever creeps past $0FFF the monitor would spill into
// VIC-native RAM at $1000+, clobbering the user's ML buffer where
// programs authored with Code Probe live. The Phase 9 acceptance
// pass reads this figure as the primary regression check.

.print "Code Probe size = " + ( * - entry ) + " bytes (budget: <= 2944)"
