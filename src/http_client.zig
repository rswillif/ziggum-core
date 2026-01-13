// =============================================================================
// http_client.zig - HTTP Client for AI Provider APIs
// =============================================================================
//
// FOR TYPESCRIPT DEVELOPERS:
// --------------------------
// This file is responsible for making HTTP requests to AI provider APIs.
// It's similar to what you might build with:
//   - fetch() or axios for HTTP requests
//   - A service layer that adapts different AI providers to a common interface
//
// KEY CONCEPTS DEMONSTRATED:
// 1. Switch expressions on tagged unions (polymorphism without classes)
// 2. HTTP client usage in Zig's standard library
// 3. JSON serialization for request bodies
// 4. JSON parsing for response bodies
// 5. Complex memory management with multiple allocations
// 6. Error handling with detailed error cases
// 7. Different authentication methods (API key vs OAuth Bearer token)
//
// ARCHITECTURE OVERVIEW:
// ----------------------
// This module provides a `send()` function that works with any Provider type.
// It acts as an adapter layer:
//
//   [Your Code] -> send(provider, messages, tools)
//                    |
//                    +-> Mock provider: returns canned response
//                    +-> Ollama provider: calls local Ollama API
//                    +-> Anthropic provider: calls Claude API (API key auth)
//                    +-> Anthropic OAuth provider: calls Claude API (Bearer token)
//                    |
//                 <- Response (unified format)
//
// AUTHENTICATION METHODS:
// -----------------------
// 1. API Key (x-api-key header):
//    Used by standard Anthropic API for pay-as-you-go billing.
//    Header: x-api-key: sk-ant-api03-...
//
// 2. OAuth Bearer Token (Authorization header):
//    Used by subscription services like Claude Code Pro/Max.
//    Header: Authorization: Bearer <oauth_token>
//
// =============================================================================

const std = @import("std");
const types = @import("providers/types.zig");
const json_utils = @import("json_utils.zig");

// =============================================================================
// DEFAULT API ENDPOINTS
// =============================================================================
// Default URLs for various AI provider APIs.
//
// TypeScript equivalent:
//   const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
// =============================================================================
const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";

// =============================================================================
// send - Send a message to an AI provider and get a response
// =============================================================================
// This is the main function of this module. It handles all AI provider
// interactions through a unified interface.
//
// PARAMETERS:
//   allocator: Memory allocator for all dynamic allocations
//   provider: Tagged union specifying which provider to use and its config
//   messages: Conversation history (array of Message structs)
//   tools: Available tools Claude can use (array of Tool structs)
//
// RETURN TYPE: `!types.Response`
// Returns a Response containing content blocks, or an error.
//
// MEMORY OWNERSHIP:
// -----------------
// The returned Response OWNS all its content. The caller is responsible for
// calling response.deinit(allocator) when done.
//
// TypeScript equivalent:
//   async function send(
//     provider: Provider,
//     messages: Message[],
//     tools: Tool[]
//   ): Promise<Response> { ... }
// =============================================================================
pub fn send(
    allocator: std.mem.Allocator,
    provider: types.Provider,
    messages: []const types.Message,
    tools: []const types.Tool,
) !types.Response {
    // -------------------------------------------------------------------------
    // SWITCH ON PROVIDER TYPE
    // -------------------------------------------------------------------------
    // Zig's switch on tagged unions is exhaustive - we MUST handle all variants.
    // This is a key safety feature: if we add a new provider type later,
    // the compiler will error here until we handle it.
    //
    // TypeScript analogy:
    //   switch (provider.type) {
    //     case 'mock': return handleMock(provider);
    //     case 'ollama': return handleOllama(provider);
    //     case 'anthropic': return handleAnthropic(provider);
    //     case 'anthropic_oauth': return handleAnthropicOAuth(provider);
    //   }
    //
    // The `|m|`, `|ollama|`, `|anthropic|` syntax captures the variant's data.
    // -------------------------------------------------------------------------
    switch (provider) {
        // =====================================================================
        // MOCK PROVIDER
        // =====================================================================
        // Returns a canned response without making any network calls.
        // Perfect for testing and development.
        //
        // TypeScript:
        //   if (provider.type === 'mock') {
        //     return { content: [{ type: 'text', text: provider.response }] };
        //   }
        // =====================================================================
        .mock => |m| {
            // Create an ArrayList to hold the response content blocks.
            // initCapacity pre-allocates space for 1 element (we know the size).
            var response_blocks = try std.ArrayList(types.ContentBlock).initCapacity(allocator, 1);

            // Add a single text block with the mock response.
            // Note: We dupe the string to give the Response ownership.
            try response_blocks.append(allocator, .{
                .text = try allocator.dupe(u8, m.response),
            });

            // Convert ArrayList to owned slice and return as Response.
            return .{ .content = try response_blocks.toOwnedSlice(allocator) };
        },

        // =====================================================================
        // OLLAMA PROVIDER
        // =====================================================================
        // Sends a request to a local Ollama server.
        // Ollama runs open-source models locally on your machine.
        //
        // API: POST http://localhost:11434/api/generate (or custom URL)
        // Payload: { "model": "llama2", "messages": [...], "stream": false }
        // =====================================================================
        .ollama => |ollama| {
            var client = std.http.Client{ .allocator = allocator };
            defer client.deinit();

            var payload_allocating = std.io.Writer.Allocating.init(allocator);
            defer payload_allocating.deinit();

            try std.json.Stringify.value(.{
                .model = ollama.model,
                .messages = messages,
                .stream = false,
            }, .{}, &payload_allocating.writer);

            const payload = try payload_allocating.toOwnedSlice();
            defer allocator.free(payload);

            var response_allocating = std.io.Writer.Allocating.init(allocator);
            defer response_allocating.deinit();

            const result = try client.fetch(.{
                .location = .{ .url = ollama.url },
                .method = .POST,
                .payload = payload,
                .response_writer = &response_allocating.writer,
            });

            if (result.status != .ok) return error.HttpError;

            const body = try response_allocating.toOwnedSlice();
            var response_blocks = try std.ArrayList(types.ContentBlock).initCapacity(allocator, 1);
            try response_blocks.append(allocator, .{ .text = body });
            return .{ .content = try response_blocks.toOwnedSlice(allocator) };
        },

        // =====================================================================
        // ANTHROPIC PROVIDER (API Key Authentication)
        // =====================================================================
        // Sends a request to Claude's API using traditional API key auth.
        // This is the standard pay-as-you-go method.
        //
        // API: POST https://api.anthropic.com/v1/messages
        // Headers:
        //   x-api-key: <api_key>           <- API KEY AUTH
        //   anthropic-version: 2023-06-01
        //   content-type: application/json
        //
        // AUTHENTICATION HEADER DIFFERENCE:
        // ---------------------------------
        // API Key auth uses: x-api-key: <key>
        // OAuth auth uses:   Authorization: Bearer <token>
        //
        // This is a key distinction for subscription-based services!
        // =====================================================================
        .anthropic => |anthropic| {
            var client = std.http.Client{ .allocator = allocator };
            defer client.deinit();

            // Build tools array in Anthropic's expected format
            var tools_val_list = try std.ArrayList(std.json.Value).initCapacity(allocator, tools.len);
            defer {
                tools_val_list.deinit(allocator);
            }

            for (tools) |t| {
                const schema_parsed = try std.json.parseFromSlice(
                    std.json.Value,
                    allocator,
                    t.input_schema_json,
                    .{},
                );
                defer schema_parsed.deinit();

                var t_map = std.json.ObjectMap.init(allocator);
                try t_map.put(
                    try allocator.dupe(u8, "name"),
                    .{ .string = try allocator.dupe(u8, t.name) },
                );
                try t_map.put(
                    try allocator.dupe(u8, "description"),
                    .{ .string = try allocator.dupe(u8, t.description) },
                );
                try t_map.put(
                    try allocator.dupe(u8, "input_schema"),
                    try json_utils.deepCopy(allocator, schema_parsed.value),
                );

                try tools_val_list.append(allocator, .{ .object = t_map });
            }

            // Build request payload
            var payload_allocating = std.io.Writer.Allocating.init(allocator);
            defer payload_allocating.deinit();

            if (tools.len > 0) {
                try std.json.Stringify.value(.{
                    .model = anthropic.model,
                    .messages = messages,
                    .max_tokens = 4096,
                    .tools = tools_val_list.items,
                }, .{}, &payload_allocating.writer);
            } else {
                try std.json.Stringify.value(.{
                    .model = anthropic.model,
                    .messages = messages,
                    .max_tokens = 4096,
                }, .{}, &payload_allocating.writer);
            }

            // Clean up tools JSON values
            for (tools_val_list.items) |v| {
                json_utils.free(allocator, v);
            }

            const payload = try payload_allocating.toOwnedSlice();
            defer allocator.free(payload);

            var response_allocating = std.io.Writer.Allocating.init(allocator);
            defer response_allocating.deinit();

            // -----------------------------------------------------------------
            // API KEY AUTHENTICATION HEADERS
            // -----------------------------------------------------------------
            // Note the x-api-key header - this is Anthropic's API key auth.
            // This is different from OAuth which uses Authorization: Bearer
            // -----------------------------------------------------------------
            const headers = [_]std.http.Header{
                .{ .name = "x-api-key", .value = anthropic.api_key },
                .{ .name = "anthropic-version", .value = "2023-06-01" },
                .{ .name = "content-type", .value = "application/json" },
            };

            const result = try client.fetch(.{
                .location = .{ .url = ANTHROPIC_API_URL },
                .method = .POST,
                .payload = payload,
                .extra_headers = &headers,
                .response_writer = &response_allocating.writer,
            });

            if (result.status != .ok) {
                const err_body = try response_allocating.toOwnedSlice();
                std.debug.print("Anthropic Error: {s}\n", .{err_body});
                allocator.free(err_body);
                return error.AnthropicError;
            }

            // Parse response using shared helper
            return try parseAnthropicResponse(allocator, &response_allocating);
        },

        // =====================================================================
        // ANTHROPIC OAUTH PROVIDER (Bearer Token Authentication)
        // =====================================================================
        // Sends a request to Claude's API using OAuth/Bearer token auth.
        // Used by subscription services like Claude Code Pro/Max.
        //
        // API: POST https://api.anthropic.com/v1/messages (or custom base_url)
        // Headers:
        //   Authorization: Bearer <token>  <- OAUTH/BEARER AUTH
        //   anthropic-version: 2023-06-01
        //   content-type: application/json
        //
        // KEY DIFFERENCES FROM API KEY AUTH:
        // ----------------------------------
        // 1. Uses "Authorization: Bearer <token>" instead of "x-api-key"
        // 2. Supports custom base_url for enterprise deployments
        // 3. Tokens may expire (unlike API keys which are long-lived)
        // 4. Billing is through subscription, not per-token
        //
        // OAUTH TOKEN SOURCES:
        // --------------------
        // - Claude Code CLI: ~/.claude/credentials.json after /login
        // - Custom OAuth flow: Token exchange after user authorization
        // - Environment variable: ANTHROPIC_AUTH_TOKEN
        //
        // TypeScript equivalent:
        //   const response = await fetch(baseUrl || 'https://api.anthropic.com/v1/messages', {
        //     method: 'POST',
        //     headers: {
        //       'Authorization': `Bearer ${accessToken}`,  // OAuth!
        //       'anthropic-version': '2023-06-01',
        //       'content-type': 'application/json'
        //     },
        //     body: JSON.stringify({ model, messages, max_tokens: 4096 })
        //   });
        // =====================================================================
        .anthropic_oauth => |oauth| {
            var client = std.http.Client{ .allocator = allocator };
            defer client.deinit();

            // -----------------------------------------------------------------
            // Build tools array (same as API key auth)
            // -----------------------------------------------------------------
            var tools_val_list = try std.ArrayList(std.json.Value).initCapacity(allocator, tools.len);
            defer {
                tools_val_list.deinit(allocator);
            }

            for (tools) |t| {
                const schema_parsed = try std.json.parseFromSlice(
                    std.json.Value,
                    allocator,
                    t.input_schema_json,
                    .{},
                );
                defer schema_parsed.deinit();

                var t_map = std.json.ObjectMap.init(allocator);
                try t_map.put(
                    try allocator.dupe(u8, "name"),
                    .{ .string = try allocator.dupe(u8, t.name) },
                );
                try t_map.put(
                    try allocator.dupe(u8, "description"),
                    .{ .string = try allocator.dupe(u8, t.description) },
                );
                try t_map.put(
                    try allocator.dupe(u8, "input_schema"),
                    try json_utils.deepCopy(allocator, schema_parsed.value),
                );

                try tools_val_list.append(allocator, .{ .object = t_map });
            }

            // -----------------------------------------------------------------
            // Build request payload (same as API key auth)
            // -----------------------------------------------------------------
            var payload_allocating = std.io.Writer.Allocating.init(allocator);
            defer payload_allocating.deinit();

            if (tools.len > 0) {
                try std.json.Stringify.value(.{
                    .model = oauth.model,
                    .messages = messages,
                    .max_tokens = 4096,
                    .tools = tools_val_list.items,
                }, .{}, &payload_allocating.writer);
            } else {
                try std.json.Stringify.value(.{
                    .model = oauth.model,
                    .messages = messages,
                    .max_tokens = 4096,
                }, .{}, &payload_allocating.writer);
            }

            // Clean up tools JSON values
            for (tools_val_list.items) |v| {
                json_utils.free(allocator, v);
            }

            const payload = try payload_allocating.toOwnedSlice();
            defer allocator.free(payload);

            var response_allocating = std.io.Writer.Allocating.init(allocator);
            defer response_allocating.deinit();

            // -----------------------------------------------------------------
            // BUILD OAUTH BEARER TOKEN HEADER
            // -----------------------------------------------------------------
            // This is the KEY difference from API key auth!
            //
            // Format: "Authorization: Bearer <access_token>"
            //
            // We need to build this string dynamically because the token
            // is a runtime value. We allocate a buffer, format the header,
            // and use it for the request.
            //
            // TypeScript:
            //   headers['Authorization'] = `Bearer ${accessToken}`;
            // -----------------------------------------------------------------
            var auth_header_buf: [2048]u8 = undefined;
            const auth_header = std.fmt.bufPrint(
                &auth_header_buf,
                "Bearer {s}",
                .{oauth.access_token},
            ) catch return error.AuthHeaderTooLong;

            // -----------------------------------------------------------------
            // OAUTH AUTHENTICATION HEADERS
            // -----------------------------------------------------------------
            // Note: Authorization header with Bearer token instead of x-api-key
            // -----------------------------------------------------------------
            const headers = [_]std.http.Header{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "anthropic-version", .value = "2023-06-01" },
                .{ .name = "content-type", .value = "application/json" },
            };

            // -----------------------------------------------------------------
            // DETERMINE API URL
            // -----------------------------------------------------------------
            // OAuth provider supports custom base_url for enterprise deployments
            // or proxy servers. Falls back to default Anthropic URL if not set.
            //
            // TypeScript:
            //   const url = oauth.baseUrl ?? 'https://api.anthropic.com/v1/messages';
            // -----------------------------------------------------------------
            const api_url = oauth.base_url orelse ANTHROPIC_API_URL;

            const result = try client.fetch(.{
                .location = .{ .url = api_url },
                .method = .POST,
                .payload = payload,
                .extra_headers = &headers,
                .response_writer = &response_allocating.writer,
            });

            // -----------------------------------------------------------------
            // HANDLE OAUTH-SPECIFIC ERRORS
            // -----------------------------------------------------------------
            // OAuth tokens can expire! A 401 Unauthorized likely means the
            // access token needs to be refreshed using the refresh_token.
            //
            // TODO: Implement automatic token refresh when we get 401
            // This would involve:
            // 1. Detecting 401 response
            // 2. Using refresh_token to get new access_token
            // 3. Retrying the request with new token
            // 4. Updating stored credentials
            //
            // For now, we just return an error and let the caller handle it.
            // -----------------------------------------------------------------
            if (result.status != .ok) {
                const err_body = try response_allocating.toOwnedSlice();
                std.debug.print("Anthropic OAuth Error (status {}): {s}\n", .{
                    @intFromEnum(result.status),
                    err_body,
                });
                allocator.free(err_body);

                // Return specific error for auth failures
                if (result.status == .unauthorized) {
                    return error.OAuthTokenExpired;
                }
                return error.AnthropicError;
            }

            // Parse response using shared helper
            return try parseAnthropicResponse(allocator, &response_allocating);
        },
    }
}

// =============================================================================
// parseAnthropicResponse - Parse Anthropic API response JSON
// =============================================================================
// Shared helper function to parse Anthropic's response format.
// Used by both API key and OAuth providers since the response format is identical.
//
// This demonstrates the DRY (Don't Repeat Yourself) principle in Zig.
// Instead of duplicating parsing logic, we extract it to a helper function.
//
// RESPONSE FORMAT:
// {
//   "content": [
//     { "type": "text", "text": "Hello!" },
//     { "type": "tool_use", "id": "...", "name": "...", "input": {...} }
//   ],
//   ... other fields we ignore ...
// }
//
// TypeScript equivalent:
//   function parseAnthropicResponse(body: string): Response {
//     const parsed = JSON.parse(body);
//     return {
//       content: parsed.content.map(block => {
//         if (block.type === 'text') return { type: 'text', text: block.text };
//         if (block.type === 'tool_use') return { type: 'tool_use', ... };
//       })
//     };
//   }
// =============================================================================
fn parseAnthropicResponse(
    allocator: std.mem.Allocator,
    response_allocating: *std.io.Writer.Allocating,
) !types.Response {
    const body = try response_allocating.toOwnedSlice();
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        body,
        .{},
    );
    defer parsed.deinit();

    // Extract content array
    const content_arr = parsed.value.object.get("content") orelse {
        return error.InvalidResponse;
    };

    // Build response blocks
    var response_blocks = try std.ArrayList(types.ContentBlock).initCapacity(
        allocator,
        content_arr.array.items.len,
    );

    // Error cleanup handler
    errdefer {
        for (response_blocks.items) |b| {
            switch (b) {
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
        response_blocks.deinit(allocator);
    }

    // Process each content block
    for (content_arr.array.items) |block_val| {
        const type_str = block_val.object.get("type") orelse continue;

        if (std.mem.eql(u8, type_str.string, "text")) {
            const text = block_val.object.get("text") orelse continue;
            try response_blocks.append(allocator, .{
                .text = try allocator.dupe(u8, text.string),
            });
        } else if (std.mem.eql(u8, type_str.string, "tool_use")) {
            const id = block_val.object.get("id") orelse continue;
            const name = block_val.object.get("name") orelse continue;
            const input = block_val.object.get("input") orelse continue;

            try response_blocks.append(allocator, .{
                .tool_use = .{
                    .id = try allocator.dupe(u8, id.string),
                    .name = try allocator.dupe(u8, name.string),
                    .input = try json_utils.deepCopy(allocator, input),
                },
            });
        }
    }

    return .{ .content = try response_blocks.toOwnedSlice(allocator) };
}
