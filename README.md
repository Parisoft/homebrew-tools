# `n64dev` — Nintendo 64 homebrew SDK

This is an **orphan branch** of [homebrew-tools](https://github.com/Parisoft/homebrew-tools)
that carries only a prebuilt [libdragon](https://github.com/DragonMinded/libdragon) SDK for
**linux x86_64**, so an agent (or you) can compile N64 ROMs with no setup beyond fetching the
cross-compiler.

```
libdragon/     # a libdragon install tree — this is what $N64_INST points at
├── BUILD.txt            provenance: source commit, toolchain, build + test commands
├── include/n64.mk       the build system, included by every project's Makefile
├── bin/                 13 host tools (n64tool, mksprite, audioconv64, mkdfs, mkfont, …)
└── mips64-elf/
    ├── include/         68 libdragon headers (+ libcart/, fatfs/, *.inc, ucode.S)
    └── lib/             libdragon.a  libdragonsys.a  n64.ld  dso.ld  rsp.ld
examples/        # upstream examples, deliberately OUTSIDE libdragon/: they only see the
                 # installed SDK, exactly like a real game — that is the install test
```

## Setup

```bash
# 1. the mips64-elf cross-compiler (not on this branch: 1.5 GB, over GitHub's 100 MB cap)
wget -q https://github.com/DragonMinded/libdragon/releases/download/toolchain-continuous-prerelease/gcc-toolchain-mips64-x86_64.deb
sudo dpkg -i gcc-toolchain-mips64-x86_64.deb && rm gcc-toolchain-mips64-x86_64.deb   # -> /opt/libdragon

# 2. point libdragon's build system at this checkout's SDK + that compiler
export N64_INST="$PWD/libdragon"
export N64_GCCPREFIX=/opt/libdragon
export PATH="$N64_INST/bin:$N64_GCCPREFIX/bin:$PATH"
```

`N64_GCCPREFIX` is only needed because the SDK here is a separate folder — with libdragon's
deb alone, `N64_INST` is already exported as `/opt/libdragon` by its `/etc/profile.d` script.
(`sudo cp -a libdragon/. /opt/libdragon/` also works and keeps every default.)

## Build a ROM

```bash
make -C examples helloworld          # -> examples/helloworld/helloworld.z64
file examples/helloworld/helloworld.z64
```

Verified on this tree: `make -C examples -j2` builds **22 ROMs** (20 examples, incl. 6 DSO
overlays and 10 DFS filesystems) with zero errors. The one exception is `audioplayer`, which
upstream makes reach into libdragon's *private* sources (`../../src/audio/libxm/xm_internal.h`);
build it from inside a libdragon checkout, or symlink a `src/` pointing at one next to
`examples/`.

Run the ROMs in [Ares](https://github.com/ares-emulator/ares) (enable *Homebrew mode*) or on
hardware via SC64 / 64drive / EverDrive64. Full walkthrough: the
[`main` branch README](https://github.com/Parisoft/homebrew-tools/blob/main/README.md).
