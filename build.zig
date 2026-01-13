// =============================================================================
// build.zig - Zig Build System Configuration
// =============================================================================
//
// FOR TYPESCRIPT DEVELOPERS:
// --------------------------
// This file is analogous to combining several files you're familiar with:
//   - package.json (defines project name, scripts)
//   - tsconfig.json (defines compilation options)
//   - webpack.config.js or rollup.config.js (defines how to bundle/build)
//
// KEY DIFFERENCE: Instead of declarative JSON, Zig uses executable code to
// define builds. This gives you full programmatic control over the build process.
//
// WHAT THIS FILE DOES:
// 1. Defines how to compile our Zig code into a shared library (.dylib/.so/.dll)
// 2. Configures target platform (like cross-compilation)
// 3. Sets up test running with `zig build test`
//
// RUNNING THE BUILD:
//   zig build              -> Compiles the library
//   zig build test         -> Runs all unit tests
//   zig build -Doptimize=ReleaseFast  -> Optimized build for production
//
// =============================================================================

// -----------------------------------------------------------------------------
// IMPORTS
// -----------------------------------------------------------------------------
// In Zig, `@import` is a built-in function (note the @ prefix) that imports modules.
//
// TypeScript equivalent:
//   import * as std from 'std';
//
// The "std" module is Zig's standard library - similar to Node.js built-ins.
// It provides file I/O, networking, data structures, and more.
// -----------------------------------------------------------------------------
const std = @import("std");

// -----------------------------------------------------------------------------
// BUILD FUNCTION - Entry Point for `zig build`
// -----------------------------------------------------------------------------
// This is the main entry point that the Zig build system calls.
//
// TypeScript analogy:
//   export default function build(b: Build): void { ... }
//
// FUNCTION SIGNATURE BREAKDOWN:
//   - `pub` = public visibility (like `export` in TS)
//   - `fn` = function keyword
//   - `build` = function name
//   - `b: *std.Build` = parameter with explicit type
//   - `*` before a type means "pointer to" (like references in other languages)
//   - `void` = no return value
//
// The `*std.Build` parameter gives us access to the build system's API,
// letting us define compilation targets, add steps, configure options, etc.
// -----------------------------------------------------------------------------
pub fn build(b: *std.Build) void {
    // -------------------------------------------------------------------------
    // STEP 1: Define Target Platform
    // -------------------------------------------------------------------------
    // "Target" specifies WHAT system we're compiling FOR.
    //
    // TypeScript comparison:
    //   In TS/Node, you typically only run on one platform at a time.
    //   Zig can cross-compile: build Linux binaries on macOS, etc.
    //
    // `standardTargetOptions` reads the `-Dtarget=...` CLI flag.
    // Examples:
    //   zig build                          -> builds for current machine
    //   zig build -Dtarget=x86_64-linux    -> builds for Linux x64
    //   zig build -Dtarget=aarch64-macos   -> builds for Apple Silicon
    //
    // The `.{}` syntax creates an anonymous struct with default values.
    // Think of it like passing `{}` as options in JavaScript.
    // -------------------------------------------------------------------------
    const target = b.standardTargetOptions(.{});

    // -------------------------------------------------------------------------
    // STEP 2: Define Optimization Mode
    // -------------------------------------------------------------------------
    // Controls how aggressively the compiler optimizes code.
    //
    // TypeScript comparison:
    //   Similar to setting NODE_ENV=production vs development,
    //   or using terser/minification in your build.
    //
    // Zig optimization modes:
    //   - Debug (default): Fast compilation, includes debug info, runtime checks
    //   - ReleaseSafe: Optimized but keeps safety checks (like array bounds)
    //   - ReleaseFast: Maximum speed, removes safety checks (use carefully!)
    //   - ReleaseSmall: Optimizes for smallest binary size
    //
    // Usage:
    //   zig build -Doptimize=ReleaseFast
    // -------------------------------------------------------------------------
    const optimize = b.standardOptimizeOption(.{});

    // -------------------------------------------------------------------------
    // STEP 3: Define the Shared Library
    // -------------------------------------------------------------------------
    // We're building a SHARED LIBRARY (also called dynamic library):
    //   - .dylib on macOS
    //   - .so on Linux
    //   - .dll on Windows
    //
    // TypeScript comparison:
    //   This is like building an npm package that other projects can use,
    //   but at the native binary level. Think of it like building a native
    //   addon (.node file) that can be loaded via require() or import.
    //
    // The library exposes C-compatible functions (defined in lib.zig) that
    // can be called from ANY language: Node.js, Python, Ruby, C++, etc.
    //
    // `b.addLibrary()` returns a compilation step that we can configure.
    // -------------------------------------------------------------------------
    const lib = b.addLibrary(.{
        // Name of the output library.
        // Results in: libziggum.dylib (macOS), libziggum.so (Linux), ziggum.dll (Windows)
        .name = "ziggum",

        // .dynamic = shared library (loaded at runtime)
        // Alternative: .static = compiled directly into the final executable
        //
        // TypeScript analogy:
        //   Dynamic linking is like lazy-loading modules at runtime.
        //   Static linking is like bundling everything into one file.
        .linkage = .dynamic,

        // Create a module configuration for this library.
        // Modules in Zig are compilation units with their own settings.
        .root_module = b.createModule(.{
            // The entry point source file for compilation.
            // All other .zig files are pulled in via @import from this file.
            //
            // Think of this like the "main" field in package.json,
            // or the entry point in webpack config.
            .root_source_file = b.path("src/lib.zig"),

            // Apply the target and optimization settings we configured above.
            .target = target,
            .optimize = optimize,
        }),
    });

    // -------------------------------------------------------------------------
    // STEP 4: Install the Built Artifact
    // -------------------------------------------------------------------------
    // `installArtifact` tells the build system to copy the compiled library
    // to the output directory (zig-out/lib/ by default).
    //
    // TypeScript comparison:
    //   Like specifying "outDir" in tsconfig.json, or the output path in webpack.
    //
    // After running `zig build`, you'll find the library at:
    //   ./zig-out/lib/libziggum.dylib (or .so/.dll)
    // -------------------------------------------------------------------------
    b.installArtifact(lib);

    // =========================================================================
    // TEST CONFIGURATION
    // =========================================================================
    // Zig has built-in testing support. Any function marked with `test "name"`
    // in your source files becomes a runnable test.
    //
    // TypeScript comparison:
    //   Similar to Jest or Mocha, but built into the language.
    //   No need for separate test runners or configuration files.
    //
    // Running tests:
    //   zig build test
    // =========================================================================

    // -------------------------------------------------------------------------
    // Create a Test Compilation Step
    // -------------------------------------------------------------------------
    // `addTest` creates a special executable that runs all `test` blocks
    // found in the specified source file AND all files it imports.
    //
    // This means tests written in lib.zig, http_client.zig, tools.zig, etc.
    // are ALL discovered and run automatically!
    // -------------------------------------------------------------------------
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            // Start from lib.zig - tests in imported files are also included.
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // -------------------------------------------------------------------------
    // Create a Run Step for the Tests
    // -------------------------------------------------------------------------
    // `addRunArtifact` creates a build step that EXECUTES the compiled test binary.
    // This separates "compile tests" from "run tests" - useful for CI/CD.
    // -------------------------------------------------------------------------
    const run_unit_tests = b.addRunArtifact(unit_tests);

    // -------------------------------------------------------------------------
    // Register the "test" Command
    // -------------------------------------------------------------------------
    // `b.step()` creates a named build step that can be invoked from CLI.
    //
    // TypeScript comparison:
    //   Like adding a script to package.json:
    //   "scripts": { "test": "jest" }
    //
    // The second argument is the description shown in `zig build --help`.
    // -------------------------------------------------------------------------
    const test_step = b.step("test", "Run unit tests");

    // -------------------------------------------------------------------------
    // Wire Up Dependencies
    // -------------------------------------------------------------------------
    // `dependOn` creates a dependency chain: running the "test" step
    // will first run `run_unit_tests`, which depends on compiling `unit_tests`.
    //
    // TypeScript comparison:
    //   Like npm scripts that call other scripts:
    //   "test": "npm run build && jest"
    //
    // The `&` operator gets the address (pointer) of run_unit_tests.step,
    // because dependOn expects a pointer to a Step, not the Step itself.
    // -------------------------------------------------------------------------
    test_step.dependOn(&run_unit_tests.step);
}
