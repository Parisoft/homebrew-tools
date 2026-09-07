# `n64dev` — build and run Nintendo 64 homebrew, no setup

A self-contained N64 development environment on an **orphan branch** of
[homebrew-tools](https://github.com/Parisoft/homebrew-tools): the libdragon SDK, its
`mips64-elf` cross-compiler, the upstream examples, and a headless N64 emulator that
speaks MCP. Nothing is installed, downloaded, built or configured — a sandbox that
wiped itself comes back to a running ROM in seconds.

**Agents: read [`AGENTS.md`](AGENTS.md) — it is the operational version of this file.**

```
n64dev/
├── setup.sh          # . ./setup.sh  → exports the environment for both halves
├── AGENTS.md         # what to run, what never to waste time on
├── libdragon/        # everything libdragon; this folder IS $N64_INST
│   ├── BUILD.txt           provenance: commits, compiler, commands, trim recipe
│   ├── include/n64.mk      the build system every project includes
│   ├── bin/                13 host tools (n64tool, mksprite, audioconv64, mkdfs, …)
│   ├── mips64-elf/         68 headers, libdragon.a, libdragonsys.a, n64.ld/dso.ld/rsp.ld
│   ├── toolchain/          mips64-elf GCC 16.2.0 + binutils 2.45 + newlib 4.4.0
│   ├── examples/           upstream examples — compiling them is the install test
│   └── src/audio/libxm/    2 private headers examples/audioplayer includes by path
└── ares-mcp/         # everything emulator
    ├── BUILD.txt           provenance: commit, compiler, commands, self-test results
    ├── bin/ares-mcp        headless N64 core: MCP server (10 tools) + CLI runner
    └── test/               e2e suite (27 checks) + ROM generators + green.z64
```

Both folders follow this repository's convention for shipped tool builds: a `BUILD.txt`
recording the exact source commit, compiler and commands, so the artifact can be
reproduced or re-trimmed later.

## Get it

```bash
git clone --depth 1 --single-branch -b n64dev \
    https://github.com/Parisoft/homebrew-tools.git n64dev
cd n64dev
```

~57 MiB transferred, one commit, and that is the whole installation: no package manager,
no root, no network left to need. Do not switch to this branch inside a clone of `main`
— it is an orphan branch, so the checkout would replace your entire working tree.

## Build a ROM, then run it

```bash
. ./setup.sh                              # N64_INST, N64_GCCPREFIX, PATH, N64_MCP
make -C libdragon/examples helloworld     # -> libdragon/examples/helloworld/helloworld.z64
ares-mcp run --rom libdragon/examples/helloworld/helloworld.z64 --homebrew \
             --frames 600 --screenshot /tmp/shot.png
```

Three checks, from fastest to most thorough — all run in a temp directory, so your
`git status` stays clean:

```bash
./setup.sh --verify        # compiles 1 ROM from scratch, checks its header   (0.2 s)
./setup.sh --smoke-test    # ...and boots it in ares-mcp over MCP             (2.3 s)
./setup.sh --verify-all    # all 22 example ROMs + ares' 27-check e2e suite   (20 s)
```

## Emulating with ares-mcp

`ares-mcp` has two modes. The CLI is the quickest way to see whether a ROM boots:

```
ares-mcp run --rom f.z64 [--homebrew] [--deterministic] [--interpreter] [--expansion]
             [--region auto|ntsc|pal] [--frames N] [--screenshot out.png] [--wav out.wav]
             [--state-in s.ares --state-out s.ares] [--gdb-port 20000] [--await-debugger]
             [--verbose]
```

and `ares-mcp mcp` is the same core behind JSON-RPC 2.0 on stdio, with ten tools —
`n64_load`, `n64_run`, `n64_input`, `n64_screenshot`, `n64_log`, `n64_status`,
`n64_record`, `n64_pause`, `n64_resume`, `n64_stop` — for an MCP client to drive a game
frame by frame (`n64_input` covers all 16 buttons and both analog axes on any of 4 ports;
`n64_load`'s `homebrew: true` is what libdragon ROMs want). Register it in an MCP config as:

```json
{ "mcpServers": { "ares-n64": { "command": "/absolute/path/to/n64dev/ares-mcp/bin/ares-mcp",
                                "args": ["mcp"] } } }
```

For an ad-hoc session against any ROM, `python3 ares-mcp/test/mcp_client.py --rom game.z64
--no-check --frames 240` does the handshake, loads, runs, screenshots and prints status
and log. `ares-mcp` also speaks the GDB remote protocol, so `--gdb-port` + `target remote`
gets you breakpoints and memory reads on a running libdragon game.

**One caveat, honestly:** RDP-rendered pixels need a Vulkan driver and an ares build with
paraLLEl-RDP (its deps come from a GitHub *release asset*, unreachable in many sandboxes).
The binary here has no RDP renderer, so `--screenshot` shows CPU-written framebuffer
content and stays blank for RDP-drawn scenes — emulation, input, audio capture, save
states, log and GDB all work. See `ares-mcp/BUILD.txt`.

## Writing a game

`libdragon/` is a libdragon **install tree** (like `/opt/libdragon` from upstream's
package), not a source checkout: `include/n64.mk` + headers + static libs + linker
scripts + host tools. A project is a `Makefile` that includes it:

```makefile
ROMNAME := mygame
BUILD_DIR = build
C_FILES := $(shell find src -name '*.c')
OBJS := $(addprefix $(BUILD_DIR)/,$(C_FILES:.c=.o))
include $(N64_INST)/include/n64.mk
all: $(ROMNAME).z64
$(BUILD_DIR)/$(ROMNAME).elf: $(OBJS)
$(ROMNAME).z64: N64_ROM_TITLE = "My Game"
clean:
	$(RM) -r $(BUILD_DIR) *.z64
```

`cp -a libdragon/examples/helloworld ~/mygame` is the fastest start. Assets are pattern
rules to the tools in `libdragon/bin` (`mksprite`, `audioconv64`, `mkfont`, `mkdfs`,
`n64dso`), and the ROM header knobs are `N64_ROM_TITLE CATEGORY SAVETYPE RTC REGION
REGIONFREE ELFCOMPRESS DSOCOMPRESS CONTROLLER1..4`. API docs: libdragon's
[wiki](https://github.com/DragonMinded/libdragon/wiki) and the headers under
`libdragon/mips64-elf/include/`.

## Constraints

* **linux x86_64** for `libdragon/bin`, `libdragon/toolchain` and `ares-mcp/bin` (host
  binaries; they need only glibc + libstdc++). On macOS/ARM, or to change libdragon or
  ares themselves, build from source — the commands are recorded in the two `BUILD.txt`
  files and the cross-compiler recipe is in the
  [`main` branch README](https://github.com/Parisoft/homebrew-tools/blob/main/README.md).
* libdragon **trunk `c4a7e11`** + GCC 16.2.0 + binutils 2.45 + newlib 4.4.0, and
  **ares-mcp `69ecdb6`**; the SDK and compiler are matched pairs, so building against a
  different libdragon revision may need `N64_INST` pointed at your own build (which
  `setup.sh` honours).
