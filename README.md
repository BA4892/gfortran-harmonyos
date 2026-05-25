# gfortran-harmonyos

Build gfortran (Fortran compiler) for HarmonyOS (OpenHarmony) using the system's
OHOS Clang 15.0.4 as the host compiler.

Fortran 代码可编译为 `.so` 共享库，通过 `LD_PRELOAD` + destructor 模式执行，
或通过 `dlopen` 在 R/Python 等宿主进程中调用。

## How it works

HarmonyOS 的 `hmmac` 内核级安全策略阻止执行用户创建的可执行文件（execve 返回 126），
因此传统 `gfortran -o hello && ./hello` 流程不可用。

本项目的解决方式是将 Fortran 代码编译为共享库（.so），通过 LD_PRELOAD 注入到
系统可执行的宿主进程（/data/storage/el2/base/host）中，在 destructor 阶段执行
Fortran 代码。详情见 [BUILD-RECIPE.md](BUILD-RECIPE.md) 第六章。

## Quick Start

```bash
# 编译并运行 Fortran 程序
fortran-run hello.f90

# 也支持编译独立可执行文件（需先配置 CRT）
gfortran -o hello hello.f90      # 编译成功
# ./hello                         # hmmac 会拦截执行
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

支持传递任意命令行参数到 Fortran 程序的 `get_command_argument()` 和
`command_argument_count()` 内置函数。参数中的空格、特殊字符会自动转义。

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
