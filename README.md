# gfortran-harmonyos

Build gfortran (Fortran compiler) for HarmonyOS (OpenHarmony) using the system's
OHOS Clang 15.0.4 as the host compiler.

Fortran code can be compiled into a `.so` shared library and executed using the `LD_PRELOAD` + destructor pattern,
or called from host processes such as R or Python via `dlopen`.

## How it works

HarmonyOS's `hmmac` kernel-level security policy prevents the execution of user-created executable files (execve returns 126),
so the traditional `gfortran -o hello && ./hello` workflow is not available.

The solution for this project involves compiling the Fortran code into a shared library (.so) and injecting it via LD_PRELOAD into
the system’s executable host process (/data/storage/el2/base/host), where the Fortran code is executed
during the destructor phase. For details, see Chapter 6 of [BUILD-RECIPE.md](BUILD-RECIPE.md).

## Quick Start

```bash
# Compile and run a Fortran program
fortran-run hello.f90

# Also supports compiling standalone executables (requires prior CRT configuration)
gfortran -o hello hello.f90      # Compilation successful
# ./hello                         # hmmac will intercept execution
```

## Requirements

- OHOS Clang 15.0.4+ (`aarch64-unknown-linux-ohos-clang`, via SDK 26, can `brew install ohos-sdk`)
- GCC 14.2.0 source (downloaded by `download.sh`)
- GMP, MPFR, MPC (downloaded by `download.sh`, or use brew: `brew install gmp mpfr mpc`)
- GNU Bash as `CONFIG_SHELL`
- `ohos-compat.h` — compatibility header for Clang's `__availability__` attribute

## Build Steps

```bash
# 1. Download GCC source
./download.sh

# 2. Configure with OHOS Clang
./configure.sh

# 3. Build (may need retries due to LLD alignment errors)
cd build && make -j$(nproc)

# 4. Install
make install prefix=~/.local/gfortran

# 5. Install CRT files (required for linking executables)
#    See BUILD-RECIPE.md §3.6 for details

# 6. Setup environment
source setup-env.sh
```

Details: [BUILD-RECIPE.md](BUILD-RECIPE.md)

## Project Status

All core Fortran features tested and working:

| Component              | Status |
|------------------------|--------|
| gfortran driver        | ✅ |
| f951 compiler backend   | ✅ |
| libgfortran (static)   | ✅ |
| libgfortran (dynamic)  | ✅ |
| Basic I/O (print/write)| ✅ |
| Math intrinsics        | ✅ |
| File I/O               | ✅ |
| Arrays & intrinsics    | ✅ |
| Character/string ops   | ✅ |
| Derived types          | ✅ |
| Modules                | ✅ |
| Allocatable arrays     | ✅ |
| Format statements      | ✅ |
| iso_c_binding          | ✅ |
| Command-line arguments | ✅ |
| Standard input (read *) | ❓ (untested) |
| R integration (dlopen) | ✅ (untested but expected) |

Full test report: [BUILD-RECIPE.md §附录C](BUILD-RECIPE.md)

## Usage

### Run Fortran code directly
```bash
fortran-run hello.f90
fortran-run hello.f90 arg1 arg2  # 支持命令行参数
```

Supports the built-in functions `get_command_argument()` and
`command_argument_count()` for passing arbitrary command-line arguments to Fortran programs. Spaces and special characters in the arguments are automatically escaped.

### Compile shared library for R/Python integration
```bash
gfortran -c -fPIC -o test.o test.f90
aarch64-unknown-linux-ohos-clang -shared -o test.so test.o \
    -Wl,--whole-archive ~/.local/gfortran/lib64/libgfortran.a \
    -Wl,--no-whole-archive \
    -Wl,--whole-archive ~/.local/gfortran/lib/gcc/.../14.2.0/libgcc.a \
    -Wl,--no-whole-archive
```
Then `dyn.load("test.so")` in R.

## Known Issues

1. **hmmac prevents direct ELF execution**: All user-created executables are
   blocked by HarmonyOS kernel-level MAC, regardless of filesystem. The
   LD_PRELOAD + destructor approach (`fortran-run`) works around this.

2. **`fortran-run` uses destructor execution**: Fortran code runs after the
   host process's `main()` returns. This means:
   - Only one Fortran `.so` can run per host process (symbol conflicts if
     multiple are loaded)
   - Some Fortran runtime state may behave differently than in a normal
     executable (e.g., `read *` from stdin is untested)

3. **No `execute_command_line`**: Requires fork/exec which hmmac blocks.

4. **No OpenMP**: libgomp was disabled at configure time (`--disable-gomp`).

5. **Standard input (`read *`) untested**: Due to the destructor execution
   model, reading from stdin has not been verified and may not work.

6. **Duplicate symbols in libgfortran.a**: `environ_test.o` conflicts with
   `environ.o` — use `-Wl,--allow-multiple-definition` when linking.

7. **`_gfortrani_` internal symbols**: `_gfortrani_init_units()` and
   `_gfortrani_flush_all_units()` must be called manually (see the generated
   C runner in `fortran-run`). Not needed when using `fortran-run`.

8. **`-nostartfiles` required for shared libs**: OHOS sysroot lacks
   `crtbeginS.o`. When linking `.so` files, always use `-nostartfiles`.

9. **libbacktrace must be linked separately**: When linking with
   `libgfortran.a`, also link `libbacktrace.a` from the build tree.

10. **LLD alignment errors during GCC build**: `R_AARCH64_LDST64_ABS_LO12_NC`
    errors affect cc1/xgcc linking only, not libgfortran/f951. Make retries
    during build (`make -j$(nproc)` may fail, just re-run).

11. **Large build directory**: After building GCC, the `build/` directory
    is ~30GB. It can be deleted after `make install` to free space.

12. **`--allow-multiple-definition` needed for static linking**: When using
    `-Wl,--whole-archive` with `libgfortran.a`, also pass
    `-Wl,--allow-multiple-definition` to suppress duplicate symbols.

13. **Build artifacts left in source directory**: `fortran-run` generates
    `.o` and `.so` files alongside the source `.f90` file.

## File Structure

| Path | Purpose |
|------|---------|
| `download.sh` | Download GCC 14.2.0 source |
| `configure.sh` | Configure with OHOS Clang |
| `build.sh` | Build wrapper |
| `setup-env.sh` | Environment setup |
| `fortran-run` | Compile & run Fortran programs |
| `ohos-push` | Push git commits to GitHub via API |
| `test/` | Test suite (14 tests) |
| `BUILD-RECIPE.md` | Full build and usage guide |

## Related HarmonyOS Projects

- [hermes-harmonyos](https://github.com/sxgou/hermes-harmonyos) — Hermes Agent compatibility layer (pure-Python shims for Rust-native deps)
- [jupyter-harmonyos](https://github.com/sxgou/jupyter-harmonyos) — Jupyter Notebook compatibility layer (ctypes-based ZMQ shim)
