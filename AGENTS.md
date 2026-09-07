# AGENTS.md — N64 homebrew on `n64dev`

Everything needed to **build** and **run** N64 homebrew is already in this folder: the
libdragon SDK, its `mips64-elf` cross-compiler, upstream's examples, and a headless
emulator you can drive over MCP. No installs, no downloads, no root, no build steps.

## 1. Set up — in *every* shell

```bash
cd ~/n64dev                       # the directory you cloned
. ./setup.sh                      # DOT-SOURCE; silent, 0.003 s, repeatable
make -C libdragon/examples helloworld
```

An agent's shell usually does **not** persist between tool calls, so an `export` in one
call is gone in the next. Prefix each build command instead of trying to remember:

```bash
cd ~/n64dev && . ./setup.sh && make -C libdragon/examples/rdpqdemo
```

In a shell that cannot source scripts: `eval "$(~/n64dev/setup.sh --print)"`.
`setup.sh` exports `N64_INST`, `N64_GCCPREFIX`, `N64_TARGET`, `N64_MCP` and `PATH`; set
`N64DEV_VERBOSE=1` to have it print them, or run `./setup.sh` to see the same.

## 2. Check yourself — three levels, all in a temp dir (your tree stays clean)

| command | proves | time |
|---|---|---|
| `./setup.sh --verify` | compiler + SDK compile and link a ROM, header is `80 37 12 40` | 0.2 s |
| `./setup.sh --smoke-test [rom.z64]` | the ROM **boots in the emulator**: MCP handshake, load, 120 frames, status, log | 2.3 s |
| `./setup.sh --verify-all` | all 22 upstream examples build (22 `.z64`, 6 `.dso`, 10 `.dfs`) | 17 s |

```
n64dev OK  -  1 ROM(s), header 80371240, toolchain: in-tree
n64dev smoke OK - the ROM booted and emulated 120 frames
```

If `--verify` fails the environment is broken; nothing else is worth trying. If it passes,
every ROM problem is in your code or Makefile. `--smoke-test` with no argument builds
`examples/helloworld` and boots that, so it also doubles as an emulator check.

## 3. Layout

| path | contents |
|---|---|
| `libdragon/` | **is** `$N64_INST`: `include/n64.mk`, `bin/` (13 asset/ROM tools), `mips64-elf/include` (68 headers), `mips64-elf/lib` (`libdragon.a`, `libdragonsys.a`, `n64.ld`, `dso.ld`, `rsp.ld`) |
| `libdragon/toolchain/` | mips64-elf GCC 16.2.0 + binutils 2.45 + newlib 4.4.0, trimmed 1.6 GB → 162 MB (`libdragon/BUILD.txt` has the recipe and its traps) |
| `libdragon/examples/` | upstream examples, verified to build against the SDK above and boot in the emulator below |
| `libdragon/src/audio/libxm/` | 2 private headers `examples/audioplayer` includes as `../../src/...` |
| `ares-mcp/bin/ares-mcp` | headless N64 core: `mcp` (JSON-RPC 2.0 stdio server, 10 tools) and `run` (CLI) |
| `ares-mcp/test/` | its 27-check e2e suite (`mcp_client.py`, works on any ROM via `--rom`), test-ROM generators, `green.z64` |

## 4. Run and observe a game

```bash
ares-mcp run --rom game.z64 --homebrew --frames 600 --screenshot /tmp/s.png \
             --wav /tmp/a.wav --deterministic          # CLI: boots, runs, writes artifacts
ares-mcp run --rom game.z64 --homebrew --gdb-port 20000 --await-debugger   # GDB remote
python3 ares-mcp/test/mcp_client.py --rom game.z64 --no-check --frames 240 # one-shot MCP session
```

Over MCP (`ares-mcp mcp`), the ten tools are `n64_load`, `n64_run` (N frames, blocks),
`n64_input` (all 16 buttons + both axes, ports 1-4, `tap`/`press`/`release`),
`n64_screenshot` (PNG inline + file), `n64_log`, `n64_status`, `n64_record` (WAV),
`n64_pause`, `n64_resume`, `n64_stop`. Use `mcp_client.py` as the pattern for a
long-lived session; stdout carries only JSON-RPC, diagnostics go to stderr.

**Pixels caveat:** RDP-rendered graphics need a Vulkan driver plus an ares build with
paraLLEl-RDP (its deps are a GitHub release asset, blocked in many sandboxes), so
`screenshot` frames are blank for RDP-drawn scenes here. What still works and what to
assert on instead: `n64_status` (`loaded`, `frames`, `game_exited`), `n64_log`
(includes exceptions and the boot trace), `--wav` capture (proves the RSP mixer runs),
save states, GDB memory reads. `ares-mcp/test/green.z64` is the positive control for the
pixel path — it draws with the CPU and the suite verifies the exact pixels, so
"screenshot is blank" is an environment limit, not your bug.

## 5. Build a game

A project is a `Makefile` plus sources; `n64.mk` owns all the rules (they are the part
that changes between libdragon releases), so do not hand-roll them:

```makefile
ROMNAME := mygame
BUILD_DIR = build
C_FILES := $(shell find src -name '*.c')
OBJS := $(addprefix $(BUILD_DIR)/,$(C_FILES:.c=.o))
include $(N64_INST)/include/n64.mk
all: $(ROMNAME).z64
$(BUILD_DIR)/$(ROMNAME).elf: $(OBJS)
$(ROMNAME).z64: N64_ROM_TITLE    = "My Game"
$(ROMNAME).z64: N64_ROM_SAVETYPE = eeprom4k      # eeprom4k | eeprom16k | sram
clean:
	$(RM) -r $(BUILD_DIR) *.z64
```

Start from `cp -a libdragon/examples/helloworld ~/mygame`. Flags `n64.mk` sets for you:
`-march=vr4300 -mtune=vr4300 -mabi=o64 -I$(N64_INCLUDEDIR)` (`o64` is the point of
libdragon — do not "fix" it), RSP asm gets `-march=mips1 -mabi=32`, plus
`--build-id=none` and a `-Map`. Assets: `filesystem/%.sprite: assets/%.png` via
`mksprite`, `.wav`/`.xm`/`.ym` via `audioconv64`, fonts via `mkfont`, and
`$(BUILD_DIR)/$(ROMNAME).dfs` via `mkdfs` → `fopen("rom://…")`. DSO overlays: `n64dso`,
see `examples/overlays`. `-Werror` is on in the examples.

## 6. Do NOT

* **Do not build binutils/GCC/newlib from source** (~42 min here, and `ftp.gnu.org` /
  `sourceware.org` are usually blocked). `libdragon/toolchain/` *is* that build.
* **Do not fetch libdragon's toolchain `.deb`**: GitHub release assets are firewalled in
  many sandboxes and `dpkg -i` needs root. `setup.sh` will use `/opt/libdragon` if a
  machine happens to have it.
* **Do not** `apt-get`/`pip install`/`docker pull` a toolchain or emulator. No distro
  ships `mips64-elf`; registries are usually blocked. (`pip install cmake ninja` *is*
  how ares-mcp was built, and is the only package-manager step anywhere in this branch.)
* **Do not** use clang or `zig cc` for ROMs, and do not try to "port" the SDK: libdragon
  needs GCC + newlib + `o64`.
* **Do not** `make` inside `libdragon/` expecting to rebuild the SDK — it is an install
  tree (`make install` output), with no sources. Rebuilding is a `BUILD.txt` operation.
* **Do not** prune `libdragon/toolchain/mips64-elf/bin/` or any `bin/` dir: GCC searches
  `<prefix>/mips64-elf/bin` for `as`/`ld` and silently falls back to host binutils.
* **Do not** switch branches in a shared clone to get here — `n64dev` is an orphan
  branch whose tree is unrelated, so a checkout replaces everything. Clone into its own
  directory.
* **Do not** conclude the emulator is broken because a screenshot is black — see §4.

## 7. Gotchas that cost real time here

* **`as: unrecognized option '-EB'`** → the *host* assembler is running. Either `PATH`
  was built in one statement (`export A=1 PATH="$A/bin:$PATH"` expands `$A` before
  assigning it — use separate `export`s, or just `. ./setup.sh`), or
  `libdragon/toolchain/mips64-elf/bin/` went missing.
* `n64tool`, `mksprite`, `mkdfs` &co have **no `--version`**: run one with no arguments
  and check its usage banner.
* `.z64` files are console binaries: never `./game.z64`, never `file`-depend on it
  either (`file` is often absent). `od -An -tx1 -N8 game.z64` → `80 37 12 40 00 00 00 00`.
* Building the examples writes into `libdragon/examples/*/` (`build/`, `*.z64`,
  `*.dfs`), so `git status` shows ~40 untracked entries. Expected; `make -C
  libdragon/examples clean` undoes it. Be careful with `git clean -xdf` here: it is
  fine for build output, but it also removes anything of yours that is untracked
  (assets you generated, scratch ROMs).
* `make -C libdragon/examples <name>` builds one example; `audioplayer` needs
  `libdragon/src/` to exist (it is there) — if you copy examples elsewhere, copy that too
  or drop `audioplayer` from the run.
* Emulation is ~50 fps on 2 cores with the software path — enough for a few hundred
  frames per check, not for a 60-second soak. Keep `--frames` small and assert on
  `status`/`log`.
* Sandbox images often lack `bc`, `file`, `xdpyinfo`, `sudo`. Use `awk`, `stat`, `od`.

## 8. Numbers (2-core sandbox, cold, nothing cached)

| step | time |
|---|---|
| `git clone --depth 1 --single-branch -b n64dev` (~57 MiB) | 5 s |
| `. ./setup.sh` | 0.003 s |
| `./setup.sh --verify` | 0.2 s |
| `make -C libdragon/examples rdpqdemo` (one game) | 0.5 s |
| `./setup.sh --smoke-test` (build + boot + 120 frames) | 2.3 s |
| `./setup.sh --verify-all` (22 ROMs) | 17 s |
| `python3 ares-mcp/test/mcp_client.py` (27 checks) | 2.4 s |
| rebuilding the cross-compiler instead (do not) | 2540 s |

If something is off by an order of magnitude, suspect the sandbox (slow disk, throttled
CPU), not your Makefile: `./setup.sh --verify` isolates the environment in 0.2 s.

## 9. Regenerating this branch (only when libdragon or ares changes)

The two `BUILD.txt` files carry the exact commands. A recovery kit with the scripts
(`build-toolchain.sh`, `build-libdragon.sh`, `trim-toolchain.sh`, `build-ares-mcp.sh`,
`stage-n64dev.sh`) is on the `n64dev-wip` branch of the same repository;
`stage-n64dev.sh --commit` assembles, build-verifies, prunes and pushes the branch in one
go. Commit hygiene: this branch is committed with git plumbing from a staging directory
(`GIT_INDEX_FILE` + `commit-tree`) — unset `GIT_DIR`/`GIT_INDEX_FILE` before any other
git command, and check the file count of the commit you are about to push.
