# Zig / SDL2 / WGPU Triangle

A cross-platform Zig graphics demo using [wgpu-native](https://github.com/gfx-rs/wgpu-native) to render a spinning triangle.

> **Related Projects:**
> - [wgpu-example](https://github.com/matthewjberger/wgpu-example) - Rust version
> - [wgpu-example-c](https://github.com/matthewjberger/wgpu-example-c) - C version
> - [wgpu-example-odin](https://github.com/matthewjberger/wgpu-example-odin) - Odin version

## Prerequisites

- [Zig](https://ziglang.org/) 0.15+
- [just](https://github.com/casey/just) - Command runner
- PowerShell (Windows)

## Quickstart

```bash
# Download and setup dependencies (wgpu-native, SDL2, zalgebra)
just setup

# Build and run
just run
```

<img width="802" height="632" alt="image" src="https://github.com/user-attachments/assets/3cb1861d-02c1-4410-a47b-a3c7fdee5e92" />

## Commands

| Command | Description |
|---------|-------------|
| `just setup` | Download wgpu-native, SDL2, and fetch Zig dependencies |
| `just build` | Build the triangle executable |
| `just build-release` | Build with release optimizations |
| `just run` | Build and run the triangle |
| `just run-release` | Build and run with release optimizations |
| `just clean` | Remove build artifacts |

## Project Structure

```
wgpu-example-zig/
├── src/
│   └── main.zig        # Main source file
├── build.zig           # Zig build configuration
├── build.zig.zon       # Zig package dependencies
├── justfile            # Build commands
├── README.md           # This file
├── include/            # Headers (created by setup)
│   ├── webgpu/         # wgpu-native headers
│   └── SDL2/           # SDL2 headers
├── lib/                # Libraries (created by setup)
├── SDL2.dll            # SDL2 runtime (created by setup)
└── wgpu_native.dll     # wgpu-native runtime (created by setup)
```

## Dependencies

- [wgpu-native](https://github.com/gfx-rs/wgpu-native) - Native WebGPU implementation
- [SDL2](https://www.libsdl.org/) - Cross-platform windowing and input
- [zalgebra](https://github.com/kooparse/zalgebra) - Linear algebra library for Zig

## Controls

- **ESC** - Quit the application
- Window can be resized
