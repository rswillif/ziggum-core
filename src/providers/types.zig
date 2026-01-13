// =============================================================================
// types.zig - Core Type Definitions for the AI Provider System
// =============================================================================
//
// FOR TYPESCRIPT DEVELOPERS:
// --------------------------
// This file defines the core data structures used throughout the application.
// It's similar to a types.ts or interfaces.ts file in a TypeScript project.
//
// KEY ZIG CONCEPTS IN THIS FILE:
// 1. Enums - Similar to TypeScript enums, but more powerful
// 2. Structs - Like TypeScript interfaces/types, but with methods
// 3. Tagged Unions - Like TypeScript discriminated unions, but type-safe
// 4. Custom JSON serialization - Implementing jsonStringify for custom output
//
// TypeScript equivalent (conceptual):
//   export type Role = 'user' | 'assistant';
//   export type ContentBlock = TextBlock | ToolUseBlock | ToolResultBlock;
//   export interface Message { role: Role; content: ContentBlock[]; }
//   export type Provider = AnthropicProvider | OllamaProvider | MockProvider;
//   export type AuthMethod = 'api_key' | 'oauth_token';
//
// =============================================================================

const std = @import("std");
const json_utils = @import("../json_utils.zig");

// =============================================================================
// ROLE ENUM
// =============================================================================
// Represents who sent a message in the conversation.
//
// ZIG ENUMS vs TYPESCRIPT:
// ------------------------
// TypeScript: type Role = 'user' | 'assistant';
//    - Just a type alias, values are strings at runtime
//
// Zig: pub const Role = enum { user, assistant };
//    - A true enum type with numeric values at runtime
//    - Can have methods attached
//    - The @tagName builtin gets the string representation
//
// MEMORY: Enums are tiny! They're stored as a small integer (u1 in this case).
// =============================================================================
pub const Role = enum {
    user, // Messages from the user (human)
    assistant, // Messages from the AI assistant (Claude)
};

// =============================================================================
// AUTH METHOD ENUM
// =============================================================================
// Represents how authentication is performed with an AI provider.
//
// SUBSCRIPTION-BASED AUTHENTICATION:
// ----------------------------------
// Many AI coding tools (like Claude Code, Cursor, GitHub Copilot) offer
// subscription plans that don't use traditional API keys. Instead, they use:
//
//   1. OAuth 2.0 tokens - User authenticates via browser, receives tokens
//   2. Session tokens - Short-lived tokens from interactive login
//   3. Bearer tokens - Generic authorization tokens
//
// This enum allows the system to support both traditional API keys AND
// subscription-based OAuth authentication.
//
// TypeScript equivalent:
//   type AuthMethod = 'api_key' | 'oauth_token';
//
// WHY SUPPORT MULTIPLE AUTH METHODS?
// ----------------------------------
// - API keys: Simple, great for server-side apps, pay-per-use billing
// - OAuth tokens: Required for subscription plans (Pro/Max), better security,
//   supports SSO, doesn't expose long-lived credentials
//
// Real-world example:
//   Claude Code with Max subscription uses OAuth tokens stored in
//   ~/.claude/credentials.json after browser-based login
// =============================================================================
pub const AuthMethod = enum {
    // -------------------------------------------------------------------------
    // API_KEY - Traditional API Key Authentication
    // -------------------------------------------------------------------------
    // Uses a static API key (e.g., "sk-ant-api03-...")
    // - Sent via x-api-key header (Anthropic) or Authorization header (others)
    // - Typically used for pay-as-you-go API access
    // - Keys are long-lived and should be kept secret
    //
    // Environment variable: ANTHROPIC_API_KEY
    // -------------------------------------------------------------------------
    api_key,

    // -------------------------------------------------------------------------
    // OAUTH_TOKEN - OAuth/Bearer Token Authentication
    // -------------------------------------------------------------------------
    // Uses OAuth 2.0 access tokens or bearer tokens
    // - Sent via Authorization: Bearer <token> header
    // - Used by subscription services (Claude Pro/Max, etc.)
    // - Tokens may be short-lived and require refresh
    //
    // Environment variable: ANTHROPIC_AUTH_TOKEN
    //
    // TOKEN LIFECYCLE:
    // - Access tokens typically expire (hours to days)
    // - Refresh tokens can obtain new access tokens
    // - Some systems handle refresh automatically
    // -------------------------------------------------------------------------
    oauth_token,
};

// =============================================================================
// CONTENT BLOCK - Tagged Union
// =============================================================================
// Represents a single piece of content within a message.
// This is Anthropic's API design - messages contain multiple content blocks.
//
// TAGGED UNIONS EXPLAINED:
// ------------------------
// A tagged union (also called "sum type" or "discriminated union") is a type
// that can hold ONE of several different types of values, plus a "tag" that
// tells you which type is currently stored.
//
// TypeScript equivalent:
//   type ContentBlock =
//     | { type: 'text'; text: string }
//     | { type: 'tool_use'; id: string; name: string; input: JsonValue }
//     | { type: 'tool_result'; tool_use_id: string; content: string };
//
// In Zig, the `union(enum)` syntax creates a tagged union where:
//   - The tag is automatically managed (stored alongside the data)
//   - You can switch on the tag to access the appropriate field
//   - Trying to access the wrong field is a compile-time error
//
// WHY TAGGED UNIONS?
// ------------------
// 1. Type safety: The compiler ensures you handle all cases
// 2. Memory efficiency: Only stores the largest variant + a small tag
// 3. No null checks: You switch on the tag, not check for null
//
// MEMORY LAYOUT:
//   [ tag (1 byte) | padding | data (size of largest variant) ]
//
// =============================================================================
pub const ContentBlock = union(enum) {
    // -------------------------------------------------------------------------
    // TEXT VARIANT
    // -------------------------------------------------------------------------
    // A simple text response from the user or assistant.
    // []const u8 is Zig's string type - a slice of bytes.
    //
    // TypeScript: { type: 'text', text: string }
    // -------------------------------------------------------------------------
    text: []const u8,

    // -------------------------------------------------------------------------
    // TOOL_USE VARIANT
    // -------------------------------------------------------------------------
    // Represents Claude requesting to use a tool.
    // When Claude wants to read a file, run a command, etc., it sends this.
    //
    // TypeScript: { type: 'tool_use', id: string, name: string, input: JsonValue }
    //
    // Anonymous struct syntax: .{ field: Type, ... }
    // This is an inline struct definition - no separate type needed.
    // -------------------------------------------------------------------------
    tool_use: struct {
        id: []const u8, // Unique ID for this tool invocation
        name: []const u8, // Tool name (e.g., "read_file")
        input: std.json.Value, // Tool arguments as parsed JSON
    },

    // -------------------------------------------------------------------------
    // TOOL_RESULT VARIANT
    // -------------------------------------------------------------------------
    // The result of executing a tool, sent back to Claude.
    //
    // TypeScript: { type: 'tool_result', tool_use_id: string, content: string }
    // -------------------------------------------------------------------------
    tool_result: struct {
        tool_use_id: []const u8, // ID matching the tool_use request
        content: []const u8, // Result of tool execution (output text)
    },

    // =========================================================================
    // CUSTOM JSON SERIALIZATION
    // =========================================================================
    // Zig's std.json can automatically serialize structs, but sometimes you
    // need custom output format. The `jsonStringify` method lets you define
    // exactly how this type should be converted to JSON.
    //
    // WHY CUSTOM SERIALIZATION?
    // -------------------------
    // Anthropic's API expects a specific JSON format with "type" fields.
    // Without custom serialization, Zig would output:
    //   { "text": "Hello" }
    // But we need:
    //   { "type": "text", "text": "Hello" }
    //
    // ANYTYPE EXPLAINED:
    // ------------------
    // `anytype` is Zig's compile-time generics. The compiler generates
    // specialized code for each type this function is called with.
    //
    // TypeScript analogy:
    //   jsonStringify<W extends JsonWriter>(jw: W): void
    // =========================================================================
    pub fn jsonStringify(self: ContentBlock, jw: anytype) !void {
        // Begin the JSON object: {
        try jw.beginObject();

        // Switch on the union tag to handle each variant.
        // This is similar to TypeScript's discriminated union narrowing:
        //   if (block.type === 'text') { ... }
        switch (self) {
            // -----------------------------------------------------------------
            // Serialize text content block
            // Output: { "type": "text", "text": "Hello" }
            // -----------------------------------------------------------------
            .text => |t| {
                try jw.objectField("type");
                try jw.write("text");
                try jw.objectField("text");
                try jw.write(t);
            },

            // -----------------------------------------------------------------
            // Serialize tool_use content block
            // Output: { "type": "tool_use", "id": "...", "name": "...", "input": {...} }
            // -----------------------------------------------------------------
            .tool_use => |tu| {
                try jw.objectField("type");
                try jw.write("tool_use");
                try jw.objectField("id");
                try jw.write(tu.id);
                try jw.objectField("name");
                try jw.write(tu.name);
                try jw.objectField("input");
                try jw.write(tu.input);
            },

            // -----------------------------------------------------------------
            // Serialize tool_result content block
            // Output: { "type": "tool_result", "tool_use_id": "...", "content": "..." }
            // -----------------------------------------------------------------
            .tool_result => |tr| {
                try jw.objectField("type");
                try jw.write("tool_result");
                try jw.objectField("tool_use_id");
                try jw.write(tr.tool_use_id);
                try jw.objectField("content");
                try jw.write(tr.content);
            },
        }

        // End the JSON object: }
        try jw.endObject();
    }
};

// =============================================================================
// MESSAGE STRUCT
// =============================================================================
// Represents a single message in the conversation history.
// Each message has a role (user/assistant) and content (array of blocks).
//
// TypeScript equivalent:
//   interface Message {
//     role: 'user' | 'assistant';
//     content: ContentBlock[];
//   }
//
// WHY CONTENT IS AN ARRAY:
// ------------------------
// Anthropic's API allows multiple content blocks per message. For example,
// Claude might respond with text AND a tool_use in the same message.
// =============================================================================
pub const Message = struct {
    role: Role, // Who sent this message
    content: []const ContentBlock, // Array of content blocks

    // -------------------------------------------------------------------------
    // Custom JSON Serialization
    // -------------------------------------------------------------------------
    // Outputs: { "role": "user", "content": [...] }
    //
    // @tagName converts the enum value to its string representation.
    // Role.user -> "user", Role.assistant -> "assistant"
    // -------------------------------------------------------------------------
    pub fn jsonStringify(self: Message, jw: anytype) !void {
        try jw.beginObject();

        // Write role as string
        try jw.objectField("role");
        try jw.write(@tagName(self.role)); // Enum to string conversion

        // Write content array
        try jw.objectField("content");
        try jw.write(self.content); // ContentBlock.jsonStringify called for each

        try jw.endObject();
    }

    // -------------------------------------------------------------------------
    // deinit - Clean up owned resources
    // -------------------------------------------------------------------------
    // Messages own their content, so we need to free everything.
    //
    // MEMORY OWNERSHIP IN ZIG:
    // ------------------------
    // Unlike TypeScript where GC handles everything, Zig requires explicit
    // decisions about who owns what memory. Here, Message owns:
    //   1. The content slice itself (the array)
    //   2. All strings within each content block
    //   3. JSON values in tool_use blocks
    //
    // The allocator parameter tells us HOW to free - it must be the same
    // allocator that was used to allocate these resources!
    // -------------------------------------------------------------------------
    pub fn deinit(self: Message, allocator: std.mem.Allocator) void {
        // Free each content block's owned data
        for (self.content) |block| {
            switch (block) {
                .text => |t| allocator.free(t), // Free the text string
                .tool_use => |tu| {
                    allocator.free(tu.id); // Free the ID string
                    allocator.free(tu.name); // Free the name string
                    json_utils.free(allocator, tu.input); // Free JSON recursively
                },
                .tool_result => |tr| {
                    allocator.free(tr.tool_use_id); // Free the ID string
                    allocator.free(tr.content); // Free the content string
                },
            }
        }

        // Free the content array itself
        allocator.free(self.content);
    }
};

// =============================================================================
// TOOL STRUCT
// =============================================================================
// Defines a tool that Claude can use (like function calling in GPT).
// Tools enable Claude to interact with the outside world.
//
// TypeScript equivalent:
//   interface Tool {
//     name: string;
//     description: string;
//     input_schema: JsonSchema;  // JSON Schema defining expected parameters
//   }
//
// NOTE: input_schema_json is stored as a string, not parsed JSON.
// This is a design choice - we can embed the schema as a string literal
// and only parse it when needed (lazy evaluation).
// =============================================================================
pub const Tool = struct {
    name: []const u8, // Tool name (e.g., "read_file")
    description: []const u8, // Human-readable description for Claude
    input_schema_json: []const u8, // JSON Schema as string (parsed when needed)
};

// =============================================================================
// PROVIDER - Tagged Union for AI Backends
// =============================================================================
// Represents different AI provider configurations.
// This is a great example of how tagged unions enable polymorphism in Zig.
//
// TypeScript equivalent:
//   type Provider =
//     | { type: 'mock'; response: string }
//     | { type: 'ollama'; model: string; url: string }
//     | { type: 'anthropic'; apiKey: string; model: string }
//     | { type: 'anthropic_oauth'; token: string; model: string; baseUrl?: string };
//
// WHY TAGGED UNIONS FOR PROVIDERS?
// --------------------------------
// Each provider has different configuration needs:
//   - Mock: Just a canned response (for testing)
//   - Ollama: Local model, needs URL and model name
//   - Anthropic: Cloud API, needs API key and model name
//   - Anthropic OAuth: Subscription auth, needs OAuth token
//
// Using a tagged union means:
//   1. Only store the fields needed for each provider
//   2. Type-safe access - can't accidentally access ollama.api_key
//   3. Exhaustive switching - compiler ensures all providers are handled
//
// SUBSCRIPTION SERVICES ARCHITECTURE:
// -----------------------------------
// Services like Claude Code (Max/Pro), Cursor, etc. use OAuth for auth:
//
//   [User] --> [Browser Login] --> [OAuth Server]
//                                       |
//                                       v
//                              [Access Token + Refresh Token]
//                                       |
//                                       v
//   [Your App] --> Authorization: Bearer <token> --> [API]
//
// The token replaces the API key for authentication.
// =============================================================================
pub const Provider = union(enum) {
    // -------------------------------------------------------------------------
    // MOCK PROVIDER
    // -------------------------------------------------------------------------
    // Returns a canned response. Perfect for testing without API calls.
    //
    // Usage in tests:
    //   const provider = Provider{ .mock = .{ .response = "Hello!" } };
    // -------------------------------------------------------------------------
    mock: struct {
        response: []const u8,
    },

    // -------------------------------------------------------------------------
    // OLLAMA PROVIDER
    // -------------------------------------------------------------------------
    // Connects to a local Ollama instance for open-source models.
    // Ollama runs models locally on your machine.
    //
    // Configuration:
    //   model: Name of the model (e.g., "llama2", "mistral")
    //   url: API endpoint (typically "http://localhost:11434/api/generate")
    // -------------------------------------------------------------------------
    ollama: struct {
        model: []const u8,
        url: []const u8,
    },

    // -------------------------------------------------------------------------
    // ANTHROPIC PROVIDER (API Key Authentication)
    // -------------------------------------------------------------------------
    // Connects to Anthropic's Claude API using traditional API key auth.
    // This is the standard pay-as-you-go method.
    //
    // Configuration:
    //   api_key: Your Anthropic API key (sk-ant-...)
    //   model: Model name (e.g., "claude-3-5-sonnet-latest")
    //
    // Authentication header: x-api-key: <api_key>
    // -------------------------------------------------------------------------
    anthropic: struct {
        api_key: []const u8,
        model: []const u8,
    },

    // -------------------------------------------------------------------------
    // ANTHROPIC OAUTH PROVIDER (Subscription/Token Authentication)
    // -------------------------------------------------------------------------
    // Connects to Anthropic's Claude API using OAuth/Bearer token auth.
    // Used by subscription services like Claude Code with Pro/Max plans.
    //
    // HOW IT DIFFERS FROM API KEY:
    // ----------------------------
    // 1. Authentication uses "Authorization: Bearer <token>" header
    // 2. Tokens come from OAuth login flow (browser-based)
    // 3. Tokens may expire and need refresh
    // 4. Billing is through subscription, not per-token usage
    //
    // Configuration:
    //   access_token: OAuth access token from authentication flow
    //   refresh_token: (optional) Token to obtain new access tokens
    //   model: Model name (e.g., "claude-3-5-sonnet-latest")
    //   base_url: (optional) Custom API endpoint for enterprise/proxies
    //
    // OPTIONAL FIELDS IN ZIG:
    // -----------------------
    // The `?` prefix makes a type optional (like `string | null` in TS).
    // Optional fields with `= null` default to null if not provided.
    //
    // TOKEN STORAGE:
    // --------------
    // Claude Code stores tokens in ~/.claude/credentials.json
    // Other services may use different locations or secure keychains.
    //
    // TypeScript equivalent:
    //   interface AnthropicOAuthConfig {
    //     accessToken: string;
    //     refreshToken?: string;
    //     model: string;
    //     baseUrl?: string;
    //   }
    // -------------------------------------------------------------------------
    anthropic_oauth: struct {
        access_token: []const u8, // OAuth access token (required)
        refresh_token: ?[]const u8 = null, // Refresh token (optional)
        model: []const u8, // Model name
        base_url: ?[]const u8 = null, // Custom API URL (optional)
    },
};

// =============================================================================
// RESPONSE STRUCT
// =============================================================================
// Represents a parsed response from an AI provider.
//
// TypeScript equivalent:
//   interface Response {
//     content: ContentBlock[];
//   }
//
// WHY SO SIMPLE?
// --------------
// This is a simplified structure. A full implementation might include:
//   - stop_reason: Why the model stopped (max_tokens, end_turn, tool_use)
//   - usage: Token counts for billing
//   - model: Which model actually responded
//
// For now, we just need the content blocks.
// =============================================================================
pub const Response = struct {
    content: []const ContentBlock, // Array of response content blocks

    // -------------------------------------------------------------------------
    // deinit - Clean up owned resources
    // -------------------------------------------------------------------------
    // Response owns its content array and all strings within.
    // -------------------------------------------------------------------------
    pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
        for (self.content) |block| {
            switch (block) {
                .text => |t| allocator.free(t),
                .tool_use => |tu| {
                    allocator.free(tu.id);
                    allocator.free(tu.name);
                    json_utils.free(allocator, tu.input);
                },
                .tool_result => |tr| {
                    allocator.free(tr.tool_use_id);
                    allocator.free(tr.content);
                },
            }
        }

        // Free the content array itself
        allocator.free(self.content);
    }
};

// =============================================================================
// UNIT TESTS
// =============================================================================
// Zig has built-in test support. Tests are written inline with the code
// using the `test "name"` syntax.
//
// TypeScript comparison:
//   Jest: describe('Message', () => { it('should serialize to JSON', () => {...}) });
//   Zig: test "JSON serialization of Message" { ... }
//
// RUNNING TESTS:
//   zig build test
//
// KEY TESTING CONCEPTS:
// 1. std.testing.allocator - A special allocator that detects memory leaks
// 2. try - Propagates errors (test fails if any try fails)
// 3. defer - Ensures cleanup runs even if assertions fail
// 4. expectEqualStrings - Asserts string equality with nice diff output
// =============================================================================
test "JSON serialization of Message" {
    // Use the testing allocator - it will fail the test if we leak memory!
    const allocator = std.testing.allocator;

    // Create a test message.
    // NOTE: This test has a bug - content should be []const ContentBlock,
    // not a string. This test would need to be fixed for the new structure.
    const msg = Message{
        .role = .user,
        .content = "Hello", // BUG: Should be a slice of ContentBlock
    };

    // Create an allocating writer to capture the JSON output.
    // This is like a StringWriter in other languages.
    var allocating = std.io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    // Serialize the message to JSON.
    try std.json.Stringify.value(msg, .{}, &allocating.writer);

    // Get the resulting string.
    const slice = try allocating.toOwnedSlice();
    defer allocator.free(slice); // Clean up after assertion

    // Assert the output matches expected format.
    try std.testing.expectEqualStrings(
        "{\"role\":\"user\",\"content\":\"Hello\"}",
        slice,
    );
}

test "AuthMethod enum values" {
    // Test that AuthMethod enum works correctly
    const api_key_auth = AuthMethod.api_key;
    const oauth_auth = AuthMethod.oauth_token;

    // @tagName converts enum to string
    try std.testing.expectEqualStrings("api_key", @tagName(api_key_auth));
    try std.testing.expectEqualStrings("oauth_token", @tagName(oauth_auth));
}
