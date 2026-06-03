# gfortran‑harmonyos – Complete Build & Usage Guide

## 1. Overview

Port GCC 14.2.0’s `gfortran` (Fortran compiler) to HarmonyOS (OpenHarmony) using the system’s native OHOS Clang 15.0.4 as the host compiler.  
Target platform: `aarch64-unknown-linux-ohos`.  
Key features: static linking of `libgfortran`, execution via `LD_PRELOAD` + destructor pattern.

## 2. Prerequisites

### 2.1 OHOS SDK (hnp package manager)

SDK installed via `hnp`. Current version:
ohos-sdk_26.0.0.18 (API 26)

SDK installation path:
/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/
├── llvm/bin/               # Clang toolchain
│   ├── clang
│   └── ...
├── sysroot/                # musl headers & libraries
│   ├── usr/include/
│   └── usr/lib/
└── build-tools/            # cmake, ninja, etc.

> **Note:** In this environment `hnp` commands are not directly callable – the SDK is pre‑installed.

### 2.2 Clang toolchain entry points

The SDK provides stable symlinks under `/data/service/hnp/bin/`:


```bash
ls /data/service/hnp/bin/aarch64-unknown-linux-ohos-clang*
# aarch64-unknown-linux-ohos-clang   → ../ohos-sdk.org/.../llvm/bin/clang
# aarch64-unknown-linux-ohos-clang++ → .../clang++

```
These are shell wrappers that locate the SDK and sysroot. Always use these wrappers when building GCC.

```bash
export OHOS_CLANG=/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang
export OHOS_CLANGXX=/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang++

```
Verify:

```bash
$OHOS_CLANG --version
# clang version 15.0.4 (...)
# Target: aarch64-unknown-linux-ohos
# Thread model: posix
```
2.3 Sysroot
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot

2.4 Other dependencies

Bash: /data/service/hnp/bin/bash – must be set as CONFIG_SHELL (GCC’s configure needs bash features)

TMPDIR: must point to a writable filesystem (hmdfs has group‑x issues – use umask 022)

3. Building GCC
3.1 Download sources
```bash
git clone <repo> gfortran-harmonyos
cd gfortran-harmonyos
./download.sh
```
download.sh:

    downloads gcc-14.2.0.tar.xz from GNU mirror

    unpacks to gcc-14.2.0/

    runs contrib/download_prerequisites (GMP, MPFR, MPC)

Directory structure:
gfortran-harmonyos/
  ├── gcc-14.2.0/
  ├── download.sh
  ├── configure.sh
  ├── build.sh
  └── build/              # build output

  3.2 Required patch files
3.2.1 ohos-compat.h

Path: build/ohos-compat.h (globally included via -include ohos-compat.h)

```c
/* GCC compatibility: ignore Clang's __availability__ attribute */
#define __availability__(...)
```

Purpose: OHOS sysroot headers use Clang’s __attribute__((__availability__)). This macro disables it for GCC’s xgcc.

Also copied to build/gcc/include-fixed/ohos-compat.h and test/ohos-compat.h. Used during libgfortran build via CPPFLAGS="-include ohos-compat.h".
3.2.2 xgcc-wrap.sh (optional, for EINTR retry)

Place anywhere (e.g. ~/.local/bin/xgcc-wrap.sh):

```bash
#!/bin/sh
# Retry wrapper for xgcc to handle EINTR on HarmonyOS
if [ $# -lt 1 ]; then exit 1; fi
XGCC="$1"; shift
for attempt in $(seq 1 30); do
    "$XGCC" "$@"; rc=$?
    [ $rc -eq 0 ] && exit 0
    if [ $rc -eq 127 ] || [ $rc -eq 1 ]; then
        usleep 100000; continue
    fi
    exit $rc
done
exec "$XGCC" "$@"

```
3.3 Configuration

```bash
./configure.sh

```
Contents of configure.sh:


```bash
#!/bin/sh
set -e
umask 022

export TMPDIR=/storage/Users/currentUser/gfortran-harmonyos/tmp
export CONFIG_SHELL=/data/service/hnp/bin/bash
export SHELL=/data/service/hnp/bin/bash
mkdir -p "$TMPDIR"

BUILD_DIR=/storage/Users/currentUser/gfortran-harmonyos/build
SRC_DIR=/storage/Users/currentUser/gfortran-harmonyos/gcc-14.2.0
PREFIX=/storage/Users/currentUser/.local/gfortran
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

OHOS_CLANG=/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang
OHOS_CLANGXX=/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang++

"$SRC_DIR/configure" \
    --host=aarch64-unknown-linux-ohos \
    --build=aarch64-unknown-linux-ohos \
    --target=aarch64-unknown-linux-ohos \
    --prefix="$PREFIX" \
    --enable-languages=c,fortran \
    --disable-bootstrap \
    --disable-multilib \
    --disable-nls \
    --disable-libsanitizer \
    --disable-gomp \
    --disable-libquadmath \
    --without-isl \
    --disable-graphite \
    --with-sysroot=/ \
    CC="$OHOS_CLANG" \
    CXX="$OHOS_CLANGXX" \
    CPP="${OHOS_CLANG} -E" \
    CXXCPP="${OHOS_CLANGXX} -E" \
    CFLAGS="-O2 -g0" \
    CXXFLAGS="-O2 -g0"


```
Key configuration options:
Parameter	              Description
--host=--build=--target	All three equal → native build (not cross‑compilation)
--disable-bootstrap	Single‑stage build; GCC does not bootstrap (host compiler is Clang)
--disable-gomp	Disable OpenMP (libgomp is complex and not needed)
--disable-libquadmath	Disable quad‑precision math library (requires extra libs)
--with-sysroot=/	Set sysroot to /; Clang finds SDK via built‑in search path
--without-isl --disable-graphite	Disable Graphite loop optimisation (depends on isl)


3.4 Compilation
```bash
cd /storage/Users/currentUser/gfortran-harmonyos/build
./../build.sh
```
build.sh:
```bash
#!/bin/sh
export TMPDIR=/storage/Users/currentUser/gfortran-harmonyos/tmp
export CONFIG_SHELL=/data/service/hnp/bin/bash
export SHELL=/data/service/hnp/bin/bash
umask 022
cd /storage/Users/currentUser/gfortran-harmonyos/build
make -j$(nproc)
```
Known build issues & workarounds

1. LLD alignment error (thin archives)

ld.lld: error: libcommon.a(diagnostic-format-sarif.o): improper alignment for relocation R_AARCH64_LDST64_ABS_LO12_NC

    Occurs when linking libbackend.a (GCC itself).

    Workaround: use make -k to continue, or a retry script (make-retry.sh).

    The final gfortran and libgfortran are still correctly built.

2. xgcc EINTR
HarmonyOS kernel may return EINTR (exit code 127). Wrapping xgcc with xgcc-wrap.sh or simply retrying make works.

3. Missing .lo files after interrupted build
Use fix-build.sh to regenerate stub .lo files from existing .libs/*.o.

3.5 Installation
cd /storage/Users/currentUser/gfortran-harmonyos/build
make install prefix=/storage/Users/currentUser/.local/gfortran
Note: Override prefix because libtool hard‑coded the absolute path during configure.


3.6 CRT files (to enable standalone executable compilation)
After installation, gfortran can compile Fortran to .o files. To also produce standalone executables (gfortran -o hello hello.f90), copy required CRT startup files from the OHOS SDK.
```bash
GFORTRAN_LIB=/storage/Users/currentUser/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot
CLANGRT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos

# musl CRT entry files
cp "$SYSROOT/usr/lib/aarch64-linux-ohos/Scrt1.o" "$GFORTRAN_LIB/"
cp "$SYSROOT/usr/lib/aarch64-linux-ohos/crti.o"  "$GFORTRAN_LIB/"
cp "$SYSROOT/usr/lib/aarch64-linux-ohos/crtn.o"  "$GFORTRAN_LIB/"

# Clang compiler‑rt CRT (rename to GCC expected names)
cp "$CLANGRT/clang_rt.crtbegin.o" "$GFORTRAN_LIB/crtbegin.o"
cp "$CLANGRT/clang_rt.crtend.o"   "$GFORTRAN_LIB/crtend.o"
```
Now you can compile executables:
```bash
gfortran -o hello hello.f90 --sysroot="$SYSROOT"
```

But: The generated ELF cannot be executed directly on HarmonyOS due to hmmac security policies (see Section 6). Use the LD_PRELOAD + destructor method.

3.7 libbacktrace standalone build (for runtime)

libbacktrace is built automatically as part of GCC and is located at:
build/aarch64-unknown-linux-ohos/libbacktrace/.libs/libbacktrace.a

No manual rebuild is needed – the final linking step will reference this .a.

4. Installed components

Installation prefix: ~/.local/gfortran/


File	Purpose
bin/gfortran	gfortran driver (ELF, 22KB)
bin/aarch64-unknown-linux-ohos-gfortran	target‑specific symlink
lib/gcc/aarch64-unknown-linux-ohos/14.2.0/f951	Fortran compiler backend (72MB)
lib/gcc/aarch64-unknown-linux-ohos/14.2.0/libgcc.a	GCC runtime static library
lib/gcc/aarch64-unknown-linux-ohos/14.2.0/libgcc_s.so.1	GCC runtime dynamic library
lib/gcc/aarch64-unknown-linux-ohos/14.2.0/specs	gfortran specs file
lib64/libgfortran.a	Fortran runtime static library (788 objects)
lib64/libgfortran.so.5.0.0	Fortran runtime dynamic library
lib64/libgfortran.so.5 → libgfortran.so.5.0.0	SO symlink
lib64/libgfortran.so → libgfortran.so.5	SO symlink


5. Environment configuration
5.1 Shell environment
   
```bash
# Add to ~/.zshenv or setup-env.sh
export PATH="$PATH:$HOME/.local/gfortran/bin"
export LD_LIBRARY_PATH="$HOME/.local/gfortran/lib64:$LD_LIBRARY_PATH"
```
5.2 gfortran wrapper
```bash
~/.local/bin/gfortran:
#!/bin/sh
export LD_LIBRARY_PATH="/storage/Users/currentUser/.local/gfortran/lib64:$LD_LIBRARY_PATH"
exec /storage/Users/currentUser/.local/gfortran/bin/gfortran "$@"
```
5.3 Verification
```bash
source ~/.zshenv
gfortran --version
# GNU Fortran (GCC) 14.2.0
```
Compile a test object:
```bash
cat > /tmp/test.f90 << 'EOF'
program hello
  print *, "hello from gfortran on HarmonyOS"
end program hello
EOF
gfortran -c -fPIC -o /tmp/test.o /tmp/test.f90
```
6. Runtime architecture
6.1 The problem: HarmonyOS blocks user‑compiled ELFs

HarmonyOS hmmac (mandatory access control) sets hmmac=use_task on all user‑writable filesystems, preventing execution of user‑created executables.
```bash
# mount output shows:
tmpfs on /storage/Users type tmpfs (...,hmmac=use_task,...)
# execve returns 126 (Permission denied)
```
All workarounds fail:

    execve directly → ❌

    execveat(fd, AT_EMPTY_PATH) → ❌

    memfd_create + execveat → ❌

    System binaries refuse LD_PRELOAD → ❌

6.2 Solution: LD_PRELOAD + destructor pattern

User source → gfortran -c -fPIC → .o
                                   → clang -shared -nostartfiles → .so → LD_PRELOAD → host process
                 C stub (destructor) ─┘                                   destructor executes Fortran

6.3 Compile the host bridge program
/data/storage/el2/base/host.c:
```c
int main(void) { return 0; }
```
Compile as PIE (required by OHOS):
```bash
aarch64-unknown-linux-ohos-clang \
    -o /data/storage/el2/base/host \
    /data/storage/el2/base/host.c
```
Verify:
```bash
file /data/storage/el2/base/host
# ELF shared object, 64-bit LSB arm64, dynamic, not stripped
```
6.4 C runtime stub (destructor pattern – final version)

/data/storage/el2/base/.fortran_runner.c (automatically generated by fortran-run):
```c
#include <stdlib.h>
#include <stdio.h>
extern int main(int argc, char *argv[]);
extern void _gfortran_set_args(int argc, char *argv[]);
extern void _gfortran_set_options(int num, int opts[]);
extern void _gfortrani_init_units(void);
extern void _gfortrani_flush_all_units(void);
static void run(void) __attribute__((destructor));
static void run(void) {
    char *argv[] = { "fortran_prog", 0 };
    int opts[] = { 255, 6, 0, 5, 1 };
    _gfortran_set_args(1, argv);
    _gfortran_set_options(5, opts);
    _gfortrani_init_units();
    main(1, argv);
    _gfortrani_flush_all_units();
}
```
Why destructor, not constructor?
The constructor runs before main() – at that point the Fortran I/O system is not fully initialised. The destructor runs during process exit, after all runtimes are ready.

opts[] parameter array:
```c
int opts[] = { 255, 6, 0, 5, 1 };
```

255 – standard output options (all stdio streams)

6 – message length

5 – signal handling behaviour

1 – allow sub‑processes

7. Detailed execution flow
7.1 Compilation & linking

User runs fortran-run hello.f90:

Step 1 – Generate C runtime stub
fortran-run creates /data/storage/el2/base/.fortran_runner.c (cached if unchanged).

Step 2 – Compile C stub to PIC object
```bash
aarch64-unknown-linux-ohos-clang -c -fPIC -O2 \
    -o /data/storage/el2/base/.fortran_runner.o \
    /data/storage/el2/base/.fortran_runner.c
```
Step 3 – Compile Fortran code to PIC object
```bash
gfortran -c -fPIC --sysroot="$SYSROOT" -o hello_pic.o hello.f90
```
Step 4 – Link as shared library
```bash
aarch64-unknown-linux-ohos-clang -shared -nostartfiles \
    -o hello.so \
    hello_pic.o .fortran_runner.o \
    -Wl,--whole-archive -Wl,--allow-multiple-definition \
    libgfortran.a \
    -Wl,--no-whole-archive \
    libbacktrace.a -lm \
    -Wl,--whole-archive libgcc.a -Wl,--no-whole-archive \
    --sysroot="$SYSROOT"
```
Linker parameters explained:
Parameter	Description
-shared -nostartfiles	Produce shared library, skip CRT startup files (OHOS lacks crtbeginS.o)
--whole-archive libgfortran.a	Force link of all object files from libgfortran.a
--allow-multiple-definition	Allow duplicate symbols (some objects inside libgfortran.a collide)
--no-whole-archive	Link subsequent libraries normally
-lm	Math library required by libgfortran
--whole-archive libgcc.a	Force inclusion of GCC runtime helper functions

7.2 Execution
```bash
export LD_LIBRARY_PATH="$HOME/.local/gfortran/lib64:$HOME/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0"
LD_PRELOAD=./hello.so /data/storage/el2/base/host
```
Sequence:

    Dynamic loader loads hello.so (via LD_PRELOAD).

    host’s main() runs and returns immediately.

    Process exit → dynamic loader calls destructor of hello.so.

    Destructor calls _gfortrani_init_units() → initialises Fortran I/O.

    Calls Fortran main().

    After Fortran main() returns, destructor calls _gfortrani_flush_all_units().

    Process exits, stdout flushed.

8. Complete usage example
8.1 Using fortran-run (recommended)
```bash
cat > hello.f90 << 'EOF'
program hello
  print *, "Hello, HarmonyOS!"
  print *, "sin(1.0) =", sin(1.0d0)
end program hello
EOF

fortran-run hello.f90
# Output:
# Built: ./hello.so
#  Hello, HarmonyOS!
#  sin(1.0) =  0.84147098480789650
```
8.2 Manual step‑by‑step
```bash
export SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot

# 1. Compile C stub
aarch64-unknown-linux-ohos-clang -c -fPIC -O2 \
    -o /data/storage/el2/base/.fortran_runner.o \
    -x c - << 'EOF'
#include <stdlib.h>
#include <stdio.h>
extern int main(int argc, char *argv[]);
extern void _gfortran_set_args(int argc, char *argv[]);
extern void _gfortran_set_options(int num, int opts[]);
extern void _gfortrani_init_units(void);
extern void _gfortrani_flush_all_units(void);
static void run(void) __attribute__((destructor));
static void run(void) {
    char *argv[] = { "fortran_prog", 0 };
    int opts[] = { 255, 6, 0, 5, 1 };
    _gfortran_set_args(1, argv);
    _gfortran_set_options(5, opts);
    _gfortrani_init_units();
    main(1, argv);
    _gfortrani_flush_all_units();
}
EOF

# 2. Compile Fortran PIC object
gfortran -c -fPIC --sysroot="$SYSROOT" -o hello_pic.o hello.f90

# 3. Link shared library
aarch64-unknown-linux-ohos-clang -shared -nostartfiles \
    -o hello.so hello_pic.o /data/storage/el2/base/.fortran_runner.o \
    -Wl,--whole-archive -Wl,--allow-multiple-definition \
    ~/.local/gfortran/lib64/libgfortran.a \
    -Wl,--no-whole-archive \
    ~/gfortran-harmonyos/build/libbacktrace/.libs/libbacktrace.a -lm \
    -Wl,--whole-archive ~/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0/libgcc.a \
    -Wl,--no-whole-archive \
    --sysroot="$SYSROOT"

# 4. Run
export LD_LIBRARY_PATH="$HOME/.local/gfortran/lib64:$HOME/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0"
LD_PRELOAD=./hello.so /data/storage/el2/base/host
```
8.3 Environment variables quick reference
```bash
export GFORTRAN=/storage/Users/currentUser/.local/gfortran/bin/gfortran
export CLANG=/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang
export HOST=/data/storage/el2/base/host
export SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot
export LIBGFORTRAN_A=/storage/Users/currentUser/.local/gfortran/lib64/libgfortran.a
export LIBGCC_A=/storage/Users/currentUser/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0/libgcc.a
export LIBBACKTRACE_A=/storage/Users/currentUser/gfortran-harmonyos/build/libbacktrace/.libs/libbacktrace.a
export LD_LIBRARY_PATH=/storage/Users/currentUser/.local/gfortran/lib64:/storage/Users/currentUser/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0
```
9. Known issues and caveats
Issue	Workaround / note
Duplicate symbol: environ_test.o inside libgfortran.a	Add -Wl,--allow-multiple-definition to the linker command line.
Missing _gfortrani_* internal symbols	Ensure libgfortran was built with internal symbols (check with nm).
-nostartfiles required for shared library linking	OHOS sysroot lacks crtbeginS.o; destructor pattern does not need CRT init/fini.
LLD alignment errors during GCC self‑link	These affect only cc1/xgcc; ignore if gfortran and libgfortran are built.
libbacktrace not linked automatically	Manually add libbacktrace.a when linking the final .so.
hmdfs permissions (group x required)	Use umask 022 before any build or file creation.
Cannot run .so directly	.so is a library, not an executable – use LD_PRELOAD.
Standard input (read *) not tested	Input inside destructor may not work; not part of the test suite.
Only one Fortran .so can be loaded at a time	LD_PRELOAD only supports one library; run multiple programs sequentially.
Build directory consumes ~30GB	Safe to delete build/ after make install.
fortran-run produces .o and .so in source directory	They can be deleted; fortran-run will regenerate them.

11. Troubleshooting
10.1 Link‑time undefined reference to _gfortrani_init_units
```bash
nm ~/.local/gfortran/lib64/libgfortran.a | grep init_units
# Expected output: 000... T _gfortrani_init_units
```
If missing, rebuild libgfortran with internal symbols enabled.
10.2 Runtime segmentation fault

Possible causes:

    Fortran I/O system state already destroyed when destructor runs.

    Try using a constructor instead (older versions of fortran_runner.c used __attribute__((constructor))).

    Check that opts[] values are appropriate.

10.3 No output

    Ensure _gfortrani_flush_all_units() is called (Fortran I/O is buffered).

    Check if stdout is redirected.

    Add setvbuf(stdout, NULL, _IONBF, 0); to the stub.

10.4 gfortran cannot find _gfortran_* symbols when compiling .o

This indicates a problem with gfortran’s specs. Verify:
```bash
gfortran -dumpspecs | head -20
```
Appendix A – File manifest
File	Source	Purpose
~/.local/gfortran/bin/gfortran	GCC make install	Fortran compiler driver
~/.local/gfortran/lib64/libgfortran.a	GCC make install	Runtime static library (linking)
~/.local/gfortran/lib64/libgfortran.so.5	GCC make install	Runtime dynamic library (loaded at runtime)
~/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0/f951	GCC make install	Fortran compiler backend
~/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0/libgcc.a	GCC make install	GCC runtime helper functions
~/gfortran-harmonyos/build/libbacktrace/.libs/libbacktrace.a	GCC build artifact	Stack trace library
~/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0/Scrt1.o	Manual copy	musl CRT entry file
~/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0/crtbegin.o	Manual copy	Clang compiler‑rt CRT initialization
/data/storage/el2/base/host	Manual compilation	LD_PRELOAD host process
/data/storage/el2/base/.fortran_runner.c	Generated by script	C runtime stub (destructor)
/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot	SDK pre‑installed	musl sysroot
/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang	SDK pre‑installed	Clang compiler wrapper

Appendix B – Build command quick reference
```bash
# Full build from scratch
cd ~/gfortran-harmonyos
./download.sh
./configure.sh
cd build && make -j$(nproc)          # may need several retries
make install prefix=~/.local/gfortran

# Compile host
aarch64-unknown-linux-ohos-clang -o /data/storage/el2/base/host /data/storage/el2/base/host.c

# Copy CRT files
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot
CLANGRT=$SYSROOT/../../llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos
GFORTRAN_LIB=~/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0
cp $SYSROOT/usr/lib/aarch64-linux-ohos/Scrt1.o $GFORTRAN_LIB/
cp $SYSROOT/usr/lib/aarch64-linux-ohos/crti.o  $GFORTRAN_LIB/
cp $SYSROOT/usr/lib/aarch64-linux-ohos/crtn.o  $GFORTRAN_LIB/
cp $CLANGRT/clang_rt.crtbegin.o $GFORTRAN_LIB/crtbegin.o
cp $CLANGRT/clang_rt.crtend.o   $GFORTRAN_LIB/crtend.o

# Install fortran-run
cp ~/gfortran-harmonyos/fortran-run ~/.local/bin/fortran-run
chmod +x ~/.local/bin/fortran-run

# Setup environment
export PATH="$PATH:$HOME/.local/gfortran/bin:$HOME/.local/bin"
export LD_LIBRARY_PATH="$HOME/.local/gfortran/lib64:$HOME/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0"

# Use
fortran-run hello.f90
```
Appendix C – Functional test report

Test date: 2026‑05‑01
Compiler: GCC 14.2.0 gfortran on aarch64-unknown-linux-ohos

#	Test item	Result	Notes
1	Basic I/O	✅	print *, write(*,*) stdout normal
2	Mathematical built‑ins	✅	sin, cos, sqrt, exp, log, atan, abs, mod, max, min, floor, ceiling, nint, aint
3	File I/O	✅	open(r/w), close, iostat, error handling
4	Array operations	✅	constructors, slice, sum, minval, maxval, reshape
5	Character/string handling	✅	trim, len, len_trim, index, char, ichar, concatenation
6	Derived types & iso_c_binding	✅	type, bind(C), C_INT/C_DOUBLE/C_FLOAT
7	Format statements	✅	I0, F8.4, I5.3, implicit DO
8	Random numbers	✅	random_seed(size/put), random_number
9	Complex I/O	✅	internal file write, advance='no' non‑advancing I/O
10	Dynamic memory	✅	allocatable arrays, allocate/deallocate, 100×100 arrays
11	Functions & subroutines	✅	interface block, contains, intent(in)
12	Modules	✅	module/use, cross‑unit calls
13	Where / Pack / Merge	✅	where‑elsewhere, pack, merge array operations
14	Command‑line arguments	✅	command_argument_count, get_command_argument(0) program name

Conclusion: gfortran on HarmonyOS is fully functional. All core Fortran features work correctly, suitable for integration with R via dlopen().

Remaining limitations:

    OpenMP disabled (--disable-gomp)

    Coarrays not tested (libcaf_single.a present but not used)

    execute_command_line / system blocked by hmmac

    Standard input (read *) not tested under destructor execution mode
