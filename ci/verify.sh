#!/usr/bin/env bash
# Verify that the built vlc-bittorrent plugin is binary-compatible with the
# official VLC win32 release.
#
# Usage:
#   verify.sh <built.dll> <official_plugin.dll> <official_libvlccore.dll>
#
# Checks performed:
#   1. built.dll is PE32 Intel i386 (32-bit)
#   2. built.dll exports vlc_entry__3_0_0f (matches official plugin ABI)
#   3. built.dll imports libvlccore.dll (same as official plugins)
#   4. built.dll does NOT import libgcc_s_*, libstdc++-*, libwinpthread-*
#      (these would require shipping extra runtime DLLs alongside VLC)
#   5. built.dll links msvcrt.dll (NOT ucrtbase.dll) — matches official VLC
#   6. Cross-check the entry symbol name against the official plugin
#
# This script uses ci/pe_inspect.py (pure Python PE parser) instead of
# objdump, because objdump's output format varies between binutils versions
# and caused silent parsing failures on Ubuntu 24.04 runners.

set -uo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <built.dll> <official_plugin.dll> <official_libvlccore.dll>" >&2
    exit 1
fi

BUILT="$1"
OFFICIAL_PLUGIN="$2"
OFFICIAL_LIBVLCCORE="$3"

# Resolve script directory so we can find pe_inspect.py regardless of CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PE_INSPECT="python3 ${SCRIPT_DIR}/pe_inspect.py"

FAIL=0

ok() { echo "  [PASS] $1"; }
err() { echo "  [FAIL] $1" >&2; FAIL=1; }

echo "==================== ABI verification ===================="
echo "Built:            $BUILT"
echo "Official plugin:  $OFFICIAL_PLUGIN"
echo "Official core:    $OFFICIAL_LIBVLCCORE"
echo ""

# ---- 1. Architecture ----
echo "[1/6] Architecture check"
FILE_OUT=$(file "$BUILT")
# `file` output varies between versions:
#   file 5.44 (Debian trixie): "PE32 executable for MS Windows 4.00 (DLL), Intel i386, ..."
#   file 5.45 (Ubuntu 24.04):  "PE32 executable (DLL) (console) Intel 80386, for MS Windows, ..."
# Match on the key tokens: "PE32" + "i386" or "80386" + "DLL"
if echo "$FILE_OUT" | grep -q "PE32" \
   && echo "$FILE_OUT" | grep -qE "Intel (i386|80386)" \
   && echo "$FILE_OUT" | grep -q "DLL"; then
    ok "PE32 Intel i386 (32-bit, matches official win32)"
else
    err "Not a PE32 i386 DLL: $FILE_OUT"
fi
echo ""

# ---- 2. Export symbol ----
echo "[2/6] Exported symbol check"
BUILT_EXPORTS=$($PE_INSPECT exports "$BUILT" 2>/dev/null)
OFFICIAL_EXPORTS=$($PE_INSPECT exports "$OFFICIAL_PLUGIN" 2>/dev/null)

# We need at minimum vlc_entry__3_0_0f
if echo "$BUILT_EXPORTS" | grep -qx "vlc_entry__3_0_0f"; then
    ok "Built plugin exports vlc_entry__3_0_0f"
else
    err "Built plugin does NOT export vlc_entry__3_0_0f"
    echo "       Built exports: $(echo $BUILT_EXPORTS | tr '\n' ' ')" >&2
fi

# Compare with official
if echo "$OFFICIAL_EXPORTS" | grep -qx "vlc_entry__3_0_0f"; then
    ok "Official plugin also exports vlc_entry__3_0_0f (ABI matches)"
else
    err "Official plugin does not export vlc_entry__3_0_0f (unexpected)"
    echo "       Official exports: $(echo $OFFICIAL_EXPORTS | tr '\n' ' ')" >&2
fi
echo ""

# ---- 3. Imports libvlccore.dll ----
echo "[3/6] libvlccore.dll import check"
BUILT_IMPORTS=$($PE_INSPECT imports "$BUILT" 2>/dev/null)
if echo "$BUILT_IMPORTS" | grep -qx "libvlccore.dll"; then
    ok "Built plugin imports libvlccore.dll (links against VLC core, as official plugins do)"
else
    err "Built plugin does NOT import libvlccore.dll"
    echo "       Built imports: $(echo $BUILT_IMPORTS | tr '\n' ' ')" >&2
fi
echo ""

# ---- 4. No GCC runtime DLLs ----
echo "[4/6] Static runtime check (no libgcc_s_*, libstdc++-*, libwinpthread-*)"
BANNED_PATTERNS='libgcc_s_.*\.dll|libstdc\+\+.*\.dll|libwinpthread.*\.dll'
BANNED=$(echo "$BUILT_IMPORTS" | grep -E "$BANNED_PATTERNS" || true)
if [ -z "$BANNED" ]; then
    ok "No GCC runtime DLLs in import table (all statically linked)"
else
    err "Found GCC runtime DLLs in imports: $BANNED"
    echo "       This means the plugin requires extra DLLs not shipped with VLC." >&2
fi
echo ""

# ---- 5. CRT is msvcrt.dll (not ucrtbase.dll) ----
echo "[5/6] CRT family check"
if echo "$BUILT_IMPORTS" | grep -qx "msvcrt.dll"; then
    ok "Built plugin links msvcrt.dll (matches official VLC 3.0.x win32)"
    if echo "$BUILT_IMPORTS" | grep -qx "ucrtbase.dll"; then
        err "Also links ucrtbase.dll — mixing CRTs can cause heap corruption"
    fi
elif echo "$BUILT_IMPORTS" | grep -qx "ucrtbase.dll"; then
    err "Built plugin links ucrtbase.dll (official VLC 3.0.x uses msvcrt.dll — mismatch)"
else
    err "Built plugin links neither msvcrt.dll nor ucrtbase.dll (unexpected)"
fi
echo ""

# ---- 6. Cross-check against official plugin ----
echo "[6/6] Cross-check with official plugin"
OFFICIAL_IMPORTS=$($PE_INSPECT imports "$OFFICIAL_PLUGIN" 2>/dev/null)
echo "       Official plugin imports:"
echo "$OFFICIAL_IMPORTS" | sed 's/^/         /'
echo ""
echo "       Built plugin imports:"
echo "$BUILT_IMPORTS" | sed 's/^/         /'
echo ""

# All official system DLLs should be a subset of built's imports (since our
# plugin also pulls in libtorrent's Winsock dependencies)
MISSING=""
for d in $OFFICIAL_IMPORTS; do
    if ! echo "$BUILT_IMPORTS" | grep -qx "$d"; then
        case "$d" in
            advapi32.dll|shlwapi.dll|ole32.dll|oleaut32.dll|gdi32.dll|user32.dll)
                # These are common system DLLs that some plugins use and others don't
                ;;
            *)
                MISSING="$MISSING $d"
                ;;
        esac
    fi
done
if [ -z "$MISSING" ]; then
    ok "All non-optional system DLLs from official plugin are also imported by built plugin"
else
    echo "       [INFO] Built plugin does not import these (may be OK if unused):$MISSING"
fi

echo ""
echo "==================== Summary ===================="
if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: PASS — plugin is binary-compatible with official VLC win32"
    exit 0
else
    echo "RESULT: FAIL — see failures above"
    exit 1
fi
