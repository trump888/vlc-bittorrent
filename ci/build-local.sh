#!/usr/bin/env bash
# Local build script — replicates what the GitHub Action does, but for local
# testing on a Debian/Ubuntu host with mingw-w64 installed via apt.
#
# Usage:
#   ./ci/build-local.sh
#
# Requires:
#   sudo apt-get install gcc-mingw-w64-i686 g++-mingw-w64-i686 \
#     binutils-mingw-w64-i686 mingw-w64-i686-dev \
#     cmake ninja-build pkg-config libboost-dev python3 zip unzip curl

set -euo pipefail

# ---- Configuration (override via env vars) ----
VLC_VERSION="${VLC_VERSION:-3.0.23}"
LIBTORRENT_VERSION="${LIBTORRENT_VERSION:-2.0.10}"
HOST="${HOST:-i686-w64-mingw32}"

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
WORKDIR="${WORKDIR:-$PROJECT_ROOT/.build-win32}"
PREFIX="${PREFIX:-$WORKDIR/prefix}"
VLC_SRC="${VLC_SRC:-$WORKDIR/vlc-src}"
VLC_INSTALL="${VLC_INSTALL:-$WORKDIR/vlc-win32/vlc-$VLC_VERSION}"

export CC="$HOST-gcc"
export CXX="$HOST-g++"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

echo "==================== vlc-bittorrent win32 local build ===================="
echo "VLC_VERSION:       $VLC_VERSION"
echo "LIBTORRENT_VERSION: $LIBTORRENT_VERSION"
echo "HOST:              $HOST"
echo "WORKDIR:           $WORKDIR"
echo "PREFIX:            $PREFIX"
echo ""

mkdir -p "$WORKDIR" "$PREFIX/lib/pkgconfig" "$PREFIX/include" "$PREFIX/lib"
cd "$WORKDIR"

# ---- 1. Download VLC source + win32 zip ----
if [ ! -d "$VLC_SRC" ]; then
    echo "[1/7] Downloading VLC $VLC_VERSION source..."
    curl -fsSL -o vlc.tar.xz \
        "https://download.videolan.org/pub/videolan/vlc/${VLC_VERSION}/vlc-${VLC_VERSION}.tar.xz"
    mkdir -p "$VLC_SRC"
    tar xf vlc.tar.xz -C "$VLC_SRC" --strip-components=1
    rm vlc.tar.xz
fi

if [ ! -d "$VLC_INSTALL" ]; then
    echo "[1/7] Downloading VLC $VLC_VERSION win32 zip..."
    curl -fsSL -o vlc-win32.zip \
        "https://download.videolan.org/pub/videolan/vlc/${VLC_VERSION}/win32/vlc-${VLC_VERSION}-win32.zip"
    mkdir -p "$(dirname "$VLC_INSTALL")"
    unzip -q vlc-win32.zip -d "$(dirname "$VLC_INSTALL")"
    rm vlc-win32.zip
fi

# ---- 2. Download libtorrent source ----
if [ ! -d "$WORKDIR/libtorrent-src" ]; then
    echo "[2/7] Downloading libtorrent-rasterbar $LIBTORRENT_VERSION..."
    curl -fsSL -o lt.tar.gz \
        "https://github.com/arvidn/libtorrent/releases/download/v${LIBTORRENT_VERSION}/libtorrent-rasterbar-${LIBTORRENT_VERSION}.tar.gz"
    mkdir -p "$WORKDIR/libtorrent-src"
    tar xf lt.tar.gz -C "$WORKDIR/libtorrent-src" --strip-components=1
    rm lt.tar.gz
fi

# ---- 3. Generate import libraries from official VLC DLLs ----
echo "[3/7] Generating import libraries from official VLC DLLs..."
python3 "$PROJECT_ROOT/ci/dll_to_def.py" \
    "$VLC_INSTALL/libvlccore.dll" /tmp/libvlccore.def libvlccore.dll
python3 "$PROJECT_ROOT/ci/dll_to_def.py" \
    "$VLC_INSTALL/libvlc.dll" /tmp/libvlc.def libvlc.dll
"$HOST-dlltool" --dllname libvlccore.dll --def /tmp/libvlccore.def \
    --output-lib "$PREFIX/lib/libvlccore.a" -k
"$HOST-dlltool" --dllname libvlc.dll --def /tmp/libvlc.def \
    --output-lib "$PREFIX/lib/libvlc.a" -k

# Boost headers: use the system libboost-dev, but generate a BoostConfig.cmake
# so CMake 3.30+ (which removed FindBoost.cmake) can find it.
echo "[3.5/7] Generating BoostConfig.cmake (for CMake 3.30+)..."
bash "$PROJECT_ROOT/ci/make-boost-config.sh" "$PREFIX" /usr/include
export Boost_DIR="$PREFIX/lib/cmake/Boost"

# ---- 4. Install .pc files ----
echo "[4/7] Installing vlc-plugin.pc + libvlc.pc..."
sed -e "s|@PREFIX@|$PREFIX|g" \
    -e "s|@VLC_SRC@|$VLC_SRC|g" \
    -e "s|@VLC_VERSION@|$VLC_VERSION|g" \
    "$PROJECT_ROOT/ci/vlc-plugin.pc.in" > "$PREFIX/lib/pkgconfig/vlc-plugin.pc"
sed -e "s|@PREFIX@|$PREFIX|g" \
    -e "s|@VLC_SRC@|$VLC_SRC|g" \
    -e "s|@VLC_VERSION@|$VLC_VERSION|g" \
    "$PROJECT_ROOT/ci/libvlc.pc.in" > "$PREFIX/lib/pkgconfig/libvlc.pc"

# ---- 5. Build libtorrent (static) ----
echo "[5/7] Building libtorrent-rasterbar (static)..."
cmake -S "$WORKDIR/libtorrent-src" -B "$WORKDIR/libtorrent-build" \
    -DCMAKE_TOOLCHAIN_FILE="$PROJECT_ROOT/ci/toolchain-mingw-i686.cmake" \
    -DCMAKE_FIND_ROOT_PATH="/usr/i686-w64-mingw32;$PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -Dstatic_runtime=ON \
    -Dencryption=OFF \
    -Dbuild_tests=OFF \
    -Dbuild_examples=OFF \
    -Dbuild_tools=OFF \
    -Dpython-bindings=OFF \
    -Ddht=ON \
    -Dexceptions=ON \
    -DBoost_DIR="$PREFIX/lib/cmake/Boost" \
    -G Ninja
cmake --build "$WORKDIR/libtorrent-build" -j"$(nproc)"
cmake --install "$WORKDIR/libtorrent-build"

# ---- 6. Build vlc-bittorrent plugin ----
echo "[6/7] Building vlc-bittorrent plugin..."
cmake -S "$PROJECT_ROOT" -B "$WORKDIR/vlc-bittorrent-build" \
    -DCMAKE_TOOLCHAIN_FILE="$PROJECT_ROOT/ci/toolchain-mingw-i686.cmake" \
    -DCMAKE_FIND_ROOT_PATH="/usr/i686-w64-mingw32;$PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DBUILD_TESTING=OFF \
    -G Ninja
cmake --build "$WORKDIR/vlc-bittorrent-build" -j"$(nproc)"

# Strip
"$HOST-strip" --strip-all "$WORKDIR/vlc-bittorrent-build/src/libaccess_bittorrent_plugin.dll"

# ---- 7. Verify ----
echo "[7/7] Verifying ABI compatibility..."
"$PROJECT_ROOT/ci/verify.sh" \
    "$WORKDIR/vlc-bittorrent-build/src/libaccess_bittorrent_plugin.dll" \
    "$VLC_INSTALL/plugins/access/libfilesystem_plugin.dll" \
    "$VLC_INSTALL/libvlccore.dll"

# ---- Done ----
echo ""
echo "==================== DONE ===================="
echo "Plugin: $WORKDIR/vlc-bittorrent-build/src/libaccess_bittorrent_plugin.dll"
ls -la "$WORKDIR/vlc-bittorrent-build/src/libaccess_bittorrent_plugin.dll"
