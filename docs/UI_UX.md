# Look at Me! (FFI & Integration)

I'm a library! I don't have a face, but I have a really nice handshake!

## What Am I?

I'm a **shared library** (`.dylib` on Mac, `.so` on Linux, `.dll` on Windows). That means I'm like a LEGO brick that other programs can snap onto!

## How Other Programs Talk To Me

They use something called **FFI** (Foreign Function Interface). It's like a universal translator!

### From Node.js
```javascript
const ffi = require('koffi');
const lib = ffi.load('./libziggum.dylib');

// Say hello with an API key
const zg_init = lib.func('void* zg_init(const char*)');
const agent = zg_init('sk-ant-...');

// Or say hello with OAuth!
const zg_init_oauth = lib.func('void* zg_init_oauth(const char*, const char*, const char*)');
const agent = zg_init_oauth(accessToken, refreshToken, null);

// Ask a question
const zg_send_prompt = lib.func('int zg_send_prompt(void*, const char*)');
zg_send_prompt(agent, 'Hello Claude!');

// Read the answer (do this in a loop!)
const buffer = Buffer.alloc(1024);
const zg_read_chunk = lib.func('int zg_read_chunk(void*, char*, size_t)');
let bytesRead;
let response = '';
while ((bytesRead = zg_read_chunk(agent, buffer, 1024)) > 0) {
  response += buffer.toString('utf8', 0, bytesRead);
}

// Say goodbye (SUPER IMPORTANT or memory goblins attack!)
const zg_deinit = lib.func('void zg_deinit(void*)');
zg_deinit(agent);
```

### From Python
```python
import ctypes

lib = ctypes.CDLL('./libziggum.dylib')

# Set up the function signatures
lib.zg_init.argtypes = [ctypes.c_char_p]
lib.zg_init.restype = ctypes.c_void_p

agent = lib.zg_init(b'sk-ant-...')
# ... do stuff ...
lib.zg_deinit(agent)
```

## The Handshake Functions

| Function | What It Does |
|----------|--------------|
| `zg_init(api_key)` | Wake up with an API key! Returns a pointer to me! |
| `zg_init_oauth(token, refresh, url)` | Wake up with OAuth! The fancy way! |
| `zg_send_prompt(agent, text)` | Ask me something! Returns 0 if happy, -1 if sad. |
| `zg_read_chunk(agent, buffer, size)` | Read my answer! Returns how many bytes I said. |
| `zg_deinit(agent)` | Say goodbye! ALWAYS DO THIS or memory leaks! |

## The Chunky Reading Pattern

I don't give you all my words at once. That would be rude! Instead:

1. You give me a bucket (`buffer`)
2. I fill it up with words
3. I tell you how many words I put in
4. You read them
5. Go back to step 1 until I say `0` (that means I'm done talking!)

This is good because:
- You don't need to know how long my answer is!
- It works for REALLY long answers!
- It's how grown-up programs do it!

## Building Me

```bash
# Make the library!
zig build

# Find me at:
./zig-out/lib/libziggum.dylib   # Mac
./zig-out/lib/libziggum.so      # Linux
./zig-out/lib/ziggum.dll        # Windows
```

## The Memory Rules

**SUPER IMPORTANT ZIGGUM-CORE RULES:**

1. If you call `zg_init` or `zg_init_oauth`, you MUST call `zg_deinit` later!
2. One `init` = One `deinit`. No more, no less!
3. After `deinit`, don't touch me anymore! I'm gone!
4. If you forget, the Memory Leak Monster will eat your RAM!

## Debug Prints

I like to tell you what I'm doing! When you call my functions, I say:
- `zg_init called` - "I heard you!"
- `Agent initialized` - "I'm awake!"
- `Sending prompt: <your message>` - "I'm thinking about it!"
- `sendPrompt succeeded` - "I figured it out!"
- `zg_deinit called` - "Goodbye friend!"

These go to `stderr` so you can see them in your terminal!
