#!/usr/bin/env bash
#
# Builds the Kyber module and runs the launcher locally with one command.
#
# Usage:
#   ./dev.sh                Full build + run (first time).
#   ./dev.sh --skip-module --skip-generate   Fast iteration on Dart-only changes.
#
# Flags:
#   --bootstrap        Run `melos bootstrap` first.
#   --skip-generate    Skip proto + FFI code generation.
#   --skip-module      Skip the module build + deploy.
#   --force            Clean the Bazel cache before building the module.
#
# On Windows (Git Bash / MSYS / Cygwin) this delegates to the native
# PowerShell script `dev.ps1`, which resolves the `melos.bat` shim correctly
# (Git Bash cannot execute `.bat` PATH shims like `melos`).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP=0
SKIP_GENERATE=0
SKIP_MODULE=0
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bootstrap) BOOTSTRAP=1; shift ;;
        --skip-generate) SKIP_GENERATE=1; shift ;;
        --skip-module) SKIP_MODULE=1; shift ;;
        --force) FORCE=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Windows (Git Bash / MSYS / Cygwin): hand off to the native PowerShell script.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        args=()
        [[ "$BOOTSTRAP" == "1" ]] && args+=(-Bootstrap)
        [[ "$SKIP_GENERATE" == "1" ]] && args+=(-SkipGenerate)
        [[ "$SKIP_MODULE" == "1" ]] && args+=(-SkipModule)
        [[ "$FORCE" == "1" ]] && args+=(-Force)
        ps1="$(cygpath -w "$REPO_ROOT/dev.ps1" 2>/dev/null || printf '%s' "$REPO_ROOT/dev.ps1")"
        echo "==> On Windows: delegating to dev.ps1"
        exec powershell -NoProfile -ExecutionPolicy Bypass -File "$ps1" "${args[@]}"
        ;;
esac

echo "==> Kyber dev: build module + run launcher"

# Resolve melos (Dart global package) even when its shim isn't on PATH.
if command -v melos >/dev/null 2>&1; then
    melos() { command melos "$@"; }
elif command -v dart >/dev/null 2>&1; then
    melos() { dart pub global run melos "$@"; }
else
    echo "ERROR: melos is not installed. Run: dart pub global activate melos" >&2
    exit 1
fi

# 1. Bootstrap (first-time / after new deps)
if [[ "$BOOTSTRAP" == "1" ]] || [[ ! -d "$REPO_ROOT/Launcher/.dart_tool" ]]; then
    echo "==> melos bootstrap"
    (cd "$REPO_ROOT" && melos bootstrap)
fi

# 2. Generate proto + FFI bindings
if [[ "$SKIP_GENERATE" == "0" ]]; then
    echo "==> Generating proto bindings"
    (cd "$REPO_ROOT" && melos run generate_proto)
    echo "==> Generating FFI bindings"
    (cd "$REPO_ROOT/Launcher" && dart run tool/ffigen.dart)
fi

# 3. Build + deploy the module (Windows/MSVC only)
if [[ "$SKIP_MODULE" == "0" ]]; then
    echo "==> Building Kyber module (Bazel)"
    (cd "$REPO_ROOT/Module" && if [[ "$FORCE" == "1" ]]; then bazel --output_user_root="C:\\bz" clean; fi && ./build.bat)
else
    echo "==> Skipping module build (--skip-module)"
fi

# 4. Run the launcher (foreground; exit flutter to stop)
echo "==> Launching launcher"
cd "$REPO_ROOT/Launcher"
flutter run
