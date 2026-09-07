# AGENTS.md — N64 homebrew on `n64dev`

This branch is a **complete, self-contained N64 development environment**: libdragon
(the SDK), a `mips64-elf` cross-compiler, and the upstream example games. Nothing has
to be installed, downloaded, compiled or configured — which is the whole point: a
sandbox that resets between attempts can be back to a working build in seconds.

## 1. Set up — do this in *every* shell

```bash
cd ~/n64dev            # the directory you cloned (see README.md for the clone command)
. ./setup.sh           # DOT-SOURCE it; it only exports variables
make -C examples helloworld && ls -l examples/helloworld/helloworld.z64
```

An agent's shell usually does **not** persist between tool calls, so an `export` in
one call is gone in the next. Prefix every build command instead of remembering it:

```bash
cd ~/n64dev && . ./setup.sh && make -C examples/rdpqdemo
```

For a shell that cannot source bash scripts (dash, CI steps): `eval "$(~/n64dev/setup.sh --print)"`.

`setup.sh` is **silent** when sourced, so prefixing every command with it costs nothing
in output; it returns non-zero only when the tree is unusable. `N64DEV_VERBOSE=1` prints
the resolved variables, and `./setup.sh` (executed, not sourced) prints them too — that
is the command to reach for when something looks off. It never compiles anything unless
asked, and never writes into the tree.

## 2. Verify — 0.3 s (or 19 s for everything)

```bash
./setup.sh --verify        # compiles examples/helloworld from scratch, checks the ROM header
./setup.sh --verify-all    # all 22 upstream examples: 22 .z64, 6 .dso, 10 .dfs
```

Both build inside a temporary copy, so your `git status` stays clean. A pass looks like:

```
n64dev OK  -  1 ROM(s), header 80371240, toolchain: in-tree
```

If `--verify` fails, the environment is broken — nothing else is worth trying. If it
passes, every ROM-building problem is in your code or your Makefile.

## 3. What is here

| path | contents |
|---|---|
| `toolchain/` | `mips64-elf` GCC 16.2.0 + binutils 2.45 + newlib 4.4.0 (linux-x86_64 host, 162 MB, trimmed — see `libdragon/BUILD.txt`) |
| `libdragon/include/n64.mk` | the makefile fragment every game includes; defines all the rules |
| `libdragon/mips64-elf/include/` | 68 public headers (`libdragon.h`, `rdpq.h`, `mixer.h`, `debug.h`, `libcart/`, `fatfs/`, …) plus `ucode.S` and `*.inc` |
| `libdragon/mips64-elf/lib/` | `libdragon.a`, `libdragonsys.a`, linker scripts `n64.ld` `dso.ld` `rsp.ld` |
| `libdragon/bin/` | 13 host asset/ROM tools: `n64tool n64sym n64elfcompress ed64romconfig audioconv64 mkdfs dumpdfs mkasset mksprite mkfont n64dso n64dso-msym n64dso-extern` |
| `examples/` | upstream example games, verified to build against exactly this SDK |
| `src/audio/libxm/` | two *private* libdragon headers, only because `examples/audioplayer` includes `../../src/audio/libxm/xm_internal.h` |

`libdragon/` is an **install tree**, not a source checkout: no `Makefile`, no `build.sh`.
That is intentional — it is what `make install` produces, and it is what `N64_INST` means.

## 4. Build a game

```bash
cd ~/n64dev && . ./setup.sh && cp -a examples/helloworld ~/mygame && cd ~/mygame
make            # -> mygame.z64 (renamed from helloworld: edit the Makefile's ROMNAME)
```

A project is a `Makefile` plus `src/`. Do not hand-roll build rules — they belong to
`n64.mk`, which is the part of libdragon that changes between releases:

```makefile
ROMNAME := mygame
BUILD_DIR = build
C_FILES := $(shell find src -name '*.c')
OBJS := $(addprefix $(BUILD_DIR)/,$(C_FILES:.c=.o))

include $(N64_INST)/include/n64.mk

all: $(ROMNAME).z64
$(BUILD_DIR)/$(ROMNAME).elf: $(OBJS)

$(ROMNAME).z64: N64_ROM_TITLE    = "My Game"   # ROM header
$(ROMNAME).z64: N64_ROM_SAVETYPE = eeprom4k    # eeprom4k | eeprom16k | sram
$(ROMNAME).z64: N64_ROM_RTC      = true        # and cart/emulator hints

clean:
	$(RM) -r $(BUILD_DIR) *.z64
```

Flags `n64.mk` adds for you — do not override them:
`-march=vr4300 -mtune=vr4300 -mabi=o64 -I$(N64_INCLUDEDIR)` for C/C++/asm,
`-march=mips1 -mabi=32` for RSP asm, `--build-id=none`, `-Wl,-Map=…`.
ROM knobs: `N64_ROM_TITLE CATEGORY SAVETYPE RTC REGION REGIONFREE ELFCOMPRESS
DSOCOMPRESS CONTROLLER1..4`.

Assets are pattern rules against the tools in `libdragon/bin`:
`filesystem/%.sprite: assets/%.png` (`mksprite`), `.wav`/`.xm`/`.ym` (`audioconv64`),
fonts (`mkfont`), and `$(BUILD_DIR)/$(ROMNAME).dfs` (`mkdfs`) linked in and read with
`fopen("rom://…")`. Overlays/dynamic libraries: `n64dso` + `%.dso` rules, see
`examples/overlays`.

Docs for the API: libdragon's Doxygen reference and wiki are on `github.com`
(reachable from sandboxes, unlike the release-asset CDN) —
`https://github.com/DragonMinded/libdragon/wiki`. Or read the headers, which are right here.

## 5. Do NOT

* **Do not build binutils/GCC/newlib from source.** It works (documented in the root
  repo README) but takes ~42 min and needs `ftp.gnu.org`/`sourceware.org`, which
  sandboxes usually block. The compiler in `toolchain/` is already that exact build.
* **Do not download libdragon's toolchain `.deb`**: GitHub *release assets* redirect to
  a CDN that is firewalled in most sandboxes, and installing needs root. `toolchain/`
  replaces it. (On a normal machine the deb is fine — then `N64_GCCPREFIX` points at
  `/opt/libdragon`, which `setup.sh` auto-detects if `toolchain/` is absent.)
* **Do not** `apt install`, `pip install` or `docker pull` a toolchain. There is no
  `mips64-elf` package in any distro, and registries are usually blocked too.
* **Do not** use `clang` or `zig cc`: libdragon needs GCC, newlib and the 64-bit
  `o64` ABI with the `vr4300` tuning; the linker scripts and RSP ucode tooling are
  GCC/binutils-specific.
* **Do not** switch branches in a shared clone to get here. `n64dev` is an *orphan*
  branch: its tree is unrelated to `main`, so a checkout replaces the whole working
  directory. Clone it into its own directory instead.

## 6. Gotchas that cost real time

* **Symptom `as: unrecognized option '-EB'`** → the host `as` is being used instead of
  `mips64-elf-as`. Two causes: (a) `PATH` built in one `export` statement —
  `export A=1 PATH="$A/bin:$PATH"` expands `$A` *before* assigning it, so use separate
  `export`s; (b) `toolchain/mips64-elf/bin/` missing or pruned — **GCC searches that
  directory for `as`/`ld`**; it is not a duplicate of `toolchain/bin/`, do not delete it.
* `n64tool`, `mksprite`, `mkdfs` &co have **no `--version`**. Run one with no
  arguments and check for its usage banner instead.
* ROMs are **not** executable by the OS. Test them in an emulator —
  [Ares](https://github.com/ares-emulator/ares) with *Homebrew mode* enabled is what
  libdragon recommends. On hardware: SummerCart64, 64drive or EverDrive-64; the debug
  loaders need a MIPS GDB (`n64sym` is here, `gdb` is not — install `gdb-multiarch` if
  you want it).
* Built ROMs land **inside** `examples/*/`, so a full `make -C examples` makes the tree
  dirty (`git status` shows untracked `build/`, `*.z64`). That is expected build output;
  clean with `make -C examples clean`.
* `-Werror` is on by default in libdragon's example Makefiles; a warning is an error.
* Minimal sandboxes often lack `bc`, `file`, `xdpy`. Use `awk`, `stat`, and
  `od -An -tx1 -N16 rom.z64` (a valid header starts `80 37 12 40 00 00 00 00`).

## 7. Numbers measured in a 2-core sandbox (cold, nothing cached)

| step | time |
|---|---|
| `git clone --depth 1 --single-branch -b n64dev` (55.6 MiB pack → 190 MB tree) | 6 s |
| `. ./setup.sh` | 0.003 s |
| `./setup.sh --verify` (compiles 1 ROM from scratch) | 0.2 s |
| `make -C examples rdpqdemo` (one game) | 0.5 s |
| `./setup.sh --verify-all` / `make -C examples -j2` (all 22 ROMs) | 17 s |
| building binutils + GCC + newlib from source instead (do not) | 2540 s |

After the clone, the whole environment is on disk and works offline. If any step above
is off by an order of magnitude, suspect a full-disk or CPU-throttled sandbox, not your
Makefile — re-run `./setup.sh --verify` to separate the two.

One more measured thing: `make` *without* sourcing `setup.sh` in the same shell fails
with `N64_INST not set` (each of your tool calls is a new shell). That is the single
most likely way to break this environment, and it is why every command in this file is
written as `. ./setup.sh && …`.
