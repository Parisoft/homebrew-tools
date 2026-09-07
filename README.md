# homebrew-tools

Tooling for homebrew game development and reverse-engineer arcade games.

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
compilers and build commands.

### Get the tools

```bash
git clone --branch nesdev --single-branch https://github.com/Parisoft/homebrew-tools.git nesdev-tools
cd nesdev-tools
```

The branch contains nothing but those two folders:

```
nesdev-tools/
├── cc65/     # cc65 V2.18 toolchain
└── mesen/    # mesen-mcp
```

### Quickstart — put the cc65 toolchain on `PATH`

```bash
cd nesdev-tools
export CC65_HOME="$(pwd)/cc65"      # REQUIRED - where include/, lib/ and cfg/ live
export PATH="$CC65_HOME/bin:$PATH"  # cc65, ca65, ld65, cl65, ...
export PATH="$(pwd)/mesen:$PATH"    # mesen-mcp
```

`CC65_HOME` must point at the directory that **contains** `include/`, `lib/` and
`cfg/` — both `<checkout>/cc65` and `<checkout>/cc65/share/cc65` work. Putting the
tools on `PATH` alone is *not* enough on cc65 2.18: it has no fallback to a
path relative to its own binary, so without `CC65_HOME` it cannot find its
headers or libraries.

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

## N64 development tools — the `n64dev` branch

Agents (and humans) looking for everything needed to build **Nintendo 64 homebrew
games** can find it on the **`n64dev` branch** of this repository. It is an *orphan
branch* — no shared history with `main` — carrying a prebuilt
[libdragon](https://github.com/DragonMinded/libdragon) SDK for **linux x86_64**:

| Path on `n64dev` | What it is | Version |
| --- | --- | --- |
| `libdragon/` | **libdragon install tree** — the whole `$N64_INST`: `mips64-elf/lib/libdragon.a` + `libdragonsys.a` and the linker scripts (`n64.ld`, `dso.ld`, `rsp.ld`), the 68 public headers (plus `libcart/`, `fatfs/`, the RSP `*.inc` files and `ucode.S`), `include/n64.mk` (which *is* the build system), and the 13 host tools: `n64tool`, `n64sym`, `n64elfcompress`, `ed64romconfig`, `audioconv64`, `mkdfs`, `dumpdfs`, `mkasset`, `mksprite`, `mkfont`, `n64dso`, `n64dso-extern`, `n64dso-msym`. | libdragon **trunk** (Git `c4a7e11`) |
| `examples/` | The upstream example games, kept **outside** `libdragon/` on purpose: they are ordinary libdragon projects that only ever see the *installed* SDK, so compiling them **is** the install test. 22 ROMs, zero errors. | same commit |

Nothing else is kept — no libdragon sources, objects, docs or tests: 293 files,
21 MB. `libdragon/BUILD.txt` records the source commit, the cross-toolchain
versions and the exact commands used.

What libdragon brings to a game: RDPQ accelerated 2D (sprites of arbitrary size and
pixel format, a text engine, custom color combiner and blender), an RSP audio mixer
with WAV / VADPCM / XM / YM / Opus playback, an in-ROM asset filesystem
(`fopen("rom://asset.dat")`), transparent asset compression, `dlopen()`-based DSO
overlays, symbolized crash screens, `debugf()` streamed to the PC, EEPROM / SRAM /
flash saves and the RTC, the open-source IPL3 boot code, and iQue Player support
without touching your sources.

### Get the tools

```bash
git clone --branch n64dev --single-branch https://github.com/Parisoft/homebrew-tools.git n64dev-tools
cd n64dev-tools
```

The branch contains nothing but those two folders:

```
n64dev-tools/
├── libdragon/     # the SDK install tree (this becomes $N64_INST)
└── examples/      # upstream examples, built against it
```

### Setup — the cross-compiler, then the environment

libdragon splits its environment in two halves, and this branch ships exactly one
of them: the **SDK**. The **mips64-elf GCC** cross-compiler is not on the branch
(1.5 GB unpacked, far over GitHub's 100 MB per-file cap); it comes from libdragon's
own rolling toolchain release, installed once per machine:

```bash
# Debian/Ubuntu — the release also has .rpm (Fedora), aarch64 and a Windows zip
wget -q https://github.com/DragonMinded/libdragon/releases/download/toolchain-continuous-prerelease/gcc-toolchain-mips64-x86_64.deb
sudo dpkg -i gcc-toolchain-mips64-x86_64.deb && rm gcc-toolchain-mips64-x86_64.deb
```

The package installs `mips64-elf-{gcc,g++,as,ld,ar,objcopy,…}` under `/opt/libdragon`
and exports `N64_INST=/opt/libdragon` by itself through `/etc/profile.d`. To use
**this branch's** SDK instead, split the two prefixes apart — `n64.mk` supports the
split out of the box (`N64_GCCPREFIX ?= $(N64_INST)`):

```bash
cd n64dev-tools
export N64_INST="$PWD/libdragon"               # SDK from this branch
export N64_GCCPREFIX=/opt/libdragon            # where mips64-elf-gcc lives
export PATH="$N64_INST/bin:$N64_GCCPREFIX/bin:$PATH"
```

| Variable | Meaning |
|---|---|
| `N64_INST` | **Required.** Root of the libdragon install. `n64.mk` is read from `$(N64_INST)/include/n64.mk`, headers from `$(N64_INST)/mips64-elf/include`, libraries from `$(N64_INST)/mips64-elf/lib`, asset tools from `$(N64_INST)/bin`. |
| `N64_GCCPREFIX` | Root holding `bin/mips64-elf-*`. Defaults to `N64_INST`; you only need it because the SDK here is a separate folder. |
| `N64_TARGET` | Triplet of the cross toolchain, `mips64-elf`. Keep the **64-bit** one — libdragon's point is the `o64` ABI (full 64-bit R4300 registers), which the old 32-bit `mips-elf` toolchains cannot emit. |

Keeping every default is also fine: `sudo cp -a libdragon/. /opt/libdragon/` drops
this SDK on top of the deb's prefix and then no variable has to be set at all.

Verify (tested on a clean checkout of `n64dev`, linux x86_64):

```console
$ mips64-elf-gcc --version
mips64-elf-gcc (GCC) 16.2.0
$ ls "$N64_INST/mips64-elf/lib"
dso.ld  libdragon.a  libdragonsys.a  n64.ld  rsp.ld
$ "$N64_INST/bin/n64tool"
Usage: n64tool [flags] [file-flags] <file> [[file-flags] <file> ...]
$ "$N64_INST/bin/mksprite"
Usage: mksprite [flags] <input files...>
```

### Quickstart — build a ROM

```console
$ make -C examples helloworld
Using N64_INST=/home/me/n64dev-tools/libdragon
    [CC] src/main.c
    [LD] build/helloworld.elf
      text       data        bss      total filename
    145240      41996       3688     190924 build/helloworld.elf
    [Z64] helloworld.z64
$ od -An -tx1 -N8 examples/helloworld/helloworld.z64
 80 37 12 40 00 00 00 00          # PI boot CIC word + zero reset: a real N64 ROM
```

A game is a Makefile that includes `n64.mk` plus its sources — do not hand-roll
rules, they are the part libdragon changes between releases (this is
`examples/helloworld/Makefile` with the comments removed):

```makefile
ROMNAME := mygame
BUILD_DIR = build
C_FILES := $(shell find src -name '*.c')
OBJS := $(addprefix $(BUILD_DIR)/,$(C_FILES:.c=.o))

include $(N64_INST)/include/n64.mk

all: $(ROMNAME).z64
$(BUILD_DIR)/$(ROMNAME).elf: $(OBJS)

$(ROMNAME).z64: N64_ROM_TITLE    = "My Game"    # ROM header…
$(ROMNAME).z64: N64_ROM_SAVETYPE = eeprom4k     # …battery save…
$(ROMNAME).z64: N64_ROM_RTC      = true         # …and cart/emulator hints

clean:
	$(RM) -r $(BUILD_DIR) *.z64
```

Assets are just more pattern rules, and `n64.mk` already knows their tools:
`filesystem/%.sprite: assets/%.png` through `mksprite`, `.wav`/`.xm`/`.ym` through
`audioconv64`, a font through `mkfont`, and `$(BUILD_DIR)/$(ROMNAME).dfs` builds the
in-ROM filesystem with `mkdfs` — link that in and `fopen("rom://…")` finds it.
`n64.mk` supplies the `%.z64` (strip → `n64elfcompress` → `n64tool` →
`ed64romconfig`), `%.dfs`, `%.v64` and `%.dso` (+ `%.externs`, `%.msym`) rules and
the `N64_ROM_*` knobs (`TITLE`, `CATEGORY`, `REGION`, `REGIONFREE`, `SAVETYPE`,
`RTC`, `CONTROLLER1..4`).

### Running the ROM

libdragon uses corners of the hardware that commercial games never touched, so it
needs an emulator that models the real chip: [Ares](https://github.com/ares-emulator/ares),
with *Homebrew mode* enabled for the developer checks. On hardware any cart that
loads custom ROMs works (SC64, 64drive, EverDrive64); use a loader that speaks
libdragon's debug protocol — [UNFLoader](https://github.com/buu342/N64-UNFLoader),
[g64drive](https://github.com/rasky/g64drive), [ed64log](https://github.com/anacierdem/ed64)
— to see `debugf()` in a console.

### Rebuilding the SDK that the branch ships

```bash
git clone https://github.com/DragonMinded/libdragon.git && cd libdragon
export N64_INST=<install-prefix> N64_GCCPREFIX=<toolchain-prefix>
make install-mk && make libdragon tools
make install && make tools-install
```

Upstream's `./build.sh` does the same but then builds the examples *inside* the
tree, which proves nothing about the install; instead copy the folder out and
compile it against the installed SDK only:

```bash
mkdir -p <test> && cp -a examples <test>/examples
make -C <test>/examples -j"$(nproc)"     # expect 22 .z64, 6 .dso, 10 .dfs, 0 errors
```

`audioplayer` is the single example that reaches into libdragon's private headers
(`../../src/audio/libxm/xm_internal.h`), so give `<test>` a `src` symlink to the
checkout — or skip that one. Then ship only what survived: `include/`, `bin/`,
`mips64-elf/` of `<install-prefix>`, on an orphan branch:

```bash
git checkout --orphan n64dev && git rm -rf .
cp -a <install-prefix> libdragon && cp -a <test>/examples examples
git add -A && git commit -m "n64dev: prebuilt libdragon SDK" && git push -f origin n64dev
```

If the **cross-compiler** itself has to be rebuilt, libdragon pins its versions in
`tools/build-toolchain.sh` (binutils 2.45, GCC 16.2.0, newlib 4.4.0.20231231 at the
time of writing) and that script does the whole job. Two notes from having done it on
a machine that could reach nothing but GitHub and PyPI:

* the sources come from git mirrors instead of the FTP sites —
  `gnutools/binutils-gdb@binutils-2_45`, `gcc-mirror/gcc@releases/gcc-16.2.0`,
  `mirror/newlib-cygwin@newlib-4.4.0` — and GMP/MPFR/MPC/zlib/m4/gperf/bison/flex
  come from wheels: `pip install --target=<pfx> --no-deps cmeel-gmp cmeel-mpfr
  cmeel-mpc cmeel-zlib cmeel-m4 cmeel-gperf bison-bin flex-bin`, then
  `--with-gmp=<pfx> --with-mpfr=<pfx> --with-mpc=<pfx>` plus
  `-I<pfx>/include -L<pfx>/lib -Wl,-rpath,<pfx>/lib` (cmeel keeps `libz` in `lib64/`);
* git trees have no generated parsers, so `bison` and `flex` must really be on
  `PATH` (`export M4=<pfx>/bin/m4` or bison fails), and `makeinfo` is best replaced
  by a stub that only creates the `-o` file — binutils' own `missing` wrapper exits
  127 and kills `bfd`.

## Tooling for reverse-engineer arcade games

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
| `n64dev` | **libdragon** SDK install tree + examples (N64 homebrew) |
| `nesdev` | **cc65** toolchain + **mesen-mcp** (NES / SNES development) |
| `mame-konami` | Headless **konami** MAME binary + MCP server |
| `mame-capcom` | Headless **capcom** MAME binary + MCP server |
| `mame-sega` | Headless **sega** MAME binary + MCP server |
| `mame-taito` | Headless **taito** MAME binary + MCP server |
| `mame-tecmo` | Headless **tecmo** MAME binary + MCP server |
| `mame-technos` | Headless **technos** MAME binary + MCP server |
| `main` | Default branch |

`n64dev`, `nesdev` and every `mame-<system>` branch is an orphaned delivery branch
(no shared history with `main`): check one out, or clone it with
`--branch <name> --single-branch`, and the tools are there.

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
