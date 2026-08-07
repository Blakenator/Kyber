# Building KYBER

## Prerequisites

- Clone the repository with `--recurse-submodules` or run `git submodule --init --recursive`
- Download and install [Protoc](https://github.com/protocolbuffers/protobuf/releases) and ensure `protoc` is in your `PATH`

------

## One-Command Local Dev (Launcher + Module)

For iterating on the Launcher and the C++ Module, run the dev script from the repository root. It handles bootstrap, proto/FFI generation, the Bazel module build + deploy, and `flutter run`:

```bash
# Windows
.\dev.ps1

# Linux/macOS
./dev.sh
```

This does **not** require a local API instance — the launcher talks to the module directly over localhost gRPC and uses the public API (prod/stage) for the server browser and moderation as normal.

Flags (both scripts):

| Flag | Meaning |
|------|---------|
| `-Bootstrap` / `--bootstrap` | Run `melos bootstrap` first (first checkout / new deps). Auto-runs if `.dart_tool` is missing. |
| `-SkipGenerate` / `--skip-generate` | Skip proto + FFI code generation (do this after proto changes too). |
| `-SkipModule` / `--skip-module` | Skip the Bazel module build + deploy (fast Dart-only iteration). |
| `-Force` / `--force` | Clean the Bazel cache before building the module (full rebuild). |

Note: the C++ Module can only be built on Windows/MSVC. On Windows, `dev.sh` (run from Git Bash/MSYS) automatically delegates to `dev.ps1` because Git Bash cannot execute the `melos.bat` shim; use either entry point.

The dev scripts preflight `dart`, `flutter`, `protoc`, and `melos`, and if `bazel` is missing they automatically download [bazelisk](https://github.com/bazelbuild/bazelisk) to `%LOCALAPPDATA%\Kyber\bazel\bazel.exe` (the Module's `.bazelversion` pins Bazel 8.0.0). You can still install bazelisk manually and put it on your `PATH` as `bazel.exe` if you prefer.

`dev.ps1` also auto-selects the **newest installed MSVC toolchain** and pins Bazel to it via `BAZEL_VC` / `BAZEL_VC_FULL_VERSION`. This matters because the Module's `ThirdParty/safetyhook` requires the C++23 `<expected>` header, which needs **Visual Studio 2022 / MSVC 14.3x+**. Bazel's auto-detection (`vswhere`) only sees *registered* VS installs and may pick an older compiler (e.g. VS 2019 / 14.29), which fails with `fatal error C1083: Cannot open include file: 'expected'`. If you build with `build.bat` directly, set `BAZEL_VC` (and `BAZEL_VC_FULL_VERSION`) to your VS 2022 Build Tools `VC` folder (e.g. `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC`).

For a `flutter run`-only loop (Dart changes only, module already built):

```bash
.\dev.ps1 -SkipModule -SkipGenerate
```

------

## Dart/Flutter Projects (Launcher, CLI, Packages)

### Prequisites
- [Flutter](https://flutter.dev) (master channel)
- [Rust](https://rustup.rs) (nightly toolchain)
- [Melos](https://melos.invertase.dev): `dart pub global activate melos`

### Bootstrapping (Required for Launcher & CLI)

Bootstrap the workspace from the repository root:

```bash
melos bootstrap
```

This installs dependencies, generates proto bindings, and runs code generation.

## Launcher (Flutter)

### Generating FFI Bindings

First you need to generate the FFI bindings:
```bash
cd Launcher
dart run tool/ffigen.dart
```

### Run in Debug Mode

From the launcher directory, run:
```bash
flutter run
```

### Build Release Binaries

From the launcher directory, run:
```bash
flutter build <platform>
```

### Building the Installer

To build the installer on Windows, you can use [Inno Setup](https://jrsoftware.org/isinfo.php) with the provided `installer.iss` script located in the `installer` folder.

## CLI (Flutter)

### Building the CLI

```bash
cd CLI
flutter pub get
flutter_rust_bridge_codegen generate
dart build cli bin/kyber_cli.dart
```

This will output the binary to `build/cli/<platform>/bundle/bin/`.

### Using the Built CLI

To run the CLI, make sure to copy the rust library from `build/cli/<platform>/bundle/lib/` next to the binary.

**Important:** Make sure to build Maxima first. Then depending on your platform, copy the following files next to the binary from the Maxima build output:

#### Windows
- `maxima-service.exe`
- `maxima-bootstrap.exe`

#### Linux
- `maxima-bootstrap`

------

## Module (C++)

### Building the KYBER Module

The KYBER Module can only be compiled on Windows, with MSVC.

First, install [bazelisk](https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-windows-amd64.exe) and drop it into your `PATH` as `bazel.exe`.

There is a bug with the gRPC client version we're using in combination with Bazel's long build paths, which makes some build paths extend past the legacy Windows path limit. To work around this, make a folder named `bz` at the root of your drive. We'll be using this folder to store bazel's intermediary files.

Ensure you have [MSYS2](https://www.msys2.org/) installed to `C:\msys64`.

Run `bazel --output_user_root="C:\bz" build --config=release Kyber`. This will take a while. Once it's done, you should have `Module/bazel-bin/Kyber.dll`. You may alternatively run the `build.bat` file in the root by running `.\build.bat` and modifying the path to the correct drive.

**Important:** The module requires the `--config=release` flag. Building without it (i.e., in debug mode) will lead to crashes.

### Using the Built Module

Once built, copy `Module/bazel-bin/Kyber.dll` to `C:/ProgramData/Kyber/Module/Kyber.dll` to test your changes with the Launcher or CLI.

### Code Completion

The KYBER module is primarily developed using Visual Studio Code with the clangd extension. `compile_commands.json` can be generated by running `clangd/refresh.bat` while inside the `Module` folder.

------

## API (Go)

Requires Go 1.24+ and protoc with Go plugins:

```bash
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
```

Build:

Linux:
```bash
cd API
./scripts/gen-proto.sh
go build -o kyber-api ./cmd/server
```

Windows:
```bash
cd API
scripts\gen-proto.bat
go build -o kyber-api.exe ./cmd/server
```

------

## Proxy (Rust)

Requires Rust nightly and protoc.

```bash
cd Proxy
cargo build --release
```

Output: `target/release/kyber_proxy`
