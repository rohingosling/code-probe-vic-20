# CLAUDE.md — Project Notes for Code Probe (VIC-20)

This file captures project-level conventions and reference material for
contributors (including Claude Code). It is the authoritative manifest for
the Release Source Archives section that `.gitattributes` references.

## Release Source Archives

GitHub auto-generates `Source code (zip)` and `Source code (tar.gz)`
archives for each release. The contents are curated via `.gitattributes`
(`export-ignore`) so the archives contain only what a contributor or
archivist actually needs. The `.gitattributes` Excluded list mirrors the
table below — keep them in sync if either changes.

### Included

| Path / Pattern                              | Reason                                                         |
|---------------------------------------------|----------------------------------------------------------------|
| `LICENSE`                                   | MIT for code, CC BY-SA 4.0 for the user manual.                |
| `README.md`                                 | Project documentation entry point.                             |
| `CLAUDE.md`                                 | This file. Project conventions and reference.                  |
| `src/code-probe-vic-20.asm`                 | Authoritative Kick Assembler source listing.                   |
| `build/code-probe.prg`                      | Pre-assembled monitor binary, so an archive recipient can try it without a Kick Assembler install. |
| `docs/code-probe-user-manual-vic-20.pdf`    | Complete user manual, typeset PDF.                             |

### Excluded (via `.gitattributes` `export-ignore`)

| Path / Pattern        | Reason                                                                              |
|-----------------------|-------------------------------------------------------------------------------------|
| `/.gitattributes`     | Tooling metadata; not relevant to archive recipients.                               |
| `/.markdownlint.json` | Editor / linter config; not relevant to archive recipients.                         |
| `/.vscode/`           | Editor settings; not relevant to archive recipients.                                |
| `/dist/`              | Tape image artefacts; distributed via GitHub Releases instead.                      |
| `/docs/claude/`       | Internal Claude-session notes; not user-facing.                                     |
| `/images/`            | Capture GIFs and graphics for README rendering; bulk irrelevant in a code archive.  |
| `/roms/`              | Third-party VIC-1211A Super Expander ROM is not redistributable from this repo.     |

## README Conventions

The 2026 README rewrite adopted these conventions. Preserve them on edits,
and apply symmetrically on the sibling `code-probe-c64` repository.

### Headings and structure

- Top-level (`## `) section headings carry an emoji prefix
  (e.g. `## 🕒 History`, `## 💾 Loading and Starting`,
  `## 👪 Code Probe Family`). Subsections (`### `) are plain — emoji is
  reserved for `## `.
- Section breaks use a `<br>` HTML tag on its own line between top-level
  sections.

### Inline formatting

- Hardware names (`**Code Probe**`, `**VIC-20**`,
  `**VIC-1211A Super Expander**`, `**C64**`, `**BASIC**`) are bolded
  inline on first prose use within a section.
- Tools (`Kick Assembler`, `Claude Code`) are linked at first prose
  mention in each meaningful section, not just at first mention in the
  document. Bold-on-hardware-names and link-tools combine via
  `[**Tool Name**](url)`.

### Badges

- Style: `flat`. White text (`logoColor=white`).
- Colour palette: drawn from the VIC-I 16-colour palette (the colours the
  VIC-20's own VIC chip can render). Avoids borrowing arbitrary brand
  colours from unrelated technologies.
- Logos: only Simple Icons logos that match the badge subject (currently
  only `commodore` qualifies).
- The Commodore platform badge uses the Simple Icons brand colour
  `#1428A0`.

### Quick Start

The `## 🚀 Quick Start` section sits between the C64 sibling callout and
the Contents TOC, giving end users immediate access to download links and
run commands. Download URLs use the GitHub release-asset format
(`https://github.com/.../releases/download/{tag}/{file}`) rather than
`raw/{tag}/{path}` URLs, so the asset names are decoupled from the tagged
tree's filesystem state. Updating an asset filename only requires
`gh release upload --clobber` and `gh release delete-asset` — no tag
rewrite.

### File naming

The user manual PDF is `docs/code-probe-user-manual-vic-20.pdf`. The C64
sibling will follow the symmetric pattern `code-probe-user-manual-c64.pdf`
when its rename lands. The platform suffix prevents Downloads-folder name
collisions when a user has both manuals.

## Cross-project notes

`code-probe-vic-20` and `code-probe-c64` are maintained as parallel
repositories with shared design DNA. The 2026 README rewrite captured a
detailed per-item adaptation log:

- **Session log:** `~/.claude/plans/code-probe-readme-edits-log.md`

The log records each README change made in this repo, why it was made,
verbatim final text, and what to change when porting to the C64 sibling.
Use it as the canonical reference when applying analogous changes there.
