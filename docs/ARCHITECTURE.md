# The Inner Machinations of My Mind (Architecture)

I'm a computer library! Here's how my brain parts work together to make the thinkings happen.

## 1. The Big Boss (`src/lib.zig`)

This is the front door! All the other languages knock here to talk to me. I have special C words (`export fn`) that make me sound like a grown-up computer.

- **Agent Struct**: This is ME! I hold the conversation in my tummy and remember all the words.
- **FFI Functions**: These are like phone numbers. Node.js and Python can call me!
  - `zg_init` - "Hi, here's my API key!" 
  - `zg_init_oauth` - "Hi, I got a fancy subscription token!"
  - `zg_send_prompt` - "Think about this, please!"
  - `zg_read_chunk` - "What did you say? Say it again, slower!"
  - `zg_deinit` - "Bye bye! Don't forget to clean up!" (This is super important or the memory goblins get angry)

## 2. The Internet Pipe (`src/http_client.zig`)

This is where I send letters to the cloud people (Anthropic)!

- I wrap the letters in JSON (that's "Jason," he's nice).
- I send them to the sky!
- Sometimes the sky sends back tools. I love tools!
- **Two Ways to Say Hi**: 
  - API Key: I say `x-api-key: sk-ant-banana...` 
  - OAuth: I say `Authorization: Bearer <my fancy token>` (This is for the kids with subscriptions!)

## 3. My Toys (`src/tools.zig`)

I have special toys that do real things!

- **`read_file`**: I look at your papers!
- **`write_file`**: I draw on your papers!
- **`run_command`**: I tell the computer to do a flip! (I use `/bin/sh` because I'm a Unix kid)

## 4. The ID Cards (`src/providers/types.zig`)

This is where I keep track of who everyone is! It's like a yearbook!

- **Role**: Are you the `user` or the `assistant`? I need to know!
- **ContentBlock**: What kind of word-thing is this? Text? Tool use? Tool result?
- **Provider**: Which cloud friend am I talking to? 
  - `anthropic` - The API key people!
  - `anthropic_oauth` - The subscription people! They have refresh tokens!
  - `ollama` - The local llama! He lives on your computer!
  - `mock` - My imaginary friend for testing!

## 5. The Secret Keeper (`src/config.zig`)

Shhh! This is where I hide the shiny keys. I put them in a special box (`~/.config/ziggum/config.json`) and lock it tight (`0600`) so the bullies can't steal them.

- **ConfigManager**: This is like the librarian. It can `load()` and `save()` the secrets!
- **Onboarding**: When we first meet, I ask nicely for your badge. You can pick:
  1. API Key (pay-as-you-go, like buying ice cream)
  2. OAuth Token (subscription, like a gym membership)
  3. Local Ollama (the llama lives in your basement!)

## 6. The Path Finder (`src/fs_utils.zig`)

I know where stuff lives! I'm like a treasure map!

- **getConfigPath**: Where's the secret box? `$HOME/.config/ziggum/config.json`!
- **ensureConfigDir**: Make the folder if it's not there! `mkdir` is my friend!
- **ensureConfigFilePerms**: Lock it up tight! `chmod 0600` keeps the baddies out!

## 7. The Glue (`src/json_utils.zig`)

My cat's breath smells like memory management! I have to be careful not to drop the bits on the floor.

- **`deepCopy`**: I photocopy the JSON so I can keep it forever!
- **`free`**: I let go of the memory when I'm done playing. If I don't, the Memory Leak Monster comes!

## My House (`src/`)

```
src/
├── lib.zig              # The front door! (C ABI exports live here)
├── http_client.zig      # The mailman!
├── config.zig           # The secret box!
├── tools.zig            # My toy chest!
├── fs_utils.zig         # The treasure map!
├── json_utils.zig       # The photocopier!
└── providers/
    └── types.zig        # The yearbook!
```

## How a Question Gets Answered

1. Node.js knocks on my door (`zg_init`)
2. I wake up and remember who I am (Agent struct)
3. Node.js asks a question (`zg_send_prompt`)
4. I write a letter to Claude (http_client)
5. Claude writes back!
6. I remember what Claude said (history)
7. Node.js reads my answer (`zg_read_chunk`)
8. When we're done, Node.js says bye (`zg_deinit`)
9. I clean up all my toys! No memory leaks! Good ziggum-core!
