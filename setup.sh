#!/bin/sh
# n64dev - Nintendo 64 homebrew environment, entirely in this tree:
#   libdragon/   SDK install tree ($N64_INST) + the mips64-elf cross-compiler + examples
#   ares-mcp/    headless N64 emulator: run a ROM, screenshot it, drive it over MCP
# Needs no network, no root, no package manager, no build step: it only points the
# environment at the files that are already next to this script.
#
#   . ./setup.sh                 # export the environment into the CURRENT shell
#   ./setup.sh --print           # print the exports (for eval / another shell type)
#   ./setup.sh --verify          # build examples/helloworld, check the ROM header
#   ./setup.sh --verify-all      # build every upstream example (22 ROMs)
#   ./setup.sh --smoke-test      # build a ROM and boot it in ares-mcp, headless
#
# Why the dot-source form: an agent's shell usually does not persist between tool
# calls, so exported variables are gone by the next command. Prefix build commands
# with `. ./setup.sh &&` rather than trying to remember the exports. Sourcing is
# silent on success so that costs no output; N64DEV_VERBOSE=1 prints the result.
#
# Exit status is 0 when the environment is usable, 1 with a reason printed otherwise.

# ---- was this file sourced (exports stick) or executed (they cannot)? ----
_n64_sourced=0
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE:-}" != "$0" ]; then _n64_sourced=1; fi
# Shells without BASH_SOURCE (dash, busybox sh) cannot tell `.` from execution, but
# there $0 is the *shell*, never this script - so a $0 that is not setup.sh means we
# are being sourced, and the "your exports died" advice below would be wrong noise.
if [ "$_n64_sourced" = 0 ] && [ "${0##*/}" != "setup.sh" ]; then _n64_sourced=1; fi

# ---- locate this script's directory (works for both `.` and direct execution) ----
# Deriving it is preferred, because a stale N64DEV_ROOT in the environment must not
# point a second checkout at the first one. But shells without BASH_SOURCE (dash, and
# any plain `sh file`/`. file`) leave $0 as the shell name, and then only an explicit
# N64DEV_ROOT can find the tree - which is exactly how bootstrap.sh's env.sh works.
_n64_self="${BASH_SOURCE:-$0}"
case "$_n64_self" in
    */*) _n64_guess=$(cd "${_n64_self%/*}" 2>/dev/null && pwd) ;;
    *)   _n64_guess="" ;;
esac
if [ -n "$_n64_guess" ] && [ -f "$_n64_guess/libdragon/include/n64.mk" ]; then
    N64DEV_ROOT="$_n64_guess"
elif [ ! -f "${N64DEV_ROOT:-}/libdragon/include/n64.mk" ]; then
    N64DEV_ROOT="${_n64_guess:-$PWD}"
fi
if [ -z "$N64DEV_ROOT" ] || [ ! -f "$N64DEV_ROOT/libdragon/include/n64.mk" ]; then
    echo "setup.sh: cannot find the n64dev tree (no libdragon/include/n64.mk)." >&2
    echo "  Run it from the branch root, e.g.:  cd ~/n64dev && . ./setup.sh" >&2
    return 1 2>/dev/null || exit 1
fi

# ---- the cross-compiler: the one in this tree, else libdragon's official prefix ----
if [ -x "$N64DEV_ROOT/libdragon/toolchain/bin/mips64-elf-gcc" ]; then
    N64_GCCPREFIX="$N64DEV_ROOT/libdragon/toolchain"
    N64_TOOLCHAIN_SOURCE="in-tree"
elif [ -x /opt/libdragon/bin/mips64-elf-gcc ]; then
    N64_GCCPREFIX=/opt/libdragon            # from libdragon's gcc-toolchain-mips64 .deb
    N64_TOOLCHAIN_SOURCE="system /opt/libdragon"
else
    echo "setup.sh: no mips64-elf toolchain found." >&2
    echo "  Expected $N64DEV_ROOT/libdragon/toolchain/bin/mips64-elf-gcc." >&2
    echo "  A partial checkout is the usual cause; the branch ships it:" >&2
    echo "  git clone --depth 1 --single-branch -b n64dev \\" >&2
    echo "      https://github.com/Parisoft/homebrew-tools.git" >&2
    return 1 2>/dev/null || exit 1
fi

export N64DEV_ROOT N64_GCCPREFIX
export N64_INST="${N64_INST:-$N64DEV_ROOT/libdragon}"   # override to use your own build
export N64_TARGET="${N64_TARGET:-mips64-elf}"
export N64_EXAMPLES="$N64_INST/examples"
N64_MCP="$N64DEV_ROOT/ares-mcp/bin/ares-mcp"
[ -x "$N64_MCP" ] || N64_MCP=""
export N64_MCP

_n64_path="$N64_INST/bin:$N64_GCCPREFIX/bin"
[ -n "$N64_MCP" ] && _n64_path="$_n64_path:$(dirname "$N64_MCP")"
case ":$PATH:" in
    *":$N64_GCCPREFIX/bin:"*) ;;
    *) PATH="$_n64_path:$PATH" ;;
esac
export PATH

if [ "${1:-}" = "--print" ]; then
    cat <<EOF
export N64DEV_ROOT='$N64DEV_ROOT'
export N64_INST='$N64_INST'
export N64_GCCPREFIX='$N64_GCCPREFIX'
export N64_TARGET='$N64_TARGET'
export N64_MCP='${N64_MCP}'
export PATH='$_n64_path:\$PATH'
EOF
    return 0 2>/dev/null || exit 0
fi

# ---- --verify / --verify-all: build in a throwaway copy, never in the tree ----
case "${1:-}" in
--verify|--verify-all)
    _n64_tmp=$(mktemp -d) || { echo "setup.sh: mktemp failed" >&2; return 1 2>/dev/null || exit 1; }
    if [ "${1:-}" = "--verify" ]; then
        cp -a "$N64_EXAMPLES/helloworld" "$_n64_tmp/" && _n64_src="$_n64_tmp/helloworld"
    else
        cp -a "$N64_EXAMPLES/." "$_n64_tmp/examples" && _n64_src="$_n64_tmp/examples"
    fi
    # examples/audioplayer reaches two levels up for a private libdragon header
    [ -d "$N64_INST/src" ] && cp -a "$N64_INST/src" "$_n64_tmp/src"
    # a copied-but-dirty tree must not be able to fake a pass
    find "$_n64_src" -name build -type d -prune -exec rm -rf {} + 2>/dev/null
    find "$_n64_src" -name '*.z64' -delete
    echo "n64dev: building ROM(s) into $_n64_src ..."
    if ! make -C "$_n64_src" "-j${N64DEV_JOBS:-4}" >"$_n64_tmp/verify.log" 2>&1; then
        echo "setup.sh: build FAILED - last lines of $_n64_tmp/verify.log:" >&2
        tail -20 "$_n64_tmp/verify.log" >&2
        rm -rf "$_n64_tmp"
        return 1 2>/dev/null || exit 1
    fi
    _n64_rom=$(find "$_n64_src" -name '*.z64' | head -1)
    [ -f "$_n64_rom" ] || { echo "setup.sh: no .z64 produced" >&2; rm -rf "$_n64_tmp"; return 1 2>/dev/null || exit 1; }
    # A valid N64 ROM starts with the CIC-NUS6B initial PI/PIST BSW word.
    _n64_magic=$(od -An -tx1 -N4 "$_n64_rom" | tr -d ' ')
    if [ "$_n64_magic" != "80371240" ]; then
        echo "setup.sh: $_n64_rom has header '$_n64_magic', expected '80371240'" >&2
        rm -rf "$_n64_tmp"
        return 1 2>/dev/null || exit 1
    fi
    _n64_n=$(find "$_n64_src" -name '*.z64' | wc -l | tr -d ' ')
    echo "n64dev OK  -  $_n64_n ROM(s), header $_n64_magic, toolchain: $N64_TOOLCHAIN_SOURCE"
    if [ "${1:-}" = "--verify-all" ] && [ -n "$N64_MCP" ] && command -v python3 >/dev/null 2>&1; then
        echo "n64dev: running ares-mcp's end-to-end suite (27 checks) ..."
        if python3 "$N64DEV_ROOT/ares-mcp/test/mcp_client.py" --bin "$N64_MCP" \
                >"$_n64_tmp/ares.log" 2>&1; then
            tail -1 "$_n64_tmp/ares.log"
        else
            echo "setup.sh: the ares-mcp e2e suite failed; last lines:" >&2
            tail -15 "$_n64_tmp/ares.log" >&2
            rm -rf "$_n64_tmp"
            return 1 2>/dev/null || exit 1
        fi
    fi
    ROM=$_n64_rom
    ;;
--smoke-test)
    # Boot a ROM in ares-mcp over MCP: handshake, tool catalog, n64_load, n64_run,
    # n64_status, log scan for exceptions, clean shutdown (ares-mcp/test/boot_check.py).
    ROM=${2:-${N64_SMOKE_ROM:-}}
    if [ -z "$N64_MCP" ]; then
        echo "setup.sh: no ares-mcp/bin/ares-mcp in this tree; nothing to boot." >&2
        return 1 2>/dev/null || exit 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "setup.sh: --smoke-test needs python3 (not installed here)." >&2
        return 1 2>/dev/null || exit 1
    fi
    _n64_tmp=$(mktemp -d) || { echo "setup.sh: mktemp failed" >&2; return 1 2>/dev/null || exit 1; }
    if [ -z "$ROM" ]; then
        cp -a "$N64_EXAMPLES/helloworld" "$_n64_tmp/"
        make -C "$_n64_tmp/helloworld" "-j${N64DEV_JOBS:-4}" >/dev/null 2>&1 ||
            { echo "setup.sh: could not build the test ROM" >&2; rm -rf "$_n64_tmp"; return 1 2>/dev/null || exit 1; }
        ROM="$_n64_tmp/helloworld/helloworld.z64"
        echo "n64dev: built examples/helloworld, booting it in ares-mcp ..."
    else
        echo "n64dev: booting $ROM in ares-mcp ..."
    fi
    if python3 "$N64DEV_ROOT/ares-mcp/test/boot_check.py" --rom "$ROM" --bin "$N64_MCP" \
            --frames "${N64_SMOKE_FRAMES:-120}" --timeout "${N64_SMOKE_TIMEOUT:-25}" \
            >"$_n64_tmp/boot.log" 2>&1; then
        # no log grep here on purpose: boot_check.py already scans n64_log for
        # exception/crash/assert and exits 3 if it finds one (grepping its report
        # would match its own "no exceptions in the log" line)
        grep -E "^BOOT OK:" "$_n64_tmp/boot.log"
        echo "n64dev smoke OK - the ROM booted and emulated ${N64_SMOKE_FRAMES:-120} frames"
        echo "  note: RDP-rendered pixels need a Vulkan driver (none here): use"
        echo "  n64_log/n64_status/exceptions for checks, or run ares with --gpu on a"
        echo "  GPU host; ares-mcp/test/green.z64 verifies the pixel path CPU-side."
    else
        echo "setup.sh: smoke test FAILED; client output:" >&2
        tail -20 "$_n64_tmp/boot.log" >&2

        rm -rf "$_n64_tmp"
        return 1 2>/dev/null || exit 1
    fi
    rm -rf "$_n64_tmp"
    ;;
"")
    ;;
*)
    echo "usage: . ./setup.sh [--print|--verify|--verify-all|--smoke-test [rom.z64]]" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

# Silent when sourced with no arguments: agents dot-source this on *every* build
# command (their shells do not persist), so any chatter here would be noise x N.
if [ "$_n64_sourced" = 1 ] && [ -z "${N64DEV_VERBOSE:-}" ] && [ -z "${1:-}" ]; then
    return 0 2>/dev/null
fi
echo "N64_INST=$N64_INST"
echo "N64_GCCPREFIX=$N64_GCCPREFIX ($N64_TOOLCHAIN_SOURCE)"
echo "N64_TARGET=$N64_TARGET"
echo "mips64-elf-gcc: $(command -v mips64-elf-gcc || echo MISSING)"
echo "ares-mcp: ${N64_MCP:-not present (build the ROMs anywhere, run them in your own emulator)}"
if [ "$_n64_sourced" = 0 ] && [ -z "${1:-}" ]; then
    echo "note: this shell ran setup.sh instead of sourcing it, so the exports died" >&2
    echo "      with it; use \`. ./setup.sh\` or \`eval \"\$(./setup.sh --print)\"\`" >&2
fi
