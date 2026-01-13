// =============================================================================
// fs_utils.zig - File System Utilities
// =============================================================================
//
// FOR TYPESCRIPT DEVELOPERS:
// --------------------------
// This file provides utility functions for file system operations, specifically
// for managing the configuration directory and file paths.
//
// TypeScript equivalent concepts:
//   - path.join() for building paths
//   - os.homedir() for getting home directory
//   - fs.mkdir() for creating directories
//   - fs.chmod() for setting file permissions
//
// KEY CONCEPTS DEMONSTRATED:
// 1. Cross-platform code (Windows vs Unix handling)
// 2. Environment variable access
// 3. POSIX system calls from Zig
// 4. Octal file permissions (Unix concepts)
// 5. Compile-time conditional compilation
//
// =============================================================================

const std = @import("std");
const builtin = @import("builtin");

// =============================================================================
// CONFIG PATH STRUCT
// =============================================================================
// A simple struct to return both the config directory and file paths.
//
// TypeScript equivalent:
//   interface ConfigPath {
//     dir: string;   // e.g., "/home/user/.config/ziggum"
//     file: string;  // e.g., "/home/user/.config/ziggum/config.json"
//   }
//
// WHY RETURN BOTH?
// ----------------
// The caller often needs both:
// - The directory to ensure it exists (ensureConfigDir)
// - The file path to read/write the config
//
// Returning both saves redundant path computation.
// =============================================================================
pub const ConfigPath = struct {
    dir: []const u8, // Path to the config directory
    file: []const u8, // Full path to the config file
};

// =============================================================================
// getConfigPath - Get the config file location
// =============================================================================
// Returns the paths for the config directory and file.
//
// PATH STRUCTURE:
//   $HOME/.config/ziggum/config.json
//
// This follows the XDG Base Directory Specification, which is the standard
// for Unix-like systems. Windows would typically use %APPDATA%.
//
// RETURN TYPE: `!ConfigPath`
// --------------------------
// The `!` means this can return an error (e.g., HOME not found, OOM).
//
// MEMORY OWNERSHIP:
// -----------------
// CRITICAL: The returned paths are ALLOCATED strings. The caller MUST free
// both `dir` and `file` when done using `allocator.free()`.
//
// TypeScript equivalent:
//   function getConfigPath(): { dir: string; file: string } {
//     const home = process.env.HOME || os.homedir();
//     return {
//       dir: path.join(home, '.config', 'ziggum'),
//       file: path.join(home, '.config', 'ziggum', 'config.json')
//     };
//   }
// =============================================================================
pub fn getConfigPath(allocator: std.mem.Allocator) !ConfigPath {
    // -------------------------------------------------------------------------
    // Get the HOME environment variable
    // -------------------------------------------------------------------------
    // std.process.getEnvVarOwned reads an environment variable and allocates
    // a copy of its value. "Owned" means the caller owns the memory.
    //
    // TypeScript: process.env.HOME
    //
    // ERROR HANDLING:
    // If HOME isn't set (rare but possible), we return a custom error.
    // Other errors (like allocation failure) are propagated.
    // -------------------------------------------------------------------------
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            // HOME not found - can't determine config location.
            // On Windows, we'd want to check USERPROFILE or APPDATA instead.
            return error.HomeNotFound;
        }
        return err; // Propagate other errors (e.g., OutOfMemory)
    };
    // Free the home string when we're done with it.
    // We only use it to build longer paths, then we don't need it anymore.
    defer allocator.free(home);

    // -------------------------------------------------------------------------
    // Build the config directory path
    // -------------------------------------------------------------------------
    // std.fs.path.join is like Node's path.join() - it concatenates path
    // segments with the correct separator for the current OS.
    //
    // The &[_][]const u8{ ... } syntax creates an array of string slices.
    // - `&` = take a pointer (join expects a pointer to array)
    // - `[_]` = array with inferred length
    // - `[]const u8` = each element is a string slice
    //
    // TypeScript: path.join(home, '.config', 'ziggum')
    // -------------------------------------------------------------------------
    const config_dir = try std.fs.path.join(allocator, &[_][]const u8{
        home,
        ".config",
        "ziggum",
    });
    // errdefer runs ONLY if an error occurs later in this function.
    // This ensures we don't leak config_dir if the next join fails.
    errdefer allocator.free(config_dir);

    // -------------------------------------------------------------------------
    // Build the config file path
    // -------------------------------------------------------------------------
    // Append "config.json" to the directory path.
    // -------------------------------------------------------------------------
    const config_file = try std.fs.path.join(allocator, &[_][]const u8{
        config_dir,
        "config.json",
    });

    // Return both paths. Caller is responsible for freeing them!
    return ConfigPath{
        .dir = config_dir,
        .file = config_file,
    };
}

// =============================================================================
// ensureConfigDir - Create the config directory if it doesn't exist
// =============================================================================
// Creates the config directory with appropriate permissions.
//
// CROSS-PLATFORM HANDLING:
// ------------------------
// This function demonstrates Zig's compile-time branching for platform-specific
// code. The `if (builtin.os.tag == .windows)` is evaluated at COMPILE TIME,
// meaning the unused branch is completely removed from the binary.
//
// TypeScript equivalent:
//   async function ensureConfigDir(path: string): Promise<void> {
//     await fs.mkdir(path, { recursive: true, mode: 0o700 });
//   }
//
// UNIX PERMISSIONS EXPLAINED:
// ---------------------------
// 0o700 is an octal number (note the 0o prefix) representing:
//   7 = rwx (read, write, execute) for owner
//   0 = --- (no permissions) for group
//   0 = --- (no permissions) for others
//
// This means only the owner can access the directory - important for security
// since it will contain API keys.
//
// PARAMETER: `path: []const u8`
// A string slice containing the directory path to create.
// =============================================================================
pub fn ensureConfigDir(path: []const u8) !void {
    // -------------------------------------------------------------------------
    // Windows implementation
    // -------------------------------------------------------------------------
    // On Windows, we use the standard library's cross-platform mkdir.
    // Windows doesn't use Unix-style permissions, so we use simpler API.
    //
    // COMPILE-TIME BRANCHING:
    // `builtin.os.tag` is a compile-time constant. This `if` is evaluated
    // at compile time, and only one branch is included in the final binary.
    // This is like C's #ifdef but type-safe and within the language.
    // -------------------------------------------------------------------------
    if (builtin.os.tag == .windows) {
        std.fs.makeDirAbsolute(path) catch |err| {
            // PathAlreadyExists is fine - the directory already exists.
            // Any other error is a real problem.
            if (err != error.PathAlreadyExists) return err;
        };
    } else {
        // ---------------------------------------------------------------------
        // Unix implementation (macOS, Linux, etc.)
        // ---------------------------------------------------------------------
        // On Unix, we use POSIX mkdir directly to set permissions atomically.
        //
        // std.posix.mkdir is a thin wrapper around the mkdir() syscall.
        // It takes the path and permission mode as arguments.
        //
        // WHY USE POSIX DIRECTLY?
        // The std.fs.makeDirAbsolute doesn't let us set permissions on creation.
        // Using POSIX mkdir lets us create with the correct mode atomically,
        // avoiding a race condition between mkdir and chmod.
        // ---------------------------------------------------------------------
        std.posix.mkdir(path, 0o700) catch |err| {
            // Directory already exists - that's OK!
            if (err != error.PathAlreadyExists) return err;
        };
    }
}

// =============================================================================
// ensureConfigFilePerms - Set secure permissions on the config file
// =============================================================================
// Sets the config file permissions to 0600 (owner read/write only).
//
// WHY THIS MATTERS:
// -----------------
// The config file contains the Anthropic API key. If other users on the
// system could read it, they could steal the key. Setting 0600 ensures
// only the owner can access the file.
//
// UNIX PERMISSIONS 0600:
//   6 = rw- (read, write, no execute) for owner
//   0 = --- (no permissions) for group
//   0 = --- (no permissions) for others
//
// TypeScript equivalent:
//   await fs.chmod(path, 0o600);
//
// NOTE ON WINDOWS:
// ----------------
// Windows doesn't use Unix-style permissions. It has ACLs (Access Control Lists)
// which are more complex. For simplicity, this function does nothing on Windows.
// A production app might want to use Windows security APIs.
// =============================================================================
pub fn ensureConfigFilePerms(path: []const u8) !void {
    // On Windows, permissions work differently (ACLs). Skip for now.
    if (builtin.os.tag == .windows) return;

    // -------------------------------------------------------------------------
    // Change file permissions using fchmodat
    // -------------------------------------------------------------------------
    // fchmodat is a POSIX function for changing file permissions.
    // It's like chmod but with more options (relative paths, flags).
    //
    // PARAMETERS:
    //   AT.FDCWD = "at the current working directory" - a special constant
    //              that tells fchmodat to interpret the path relative to cwd
    //              (but our path is absolute, so this doesn't matter)
    //   path     = the file path to change
    //   0o600    = the new permission mode
    //   0        = flags (0 = no special flags)
    //
    // WHY FCHMODAT INSTEAD OF CHMOD?
    // fchmodat is more flexible and can handle file descriptors.
    // Zig's std.posix exposes it, making it available cross-platform on Unix.
    // -------------------------------------------------------------------------
    try std.posix.fchmodat(
        std.posix.AT.FDCWD, // Use current directory as base (path is absolute anyway)
        path, // Path to the file
        0o600, // Owner read/write only
        0, // No flags
    );
}
