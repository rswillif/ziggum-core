// =============================================================================
// lib.zig - Main Library Entry Point & C FFI Exports
// =============================================================================
//
// FOR TYPESCRIPT DEVELOPERS:
// --------------------------
// This file serves multiple purposes:
//   1. Acts as the "main" entry point for the library (like index.ts)
//   2. Defines the Agent struct - the core class of this application
//   3. Exports C-compatible functions for Foreign Function Interface (FFI)
//
// FFI EXPLANATION:
// ----------------
// FFI allows code written in one language to call code in another language.
// The `export fn` functions at the bottom of this file create a C ABI
// (Application Binary Interface) that can be called from:
//   - Node.js via node-ffi-napi or Koffi
//   - Python via ctypes or cffi
//   - Any language that can call C functions
//
// TypeScript analogy:
//   Imagine if you could `require()` a compiled Rust/C++ library directly.
//   That's what FFI enables. The Zig library becomes a .dylib/.so/.dll
//   that Node.js can load and call functions from.
//
// MULTI-AUTH SUPPORT:
// -------------------
// This library supports multiple authentication methods:
//   1. API Key auth (zg_init) - Traditional pay-as-you-go
//   2. OAuth/Bearer token auth (zg_init_oauth) - Subscription services
//
// This allows integration with both direct API access AND subscription-based
// services like Claude Code Pro/Max.
//
// =============================================================================

// =============================================================================
// IMPORTS
// =============================================================================
// Zig uses @import to bring in other modules. Unlike TypeScript's static imports,
// @import is a compile-time built-in function that the compiler evaluates.
//
// TypeScript equivalent:
//   import * as std from 'std';
//   import * as types from './providers/types';
//   import * as http_client from './http_client';
//   import * as tools from './tools';
//   import * as json_utils from './json_utils';
// =============================================================================

const std = @import("std"); // Standard library - like Node.js built-ins
const types = @import("providers/types.zig"); // Type definitions (Message, Provider, etc.)
const http_client = @import("http_client.zig"); // HTTP client for API calls
const tools = @import("tools.zig"); // Tool definitions and execution
const json_utils = @import("json_utils.zig"); // JSON deep copy and free utilities

// =============================================================================
// AGENT STRUCT
// =============================================================================
// In Zig, a `struct` is similar to a TypeScript class, but with some key differences:
//   - No inheritance (use composition instead)
//   - No constructors (use a static `init` function by convention)
//   - Methods are just functions that take `self` as the first parameter
//   - Memory management is explicit - you decide when to allocate/free
//
// TypeScript equivalent (conceptually):
//   class Agent {
//     private allocator: Allocator;
//     private provider: Provider;
//     private history: Message[];
//     // ...
//   }
//
// AUTHENTICATION MODES:
// ---------------------
// The Agent supports multiple Provider types, each with different auth:
//   - anthropic: Uses API key (x-api-key header)
//   - anthropic_oauth: Uses Bearer token (Authorization header)
//   - ollama: No auth (local server)
//   - mock: No auth (testing)
//
// =============================================================================
pub const Agent = struct {
    // -------------------------------------------------------------------------
    // FIELDS
    // -------------------------------------------------------------------------
    // Zig struct fields are declared with `name: Type` syntax.
    // Unlike TypeScript, there's no `private` keyword - convention uses
    // documentation and naming to indicate visibility.
    // -------------------------------------------------------------------------

    // GeneralPurposeAllocator (GPA) is Zig's "smart" allocator.
    // TypeScript comparison: In JS, memory is managed by the garbage collector.
    // In Zig, YOU manage memory. The GPA helps detect leaks and use-after-free bugs.
    //
    // The `.{}` inside the type is for compile-time configuration options.
    // It's like `new GeneralPurposeAllocator({ /* default options */ })`.
    gpa: std.heap.GeneralPurposeAllocator(.{}),

    // An Allocator interface - used for ALL memory allocations in this struct.
    // TypeScript analogy: Think of this as an injected dependency for memory ops.
    // Instead of `new Array()`, Zig code does `allocator.alloc(T, count)`.
    allocator: std.mem.Allocator,

    // The AI provider configuration (Anthropic, Anthropic OAuth, Ollama, or Mock).
    // This is a "tagged union" - similar to TypeScript discriminated unions:
    //   type Provider =
    //     | { type: 'anthropic', apiKey: string }
    //     | { type: 'anthropic_oauth', accessToken: string }
    //     | { type: 'ollama', ... }
    provider: types.Provider,

    // Message history - stores the conversation.
    // ArrayList is Zig's dynamic array, similar to JavaScript arrays.
    // TypeScript equivalent: Message[]
    history: std.ArrayList(types.Message),

    // Tool schemas for Claude's tool-use feature.
    // This is a slice (pointer + length) to an array of Tool structs.
    // TypeScript equivalent: readonly Tool[]
    tools_schemas: []const types.Tool,

    // -------------------------------------------------------------------------
    // RESPONSE BUFFERING
    // -------------------------------------------------------------------------
    // For FFI, we buffer the full response and let the caller read it in chunks.
    // This simplifies the C ABI - the caller can read until they get 0 bytes.
    //
    // TypeScript analogy:
    //   private responseBuffer: string | null = null;
    //   private responsePosition: number = 0;
    // -------------------------------------------------------------------------

    // Optional buffer holding the current response text.
    // The `?` makes this an optional type - like `string | null` in TypeScript.
    // `[]const u8` is a slice of bytes - Zig's representation of strings.
    current_response_buffer: ?[]const u8 = null,

    // Current read position within the response buffer.
    response_pos: usize = 0,

    // =========================================================================
    // STATIC METHODS (No self parameter)
    // =========================================================================

    // -------------------------------------------------------------------------
    // init - Constructor Function (API Key Authentication)
    // -------------------------------------------------------------------------
    // Zig convention: Use a static `init` function instead of constructors.
    // This function allocates and initializes a new Agent with API key auth.
    //
    // RETURN TYPE EXPLANATION:
    // `!*Agent` means "returns a pointer to Agent, OR an error".
    // The `!` is Zig's error union syntax.
    //
    // TypeScript equivalent:
    //   static async init(apiKey: string): Promise<Agent> { ... }
    //
    // WHY RETURN A POINTER?
    // We allocate the Agent on the heap so it can outlive this function.
    // The pointer lets us pass the Agent across the FFI boundary to other languages.
    //
    // USE CASE:
    // This init function is for traditional API key authentication.
    // For OAuth/subscription auth, use initWithOAuth instead.
    // -------------------------------------------------------------------------
    pub fn init(api_key: []const u8) !*Agent {
        // ---------------------------------------------------------------------
        // STEP 1: Allocate the Agent struct itself using page_allocator
        // ---------------------------------------------------------------------
        // page_allocator is the simplest allocator - it gets memory directly
        // from the operating system in page-sized chunks (usually 4KB).
        //
        // We use page_allocator for the Agent struct because:
        // 1. The Agent owns its own GPA, so we can't use the GPA to allocate it
        // 2. The Agent lives for the entire session, so page overhead is fine
        //
        // TypeScript analogy:
        //   const agent = new Agent(); // JS does this implicitly
        // ---------------------------------------------------------------------
        const agent = try std.heap.page_allocator.create(Agent);

        // ---------------------------------------------------------------------
        // STEP 2: Initialize the General Purpose Allocator
        // ---------------------------------------------------------------------
        // The GPA is a more sophisticated allocator that:
        // - Tracks allocations to detect memory leaks
        // - Validates frees to catch double-free bugs
        // - Can be configured for debugging or performance
        //
        // The `{}` creates a default-initialized GPA.
        // ---------------------------------------------------------------------
        agent.gpa = std.heap.GeneralPurposeAllocator(.{}){};

        // Get an Allocator interface from the GPA.
        // This is Zig's dependency injection pattern for memory management.
        agent.allocator = agent.gpa.allocator();

        // Capture the allocator in a local variable for convenience.
        const allocator = agent.allocator;

        // ---------------------------------------------------------------------
        // STEP 3: Set up the Provider (Anthropic with API Key)
        // ---------------------------------------------------------------------
        // We're creating an Anthropic provider with the given API key.
        //
        // IMPORTANT: `allocator.dupe(u8, api_key)` creates a COPY of the string.
        // This is necessary because:
        // 1. The caller might free their copy of api_key after init returns
        // 2. We need to own this memory so we can free it in deinit
        //
        // TypeScript analogy:
        //   this.provider = { type: 'anthropic', apiKey: apiKey.slice() };
        // ---------------------------------------------------------------------
        agent.provider = .{
            .anthropic = .{
                .api_key = try allocator.dupe(u8, api_key),
                .model = "claude-3-5-sonnet-latest",
            },
        };

        // ---------------------------------------------------------------------
        // STEP 4: Initialize the message history
        // ---------------------------------------------------------------------
        // ArrayList needs to be initialized before use.
        // `{}` creates an empty ArrayList - it will allocate when items are added.
        //
        // TypeScript analogy:
        //   this.history = [];
        // ---------------------------------------------------------------------
        agent.history = std.ArrayList(types.Message){};

        // ---------------------------------------------------------------------
        // STEP 5: Load tool schemas
        // ---------------------------------------------------------------------
        // Get the schemas for tools (read_file, write_file, run_command).
        // These tell Claude what tools are available and how to call them.
        //
        // TypeScript analogy:
        //   this.toolsSchemas = await tools.getSchemas();
        // ---------------------------------------------------------------------
        agent.tools_schemas = try tools.getSchemas(allocator);

        // Initialize response buffer state.
        agent.current_response_buffer = null;
        agent.response_pos = 0;

        return agent;
    }

    // -------------------------------------------------------------------------
    // initWithOAuth - Constructor Function (OAuth/Bearer Token Authentication)
    // -------------------------------------------------------------------------
    // Creates a new Agent using OAuth Bearer token authentication.
    // This is used for subscription-based services like Claude Code Pro/Max.
    //
    // DIFFERENCE FROM init():
    // - init() uses API key auth (x-api-key header)
    // - initWithOAuth() uses Bearer token auth (Authorization header)
    //
    // PARAMETERS:
    //   access_token: OAuth access token from authentication flow
    //   refresh_token: (optional) Token to obtain new access tokens
    //   base_url: (optional) Custom API endpoint for enterprise deployments
    //
    // TypeScript equivalent:
    //   static async initWithOAuth(
    //     accessToken: string,
    //     refreshToken?: string,
    //     baseUrl?: string
    //   ): Promise<Agent> { ... }
    //
    // TOKEN SOURCES:
    // --------------
    // 1. Claude Code CLI: Run `claude` then `/login`, tokens in ~/.claude/credentials.json
    // 2. Environment variable: ANTHROPIC_AUTH_TOKEN
    // 3. Custom OAuth flow: Your own authentication implementation
    //
    // WHY OAUTH?
    // ----------
    // OAuth/Bearer tokens are used by subscription services because:
    // 1. They can be short-lived (better security than long-lived API keys)
    // 2. They support token refresh without re-authentication
    // 3. They integrate with SSO/enterprise identity providers
    // 4. Billing is through subscription, not per-token usage
    // -------------------------------------------------------------------------
    pub fn initWithOAuth(
        access_token: []const u8,
        refresh_token: ?[]const u8,
        base_url: ?[]const u8,
    ) !*Agent {
        // Allocate the Agent struct using page_allocator
        const agent = try std.heap.page_allocator.create(Agent);

        // Initialize the General Purpose Allocator
        agent.gpa = std.heap.GeneralPurposeAllocator(.{}){};
        agent.allocator = agent.gpa.allocator();
        const allocator = agent.allocator;

        // ---------------------------------------------------------------------
        // Set up the Provider (Anthropic with OAuth)
        // ---------------------------------------------------------------------
        // We're creating an anthropic_oauth provider variant.
        // This uses Bearer token authentication instead of API key.
        //
        // OPTIONAL FIELDS:
        // refresh_token and base_url are optional (?[]const u8).
        // We only allocate copies if they have values.
        //
        // TypeScript:
        //   this.provider = {
        //     type: 'anthropic_oauth',
        //     accessToken: accessToken,
        //     refreshToken: refreshToken ?? undefined,
        //     baseUrl: baseUrl ?? undefined,
        //     model: 'claude-3-5-sonnet-latest'
        //   };
        // ---------------------------------------------------------------------
        agent.provider = .{
            .anthropic_oauth = .{
                .access_token = try allocator.dupe(u8, access_token),
                .refresh_token = if (refresh_token) |rt|
                    try allocator.dupe(u8, rt)
                else
                    null,
                .model = "claude-3-5-sonnet-latest",
                .base_url = if (base_url) |url|
                    try allocator.dupe(u8, url)
                else
                    null,
            },
        };

        // Initialize message history and tools (same as API key init)
        agent.history = std.ArrayList(types.Message){};
        agent.tools_schemas = try tools.getSchemas(allocator);
        agent.current_response_buffer = null;
        agent.response_pos = 0;

        return agent;
    }

    // -------------------------------------------------------------------------
    // initWithProvider - Constructor Function (Generic Provider)
    // -------------------------------------------------------------------------
    // Creates a new Agent with any Provider type.
    // This is the most flexible init function - it accepts a pre-configured
    // Provider tagged union, allowing any authentication method.
    //
    // PARAMETERS:
    //   provider: A fully configured Provider tagged union
    //
    // TypeScript equivalent:
    //   static async initWithProvider(provider: Provider): Promise<Agent> { ... }
    //
    // USE CASES:
    // ----------
    // 1. Mock provider for testing
    // 2. Ollama for local models
    // 3. Custom provider configurations
    // 4. When you've already parsed config and built a Provider
    //
    // MEMORY OWNERSHIP:
    // -----------------
    // IMPORTANT: This function takes OWNERSHIP of the strings in the provider!
    // The provider's strings should be allocated with a persistent allocator,
    // as they will be freed when the Agent is deinitialized.
    // -------------------------------------------------------------------------
    pub fn initWithProvider(provider: types.Provider) !*Agent {
        const agent = try std.heap.page_allocator.create(Agent);

        agent.gpa = std.heap.GeneralPurposeAllocator(.{}){};
        agent.allocator = agent.gpa.allocator();
        const allocator = agent.allocator;

        // Store the provider directly (caller transfers ownership)
        agent.provider = provider;

        agent.history = std.ArrayList(types.Message){};
        agent.tools_schemas = try tools.getSchemas(allocator);
        agent.current_response_buffer = null;
        agent.response_pos = 0;

        return agent;
    }

    // -------------------------------------------------------------------------
    // deinit - Destructor Function
    // -------------------------------------------------------------------------
    // Zig convention: Use `deinit` to clean up resources.
    // This is called when you're done with the Agent.
    //
    // CRITICAL: Zig has NO garbage collector. If you don't call deinit,
    // you have a memory leak! The GPA will even tell you about leaks
    // when the program exits (in debug mode).
    //
    // TypeScript analogy:
    //   destroy(): void {
    //     // In JS, you'd just let GC handle it
    //     // In Zig, we explicitly free everything
    //   }
    //
    // PARAMETER: `self: *Agent` - pointer to this Agent instance.
    // This is like `this` in TypeScript, but explicit.
    //
    // MULTI-PROVIDER CLEANUP:
    // -----------------------
    // Since we support multiple provider types, we need to handle
    // cleanup for each variant differently. API key auth has one string,
    // OAuth auth has multiple optional strings.
    // -------------------------------------------------------------------------
    pub fn deinit(self: *Agent) void {
        const allocator = self.allocator;

        // ---------------------------------------------------------------------
        // Free provider-specific resources
        // ---------------------------------------------------------------------
        // `switch` on a tagged union requires handling all variants.
        // Each provider type has different owned resources to free.
        //
        // EXHAUSTIVE SWITCH:
        // Zig requires you handle ALL variants. If we add a new provider,
        // the compiler will error until we add cleanup code for it.
        // This prevents memory leaks from forgotten cleanup paths!
        // ---------------------------------------------------------------------
        switch (self.provider) {
            .anthropic => |a| {
                // API key auth: just the API key string
                allocator.free(a.api_key);
            },
            .anthropic_oauth => |oauth| {
                // OAuth auth: access token, optional refresh token, optional base URL
                allocator.free(oauth.access_token);
                if (oauth.refresh_token) |rt| allocator.free(rt);
                if (oauth.base_url) |url| allocator.free(url);
            },
            .ollama => |o| {
                // Ollama: model and URL strings
                // Note: These might be string literals (static), but we free anyway
                // because we can't know at runtime. Freeing static strings is safe
                // but freeing allocated strings is required.
                _ = o; // URL and model are typically static, no free needed
            },
            .mock => |m| {
                // Mock: response string
                _ = m; // Response is typically a static string literal
            },
        }

        // Free all messages in history.
        // Each message owns its content, so we call deinit on each.
        for (self.history.items) |msg| {
            msg.deinit(allocator);
        }
        // Free the ArrayList's internal buffer.
        self.history.deinit(allocator);

        // Free the tool schemas array.
        allocator.free(self.tools_schemas);

        // Free the response buffer if it exists.
        // `if (optional) |value|` unwraps the optional, giving us the value.
        if (self.current_response_buffer) |r| allocator.free(r);

        // Deinitialize the GPA - this checks for memory leaks in debug mode!
        // The `_` discards the return value (leak check result).
        _ = self.gpa.deinit();

        // Finally, free the Agent struct itself.
        // We use page_allocator because that's what we used to allocate it.
        std.heap.page_allocator.destroy(self);
    }

    // -------------------------------------------------------------------------
    // sendPrompt - Send a message and get a response
    // -------------------------------------------------------------------------
    // Sends the user's prompt to Claude and stores the response.
    //
    // ERROR HANDLING:
    // The `!void` return type means "returns void OR an error".
    // The `try` keyword propagates errors - if http_client.send fails,
    // sendPrompt immediately returns that error to its caller.
    //
    // TypeScript analogy:
    //   async sendPrompt(text: string): Promise<void> {
    //     // throws on error
    //   }
    //
    // AUTHENTICATION:
    // This works with any provider type. The http_client.send function
    // handles the authentication differences internally based on the
    // provider variant (API key vs OAuth token).
    // -------------------------------------------------------------------------
    pub fn sendPrompt(self: *Agent, text: []const u8) !void {
        const allocator = self.allocator;

        // ---------------------------------------------------------------------
        // Clear any previous response
        // ---------------------------------------------------------------------
        // We only keep one response at a time. Free the old one if it exists.
        if (self.current_response_buffer) |r| {
            allocator.free(r);
            self.current_response_buffer = null;
            self.response_pos = 0;
        }

        // ---------------------------------------------------------------------
        // Create the user message
        // ---------------------------------------------------------------------
        // Allocate a single-element array for the content block.
        // In Zig, strings are content blocks with type "text".
        //
        // TypeScript analogy:
        //   const userContent: ContentBlock[] = [{ type: 'text', text }];
        // ---------------------------------------------------------------------
        var user_content = try allocator.alloc(types.ContentBlock, 1);
        user_content[0] = .{ .text = try allocator.dupe(u8, text) };

        // Add the user message to history.
        try self.history.append(allocator, .{
            .role = .user,
            .content = user_content,
        });

        // ---------------------------------------------------------------------
        // Send the request to Claude
        // ---------------------------------------------------------------------
        // This is a blocking HTTP call. The `try` propagates any errors.
        // We pass the full history so Claude has context of the conversation.
        //
        // The http_client.send function handles different provider types:
        // - anthropic: Uses x-api-key header
        // - anthropic_oauth: Uses Authorization: Bearer header
        // - ollama: Calls local Ollama API
        // - mock: Returns canned response
        //
        // TypeScript analogy:
        //   const response = await httpClient.send(provider, history, tools);
        // ---------------------------------------------------------------------
        const response = try http_client.send(
            allocator,
            self.provider,
            self.history.items,
            self.tools_schemas,
        );
        // `defer` schedules code to run when the current scope exits.
        // This ensures we clean up `response` even if later code fails.
        defer response.deinit(allocator);

        // ---------------------------------------------------------------------
        // Process the response
        // ---------------------------------------------------------------------
        // Copy response content to assistant message and buffer text for reading.
        //
        // errdefer is like defer, but only runs if an error occurs.
        // It's perfect for cleanup in error cases.
        // ---------------------------------------------------------------------
        var assistant_content = try allocator.alloc(types.ContentBlock, response.content.len);
        var full_text = std.ArrayList(u8){};
        errdefer full_text.deinit(allocator);

        // Process each content block from the response.
        for (response.content, 0..) |block, i| {
            // `switch` on tagged unions with capture syntax `|t|` extracts the value.
            assistant_content[i] = switch (block) {
                .text => |t| blk: {
                    // Accumulate all text for the response buffer.
                    try full_text.appendSlice(allocator, t);
                    // Create an owned copy for the history.
                    // `blk:` is a block label, `break :blk value` returns from it.
                    break :blk types.ContentBlock{ .text = try allocator.dupe(u8, t) };
                },
                .tool_use => |tu| types.ContentBlock{
                    .tool_use = .{
                        .id = try allocator.dupe(u8, tu.id),
                        .name = try allocator.dupe(u8, tu.name),
                        .input = try json_utils.deepCopy(allocator, tu.input),
                    },
                },
                .tool_result => |tr| types.ContentBlock{
                    .tool_result = .{
                        .tool_use_id = try allocator.dupe(u8, tr.tool_use_id),
                        .content = try allocator.dupe(u8, tr.content),
                    },
                },
            };
        }

        // Add assistant response to history.
        try self.history.append(allocator, .{
            .role = .assistant,
            .content = assistant_content,
        });

        // Store the full text response for chunked reading via FFI.
        // `toOwnedSlice` returns ownership of the ArrayList's buffer.
        self.current_response_buffer = try full_text.toOwnedSlice(allocator);
        self.response_pos = 0;
    }

    // -------------------------------------------------------------------------
    // readChunk - Read a chunk of the response
    // -------------------------------------------------------------------------
    // Reads up to `buffer.len` bytes from the current response into the
    // provided buffer. Returns the number of bytes actually read, or 0
    // if there's no more data.
    //
    // This enables the FFI pattern where callers read in a loop until
    // they get 0, indicating end of response.
    //
    // TypeScript analogy:
    //   readChunk(buffer: Uint8Array): number {
    //     const remaining = this.responseBuffer.slice(this.responsePos);
    //     const toCopy = Math.min(remaining.length, buffer.length);
    //     buffer.set(remaining.slice(0, toCopy));
    //     this.responsePos += toCopy;
    //     return toCopy;
    //   }
    // -------------------------------------------------------------------------
    pub fn readChunk(self: *Agent, buffer: []u8) i32 {
        // Handle case where there's no response to read.
        // `orelse` provides a default when the optional is null.
        const data = self.current_response_buffer orelse return 0;

        // Check if we've already read everything.
        if (self.response_pos >= data.len) return 0;

        // Calculate how much to copy.
        const remaining = data.len - self.response_pos;
        const to_copy = @min(remaining, buffer.len);

        // Copy data from response buffer to caller's buffer.
        // @memcpy is a built-in for efficient memory copying.
        @memcpy(
            buffer[0..to_copy],
            data[self.response_pos .. self.response_pos + to_copy],
        );

        // Advance the read position.
        self.response_pos += to_copy;

        // Return the number of bytes copied.
        // @intCast converts usize to i32 (the return type).
        return @intCast(to_copy);
    }
};

// =============================================================================
// C FFI EXPORTS
// =============================================================================
// These functions create a C-compatible API that can be called from other
// languages. The `export` keyword:
//   1. Uses C calling convention (how arguments are passed at CPU level)
//   2. Prevents name mangling (keeps function names as-is in the binary)
//   3. Makes the function visible in the shared library's symbol table
//
// WHY USE C ABI?
// C is the "lingua franca" of programming languages. Almost every language
// can call C functions, so exporting a C API maximizes compatibility.
//
// FFI FROM NODE.JS EXAMPLE:
//   const ffi = require('koffi');
//   const lib = ffi.load('./libziggum.dylib');
//   const zg_init = lib.func('void* zg_init(const char*)');
//   const agent = zg_init('sk-ant-...');
//
// AUTHENTICATION FUNCTIONS:
// -------------------------
// We provide two init functions for different auth methods:
//   - zg_init: API key authentication (traditional)
//   - zg_init_oauth: OAuth/Bearer token authentication (subscriptions)
//
// This mirrors the dual-auth support in Claude Code where users can either:
//   - Use ANTHROPIC_API_KEY environment variable
//   - Use OAuth tokens from Claude Pro/Max subscription
// =============================================================================

// Type alias for the opaque pointer we return to FFI callers.
// `*anyopaque` is Zig's equivalent of `void*` in C - a generic pointer
// whose concrete type is unknown to the caller.
//
// This is called an "opaque pointer" because callers can't see inside it.
// They just pass it back to our functions, which know it's really an *Agent.
const ZgAgent = *anyopaque;

// =============================================================================
// zg_init - Create a new Agent (API Key Authentication)
// =============================================================================
// Creates and initializes a new Agent instance using API key authentication.
// This is the traditional method for Anthropic API access.
//
// C SIGNATURE: void* zg_init(const char* api_key)
//
// PARAMETERS:
//   api_key: Null-terminated C string containing the Anthropic API key
//            Format: "sk-ant-api03-..." (starts with "sk-ant-")
//
// RETURNS:
//   - Opaque pointer to the Agent on success
//   - null on failure
//
// USAGE FROM NODE.JS:
//   const agent = zg_init(Buffer.from('sk-ant-...\0'));
//   if (!agent) throw new Error('Failed to initialize agent');
//
// ENVIRONMENT VARIABLE:
//   Typically, API keys come from: process.env.ANTHROPIC_API_KEY
//
// WHEN TO USE:
//   - Pay-as-you-go API access
//   - Server-side applications
//   - When you have a Console API key
// =============================================================================
export fn zg_init(api_key: [*c]const u8) ?ZgAgent {
    // Debug output to help troubleshoot FFI issues.
    std.debug.print("zg_init called\n", .{});

    // Convert C string to Zig slice.
    // [*c]const u8 is a C-style pointer (null-terminated string).
    // std.mem.span finds the null terminator and returns a proper slice.
    //
    // TypeScript analogy:
    //   const apiKeySlice = apiKey.toString('utf8'); // from Buffer
    const api_key_slice = std.mem.span(api_key);

    // Try to create the agent, handling any errors.
    // `catch |err|` captures the error for logging.
    const agent = Agent.init(api_key_slice) catch |err| {
        std.debug.print("Agent.init failed: {}\n", .{err});
        return null; // Return null to indicate failure to FFI caller
    };

    std.debug.print("Agent initialized\n", .{});

    // Cast the *Agent pointer to an opaque pointer.
    // @ptrCast performs type-safe pointer casting.
    return @ptrCast(agent);
}

// =============================================================================
// zg_init_oauth - Create a new Agent (OAuth/Bearer Token Authentication)
// =============================================================================
// Creates and initializes a new Agent instance using OAuth authentication.
// This is used for subscription-based services like Claude Code Pro/Max.
//
// C SIGNATURE: void* zg_init_oauth(const char* access_token,
//                                   const char* refresh_token,
//                                   const char* base_url)
//
// PARAMETERS:
//   access_token: Null-terminated C string containing the OAuth access token
//                 This is the Bearer token used for API requests.
//
//   refresh_token: Null-terminated C string for token refresh (can be NULL)
//                  Used to obtain new access tokens when they expire.
//                  Pass NULL if not available.
//
//   base_url: Null-terminated C string for custom API endpoint (can be NULL)
//             For enterprise deployments or proxies.
//             Pass NULL to use default: https://api.anthropic.com
//
// RETURNS:
//   - Opaque pointer to the Agent on success
//   - null on failure
//
// USAGE FROM NODE.JS:
//   // With just access token
//   const agent = zg_init_oauth(
//     Buffer.from(accessToken + '\0'),
//     null,
//     null
//   );
//
//   // With refresh token
//   const agent = zg_init_oauth(
//     Buffer.from(accessToken + '\0'),
//     Buffer.from(refreshToken + '\0'),
//     null
//   );
//
// TOKEN SOURCES:
//   1. Claude Code CLI: ~/.claude/credentials.json after /login
//   2. Environment variable: ANTHROPIC_AUTH_TOKEN
//   3. Custom OAuth flow: Token exchange after user authorization
//
// WHEN TO USE:
//   - Claude Pro/Max subscription users
//   - Enterprise SSO deployments
//   - When you have OAuth tokens instead of API keys
//
// WHY SEPARATE FROM zg_init?
// --------------------------
// OAuth tokens have different characteristics than API keys:
//   - Tokens may expire and need refresh
//   - Different header format (Authorization: Bearer vs x-api-key)
//   - May come from browser-based authentication
//   - Billing is through subscription, not per-request
//
// Having a separate function makes the authentication method explicit
// and allows proper handling of the optional refresh_token and base_url.
// =============================================================================
export fn zg_init_oauth(
    access_token: [*c]const u8,
    refresh_token: [*c]const u8,
    base_url: [*c]const u8,
) ?ZgAgent {
    std.debug.print("zg_init_oauth called\n", .{});

    // Convert C strings to Zig slices, handling NULL pointers.
    // In C, NULL means "no value" for optional parameters.
    //
    // The pattern: if (ptr != null) std.mem.span(ptr) else null
    // - Checks if the C pointer is NULL
    // - If not NULL, converts to Zig slice
    // - If NULL, keeps it as Zig null
    const access_token_slice = std.mem.span(access_token);

    // Handle optional refresh_token (may be NULL from C caller)
    const refresh_token_slice: ?[]const u8 = if (refresh_token != null)
        std.mem.span(refresh_token)
    else
        null;

    // Handle optional base_url (may be NULL from C caller)
    const base_url_slice: ?[]const u8 = if (base_url != null)
        std.mem.span(base_url)
    else
        null;

    // Create the agent with OAuth authentication
    const agent = Agent.initWithOAuth(
        access_token_slice,
        refresh_token_slice,
        base_url_slice,
    ) catch |err| {
        std.debug.print("Agent.initWithOAuth failed: {}\n", .{err});
        return null;
    };

    std.debug.print("Agent initialized with OAuth\n", .{});
    return @ptrCast(agent);
}

// =============================================================================
// zg_deinit - Destroy an Agent
// =============================================================================
// Cleans up and frees an Agent instance. MUST be called when done!
//
// C SIGNATURE: void zg_deinit(void* agent)
//
// PARAMETERS:
//   agent: Opaque pointer returned from zg_init or zg_init_oauth
//
// USAGE FROM NODE.JS:
//   zg_deinit(agent);
//   // agent is now invalid - don't use it anymore!
//
// IMPORTANT:
//   - Call this exactly once per agent
//   - After calling, the agent pointer is invalid
//   - Failing to call this leaks memory
// =============================================================================
export fn zg_deinit(agent: ZgAgent) void {
    std.debug.print("zg_deinit called\n", .{});

    // Cast opaque pointer back to *Agent.
    // @alignCast ensures the pointer has proper alignment for the Agent struct.
    // @ptrCast then converts the type.
    const self: *Agent = @ptrCast(@alignCast(agent));

    // Clean up all resources.
    self.deinit();
}

// =============================================================================
// zg_send_prompt - Send a prompt and get a response
// =============================================================================
// Sends a user message to Claude and waits for the response.
// After this call returns successfully, use zg_read_chunk to get the response.
//
// C SIGNATURE: int zg_send_prompt(void* agent, const char* text)
//
// PARAMETERS:
//   agent: Opaque pointer from zg_init or zg_init_oauth
//   text: Null-terminated C string containing the user's message
//
// RETURNS:
//   - 0 on success
//   - -1 on failure (check debug output for details)
//
// USAGE FROM NODE.JS:
//   const result = zg_send_prompt(agent, Buffer.from('Hello Claude!\0'));
//   if (result !== 0) throw new Error('Send failed');
//
// ERROR CODES:
//   Return of -1 may indicate:
//   - Network error
//   - Authentication error (invalid/expired token)
//   - Rate limiting
//   - Invalid request
//
// For OAuth agents, a -1 might mean the access token expired.
// In this case, you may need to refresh the token and create a new agent.
// =============================================================================
export fn zg_send_prompt(agent: ZgAgent, text: [*c]const u8) i32 {
    std.debug.print("zg_send_prompt called\n", .{});

    // Cast opaque pointer back to *Agent.
    const self: *Agent = @ptrCast(@alignCast(agent));

    // Convert C string to Zig slice.
    const text_slice = std.mem.span(text);
    std.debug.print("Sending prompt: {s}\n", .{text_slice});

    // Send the prompt, handling errors.
    self.sendPrompt(text_slice) catch |err| {
        std.debug.print("sendPrompt failed: {}\n", .{err});
        return -1; // Return error code to FFI caller
    };

    std.debug.print("sendPrompt succeeded\n", .{});
    return 0; // Success
}

// =============================================================================
// zg_read_chunk - Read a chunk of the response
// =============================================================================
// Reads response data into a buffer. Call repeatedly until it returns 0.
//
// C SIGNATURE: int zg_read_chunk(void* agent, char* buffer, size_t capacity)
//
// PARAMETERS:
//   agent: Opaque pointer from zg_init or zg_init_oauth
//   buffer: Pre-allocated buffer to receive data
//   capacity: Size of the buffer in bytes
//
// RETURNS:
//   - Number of bytes written to buffer (> 0)
//   - 0 when all data has been read (end of response)
//
// USAGE PATTERN FROM NODE.JS:
//   const buffer = Buffer.alloc(1024);
//   let response = '';
//   let bytesRead;
//   while ((bytesRead = zg_read_chunk(agent, buffer, buffer.length)) > 0) {
//     response += buffer.toString('utf8', 0, bytesRead);
//   }
//   console.log('Response:', response);
//
// WHY CHUNKED READING?
// --------------------
// This pattern is efficient for FFI because:
// 1. We don't need to know response size upfront
// 2. The caller controls buffer allocation
// 3. Works well with streaming/progressive display
// 4. Memory efficient for large responses
// =============================================================================
export fn zg_read_chunk(agent: ZgAgent, buffer: [*c]u8, capacity: usize) i32 {
    // Cast opaque pointer back to *Agent.
    const self: *Agent = @ptrCast(@alignCast(agent));

    // Convert C pointer to Zig slice.
    // `buffer[0..capacity]` creates a slice from the C pointer.
    const buf = buffer[0..capacity];

    // Read and return number of bytes copied.
    return self.readChunk(buf);
}
