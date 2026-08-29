# homebrew-tools

Tooling for homebrew game development.

## NES / SNES development tools — the `nesdev` branch

Agents (and humans) looking for everything needed to develop **NES and SNES games**
can find it on the **`nesdev` branch** of this repository. It is an *orphan branch*
— no shared history with `main` — carrying a prebuilt **assembler/compiler toolchain**
and a **headless emulator with an MCP server**:

| Path on `nesdev` | What it is | Version |
| --- | --- | --- |
| `cc65/` | **cc65 toolchain** — `cc65` (6502/65816 C compiler), `ca65` (macro assembler), `ld65` (linker), plus `cl65`, `ar65`, `co65`, `da65`, `od65`, `sp65`, `grc65`, `chrcvt65`, `sim65`. Ships headers, C libraries and linker configs for the **`nes`** and **`snes`** targets. | cc65 **V2.18** (Git `6efb71b`) |
| `mesen/` | **`mesen-mcp`** — the Mesen emulation core behind a stdio [MCP](https://modelcontextprotocol.io) server: load & drive a ROM, read/write memory, breakpoints, CPU stepping/tracing, PPU inspection (tilemaps, sprites, palettes), audio capture, Lua scripting, record/replay. **49 tools**, no display server, no sound device, no .NET runtime. | MesenMCP `f33a8af` (97/97 self-tests) |

Both are built for **linux x86_64** and are relocatable — the checkout can live
anywhere. `cc65/BUILD.txt` and `mesen/BUILD.txt` record the exact source commits,
compilers and build commands; `SHA256SUMS.txt` has checksums for every file.

### Get the tools

```bash
git clone --branch nesdev --single-branch https://github.com/Parisoft/homebrew-tools.git nesdev-tools
cd nesdev-tools
```

### Quickstart — put the cc65 toolchain on `PATH`

```bash
export CC65_HOME="$(pwd)/cc65"
export PATH="$CC65_HOME/bin:$PATH"
```

…or use the bundled helper, which also puts `mesen-mcp` on `PATH`:

```bash
cd nesdev-tools && . ./env.sh
```

Verify (tested on a clean checkout, linux x86_64):

```console
$ cc65 --version
cc65 V2.18 - Git 6efb71b
$ ca65 --version
ca65 V2.18 - Git 6efb71b
$ ld65 --version
ld65 V2.18 - Git 6efb71b
$ cl65 --version
cl65 V2.18 - Git 6efb71b
```

That is all the setup there is: the binaries resolve their headers, libraries and
linker configs relative to themselves, so `PATH` alone is enough (and setting
`CC65_HOME` as above also works).

### Quickstart — build a NES ROM and run it in the emulator

```bash
cl65 -t nes -o game.nes game.c                       # compile + assemble + link
mesen-mcp --rom game.nes --frames 300 --screenshot frame.png
```

Use `-t snes` instead of `-t nes` to target the SNES. To drive the emulator from
an agent, register it as an MCP server (Claude Desktop / Cursor / any stdio host):

```json
{
  "mcpServers": {
    "mesen": { "command": "/absolute/path/to/nesdev-tools/mesen/mesen-mcp" }
  }
}
```

`mesen-mcp` is designed to run with **no `$DISPLAY`**. Pass `--home <dir>` to keep
settings, battery RAM, savestates and captures between runs; firmware files (e.g.
GBA's `gba_bios.bin`) go in `<home>/Firmware/`. One ROM per process — `load_rom`
replaces the current one.
