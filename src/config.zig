// =============================================================================
// config.zig - Configuration Management System
// =============================================================================
//
// FOR TYPESCRIPT DEVELOPERS:
// --------------------------
// This file handles application configuration - loading, saving, and initial
// setup (onboarding). It's similar to what you might build with:
//   - dotenv for environment variables
//   - config packages like 'conf' or 'configstore'
//   - A setup wizard for first-time users
//
// KEY CONCEPTS DEMONSTRATED:
// 1. File I/O operations (reading/writing JSON config files)
// 2. JSON parsing and serialization
// 3. Interactive console I/O (reading from stdin, writing to stdout)
// 4. Memory management with explicit allocation/deallocation
// 5. Error handling with Zig's error union types
// 6. Optional types for nullable configuration fields
//
// CONFIG FILE LOCATION:
//   ~/.config/ziggum/config.json
//
// This follows the XDG Base Directory specification for Unix-like systems.
//
// MULTI-AUTH SUPPORT:
// -------------------
// This config system supports both traditional API key authentication AND
// OAuth/subscription-based authentication (like Claude Code Pro/Max).
// The `auth_method` field determines which credentials are used.
//
// =============================================================================

const std = @import("std");
const fs_utils = @import("fs_utils.zig");
const types = @import("providers/types.zig");

// =============================================================================
// CONFIG STRUCT
// =============================================================================
// Holds the application configuration data including authentication credentials.
//
// TypeScript equivalent:
//   interface Config {
//     // Provider selection
//     provider_type: 'anthropic' | 'anthropic_oauth' | 'ollama';
//
//     // Anthropic API key auth
//     anthropic_api_key?: string;
//
//     // OAuth/subscription auth
//     anthropic_access_token?: string;
//     anthropic_refresh_token?: string;
//     anthropic_base_url?: string;
//
//     // Ollama config
//     ollama_url?: string;
//
//     // Common settings
//     model: string;
//   }
//
// DESIGN DECISION - FLAT CONFIG:
// ------------------------------
// We use a flat structure with optional fields rather than nested objects.
// This simplifies JSON serialization and makes it easy to add new providers.
// The `provider_type` field determines which credentials are actually used.
//
// DEFAULT VALUES IN ZIG:
// ----------------------
// Unlike TypeScript where defaults are handled in runtime code, Zig structs
// can have default field values directly in the type definition. These are
// used when creating instances with `.{}` syntax and omitting the field.
//
// OPTIONAL TYPES:
// ---------------
// The `?` prefix makes a type optional (nullable).
// ?[]const u8 means "string or null" - like `string | null` in TypeScript.
// =============================================================================
pub const Config = struct {
    // =========================================================================
    // PROVIDER SELECTION
    // =========================================================================
    // Determines which AI provider and authentication method to use.
    //
    // VALUES:
    //   "anthropic"       - Anthropic API with API key auth
    //   "anthropic_oauth" - Anthropic API with OAuth/subscription auth
    //   "ollama"          - Local Ollama instance
    //
    // TypeScript: provider_type: 'anthropic' | 'anthropic_oauth' | 'ollama'
    // =========================================================================
    provider_type: []const u8 = "anthropic",

    // =========================================================================
    // ANTHROPIC API KEY AUTHENTICATION
    // =========================================================================
    // Traditional API key for pay-as-you-go Anthropic API access.
    // Used when provider_type = "anthropic"
    //
    // Get your key at: https://console.anthropic.com/
    // Environment variable: ANTHROPIC_API_KEY
    // =========================================================================
    anthropic_api_key: ?[]const u8 = null,

    // =========================================================================
    // OAUTH/SUBSCRIPTION AUTHENTICATION
    // =========================================================================
    // OAuth tokens for subscription-based access (Claude Pro/Max, etc.)
    // Used when provider_type = "anthropic_oauth"
    //
    // HOW TO OBTAIN TOKENS:
    // ---------------------
    // 1. Claude Code: Run `claude` CLI and use `/login` command
    //    Tokens stored in ~/.claude/credentials.json
    //
    // 2. Custom OAuth: Implement OAuth 2.0 flow with Anthropic
    //    - Authorization endpoint, token exchange, etc.
    //
    // TOKEN LIFECYCLE:
    // ----------------
    // - access_token: Used for API requests, typically expires in hours/days
    // - refresh_token: Used to obtain new access tokens without re-login
    //
    // Environment variable: ANTHROPIC_AUTH_TOKEN (for access_token)
    // =========================================================================
    anthropic_access_token: ?[]const u8 = null, // OAuth access token
    anthropic_refresh_token: ?[]const u8 = null, // OAuth refresh token

    // Custom API base URL (for enterprise deployments or proxies)
    // Default: https://api.anthropic.com
    anthropic_base_url: ?[]const u8 = null,

    // =========================================================================
    // OLLAMA CONFIGURATION
    // =========================================================================
    // Settings for local Ollama instance.
    // Used when provider_type = "ollama"
    //
    // Default URL: http://localhost:11434/api/chat
    // =========================================================================
    ollama_url: ?[]const u8 = null,

    // =========================================================================
    // COMMON SETTINGS
    // =========================================================================
    // Model name - used by all providers
    // Examples: "claude-3-5-sonnet-latest", "llama2", "mistral"
    // =========================================================================
    model: []const u8 = "claude-3-5-sonnet-latest",

    // -------------------------------------------------------------------------
    // deinit - Clean up owned string memory
    // -------------------------------------------------------------------------
    // Config owns its strings (they were allocated with dupe), so we must free.
    //
    // IMPORTANT: In Zig, if you allocate memory with an allocator, you MUST
    // free it with the SAME allocator. This is why we pass the allocator here.
    //
    // OPTIONAL HANDLING:
    // ------------------
    // For optional fields (?[]const u8), we only free if the value is not null.
    // The `if (field) |value|` syntax unwraps the optional if it has a value.
    //
    // TypeScript comparison:
    //   No equivalent - JS GC handles this automatically.
    //   But think of it like manually calling .dispose() on resources.
    // -------------------------------------------------------------------------
    pub fn deinit(self: Config, allocator: std.mem.Allocator) void {
        // Free provider_type (always present, has default)
        allocator.free(self.provider_type);

        // Free optional Anthropic API key
        if (self.anthropic_api_key) |key| allocator.free(key);

        // Free optional OAuth tokens
        if (self.anthropic_access_token) |token| allocator.free(token);
        if (self.anthropic_refresh_token) |token| allocator.free(token);
        if (self.anthropic_base_url) |url| allocator.free(url);

        // Free optional Ollama URL
        if (self.ollama_url) |url| allocator.free(url);

        // Free model (always present, has default)
        allocator.free(self.model);
    }

    // -------------------------------------------------------------------------
    // toProvider - Convert Config to Provider tagged union
    // -------------------------------------------------------------------------
    // Creates the appropriate Provider variant based on provider_type.
    // This bridges the gap between the flat config file and the typed Provider.
    //
    // RETURN TYPE: `!types.Provider`
    // Returns a Provider on success, or an error if config is invalid.
    //
    // ERRORS:
    //   error.MissingApiKey - API key auth selected but no key provided
    //   error.MissingAccessToken - OAuth auth selected but no token provided
    //   error.MissingOllamaUrl - Ollama selected but no URL provided
    //   error.UnknownProviderType - Invalid provider_type value
    //
    // MEMORY OWNERSHIP:
    // -----------------
    // The returned Provider contains REFERENCES to strings owned by Config.
    // DO NOT free the Config while the Provider is still in use!
    //
    // TypeScript equivalent:
    //   toProvider(): Provider {
    //     switch (this.provider_type) {
    //       case 'anthropic': return { type: 'anthropic', ... };
    //       case 'anthropic_oauth': return { type: 'anthropic_oauth', ... };
    //       case 'ollama': return { type: 'ollama', ... };
    //       default: throw new Error('Unknown provider');
    //     }
    //   }
    // -------------------------------------------------------------------------
    pub fn toProvider(self: Config) !types.Provider {
        // Check provider_type and create the appropriate variant
        if (std.mem.eql(u8, self.provider_type, "anthropic")) {
            // Traditional API key authentication
            const api_key = self.anthropic_api_key orelse {
                return error.MissingApiKey;
            };
            return types.Provider{
                .anthropic = .{
                    .api_key = api_key,
                    .model = self.model,
                },
            };
        } else if (std.mem.eql(u8, self.provider_type, "anthropic_oauth")) {
            // OAuth/subscription authentication
            const access_token = self.anthropic_access_token orelse {
                return error.MissingAccessToken;
            };
            return types.Provider{
                .anthropic_oauth = .{
                    .access_token = access_token,
                    .refresh_token = self.anthropic_refresh_token,
                    .model = self.model,
                    .base_url = self.anthropic_base_url,
                },
            };
        } else if (std.mem.eql(u8, self.provider_type, "ollama")) {
            // Local Ollama instance
            const url = self.ollama_url orelse {
                return error.MissingOllamaUrl;
            };
            return types.Provider{
                .ollama = .{
                    .model = self.model,
                    .url = url,
                },
            };
        } else {
            return error.UnknownProviderType;
        }
    }
};

// =============================================================================
// CONFIG MANAGER STRUCT
// =============================================================================
// Handles loading, saving, and initializing configuration.
// This is a "manager" pattern - a stateless struct that encapsulates operations.
//
// TypeScript equivalent:
//   class ConfigManager {
//     constructor(private allocator: Allocator) {}
//     load(): Config | null { ... }
//     save(config: Config): void { ... }
//     initOnboarding(): Config { ... }
//   }
//
// WHY A STRUCT WITH ONE FIELD?
// ----------------------------
// We need to pass an allocator to all operations. Rather than passing it to
// every function, we store it in the struct. This is common in Zig - structs
// often hold their dependencies (like allocators) as fields.
// =============================================================================
pub const ConfigManager = struct {
    // The allocator used for all memory operations.
    // This is Zig's dependency injection pattern.
    allocator: std.mem.Allocator,

    // =========================================================================
    // load - Load configuration from disk
    // =========================================================================
    // Attempts to read and parse the config file.
    //
    // RETURN TYPE: `!?Config`
    // -----------------------
    // This is a powerful Zig idiom combining two concepts:
    //   - `?Config` = Optional (Config or null)
    //   - `!` = Error union (might return an error)
    //
    // So `!?Config` means: "Returns Config, or null, or an error"
    //
    // TypeScript equivalent:
    //   async load(): Promise<Config | null> {
    //     // throws on read/parse errors
    //     // returns null if file doesn't exist
    //   }
    //
    // MEMORY OWNERSHIP:
    // -----------------
    // The returned Config OWNS its strings - they are newly allocated copies.
    // The caller is responsible for calling config.deinit() when done.
    // =========================================================================
    pub fn load(self: ConfigManager) !?Config {
        // ---------------------------------------------------------------------
        // Get the config file path
        // ---------------------------------------------------------------------
        const path = try fs_utils.getConfigPath(self.allocator);
        defer self.allocator.free(path.dir);
        defer self.allocator.free(path.file);

        // ---------------------------------------------------------------------
        // Open the config file
        // ---------------------------------------------------------------------
        const file = std.fs.openFileAbsolute(path.file, .{}) catch |err| {
            if (err == error.FileNotFound) return null; // No config yet - OK!
            return err; // Other error - propagate it
        };
        defer file.close();

        // ---------------------------------------------------------------------
        // Read the entire file content
        // ---------------------------------------------------------------------
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        // ---------------------------------------------------------------------
        // Parse JSON into Config struct
        // ---------------------------------------------------------------------
        const parsed = try std.json.parseFromSlice(
            Config,
            self.allocator,
            content,
            .{},
        );
        defer parsed.deinit();

        // ---------------------------------------------------------------------
        // Create an owned copy
        // ---------------------------------------------------------------------
        // CRITICAL: parsed.value contains slices pointing into `content`.
        // We must copy all strings to create an independent Config.
        //
        // HELPER FUNCTION FOR OPTIONALS:
        // We use a local helper to handle duplicating optional strings.
        // ---------------------------------------------------------------------
        const dupeOptional = struct {
            fn dupe(alloc: std.mem.Allocator, maybe_str: ?[]const u8) !?[]const u8 {
                if (maybe_str) |str| {
                    return try alloc.dupe(u8, str);
                }
                return null;
            }
        }.dupe;

        return Config{
            .provider_type = try self.allocator.dupe(u8, parsed.value.provider_type),
            .anthropic_api_key = try dupeOptional(self.allocator, parsed.value.anthropic_api_key),
            .anthropic_access_token = try dupeOptional(self.allocator, parsed.value.anthropic_access_token),
            .anthropic_refresh_token = try dupeOptional(self.allocator, parsed.value.anthropic_refresh_token),
            .anthropic_base_url = try dupeOptional(self.allocator, parsed.value.anthropic_base_url),
            .ollama_url = try dupeOptional(self.allocator, parsed.value.ollama_url),
            .model = try self.allocator.dupe(u8, parsed.value.model),
        };
    }

    // =========================================================================
    // save - Save configuration to disk
    // =========================================================================
    // Writes the config to the config file as JSON.
    //
    // TypeScript equivalent:
    //   async save(config: Config): Promise<void> {
    //     await fs.mkdir(configDir, { recursive: true });
    //     await fs.writeFile(configPath, JSON.stringify(config));
    //     await fs.chmod(configPath, 0o600);
    //   }
    // =========================================================================
    pub fn save(self: ConfigManager, config: Config) !void {
        const path = try fs_utils.getConfigPath(self.allocator);
        defer self.allocator.free(path.dir);
        defer self.allocator.free(path.file);

        try fs_utils.ensureConfigDir(path.dir);

        const file = try std.fs.createFileAbsolute(path.file, .{});
        defer file.close();

        var stdout_buf: [4096]u8 = undefined; // Larger buffer for more fields
        var writer = file.writer(&stdout_buf);
        try std.json.Stringify.value(config, .{}, &writer.interface);
        try writer.interface.flush();

        try fs_utils.ensureConfigFilePerms(path.file);
    }

    // =========================================================================
    // initOnboarding - Interactive first-time setup
    // =========================================================================
    // Guides the user through initial configuration via console prompts.
    // Now supports multiple authentication methods!
    //
    // FLOW:
    // 1. Ask user which authentication method they want to use
    // 2. Prompt for the appropriate credentials
    // 3. Save config and return
    //
    // TypeScript equivalent:
    //   async initOnboarding(): Promise<Config> {
    //     const rl = readline.createInterface({ input: stdin, output: stdout });
    //     const authMethod = await rl.question('Choose auth method: ');
    //     // ... prompt for credentials based on choice
    //   }
    // =========================================================================
    pub fn initOnboarding(self: ConfigManager) !Config {
        var stdout_buf: [1024]u8 = undefined;
        var stdout_wrapped = std.fs.File.stdout().writer(&stdout_buf);
        const stdout = &stdout_wrapped.interface;

        var stdin_buf: [1024]u8 = undefined;
        var stdin = std.fs.File.stdin().reader(&stdin_buf);

        // ---------------------------------------------------------------------
        // Display onboarding header
        // ---------------------------------------------------------------------
        try stdout.writeAll("\n");
        try stdout.writeAll(" 🤠 ONBOARDING: OBTAINING YOUR BADGE \n");
        try stdout.writeAll(" ──────────────────────────────────── \n\n");

        try stdout.writeAll(" Welcome to Ziggum. Let's set up your AI provider.\n\n");

        // ---------------------------------------------------------------------
        // Prompt for authentication method
        // ---------------------------------------------------------------------
        try stdout.writeAll(" Choose your authentication method:\n");
        try stdout.writeAll("   [1] Anthropic API Key (pay-as-you-go)\n");
        try stdout.writeAll("   [2] Anthropic OAuth Token (Pro/Max subscription)\n");
        try stdout.writeAll("   [3] Local Ollama\n\n");

        try stdout.writeAll(" [ CHOICE (1/2/3) ] > ");
        try stdout.flush();

        const choice_raw = try stdin.interface.takeDelimiter('\n') orelse {
            return error.EndOfStream;
        };
        const choice = std.mem.trim(u8, choice_raw, " \r\n");

        // ---------------------------------------------------------------------
        // Handle each authentication method
        // ---------------------------------------------------------------------
        if (std.mem.eql(u8, choice, "1")) {
            // API Key authentication
            try stdout.writeAll("\n Your key will be stored securely in ~/.config/ziggum/config.json\n\n");
            try stdout.writeAll(" [ 🔑 ANTHROPIC API KEY ] > ");
            try stdout.flush();

            const key_raw = try stdin.interface.takeDelimiter('\n') orelse {
                return error.EndOfStream;
            };
            const key = std.mem.trim(u8, key_raw, " \r\n");

            const config = Config{
                .provider_type = try self.allocator.dupe(u8, "anthropic"),
                .anthropic_api_key = try self.allocator.dupe(u8, key),
                .model = try self.allocator.dupe(u8, "claude-3-5-sonnet-latest"),
            };

            try self.save(config);
            try stdout.writeAll("\n [ ✅ API KEY SECURED ]\n\n");
            try stdout.flush();
            return config;
        } else if (std.mem.eql(u8, choice, "2")) {
            // OAuth token authentication
            try stdout.writeAll("\n For OAuth auth, you need an access token from your subscription.\n");
            try stdout.writeAll(" (Claude Code users: check ~/.claude/credentials.json)\n\n");
            try stdout.writeAll(" [ 🎫 ACCESS TOKEN ] > ");
            try stdout.flush();

            const token_raw = try stdin.interface.takeDelimiter('\n') orelse {
                return error.EndOfStream;
            };
            const token = std.mem.trim(u8, token_raw, " \r\n");

            // Optionally ask for refresh token
            try stdout.writeAll("\n [ 🔄 REFRESH TOKEN (optional, press Enter to skip) ] > ");
            try stdout.flush();

            const refresh_raw = try stdin.interface.takeDelimiter('\n') orelse {
                return error.EndOfStream;
            };
            const refresh = std.mem.trim(u8, refresh_raw, " \r\n");

            const config = Config{
                .provider_type = try self.allocator.dupe(u8, "anthropic_oauth"),
                .anthropic_access_token = try self.allocator.dupe(u8, token),
                .anthropic_refresh_token = if (refresh.len > 0)
                    try self.allocator.dupe(u8, refresh)
                else
                    null,
                .model = try self.allocator.dupe(u8, "claude-3-5-sonnet-latest"),
            };

            try self.save(config);
            try stdout.writeAll("\n [ ✅ OAUTH TOKEN SECURED ]\n\n");
            try stdout.flush();
            return config;
        } else if (std.mem.eql(u8, choice, "3")) {
            // Ollama (local)
            try stdout.writeAll("\n Enter your Ollama API URL (or press Enter for default):\n");
            try stdout.writeAll(" Default: http://localhost:11434/api/chat\n\n");
            try stdout.writeAll(" [ 🦙 OLLAMA URL ] > ");
            try stdout.flush();

            const url_raw = try stdin.interface.takeDelimiter('\n') orelse {
                return error.EndOfStream;
            };
            const url_trimmed = std.mem.trim(u8, url_raw, " \r\n");
            const url = if (url_trimmed.len > 0)
                url_trimmed
            else
                "http://localhost:11434/api/chat";

            try stdout.writeAll("\n [ MODEL NAME ] > ");
            try stdout.flush();

            const model_raw = try stdin.interface.takeDelimiter('\n') orelse {
                return error.EndOfStream;
            };
            const model_trimmed = std.mem.trim(u8, model_raw, " \r\n");
            const model = if (model_trimmed.len > 0)
                model_trimmed
            else
                "llama2";

            const config = Config{
                .provider_type = try self.allocator.dupe(u8, "ollama"),
                .ollama_url = try self.allocator.dupe(u8, url),
                .model = try self.allocator.dupe(u8, model),
            };

            try self.save(config);
            try stdout.writeAll("\n [ ✅ OLLAMA CONFIGURED ]\n\n");
            try stdout.flush();
            return config;
        } else {
            // Invalid choice - default to API key
            try stdout.writeAll("\n Invalid choice. Defaulting to API key authentication.\n\n");
            try stdout.writeAll(" [ 🔑 ANTHROPIC API KEY ] > ");
            try stdout.flush();

            const key_raw = try stdin.interface.takeDelimiter('\n') orelse {
                return error.EndOfStream;
            };
            const key = std.mem.trim(u8, key_raw, " \r\n");

            const config = Config{
                .provider_type = try self.allocator.dupe(u8, "anthropic"),
                .anthropic_api_key = try self.allocator.dupe(u8, key),
                .model = try self.allocator.dupe(u8, "claude-3-5-sonnet-latest"),
            };

            try self.save(config);
            try stdout.writeAll("\n [ ✅ API KEY SECURED ]\n\n");
            try stdout.flush();
            return config;
        }
    }
};

// =============================================================================
// UNIT TESTS
// =============================================================================
test "Config serialization" {
    const allocator = std.testing.allocator;

    const config = Config{
        .provider_type = "anthropic",
        .anthropic_api_key = "test-key",
        .model = "test-model",
    };

    var allocating = std.io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    try std.json.Stringify.value(config, .{}, &allocating.writer);

    const slice = try allocating.toOwnedSlice();
    defer allocator.free(slice);

    const parsed = try std.json.parseFromSlice(Config, allocator, slice, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings(config.provider_type, parsed.value.provider_type);
    try std.testing.expectEqualStrings(config.model, parsed.value.model);
}

test "Config toProvider - anthropic" {
    const config = Config{
        .provider_type = "anthropic",
        .anthropic_api_key = "test-key",
        .model = "claude-3-5-sonnet-latest",
    };

    const provider = try config.toProvider();

    switch (provider) {
        .anthropic => |a| {
            try std.testing.expectEqualStrings("test-key", a.api_key);
            try std.testing.expectEqualStrings("claude-3-5-sonnet-latest", a.model);
        },
        else => return error.UnexpectedProviderType,
    }
}

test "Config toProvider - anthropic_oauth" {
    const config = Config{
        .provider_type = "anthropic_oauth",
        .anthropic_access_token = "oauth-token-123",
        .anthropic_refresh_token = "refresh-token-456",
        .model = "claude-3-5-sonnet-latest",
    };

    const provider = try config.toProvider();

    switch (provider) {
        .anthropic_oauth => |a| {
            try std.testing.expectEqualStrings("oauth-token-123", a.access_token);
            try std.testing.expectEqualStrings("refresh-token-456", a.refresh_token.?);
            try std.testing.expectEqualStrings("claude-3-5-sonnet-latest", a.model);
        },
        else => return error.UnexpectedProviderType,
    }
}
