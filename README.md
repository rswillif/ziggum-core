```text
 ██████   ███   ████  ████   █   █  █   █          ████    ████   ████   █████
      █    █   █      █      █   █  ██ ██         █       █    █  █   █  █    
    █      █   █ ███  █ ███  █   █  █ █ █  ████   █       █    █  ████   ████ 
  █        █   █   █  █   █  █   █  █   █         █       █    █  █  █   █    
 ██████   ███   ████  ████    ███   █   █          ████    ████   █   █  █████
```


> *"Me fail build? That's unpossible!"*


**ziggum-core** is the high-performance, core engine for open source agent frameworks. It is a synchronous Zig library that exposes a Blocking C ABI for LLM interaction and system tool execution.

---

## Features

- **C ABI**: Simple, reliable interface for embedding in any language (TypeScript/Bun, C, etc.).
- **Multi-Auth Support**: Works with API keys (pay-as-you-go) OR OAuth tokens (Claude Pro/Max subscriptions).
- **System Tools**: Low-level filesystem and shell access tools for the agent.
- **Memory Safe**: Strict manual memory management with explicit allocators.

## Installation

To build the shared library (`.dylib` or `.so`):

```bash
./install.sh
```

The library will be located in `zig-out/lib/`.

## Build & Test

```bash
# Build shared library
zig build

# Run unit tests
zig build test
```

## Documentation

Comprehensive documentation is available in the [docs/](docs/) directory:

- [**The Inner Machinations**](docs/ARCHITECTURE.md): Architecture overview.
- [**The Secret Club Rules**](docs/CONFIGURATION.md): Configuration details.
- [**Legacy Specs**](docs/): Historical design documents.

---

## Learn Zig Through Real Code

**This project doubles as a learning resource for TypeScript/JavaScript developers curious about Zig.**

Every `.zig` file in this codebase is extensively commented with:

- **TypeScript comparisons** - Direct parallels to patterns you already know
- **Memory management explanations** - The "why" behind allocators and `defer`
- **Concept breakdowns** - Tagged unions, error unions, comptime, and more
- **Line-by-line annotations** - No magic left unexplained

### Why Zig?

If you're a TypeScript developer, you might wonder why learn a systems language:

| TypeScript | Zig |
|------------|-----|
| Garbage collected | Manual memory (but safe patterns!) |
| Runtime type checks | Compile-time guarantees |
| Node.js runtime overhead | Direct machine code |
| `npm install` 500MB | Zero dependencies |
| "It works on my machine" | Cross-compile to any target |

Zig gives you **C-level performance** with **modern ergonomics** and **no hidden control flow**.

### File Guide for Learners

Start here and work your way through:

| File | What You'll Learn |
|------|-------------------|
| [`build.zig`](build.zig) | Build system (like package.json + tsconfig combined) |
| [`src/lib.zig`](src/lib.zig) | Main entry point, structs, FFI exports |
| [`src/providers/types.zig`](src/providers/types.zig) | Enums, tagged unions (discriminated unions), multi-provider patterns |
| [`src/config.zig`](src/config.zig) | File I/O, JSON parsing, error handling, multi-auth config |
| [`src/fs_utils.zig`](src/fs_utils.zig) | Cross-platform code, POSIX, environment variables |
| [`src/http_client.zig`](src/http_client.zig) | HTTP requests, complex JSON manipulation |
| [`src/json_utils.zig`](src/json_utils.zig) | Recursive functions, deep copy, memory cleanup |
| [`src/tools.zig`](src/tools.zig) | Process spawning, multi-line strings, dispatch |

### Key Concepts Mapped to TypeScript

```
TypeScript                          Zig
─────────────────────────────────────────────────────
interface Foo { ... }           →   const Foo = struct { ... };
type Union = A | B              →   const Union = union(enum) { a: A, b: B };
foo?.bar                        →   if (foo) |f| f.bar else null
async/await                     →   No colored functions - all sync!
try { } catch { }               →   try expression catch |err| { }
array.push(x)                   →   try list.append(allocator, x)
JSON.parse(str)                 →   std.json.parseFromSlice(T, ...)
console.log()                   →   std.debug.print("{}\n", .{val})
```

### Getting Started with Zig

1. **Install Zig**: https://ziglang.org/download/
2. **Clone this repo** and read the commented source files
3. **Run the tests**: `zig build test`
4. **Modify and experiment** - the compiler errors are your friend!

---

## Contributing

Found a way to improve performance, a missed edge case, or to make the comments clearer for prospective developers? PRs welcome! This project aims to be a gentle on-ramp to Zig for developers well versed in Typescript or similar languages.

## Community

- **Zig Discord**: https://discord.gg/zig
- **Zig Subreddit**: https://reddit.com/r/zig
- **Ziggit Forum**: https://ziggit.dev

## License

MIT
