// =============================================================================
// json_utils.zig - JSON Value Manipulation Utilities
// =============================================================================
//
// FOR TYPESCRIPT DEVELOPERS:
// --------------------------
// This file provides utilities for working with dynamic JSON values.
// In TypeScript, JSON manipulation is trivial because objects are references
// and the garbage collector handles memory. In Zig, we need explicit functions
// to copy and free JSON structures.
//
// KEY CONCEPTS DEMONSTRATED:
// 1. Recursive functions in Zig
// 2. Working with std.json.Value (Zig's dynamic JSON type)
// 3. Deep copying nested data structures
// 4. Manual memory management for tree structures
// 5. Pattern matching on tagged unions
//
// WHY THIS FILE EXISTS:
// ---------------------
// When working with Anthropic's API, we receive JSON responses with tool
// inputs that we need to:
//   1. Copy (because the parser's memory is freed after parsing)
//   2. Free (when we're done with the values)
//
// TypeScript doesn't need this because:
//   - Objects are passed by reference (no copying needed)
//   - Garbage collector frees unused memory automatically
//
// Zig equivalent of JavaScript's:
//   const copy = JSON.parse(JSON.stringify(original));  // deepCopy
//   // No equivalent for free - GC handles it
//
// =============================================================================

const std = @import("std");

// =============================================================================
// deepCopy - Create a complete independent copy of a JSON value
// =============================================================================
// Recursively copies a std.json.Value and all its nested contents.
//
// WHY DEEP COPY IS NEEDED:
// ------------------------
// In Zig, when you parse JSON, the resulting values contain pointers (slices)
// into the original JSON string buffer. When that buffer is freed, those
// pointers become invalid (dangling pointers = bugs!).
//
// Deep copying creates independent allocations for everything, so the copy
// remains valid even after the original is freed.
//
// MEMORY OWNERSHIP:
// -----------------
// The returned Value owns ALL of its memory. Strings, arrays, objects - all
// newly allocated. The caller MUST call `free(allocator, value)` when done.
//
// RECURSIVE STRUCTURE:
// --------------------
// This function calls itself for nested values, which is how we handle
// arbitrarily deep JSON structures (arrays of arrays, objects with object
// values, etc.).
//
// TypeScript equivalent:
//   function deepCopy(val: JsonValue): JsonValue {
//     if (val === null || typeof val !== 'object') return val;
//     if (Array.isArray(val)) return val.map(deepCopy);
//     return Object.fromEntries(
//       Object.entries(val).map(([k, v]) => [k, deepCopy(v)])
//     );
//   }
//
// PARAMETERS:
//   allocator: Used for all memory allocations
//   val: The JSON value to copy
//
// RETURNS:
//   A new std.json.Value that is an independent copy of the input
// =============================================================================
pub fn deepCopy(allocator: std.mem.Allocator, val: std.json.Value) !std.json.Value {
    // -------------------------------------------------------------------------
    // SWITCH ON JSON VALUE TYPE
    // -------------------------------------------------------------------------
    // std.json.Value is a tagged union with these variants:
    //   - .null: JSON null
    //   - .bool: true/false
    //   - .integer: Whole numbers
    //   - .float: Decimal numbers
    //   - .number_string: Numbers stored as strings (for precision)
    //   - .string: String values
    //   - .array: Arrays of values
    //   - .object: Key-value object maps
    //
    // We handle each type appropriately based on whether it needs copying.
    // -------------------------------------------------------------------------
    switch (val) {
        // ---------------------------------------------------------------------
        // PRIMITIVE VALUES - No allocation needed
        // ---------------------------------------------------------------------
        // These types are "value types" - they're stored inline in the tagged
        // union, not as pointers. We can just return them directly.
        //
        // TypeScript: primitives (numbers, booleans, null) are already values
        // ---------------------------------------------------------------------
        .null, .bool, .number_string, .float, .integer => return val,

        // ---------------------------------------------------------------------
        // STRING VALUES - Need to duplicate
        // ---------------------------------------------------------------------
        // Strings in Zig are slices (pointer + length) pointing to memory
        // somewhere else. We need to allocate new memory and copy the bytes.
        //
        // allocator.dupe(u8, s) allocates a new buffer and copies s into it.
        //
        // TypeScript: strings are immutable and interned, no copy needed
        //
        // CAPTURE SYNTAX: `.string => |s|` extracts the string slice into `s`
        // ---------------------------------------------------------------------
        .string => |s| return .{ .string = try allocator.dupe(u8, s) },

        // ---------------------------------------------------------------------
        // ARRAY VALUES - Deep copy each element
        // ---------------------------------------------------------------------
        // JSON arrays can contain any JSON value, including nested arrays
        // and objects. We need to:
        //   1. Create a new ArrayList with the same capacity
        //   2. Deep copy each element and add to the new array
        //
        // TypeScript: val.map(item => deepCopy(item))
        //
        // NOTE: std.json.Array is an alias for ArrayList(Value)
        // ---------------------------------------------------------------------
        .array => |a| {
            // Create a new array with pre-allocated capacity for efficiency
            var new_arr = try std.json.Array.initCapacity(allocator, a.items.len);

            // Copy each element recursively
            for (a.items) |v| {
                // Note: If deepCopy fails partway through, we'd have a
                // partial copy. In production, you might want errdefer cleanup.
                try new_arr.append(try deepCopy(allocator, v));
            }

            return .{ .array = new_arr };
        },

        // ---------------------------------------------------------------------
        // OBJECT VALUES - Deep copy keys and values
        // ---------------------------------------------------------------------
        // JSON objects are key-value maps where:
        //   - Keys are always strings (need copying)
        //   - Values can be any JSON value (need deep copying)
        //
        // TypeScript:
        //   Object.fromEntries(
        //     Object.entries(val).map(([k, v]) => [k, deepCopy(v)])
        //   )
        //
        // std.json.ObjectMap is a StringHashMap(Value) under the hood
        // ---------------------------------------------------------------------
        .object => |o| {
            // Create a new empty object map
            var new_obj = std.json.ObjectMap.init(allocator);

            // Iterate through all key-value pairs
            var it = o.iterator();
            while (it.next()) |entry| {
                // entry.key_ptr.* dereferences the pointer to get the key string
                // entry.value_ptr.* gets the value
                //
                // We must dupe the key AND deep copy the value
                try new_obj.put(
                    try allocator.dupe(u8, entry.key_ptr.*),
                    try deepCopy(allocator, entry.value_ptr.*),
                );
            }

            return .{ .object = new_obj };
        },
    }
}

// =============================================================================
// free - Recursively free a JSON value and all its contents
// =============================================================================
// Deallocates all memory associated with a std.json.Value.
//
// WHY FREE IS NEEDED:
// -------------------
// When we deep copy JSON values, we allocate memory. Without a corresponding
// free, we'd have memory leaks. This function walks the entire JSON tree
// and frees everything.
//
// RECURSION:
// ----------
// Just like deepCopy, this function is recursive. Freeing an array means
// freeing each element; freeing an object means freeing each key and value.
//
// IMPORTANT: After calling free(), the Value is invalid and must not be used.
// There's no "null safety" - the memory is gone.
//
// TypeScript equivalent:
//   // No equivalent - GC handles this automatically!
//   // In JS, you just stop referencing the object
//
// PARAMETERS:
//   allocator: MUST be the same allocator used to create/copy this value!
//   val: The JSON value to free
//
// RETURNS: void (nothing - it's cleanup code)
// =============================================================================
pub fn free(allocator: std.mem.Allocator, val: std.json.Value) void {
    switch (val) {
        // ---------------------------------------------------------------------
        // PRIMITIVE VALUES - Nothing to free
        // ---------------------------------------------------------------------
        // These values don't have any allocated memory - they're stored
        // inline in the tagged union itself.
        // ---------------------------------------------------------------------
        .null, .bool, .number_string, .float, .integer => {},

        // ---------------------------------------------------------------------
        // STRING VALUES - Free the string buffer
        // ---------------------------------------------------------------------
        // Strings are slices pointing to allocated memory. Free it.
        //
        // CAPTURE: |s| extracts the []const u8 string slice
        // ---------------------------------------------------------------------
        .string => |s| allocator.free(s),

        // ---------------------------------------------------------------------
        // ARRAY VALUES - Free elements then the array itself
        // ---------------------------------------------------------------------
        // Order matters here:
        //   1. First, free each element (recursive call)
        //   2. Then, free the array's internal buffer
        //
        // If we freed the array first, we couldn't access the elements!
        //
        // MUTABLE COPY:
        // `var mutable_a = a` creates a mutable copy because the `a` captured
        // from the switch is immutable, but deinit needs a mutable reference.
        //
        // TypeScript: Just let it go out of scope and GC cleans up
        // ---------------------------------------------------------------------
        .array => |a| {
            // Free each element recursively
            for (a.items) |v| {
                free(allocator, v);
            }

            // Free the array structure itself
            // Need a mutable copy to call deinit
            var mutable_a = a;
            mutable_a.deinit();
        },

        // ---------------------------------------------------------------------
        // OBJECT VALUES - Free keys, values, then the map
        // ---------------------------------------------------------------------
        // Objects have three things to free:
        //   1. Each key string (allocated via dupe)
        //   2. Each value (recursive - could be anything)
        //   3. The ObjectMap structure itself
        //
        // Again, order matters - free contents before the container!
        // ---------------------------------------------------------------------
        .object => |o| {
            // Need mutable to iterate and call deinit
            var mutable_o = o;
            var it = mutable_o.iterator();

            // Free each key-value pair
            while (it.next()) |entry| {
                // Free the key string
                allocator.free(entry.key_ptr.*);
                // Free the value (recursive)
                free(allocator, entry.value_ptr.*);
            }

            // Free the hash map structure
            mutable_o.deinit();
        },
    }
}
