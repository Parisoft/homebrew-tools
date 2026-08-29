#!/bin/sh
# Put the nesdev toolchain on PATH.
#
#   cd nesdev-tools
#   . ./env.sh        # source it — running it as ./env.sh will not affect your shell
#
# Uses the current directory, so cd into the checkout first.

NESDEV_HOME=$(pwd)

if [ ! -x "$NESDEV_HOME/cc65/bin/cc65" ]; then
    echo "env.sh: no cc65/bin/cc65 in $NESDEV_HOME" >&2
    echo "env.sh: cd into the nesdev-tools checkout, then run ' . ./env.sh'" >&2
    return 1 2>/dev/null || exit 1
fi

export CC65_HOME="$NESDEV_HOME/cc65"
export PATH="$CC65_HOME/bin:$NESDEV_HOME/mesen:$PATH"

echo "nesdev tools ready:"
echo "  CC65_HOME = $CC65_HOME"
echo "  cc65      -> $(command -v cc65)"
echo "  ca65      -> $(command -v ca65)"
echo "  ld65      -> $(command -v ld65)"
echo "  mesen-mcp -> $(command -v mesen-mcp)"
