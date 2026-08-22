# CMake toolchain file for i686-w64-mingw32 cross-compilation
# Targets the official VideoLAN VLC 3.0.x win32 ABI:
#   - mingw-w64 i686 (Debian/Ubuntu)
#   - msvcrt.dll (NOT ucrt)
#   - Static libgcc / libstdc++ / libwinpthread (no extra runtime DLLs)

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86)

# Search path: cross sysroot first, then project prefix
set(CMAKE_FIND_ROOT_PATH
    "/usr/i686-w64-mingw32"
    "$ENV{PREFIX}")

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

# Boost: use the host's libboost-dev headers (they're platform-independent).
# This works on Ubuntu 24.04 (Boost 1.83) and Debian 13 (Boost 1.83).
set(BOOST_ROOT "/usr" CACHE PATH "")
set(BOOST_NO_SYSTEM_PATHS OFF CACHE BOOL "")
set(Boost_USE_STATIC_LIBS ON)
set(Boost_USE_MULTITHREADED ON)
set(Boost_USE_STATIC_RUNTIME ON)
