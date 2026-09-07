#!/usr/bin/env bash
#
# bootstrap.sh — set up the homebrew-tools toolchains.
#
# Usage:
#   ./bootstrap.sh nesdev              # NES/SNES dev tools (cc65 + mesen-mcp)
#   ./bootstrap.sh n64dev              # N64 dev tools (libdragon + mips64-elf GCC + ares-mcp)
#   ./bootstrap.sh mame <system>       # headless MAME + MCP server for <system>
#
#   <system> is one of: konami capcom sega taito tecmo technos
#
# Each target is fetched as a shallow (--depth 1) single-branch clone of the
# matching orphan branch of this repository, into a directory named after the
# branch (nesdev/, n64dev/ or mame-<system>/), and then set up per the README.
#
# After a successful run an env file is written next to the checkout:
#   <dir>/env.sh   ->   source it to put the tools on PATH.
#
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Parisoft/homebrew-tools.git}"
BASE_DIR="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MAME_SYSTEMS=(konami capcom sega taito tecmo technos)

msg()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
}

# clone_branch <branch> <target-dir>
clone_branch() {
  local branch="$1" dir="$2"
  if [ -d "$dir/.git" ]; then
    msg "Updating existing checkout in '$dir' (branch $branch)"
    git -C "$dir" fetch --depth 1 origin "$branch"
    git -C "$dir" checkout -q -B "$branch" FETCH_HEAD
  else
    [ -e "$dir" ] && die "'$dir' exists and is not a git checkout."
    msg "Cloning branch '$branch' into '$dir' (shallow)"
    # --single-branch --depth 1, cloned straight into <dir> so the working copy
    # is named after the branch instead of 'homebrew-tools'.
    git clone --quiet --depth 1 --single-branch --branch "$branch" "$REPO_URL" "$dir"
  fi
  ok "$branch -> $dir"
}

# ---------------------------------------------------------------- nesdev ----
setup_nesdev() {
  need git
  local dir="$BASE_DIR/nesdev"
  clone_branch nesdev "$dir"

  [ -d "$dir/cc65/bin" ] || die "cc65/bin missing from the nesdev checkout."
  [ -f "$dir/mesen/mesen-mcp" ] || die "mesen/mesen-mcp missing from the nesdev checkout."

  msg "Making binaries executable"
  chmod +x "$dir"/cc65/bin/* "$dir/mesen/mesen-mcp"

  # CC65_HOME must point at the dir containing include/, lib/ and cfg/.
  cat > "$dir/env.sh" <<EOF
# source this file to use the nesdev tools
export CC65_HOME="$dir/cc65"
export PATH="\$CC65_HOME/bin:$dir/mesen:\$PATH"
EOF
  ok "wrote $dir/env.sh"

  msg "Verifying toolchain"
  # shellcheck disable=SC1090
  source "$dir/env.sh"
  local t
  for t in cc65 ca65 ld65 cl65; do
    printf '  %-6s ' "$t"; "$t" --version 2>&1 | head -1
  done
  if "$dir/mesen/mesen-mcp" --help >/dev/null 2>&1; then
    ok "mesen-mcp runs headless"
  else
    warn "mesen-mcp --help returned non-zero (it is an stdio MCP server; this may be fine)"
  fi

  cat <<EOF

$(msg "nesdev ready")
  source $dir/env.sh
  cl65 -t nes -o game.nes game.c        # use -t snes for SNES
  mesen-mcp --rom game.nes --frames 300 --screenshot frame.png

MCP client registration:
  "mesen": { "command": "$dir/mesen/mesen-mcp" }
EOF
}

# ------------------------------------------------------------------ mame ----
setup_mame() {
  local system="${1:-}"
  [ -n "$system" ] || die "mame requires a <system>: ${MAME_SYSTEMS[*]}"
  local known=0 s
  for s in "${MAME_SYSTEMS[@]}"; do [ "$s" = "$system" ] && known=1; done
  [ "$known" = 1 ] || warn "'$system' is not a known system (${MAME_SYSTEMS[*]}); trying anyway."

  need git; need xz; need node; need npm

  local branch="mame-$system"
  local dir="$BASE_DIR/$branch"
  clone_branch "$branch" "$dir"

  [ -f "$dir/mame.xz" ] || die "mame.xz missing from the $branch checkout."
  msg "Decompressing mame.xz"
  xz -dkf "$dir/mame.xz"
  chmod +x "$dir/mame"
  ok "$(du -h "$dir/mame" | cut -f1) binary at $dir/mame"

  msg "Installing MCP server dependencies (npm install)"
  ( cd "$dir/mcp-server" && npm install --silent --no-audit --no-fund )
  ok "mcp-server dependencies installed"

  cat > "$dir/env.sh" <<EOF
# source this file to use the $branch tools
export MAME_DIR="$dir"
export MAME_BINARY="$dir/mame"
export MAME_ROMPATH="\${MAME_ROMPATH:-$dir/roms}"
export PATH="$dir:\$PATH"
EOF
  ok "wrote $dir/env.sh"

  msg "Verifying binary"
  ldd "$dir/mame" || true
  "$dir/mame" -help >/dev/null 2>&1 && ok "./mame -help works with no DISPLAY" \
    || warn "./mame -help failed"

  cat <<EOF

$(msg "$branch ready")
  source $dir/env.sh
  ./mame -listfull '*'          # list the machines in this driver set

MCP client registration:
  "mame": {
    "command": "node",
    "args": ["$dir/mcp-server/src/index.mjs"],
    "env": {
      "MAME_DIR": "$dir",
      "MAME_BINARY": "$dir/mame",
      "MAME_ROMPATH": "/path/to/your/roms"
    }
  }

Note: ROMs are never distributed with this repo — point MAME_ROMPATH at your own dumps.
EOF
}

# ---------------------------------------------------------------- n64dev ----
setup_n64dev() {
  need git
  local dir="$BASE_DIR/n64dev"
  clone_branch n64dev "$dir"

  [ -f "$dir/libdragon/include/n64.mk" ] || die "libdragon/include/n64.mk missing from the n64dev checkout."
  [ -x "$dir/libdragon/toolchain/bin/mips64-elf-gcc" ] \
    || die "libdragon/toolchain is missing (a pruned/partial checkout): rm -rf '$dir' and re-run."

  msg "Making binaries executable"
  chmod +x "$dir/setup.sh"
  chmod +x "$dir"/libdragon/bin/* "$dir"/libdragon/toolchain/bin/* 2>/dev/null || true
  [ -f "$dir/ares-mcp/bin/ares-mcp" ] && chmod +x "$dir/ares-mcp/bin/ares-mcp"
  ok "$(ls -1 "$dir/libdragon/bin" | wc -l) host tools, gcc for $("$dir"/libdragon/toolchain/bin/mips64-elf-gcc -dumpmachine)"

  # The checkout carries its own environment script (it knows where libdragon/,
  # toolchain/ and ares-mcp/ sit, and falls back to /opt/libdragon); env.sh only pins
  # N64DEV_ROOT so that `source env.sh` also works from another directory and in
  # shells without BASH_SOURCE.
  cat > "$dir/env.sh" <<EOF
# source this file to use the n64dev tools
export N64DEV_ROOT="$dir"
. "\$N64DEV_ROOT/setup.sh"
EOF
  ok "wrote $dir/env.sh"

  msg "Verifying the compiler by building examples/helloworld"
  "$dir/setup.sh" --verify || die "setup.sh --verify failed; see libdragon/BUILD.txt for the tree layout."

  if [ -x "$dir/ares-mcp/bin/ares-mcp" ] && command -v python3 >/dev/null 2>&1; then
    msg "Verifying the emulator by booting that ROM over MCP (headless)"
    local out
    if out=$("$dir/setup.sh" --smoke-test 2>&1); then
      printf '%s\n' "$out" | grep -E '^BOOT OK:' || true
      ok "ares-mcp booted the ROM"
    else
      warn "the emulator check failed; the compiler works, so builds are unaffected:"
      printf '%s\n' "$out" | tail -5 >&2
    fi
  else
    warn "skipped the emulator check (no ares-mcp binary or no python3)."
  fi

  cat <<EOF

$(msg "n64dev ready")
  source $dir/env.sh
  cd $dir && make -C libdragon/examples/helloworld     # -> .z64; your own game: include \$(N64_INST)/include/n64.mk
  cd $dir && ./setup.sh --smoke-test                  # build a ROM and boot it, headless
  cd $dir && ./setup.sh --verify-all                  # all 22 example ROMs + the e2e suite

MCP client registration:
  "n64": { "command": "$dir/ares-mcp/bin/ares-mcp", "args": ["mcp"] }

Note: screenshots of RDP-drawn scenes need a Vulkan driver and an ares build with
paraLLEl-RDP (see ares-mcp/BUILD.txt); emulation, input, audio, log and GDB work without.
EOF
}

# ------------------------------------------------------------------ main ----
case "${1:-}" in
  nesdev)        setup_nesdev ;;
  n64dev)        setup_n64dev ;;
  mame)          setup_mame "${2:-}" ;;
  -h|--help|"")  usage 0 ;;
  *)             die "unknown option '$1' (try --help)" ;;
esac
