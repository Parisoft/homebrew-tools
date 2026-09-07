#!/bin/sh
# n64dev - Nintendo 64 homebrew SDK (libdragon + mips64-elf toolchain), in-tree.
# Needs no network, no root, no package manager, no build step: it only points the
# environment at the files that are already next to this script.
#
#   . ./setup.sh              # export the environment into the CURRENT shell
#   ./setup.sh --print        # print the exports (for eval / a different shell)
#   ./setup.sh --verify       # build examples/helloworld, check the ROM header
#   ./setup.sh --verify-all   # also build every upstream example (~22 ROMs)
#
# Why the dot-source form: an agent's shell usually does not persist between tool
# calls, so exported variables are gone by the next command. Prefix build commands
# with `. ./setup.sh &&` rather than trying to remember the exports.
#
# Exit status is 0 when the environment is usable, 1 with a reason printed otherwise.

# ---- was this file sourced (so exports stick) or executed (so they cannot)? ----
_n64_sourced=0
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE:-}" != "$0" ]; then _n64_sourced=1; fi

# ---- locate this script's directory (works for both `.` and direct execution) ----
_n64_self="${BASH_SOURCE:-$0}"          # bash/zsh when sourced, $0 when executed
case "$_n64_self" in
    */*) N64DEV_ROOT="${_n64_self%/*}" ;;
    .)   N64DEV_ROOT="$PWD" ;;
    *)   N64DEV_ROOT="$PWD" ;;          # sourced as `setup.sh` from the branch root
esac
N64DEV_ROOT=$(cd "$N64DEV_ROOT" 2>/dev/null && pwd) || N64DEV_ROOT=""
if [ -z "$N64DEV_ROOT" ] || [ ! -d "$N64DEV_ROOT/libdragon" ]; then
    echo "setup.sh: cannot find the n64dev tree (run it from the branch root, e.g.:" >&2
    echo "  cd ~/homebrew-tools-n64dev && . ./setup.sh)" >&2
    return 1 2>/dev/null || exit 1
fi

# ---- choose a toolchain: the one in this tree, else libdragon's official prefix ----
if [ -x "$N64DEV_ROOT/toolchain/bin/mips64-elf-gcc" ]; then
    N64_GCCPREFIX="$N64DEV_ROOT/toolchain"
    N64_TOOLCHAIN_SOURCE="in-tree"
elif [ -x /opt/libdragon/bin/mips64-elf-gcc ]; then
    N64_GCCPREFIX=/opt/libdragon        # from libdragon's gcc-toolchain-mips64 .deb
    N64_TOOLCHAIN_SOURCE="system /opt/libdragon"
else
    echo "setup.sh: no mips64-elf toolchain found." >&2
    echo "  Expected $N64DEV_ROOT/toolchain/bin/mips64-elf-gcc." >&2
    echo "  The branch ships it; if it is missing you have a partial checkout:" >&2
    echo "  git clone --depth 1 --single-branch -b n64dev \\" >&2
    echo "      https://github.com/Parisoft/homebrew-tools.git" >&2
    return 1 2>/dev/null || exit 1
fi

export N64_GCCPREFIX
export N64DEV_ROOT
export N64_INST="${N64_INST:-$N64DEV_ROOT/libdragon}"   # override to use your own build
export N64_TARGET="${N64_TARGET:-mips64-elf}"
case ":$PATH:" in
    *":$N64_GCCPREFIX/bin:"*) ;;
    *) PATH="$N64_INST/bin:$N64_GCCPREFIX/bin:$PATH" ;;
esac
export PATH

if [ "${1:-}" = "--print" ]; then
    cat <<EOF
export N64DEV_ROOT='$N64DEV_ROOT'
export N64_INST='$N64_INST'
export N64_GCCPREFIX='$N64_GCCPREFIX'
export N64_TARGET='$N64_TARGET'
export PATH='$N64_INST/bin:$N64_GCCPREFIX/bin:\$PATH'
EOF
    return 0 2>/dev/null || exit 0
fi

# ---- verification: build a ROM in a throwaway directory (never dirties the tree) ----
if [ "${1:-}" = "--verify" ] || [ "${1:-}" = "--verify-all" ]; then
    _n64_tmp=$(mktemp -d) || { echo "setup.sh: mktemp failed" >&2; return 1 2>/dev/null || exit 1; }
    cp -a "$N64DEV_ROOT/examples/helloworld" "$_n64_tmp/" 2>/dev/null
    _n64_src="$_n64_tmp/helloworld"
    if [ "${1:-}" = "--verify-all" ]; then
        cp -a "$N64DEV_ROOT/examples/." "$_n64_tmp/examples" && _n64_src="$_n64_tmp/examples"
        # examples/audioplayer reaches two levels up for a private libdragon header
        [ -d "$N64DEV_ROOT/src" ] && cp -a "$N64DEV_ROOT/src" "$_n64_tmp/src"
    fi
    # Clean first: a copied-but-dirty tree must not be able to fake a pass.
    find "$_n64_src" -name build -type d -prune -exec rm -rf {} + 2>/dev/null
    make -C "$_n64_src" clean >/dev/null 2>&1
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
    rm -rf "$_n64_tmp"
    echo "n64dev OK  -  $_n64_n ROM(s), header $_n64_magic, toolchain: $N64_TOOLCHAIN_SOURCE"
fi

if [ "${1:-}" != "" ] && [ "${1:-}" != "--verify" ] && [ "${1:-}" != "--verify-all" ]; then
    echo "usage: . ./setup.sh [--print|--verify|--verify-all]" >&2
    return 1 2>/dev/null || exit 1
fi

# Silent when sourced with no arguments: agents dot-source this on *every* build
# command (their shells do not persist), so any chatter here would be noise x N.
# Set N64DEV_VERBOSE=1 to see the resolved environment, or run `./setup.sh`.
if [ "$_n64_sourced" = 1 ] && [ -z "${N64DEV_VERBOSE:-}" ]; then
    return 0 2>/dev/null
fi
if [ -z "${1:-}" ]; then
    echo "N64_INST=$N64_INST"
    echo "N64_GCCPREFIX=$N64_GCCPREFIX ($N64_TOOLCHAIN_SOURCE)"
    echo "N64_TARGET=$N64_TARGET"
    echo "mips64-elf-gcc: $(command -v mips64-elf-gcc || echo MISSING)"
    if [ "$_n64_sourced" = 0 ]; then
        echo "note: this shell ran setup.sh instead of sourcing it, so the exports died" >&2
        echo "      with it; use \`. ./setup.sh\` or \`eval \"\$(./setup.sh --print)\"\`" >&2
    fi
fi
