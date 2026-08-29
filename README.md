# nesdev — prebuilt NES/SNES development tools

This is an **orphan branch** of [`Parisoft/homebrew-tools`](https://github.com/Parisoft/homebrew-tools):
it shares no history with `main`, and it exists purely as a binary drop of the
tooling needed to build, run and debug **NES and SNES games**.

Two things live here:

| Folder | What it is | Version |
|---|---|---|
| [`cc65/`](cc65/) | The **cc65 toolchain** — `cc65` (6502/65816 C compiler), `ca65` (macro assembler), `ld65` (linker) plus `ar65`, `cl65`, `co65`, `da65`, `od65`, `sp65`, `grc65`, `chrcvt65`, `sim65`. Ships headers, C libraries and linker configs for the **`nes`** and **`snes`** targets (and every other cc65 target). | **cc65 V2.18** |
| [`mesen/`](mesen/) | **`mesen-mcp`** — the Mesen emulation core wrapped in a headless [MCP](https://modelcontextprotocol.io) server. Load and drive a ROM, read/write memory, set breakpoints, step/trace the CPU, inspect the PPU (tilemaps, sprites, palettes), capture audio, script in Lua, record/replay regression tests. **49 MCP tools over stdio**, no display server, no sound device, no .NET runtime. | MesenMCP `f33a8af` |

Everything is built for **linux x86_64**. See `cc65/BUILD.txt` and `mesen/BUILD.txt`
for exact source commits, compilers and build commands.

## Get it

```bash
git clone --branch nesdev --single-branch https://github.com/Parisoft/homebrew-tools.git nesdev-tools
cd nesdev-tools
```

## Quickstart — put the cc65 toolchain on `PATH`

```bash
export CC65_HOME="$(pwd)/cc65"
export PATH="$CC65_HOME/bin:$PATH"
```

…or use the helper script, which does the same thing and also puts `mesen-mcp` on `PATH`:

```bash
. ./env.sh
```

Verify:

```bash
$ cc65 --version
cc65 V2.18 - Git 6efb71b
$ ca65 --version
ca65 V2.18 - Git 6efb71b
$ ld65 --version
ld65 V2.18 - Git 6efb71b
```

That is all that is needed — the binaries resolve their headers/libs/cfg relative
to themselves, so the folder can be checked out anywhere and even moved around.

### Build a NES ROM

```bash
cl65 -t nes -o game.nes game.c          # compile + assemble + link in one step
```

`cl65` is the driver: it calls `cc65` → `ca65` → `ld65` for you and picks the
right `nes` startup code, library and linker config. Swap `-t nes` for `-t snes`
to target the SNES.

Or step through it manually:

```bash
cc65 -t nes -O game.c -o game.s
ca65 -t nes game.s -o game.o
ld65 -t nes -o game.nes -C $CC65_HOME/cfg/nes.cfg game.o $CC65_HOME/lib/nes.lib
```

### Run / debug it in the emulator

```bash
mesen-mcp --rom game.nes --frames 300 --screenshot frame.png   # quick CLI check
mesen-mcp                                                      # MCP server on stdio
```

Wire it into any MCP host (Claude Desktop, Cursor, …):

```json
{
  "mcpServers": {
    "mesen": { "command": "/absolute/path/to/nesdev-tools/mesen/mesen-mcp" }
  }
}
```

## Notes

- `mesen-mcp` runs with **no `$DISPLAY`** — that is its intended environment.
  Use `--home <dir>` to keep settings, battery RAM, savestates and captures
  between runs (firmware, e.g. GBA's `gba_bios.bin`, goes in `<home>/Firmware/`).
- One ROM per `mesen-mcp` process; `load_rom` swaps the current one.
- The `cc65/*.symlink` entries (`include`, `asminc`, `cfg`, `lib`, `target`) point
  into `share/cc65/` so that both `CC65_HOME=<root>` and binary-relative lookup work.
