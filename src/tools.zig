// =============================================================================
// tools.zig - Tool Definitions and Execution for Claude
// =============================================================================
//
// FOR TYPESCRIPT DEVELOPERS:
// --------------------------
// This file implements "tools" (also called "functions" in OpenAI's API).
// Tools allow Claude to interact with the outside world by:
//   1. Reading files
//   2. Writing files
//   3. Running shell commands
//
// Think of this like implementing function calling for an LLM:
//   - getSchemas(): Returns the tool definitions (JSON schemas)
//   - dispatch(): Routes tool calls to the appropriate handler
//   - read_file(), write_file(), run_command(): The actual implementations
//
// TypeScript equivalent architecture:
//   const tools = {
//     read_file: { schema: {...}, handler: async (args) => {...} },
//     write_file: { schema: {...}, handler: async (args) => {...} },
//     run_command: { schema: {...}, handler: async (args) => {...} },
//   };
//
// KEY CONCEPTS DEMONSTRATED:
// 1. Multi-line string literals (raw strings)
// 2. File I/O operations
// 3. Process spawning (running shell commands)
// 4. Dynamic dispatch based on string matching
// 5. JSON schema definitions for tool parameters
//
// =============================================================================

const std = @import("std");
const types = @import("providers/types.zig");

// =============================================================================
// getSchemas - Return tool definitions for Claude
// =============================================================================
// Returns an array of Tool structs that describe what tools are available
// and how to call them. These schemas are sent to Claude so it knows what
// tools it can use and what arguments each tool expects.
//
// JSON SCHEMA:
// ------------
// Each tool has an input_schema that follows JSON Schema format.
// This tells Claude:
//   - What type of input to provide ("object" with "properties")
//   - What fields are available and their types
//   - Which fields are required
//   - Human-readable descriptions for each field
//
// TypeScript equivalent:
//   function getSchemas(): Tool[] {
//     return [
//       {
//         name: 'read_file',
//         description: 'Read a file...',
//         input_schema: { type: 'object', properties: {...}, required: [...] }
//       },
//       ...
//     ];
//   }
//
// MEMORY OWNERSHIP:
// -----------------
// Returns an owned slice - caller must free with allocator.free() when done.
// The Tool structs contain string literals (compile-time constants), so
// only the array itself needs to be freed, not the individual strings.
// =============================================================================
pub fn getSchemas(allocator: std.mem.Allocator) ![]types.Tool {
    // Create an ArrayList with pre-allocated capacity for our 3 tools
    var tools_list = try std.ArrayList(types.Tool).initCapacity(allocator, 3);

    // -------------------------------------------------------------------------
    // TOOL 1: read_file
    // -------------------------------------------------------------------------
    // Reads the contents of a file and returns them as text.
    //
    // MULTI-LINE STRING LITERALS:
    // ---------------------------
    // The `\\` prefix starts a multi-line string literal in Zig.
    // Each line must start with `\\` and the literal continues until a line
    // doesn't start with `\\`.
    //
    // This is MUCH cleaner than escaping quotes in a regular string:
    //   "{\"type\": \"object\"...}"  // Escaped - hard to read!
    //   \\{ "type": "object"...      // Multi-line - readable!
    //
    // TypeScript equivalent:
    //   const schema = `{
    //     "type": "object",
    //     "properties": {
    //       "path": { "type": "string", "description": "..." }
    //     },
    //     "required": ["path"]
    //   }`;
    // -------------------------------------------------------------------------
    try tools_list.append(allocator, .{
        .name = "read_file",
        .description = "Read the contents of a file from disk.",
        .input_schema_json =
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "path": {
        \\      "type": "string",
        \\      "description": "The absolute or relative path to the file."
        \\    }
        \\  },
        \\  "required": ["path"]
        \\}
        ,
    });

    // -------------------------------------------------------------------------
    // TOOL 2: write_file
    // -------------------------------------------------------------------------
    // Creates or overwrites a file with the specified content.
    // -------------------------------------------------------------------------
    try tools_list.append(allocator, .{
        .name = "write_file",
        .description = "Write or overwrite a file with specific content.",
        .input_schema_json =
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "path": {
        \\      "type": "string",
        \\      "description": "The path to the file to create or overwrite."
        \\    },
        \\    "content": {
        \\      "type": "string",
        \\      "description": "The content to write to the file."
        \\    }
        \\  },
        \\  "required": ["path", "content"]
        \\}
        ,
    });

    // -------------------------------------------------------------------------
    // TOOL 3: run_command
    // -------------------------------------------------------------------------
    // Executes a shell command and returns stdout.
    // Uses /bin/sh on Unix systems.
    // -------------------------------------------------------------------------
    try tools_list.append(allocator, .{
        .name = "run_command",
        .description = "Execute a shell command and return its output.",
        .input_schema_json =
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "command": {
        \\      "type": "string",
        \\      "description": "The shell command to execute."
        \\    }
        \\  },
        \\  "required": ["command"]
        \\}
        ,
    });

    // Convert ArrayList to a plain slice and return
    // toOwnedSlice transfers ownership to the caller
    return try tools_list.toOwnedSlice(allocator);
}

// =============================================================================
// read_file - Read a file's contents
// =============================================================================
// Opens a file and reads its entire contents into memory.
//
// PARAMETERS:
//   allocator: Used to allocate the buffer for file contents
//   path: Path to the file (relative to current working directory)
//
// RETURNS:
//   Owned slice containing file contents. Caller must free!
//
// ERRORS:
//   - FileNotFound: File doesn't exist
//   - AccessDenied: Permission denied
//   - OutOfMemory: File too large or allocation failed
//
// TypeScript equivalent:
//   async function read_file(path: string): Promise<string> {
//     return await fs.readFile(path, 'utf8');
//   }
//
// ZIG FILE I/O PATTERN:
// ---------------------
// 1. std.fs.cwd() gets the current working directory as a Dir
// 2. .openFile() opens a file relative to that directory
// 3. defer file.close() ensures cleanup
// 4. .readToEndAlloc() reads everything into a new allocation
// =============================================================================
pub fn read_file(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    // Open the file relative to current working directory
    // The `.{}` are default open options (read-only)
    const file = try std.fs.cwd().openFile(path, .{});
    // Ensure file is closed when we leave this scope
    defer file.close();

    // Read entire file into memory
    // Second parameter is max size - std.math.maxInt(usize) means "no limit"
    // In practice, you might want a reasonable limit to prevent OOM
    //
    // NOTE: This loads the ENTIRE file into memory. For very large files,
    // you'd want streaming reads instead.
    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

// =============================================================================
// write_file - Write content to a file
// =============================================================================
// Creates or overwrites a file with the specified content.
//
// PARAMETERS:
//   path: Path to the file to create/overwrite
//   content: The content to write
//
// RETURNS: void (nothing on success)
//
// ERRORS:
//   - AccessDenied: Permission denied
//   - NoSpaceLeft: Disk full
//   - etc.
//
// TypeScript equivalent:
//   async function write_file(path: string, content: string): Promise<void> {
//     await fs.writeFile(path, content);
//   }
//
// NOTE: This function doesn't need an allocator because it doesn't allocate
// any new memory - it just writes the provided content to disk.
// =============================================================================
pub fn write_file(path: []const u8, content: []const u8) !void {
    // Create or truncate the file
    // .{} uses default options (write mode, truncate if exists, create if not)
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    // Write all content to the file
    // writeAll ensures everything is written, handling partial writes
    try file.writeAll(content);
}

// =============================================================================
// run_command - Execute a shell command
// =============================================================================
// Spawns a shell process to execute a command and captures its output.
//
// PARAMETERS:
//   allocator: Used to allocate buffers for stdout/stderr
//   cmd: The command to execute (passed to /bin/sh -c)
//
// RETURNS:
//   Owned slice containing stdout. Caller must free!
//
// TypeScript equivalent:
//   import { exec } from 'child_process';
//   async function run_command(cmd: string): Promise<string> {
//     return new Promise((resolve, reject) => {
//       exec(cmd, (err, stdout) => err ? reject(err) : resolve(stdout));
//     });
//   }
//
// PROCESS SPAWNING IN ZIG:
// ------------------------
// 1. std.process.Child represents a child process
// 2. .init() configures it with argv and settings
// 3. stdout_behavior = .Pipe captures stdout
// 4. .spawn() starts the process
// 5. Read from stdout pipe
// 6. .wait() waits for completion and gets exit status
//
// SECURITY NOTE:
// --------------
// This executes arbitrary shell commands! In production, you'd want:
//   - Input validation
//   - Sandboxing
//   - Timeouts
//   - Resource limits
// =============================================================================
pub fn run_command(allocator: std.mem.Allocator, cmd: []const u8) ![]u8 {
    // -------------------------------------------------------------------------
    // Configure the child process
    // -------------------------------------------------------------------------
    // We use /bin/sh -c to execute the command through a shell.
    // This allows shell features like pipes, redirects, etc.
    //
    // The &[_][]const u8{...} syntax creates an array of string slices
    // (the argv for the child process).
    // -------------------------------------------------------------------------
    var child = std.process.Child.init(
        &[_][]const u8{ "/bin/sh", "-c", cmd },
        allocator,
    );

    // Configure stdout/stderr to be captured via pipes
    // .Pipe means "create a pipe I can read from"
    // Other options: .Inherit (pass through), .Close (discard), .Ignore
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    // -------------------------------------------------------------------------
    // Start the process
    // -------------------------------------------------------------------------
    // spawn() forks and execs the child process.
    // After this, the process is running in parallel!
    // -------------------------------------------------------------------------
    try child.spawn();

    // -------------------------------------------------------------------------
    // Read stdout
    // -------------------------------------------------------------------------
    // child.stdout is now a readable pipe connected to the child's stdout.
    // We read everything into memory.
    //
    // Note: The `.?` is the optional unwrap operator - stdout is optional
    // because it depends on stdout_behavior. Since we set it to .Pipe,
    // we know it exists.
    // -------------------------------------------------------------------------
    const stdout = try child.stdout.?.readToEndAlloc(allocator, std.math.maxInt(usize));
    errdefer allocator.free(stdout); // Free on error

    // Read stderr too (we discard it, but must read to prevent blocking)
    const stderr = try child.stderr.?.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(stderr); // Always free stderr

    // -------------------------------------------------------------------------
    // Wait for process to complete
    // -------------------------------------------------------------------------
    // wait() blocks until the child exits and returns the exit status.
    // We ignore the status here, but you might want to check it:
    //   if (result.term.Exited != 0) return error.CommandFailed;
    // -------------------------------------------------------------------------
    _ = try child.wait();

    return stdout;
}

// =============================================================================
// dispatch - Route a tool call to the appropriate handler
// =============================================================================
// Given a tool name and arguments (as parsed JSON), executes the tool
// and returns the result.
//
// This is the "router" that connects Claude's tool_use requests to our
// actual implementations.
//
// PARAMETERS:
//   allocator: For any allocations needed
//   name: Tool name (e.g., "read_file")
//   args: Tool arguments as a parsed JSON value (expected to be an object)
//
// RETURNS:
//   Owned string slice with the result. Caller must free!
//
// TypeScript equivalent:
//   async function dispatch(name: string, args: JsonObject): Promise<string> {
//     switch (name) {
//       case 'read_file': return await read_file(args.path);
//       case 'write_file':
//         await write_file(args.path, args.content);
//         return 'File written successfully';
//       case 'run_command': return await run_command(args.command);
//       default: throw new Error('Unknown tool');
//     }
//   }
//
// PATTERN MATCHING ON STRINGS:
// ----------------------------
// Zig doesn't have switch on strings (strings aren't compile-time constants).
// Instead, we use if-else with std.mem.eql for string comparison.
// =============================================================================
pub fn dispatch(
    allocator: std.mem.Allocator,
    name: []const u8,
    args: std.json.Value,
) ![]u8 {
    // -------------------------------------------------------------------------
    // READ_FILE tool
    // -------------------------------------------------------------------------
    if (std.mem.eql(u8, name, "read_file")) {
        // Extract the "path" argument from the JSON object
        // args.object.get() returns an optional - null if key doesn't exist
        const path = args.object.get("path") orelse return error.MissingArgument;

        // path is a json.Value, .string extracts the string slice
        return try read_file(allocator, path.string);
    }
    // -------------------------------------------------------------------------
    // WRITE_FILE tool
    // -------------------------------------------------------------------------
    else if (std.mem.eql(u8, name, "write_file")) {
        const path = args.object.get("path") orelse return error.MissingArgument;
        const content = args.object.get("content") orelse return error.MissingArgument;

        // write_file doesn't return anything meaningful
        try write_file(path.string, content.string);

        // Return a confirmation message
        // allocator.dupe creates an owned copy of the string literal
        // (string literals have static lifetime, but we need to return
        // something the caller can free, for consistency)
        return try allocator.dupe(u8, "File written successfully");
    }
    // -------------------------------------------------------------------------
    // RUN_COMMAND tool
    // -------------------------------------------------------------------------
    else if (std.mem.eql(u8, name, "run_command")) {
        const cmd = args.object.get("command") orelse return error.MissingArgument;

        return try run_command(allocator, cmd.string);
    }
    // -------------------------------------------------------------------------
    // UNKNOWN TOOL
    // -------------------------------------------------------------------------
    else {
        return error.UnknownTool;
    }
}

// =============================================================================
// UNIT TESTS
// =============================================================================
// These tests verify our tools work correctly. They're run with `zig build test`.
//
// TEST ISOLATION:
// ---------------
// Good tests are isolated - they don't affect each other. Our file tests
// create temporary files and clean them up with `defer`.
//
// std.testing.allocator:
// ----------------------
// A special allocator that fails the test if memory is leaked.
// This is incredibly useful for catching memory management bugs!
// =============================================================================

// Test read_file and write_file together (round trip)
test "file i/o tools" {
    const allocator = std.testing.allocator;

    // Test data
    const test_path = "test_io.txt";
    const test_content = "hello tools";

    // Write a test file
    try write_file(test_path, test_content);

    // Ensure we clean up the test file, even if the test fails
    // std.fs.cwd().deleteFile removes the file
    defer std.fs.cwd().deleteFile(test_path) catch {};

    // Read it back
    const read = try read_file(allocator, test_path);
    defer allocator.free(read); // Free the read buffer

    // Verify contents match
    // expectEqualStrings gives nice diff output on failure
    try std.testing.expectEqualStrings(test_content, read);
}

// Test the dispatch function
test "tool dispatch" {
    const allocator = std.testing.allocator;

    // Create JSON arguments as a string and parse them
    // This simulates what Claude would send us
    const json_text = "{\"path\": \"test_dispatch.txt\", \"content\": \"dispatch work\"}";
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    // Dispatch the write_file tool
    const result = try dispatch(allocator, "write_file", parsed.value);
    defer allocator.free(result);

    // Clean up test file
    defer std.fs.cwd().deleteFile("test_dispatch.txt") catch {};

    // Verify the file was actually written
    const read = try read_file(allocator, "test_dispatch.txt");
    defer allocator.free(read);

    try std.testing.expectEqualStrings("dispatch work", read);
}
