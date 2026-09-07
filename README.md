# `n64dev` — a self-contained Nintendo 64 homebrew SDK

An **orphan branch** of [homebrew-tools](https://github.com/Parisoft/homebrew-tools)
carrying a prebuilt [libdragon](https://github.com/DragonMinded/libdragon) SDK **and**
the `mips64-elf` cross-compiler it needs, for **linux x86_64**. Clone it, dot-source one
script, build a ROM — no package manager, no root, no network, no compilation of
toolchains. It is built for agents in sandboxes that reset between attempts: the whole
environment comes from `git` and is ready in well under a minute.

**Agents: read [`AGENTS.md`](AGENTS.md) — it is the short, operational version.**

```
toolchain/       mips64-elf GCC 16.2.0 + binutils 2.45 + newlib 4.4.0 (162 MB, trimmed)
libdragon/       a libdragon install tree — what $N64_INST points at
├── BUILD.txt            provenance: source commit, toolchain, build + test commands
├── include/n64.mk       the build system, included by every project's Makefile
├── bin/                 13 host tools (n64tool, mksprite, audioconv64, mkdfs, mkfont, …)
└── mips64-elf/
    ├── include/         68 libdragon headers (+ libcart/, fatfs/, *.inc, ucode.S)
    └── lib/             libdragon.a  libdragonsys.a  n64.ld  dso.ld  rsp.ld
examples/        upstream examples, deliberately OUTSIDE libdragon/: they only see the
                 installed SDK, exactly like a real game — that is the install test
src/audio/libxm/ two private libdragon headers, needed by examples/audioplayer's
                 #include "../../src/audio/libxm/xm_internal.h"
setup.sh         exports the environment (+ --verify); AGENTS.md  what to do / not do
```

## Get it

```bash
git clone --depth 1 --single-branch -b n64dev \
    https://github.com/Parisoft/homebrew-tools.git n64dev
cd n64dev
```

~200 MB, one commit, nothing else fetched. Do not switch branches in an existing clone of
this repo to get here: `n64dev` is an orphan, so a checkout replaces the entire working
tree (that also means `git status` there will never show the other branches' files).

## Set up and build

```bash
. ./setup.sh                     # N64_INST, N64_GCCPREFIX, PATH — instant, repeatable
./setup.sh --verify              # builds a ROM from scratch into a temp dir: "n64dev OK"
make -C examples helloworld      # -> examples/helloworld/helloworld.z64
make -C examples -j2             # the whole example matrix: 22 ROMs, 0 errors
```

`setup.sh` only exports variables, so re-run it in every shell you start — with most
agent harnesses a new tool call means a new shell and the previous exports are gone.

Measured in a 2-core sandbox, cold: clone transfers 55.6 MiB (6 s) → `--verify` builds
a ROM in 0.2 s → the whole example matrix (22 ROMs) in 17 s. No root, no network after
the clone. [`AGENTS.md`](AGENTS.md) has the full table and the pitfalls.

## Start a game from the example skeleton

```bash
cp -a examples/helloworld ~/mygame && cd ~/mygame
make            # edit the Makefile: ROMNAME, sources under src/, N64_ROM_TITLE
```

`include $(N64_INST)/include/n64.mk)` gives you `%.z64` (link → strip → `n64elfcompress`
→ `n64tool` → `ed64romconfig`), `%.dfs`, `%.v64`, `%.dso` and the asset rules
(`mksprite`, `audioconv64`, `mkfont`); the ROM header is set with `N64_ROM_TITLE`,
`N64_ROM_SAVETYPE`, `N64_ROM_RTC`, `N64_ROM_REGION…`. `examples/` covers each subsystem:
`rdpqdemo` (display), `spriteanim`, `fontgallery`, `joypadtest`, `mixertest`,
`audioplayer` (XM/YM modules), `overlays` (DSO), `dfs` (`rom://` files), `eepromfstest`,
`cpaktest` (Controller Pak), `timers`, `rspqdemo`, `vrutest`, `test`/`cpptest` (unit tests).

API reference: libdragon's [wiki](https://github.com/DragonMinded/libdragon/wiki) and
Doxygen docs on GitHub, and the headers in `libdragon/mips64-elf/include/`.

## Running a ROM

`.z64` files are console binaries, not host executables. In
[Ares](https://github.com/ares-emulator/ares) enable *Homebrew mode* (a plain emulator
also works, but timing-sensitive code wants accurate RDP/RSP). On hardware:
SummerCart64, 64drive or EverDrive-64 — `n64sym` and the debug loader give you GDB
over the cart link. Full walkthrough in the
[`main` branch README](https://github.com/Parisoft/homebrew-tools/blob/main/README.md).

## Constraints

* **linux x86_64 only** for the tools (`toolchain/bin`, `libdragon/bin` are host
  binaries; they need only glibc + libstdc++, no other runtime deps). On macOS/ARM, or
  to change libdragon itself, build the SDK from upstream — the commands and the exact
  trim recipe are recorded in [`libdragon/BUILD.txt`](libdragon/BUILD.txt), and the
  cross-compiler recipe (42 min, needs `ftp.gnu.org`) in the root README.
* **GCC + newlib + `o64`**, as `n64.mk` configures; no clang/zig support.
* `libdragon/` has no sources by design — it is `make install` output. If you need the
  library's internals, clone `DragonMinded/libdragon` (`--depth 1`) next to this.
