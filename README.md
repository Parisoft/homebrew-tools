# homebrew-tools

Build artifacts and tooling for arcade ROM **disassembly** and **porting to new
systems**, driven by AI agents.

Agents use these binaries to reverse-engineer arcade games: load a game into a
headless [MAME](https://www.mamedev.org/) and drive it over the
[Model Context Protocol](https://modelcontextprotocol.io) to inspect memory,
registers, disassembly, execution coverage, decoded graphics, screenshots and
audio. This enables ROM dump analysis, understanding how a board works, and
porting a game's logic to a new platform.

## Branches

| Branch | Contents |
|---|---|
| `mame-konami` | Headless **konami** MAME binary + MCP server |
| `mame-capcom` | Headless **capcom** MAME binary + MCP server |
| `mame-sega` | Headless **sega** MAME binary + MCP server |
| `mame-taito` | Headless **taito** MAME binary + MCP server |
| `mame-tecmo` | Headless **tecmo** MAME binary + MCP server |
| `mame-technos` | Headless **technos** MAME binary + MCP server |
| `main` | Default branch |

Each `mame-<system>` branch is an orphaned delivery branch (no shared history
with `main`).

## What a MAME binary gives an agent

Each `mame-<system>` branch carries a compressed headless MAME binary built for a
specific arcade manufacturer/driver set (e.g. `mame-tecmo`), plus the
`mcp-server` (Node supervisor), the MAME Lua plugin (`plugins/mcp/`), and the MAME
data directories (`artwork`, `roms`, `samples`). Together they expose ~67 MCP
tools for debugging and reverse-engineering ROMs.

The binary is the headless fork from [Parisoft/mame-mcp](https://github.com/Parisoft/mame-mcp),
which strips all display/graphics dependencies (`OSD=headless`) and adds MCP
bindings for graphics, disassembly and execution coverage.

> **Why the binary is stored compressed.** A full manufacturer headless build is
> often ~75–110 MB — over or near GitHub's 100 MB hard limit for a single file —
> so it cannot be committed raw. `mame.xz` is typically 10–22 MB. This is the same
> reason the upstream README suggests stripping + `xz` for distribution. (A
> `SUBTARGET=tiny` build is ~86 MB raw / 65 MB stripped and *would* fit under
> 100 MB, but it only contains 59 machines and no full manufacturer set.)

## Using a MAME binary

```bash
git checkout mame-tecmo          # or mame-technos, mame-konami, ...
xz -dk mame.xz                   # decompress the binary
chmod +x mame
./mame -listfull rygar           # tecmo: Rygar, silkworm, ...
./mame -listfull ddragon         # technos: Double Dragon, renegade, ...

cd mcp-server && npm install     # install the MCP server deps
```

Register with an MCP client (the branch is fully self-contained — `MAME_DIR` can
point straight at it):

```json
{
  "mcpServers": {
    "mame": {
      "command": "node",
      "args": ["/path/to/homebrew-tools/mcp-server/src/index.mjs"],
      "env": {
        "MAME_DIR": "/path/to/homebrew-tools",
        "MAME_BINARY": "/path/to/homebrew-tools/mame",
        "MAME_ROMPATH": "/path/to/roms"
      }
    }
  }
}
```

> The MAME Lua plugin (`plugins/mcp/`) **is** shipped on these branches — the
> `mcp-server` launches MAME with `-plugin mcp -pluginspath <MAME_DIR>/plugins`, so
> it works out of the box. ROMs are **never** distributed with this repo: point
> `MAME_ROMPATH` at your own dumps.

---

## Building a MAME binary for a target system

These are the exact steps used to produce `mame.xz` on the `mame-tecmo` /
`mame-technos` (and earlier manufacturer) branches. Repeat them for any target
system.

### 1. Check out the mame-mcp fork

```bash
git clone https://github.com/Parisoft/mame-mcp.git
cd mame-mcp
git checkout arena/01a03e9a-mame-mcp
```

### 2. Build the headless binary for a driver set

```bash
make OSD=headless SOURCES=src/mame/tecmo NOWERROR=1 -j1
```

- `OSD=headless` — display-free OSD, no SDL/X11/Qt/OpenGL needed to build or run.
- `SOURCES=src/mame/tecmo` — build only the tecmo drivers (a whole directory is
  walked recursively by `makedep.py`; MAME auto-derives the required CPUs, sound
  chips and video hardware). Use `src/mame/technos` for Technos Japan.
- `NOWERROR=1` — GCC 12 emits `-Werror=restrict` false positives.

**Required `NO_USE_*` flags.** On Linux, MAME's `modules.lua` defaults
`NO_USE_MIDI`/`NO_USE_PORTAUDIO` to *enabled*, which pulls PortAudio/PortMidi and
drags in ALSA (`alsa/asoundlib.h`). The headless OSD doesn't need audio at all, so
disable them:

```bash
make OSD=headless SOURCES=src/mame/tecmo NOWERROR=1 \
     NO_USE_MIDI=1 NO_USE_PORTAUDIO=1 -j1
```

**Generate-time vs build-time.** `OSD`, `SOURCES`, `NOWERROR` and every `NO_USE_*`
flag are consumed by genie when it *generates* the makefiles, not when `make`
compiles. If you add/change one after a build, the tree was already generated
without it and the change silently does nothing. After changing any of them run
`rm -rf build/projects` (or `REGENIE=1`) before rebuilding.

**Memory.** Budget ~3 GB RAM per parallel job; add swap if tight, or use `-j1` on
a 4 GB machine:

```bash
sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none
sudo chmod 600 /swapfile && sudo mkswap -q /swapfile && sudo swapon /swapfile
```

**Output name.** Without `SUBTARGET=tiny` the binary is **`./mame`** (not
`mametiny`) in the repo root. If you also pass `SUBTARGET=tiny` the name becomes
`./mametiny`.

> **Gotcha if a flag change causes a full recompile:** if you regenerate the
> project after `SOURCES` was already compiled (e.g. to add the `NO_USE_*` flags),
> the regenerated makefile can recompile large portions of the tree. A faster path
> is to regenerate once, then build only the `mame` target:
>
> ```bash
> make -C build/projects/headless/mame/gmake-linux config=release mame
> ```
>
> This skips the portaudio/portmidi 3rd-party projects entirely.

### 3. Verify the binary

```bash
ldd mame                   # should list only libc/libstdc++/libm/libgcc
./mame -help               # works with no DISPLAY set
./mame -listfull rygar     # tecmo drivers (e.g. "Rygar (US set 1)")
./mame -listfull ddragon   # technos drivers (e.g. "Double Dragon (World set 1)")
```

### 4. Package the artifacts

Keep only the binary, the `mcp-server` directory, the MAME Lua plugin
(`plugins/mcp/`), and every data directory that contains a `dir.txt` (`artwork/`,
`roms/`, `samples/`). Compress the binary:

```bash
xz -6 -T2 -c mame > mame.xz
```

Stage the artifacts into a clean folder:

```bash
mkdir -p /tmp/artifacts
cp mame.xz /tmp/artifacts/
cp -r mcp-server plugins artwork roms samples /tmp/artifacts/
cp -r src/mame/tecmo /tmp/artifacts/src/mame/   # driver source as reference
```

### 5. Ship them on an orphaned branch

```bash
cd <this repo>
git checkout --orphan mame-tecmo   # new root branch, no history
git rm -rf .
cp -r /tmp/artifacts/. .
git add -A
git commit -m "Add tecmo MAME binary (mame.xz) and MCP server"
git push origin mame-tecmo
```
