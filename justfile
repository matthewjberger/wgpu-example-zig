set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]

[private]
default:
    @just --list

# Fetch dependencies and setup libraries
setup:
    @echo "Fetching Zig dependencies..."
    zig fetch --save https://github.com/kooparse/zalgebra/archive/refs/heads/main.zip
    @echo "Setting up SDL2..."
    New-Item -ItemType Directory -Force -Path include/SDL2 | Out-Null
    Invoke-WebRequest -Uri "https://github.com/libsdl-org/SDL/releases/download/release-2.30.10/SDL2-devel-2.30.10-VC.zip" -OutFile sdl2.zip
    Expand-Archive -Force sdl2.zip -DestinationPath sdl2-temp
    Copy-Item sdl2-temp/SDL2-2.30.10/include/* include/SDL2/
    Copy-Item sdl2-temp/SDL2-2.30.10/lib/x64/SDL2.dll .
    Copy-Item sdl2-temp/SDL2-2.30.10/lib/x64/SDL2.lib .
    Remove-Item -Recurse -Force sdl2-temp, sdl2.zip
    @echo "Setting up wgpu-native..."
    New-Item -ItemType Directory -Force -Path include/webgpu | Out-Null
    New-Item -ItemType Directory -Force -Path lib | Out-Null
    Invoke-WebRequest -Uri "https://github.com/gfx-rs/wgpu-native/releases/download/v25.0.2.2/wgpu-windows-x86_64-msvc-release.zip" -OutFile wgpu.zip
    Expand-Archive -Force wgpu.zip -DestinationPath wgpu-temp
    Get-ChildItem -Recurse wgpu-temp -Filter "wgpu_native.dll" | Copy-Item -Destination .
    Get-ChildItem -Recurse wgpu-temp -Filter "wgpu_native.dll.lib" | Copy-Item -Destination lib/wgpu_native.lib
    Get-ChildItem -Recurse wgpu-temp -Filter "webgpu.h" | Copy-Item -Destination include/webgpu/
    Get-ChildItem -Recurse wgpu-temp -Filter "wgpu.h" | Copy-Item -Destination include/webgpu/
    Remove-Item -Recurse -Force wgpu-temp, wgpu.zip
    @echo "Setup complete!"

# Build the triangle executable
build:
    zig build

# Build with optimizations
build-release:
    zig build -Doptimize=ReleaseFast

# Run the triangle example
run: build
    zig build run

# Run with release optimizations
run-release: build-release
    zig build run -Doptimize=ReleaseFast

# Clean build artifacts
clean:
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue zig-out
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue .zig-cache
