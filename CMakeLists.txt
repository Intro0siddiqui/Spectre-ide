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
# FLTK options to minimize build time/deps
set(FLTK_BUILD_TEST NO CACHE BOOL "" FORCE)
set(FLTK_BUILD_EXAMPLES NO CACHE BOOL "" FORCE)
set(FLTK_BUILD_FLUID NO CACHE BOOL "" FORCE)
set(FLTK_BUILD_FLTK_OPTIONS NO CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(fltk)

# Source files
file(GLOB_RECURSE SOURCES "src/*.cpp")

add_executable(spectre ${SOURCES})

# Include directories
target_include_directories(spectre PRIVATE src)

# Link FLTK
target_link_libraries(spectre PRIVATE fltk)
