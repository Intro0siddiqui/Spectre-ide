cmake_minimum_required(VERSION 3.15)
project(spectre-ide CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Fetch FLTK
include(FetchContent)
FetchContent_Declare(
  fltk
  GIT_REPOSITORY https://github.com/fltk/fltk.git
  GIT_TAG        master
)
set(FLTK_BUILD_TEST NO CACHE BOOL "" FORCE)
set(FLTK_BUILD_EXAMPLES NO CACHE BOOL "" FORCE)
set(FLTK_BUILD_FLUID NO CACHE BOOL "" FORCE)
set(FLTK_BUILD_FLTK_OPTIONS NO CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(fltk)

# Build Zig Library
find_program(ZIG_EXE zig REQUIRED)
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/libspectre_core.a
    COMMAND ${ZIG_EXE} build -p ${CMAKE_CURRENT_BINARY_DIR}/zig_out -Doptimize=ReleaseSmall
    COMMAND cp ${CMAKE_CURRENT_BINARY_DIR}/zig_out/lib/libspectre_core.a ${CMAKE_CURRENT_BINARY_DIR}/libspectre_core.a
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Building Zig Core Library"
)
add_custom_target(zig_build DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/libspectre_core.a)

# Source files
file(GLOB_RECURSE SOURCES "src/main.cpp" "src/ui/*.cpp")

add_executable(spectre ${SOURCES})
add_dependencies(spectre zig_build)

# Disable PIE to link with Zig static lib
target_compile_options(spectre PRIVATE -fno-pie)
target_link_options(spectre PRIVATE -no-pie)

# Include directories
target_include_directories(spectre PRIVATE src)

# Link Libraries
target_link_libraries(spectre PRIVATE fltk ${CMAKE_CURRENT_BINARY_DIR}/libspectre_core.a)

