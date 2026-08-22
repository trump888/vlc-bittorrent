# CMake toolchain file for i686-w64-mingw32 cross-compilation
# Targets the official VideoLAN VLC 3.0.x win32 ABI:
#   - mingw-w64 i686 (Debian/Ubuntu)
#   - msvcrt.dll (NOT ucrt)
#   - Static libgcc / libstdc++ / libwinpthread (no extra runtime DLLs)
#
# IMPORTANT: This toolchain looks up CMAKE_FIND_ROOT_PATH from the cmake
# variable CMAKE_FIND_ROOT_PATH (which can be set via -D on the command line
# or via the parent project's cache). It also falls back to $ENV{PREFIX} for
# backwards compatibility with the local build script.
#
# We deliberately do NOT hardcode a path here, because:
#   1. The CI runner's prefix differs from a local dev machine's prefix.
#   2. Relying on $ENV{PREFIX} alone is fragile — GitHub Actions' env: block
#      may not be visible to the toolchain file at the moment CMake first
#      reads it. Passing -DCMAKE_FIND_ROOT_PATH=... explicitly on the cmake
#      command line is reliable.

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86)

# Build the find root path: mingw sysroot + project prefix.
# CMAKE_FIND_ROOT_PATH can be passed as -D on the cmake command line; if it's
# set there, that value wins. Otherwise we fall back to $ENV{PREFIX} for
# local builds.
if(NOT DEFINED CMAKE_FIND_ROOT_PATH)
    if(DEFINED ENV{PREFIX})
        set(CMAKE_FIND_ROOT_PATH "/usr/i686-w64-mingw32" "$ENV{PREFIX}")
    else()
        set(CMAKE_FIND_ROOT_PATH "/usr/i686-w64-mingw32")
    endif()
endif()

set(CMAKE_C_COMPILER   i686-w64-mingw32-gcc)
set(CMAKE_CXX_COMPILER i686-w64-mingw32-g++)
set(CMAKE_RC_COMPILER  i686-w64-mingw32-windres)

set(CMAKE_AR           i686-w64-mingw32-ar CACHE FILEPATH "")
set(CMAKE_RANLIB       i686-w64-mingw32-ranlib CACHE FILEPATH "")
set(CMAKE_STRIP        i686-w64-mingw32-strip CACHE FILEPATH "")
set(CMAKE_DLLTOOL      i686-w64-mingw32-dlltool CACHE FILEPATH "")

# Only look for libs/headers in the cross sysroot, not on the host
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Static linking of libgcc / libstdc++ / libwinpthread into the final DLL.
# This avoids shipping libgcc_s_dw2-1.dll / libstdc++-6.dll / libwinpthread-1.dll
# alongside the plugin — important because official VLC doesn't bundle them.
set(CMAKE_C_FLAGS_INIT              "-static-libgcc")
set(CMAKE_CXX_FLAGS_INIT            "-static-libgcc -static-libstdc++")
set(CMAKE_EXE_LINKER_FLAGS_INIT     "-static-libgcc -static-libstdc++ -static -lpthread")
set(CMAKE_SHARED_LINKER_FLAGS_INIT  "-static-libgcc -static-libstdc++ -static -lpthread")
set(CMAKE_MODULE_LINKER_FLAGS_INIT  "-static-libgcc -static-libstdc++ -static -lpthread")

# Boost: handled separately by ci/make-boost-config.sh, which copies the
# platform-independent Boost headers into <prefix>/include/boost/ and
# generates a BoostConfig.cmake pointing there. find_package(Boost) then
# picks it up via CMAKE_FIND_ROOT_PATH.
set(Boost_NO_BOOST_CMAKE OFF CACHE BOOL "")
