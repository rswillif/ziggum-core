# The Secret Club Rules (Configuration)

To be in the Ziggum Club, you need the secret password! But now there's THREE ways to get in!

## Where I Hide It

I put the secret note under my mattress. 
Actually, I put it here: `$HOME/.config/ziggum/config.json`.

## Getting Your Badge (Onboarding)

When we first meet, I will ask you how you want to join the club!

### Option 1: The API Key Way (Pay-as-you-go)
This is like buying ice cream one scoop at a time!

1. I say "Howdy! Pick a number!"
2. You pick `1` for API Key
3. You whisper the magic key (`sk-ant-...`)
4. I lock it in a box so Principal Skinner can't see it!

### Option 2: The OAuth Token Way (Subscription)
This is like a gym membership! You pay monthly and get all the muscles!

1. I say "Howdy! Pick a number!"
2. You pick `2` for OAuth
3. You give me your Access Token (the one from Claude Code!)
4. If you have a Refresh Token, you can give me that too!
5. I keep them both safe and cozy!

**Where do OAuth tokens come from?**
- Run `claude` (the Claude Code CLI)
- Type `/login` and do the browser dance!
- Your tokens hide in `~/.claude/credentials.json`

### Option 3: The Local Llama (Ollama)
This is like having a pet llama that lives in your basement!

1. Pick `3` for Ollama
2. Tell me where your llama lives (usually `http://localhost:11434/api/chat`)
3. Tell me your llama's name (like `llama2` or `mistral`)

## Writing the Note Yourself

If you want to write the note, you can! Here are the recipes:

### API Key Recipe
```json
{
  "provider_type": "anthropic",
  "anthropic_api_key": "sk-ant-banana-breath",
  "model": "claude-3-5-sonnet-latest"
}
```

### OAuth Recipe (The Fancy One!)
```json
{
  "provider_type": "anthropic_oauth",
  "anthropic_access_token": "your-access-token-here",
  "anthropic_refresh_token": "your-refresh-token-here",
  "anthropic_base_url": null,
  "model": "claude-3-5-sonnet-latest"
}
```
*The refresh token and base_url are optional! Like sprinkles on ice cream!*

### Ollama Recipe (The Local One!)
```json
{
  "provider_type": "ollama",
  "ollama_url": "http://localhost:11434/api/chat",
  "model": "llama2"
}
```

## The All-Growed-Up Config (Full Reference)

Here's ALL the things you can put in the config:

| Field | What It Does | When You Need It |
|-------|--------------|------------------|
| `provider_type` | Which door to knock on | Always! Pick `anthropic`, `anthropic_oauth`, or `ollama` |
| `anthropic_api_key` | The magic key for pay-as-you-go | When `provider_type` is `anthropic` |
| `anthropic_access_token` | The OAuth ticket | When `provider_type` is `anthropic_oauth` |
| `anthropic_refresh_token` | Gets you a new ticket when yours expires | Optional for OAuth |
| `anthropic_base_url` | A different door (for enterprise) | Optional for OAuth |
| `ollama_url` | Where the llama lives | When `provider_type` is `ollama` |
| `model` | Which brain to use | Always! |

### The Smartest Brains
- `claude-3-5-sonnet-latest` (This one is Super Nintendo Chalmers!)
- `claude-3-opus-latest` (This one is Lisa!)
- `claude-3-haiku-20240307` (This one runs fast like Bart!)

## Safety Rules

- I promise not to show your key to the bullies.
- I only talk to the Cloud People (`api.anthropic.com`) unless you give me a different `base_url`.
- My cat says `0600` keeps the bad guys out! That means only YOU can read the file!
- OAuth tokens are like library cards - they expire! But the refresh token can get you a new one!

## The Environment Variable Shortcut

If you don't want to make a config file, you can use environment variables!

```bash
# For API Key
export ANTHROPIC_API_KEY="sk-ant-your-key-here"

# For OAuth
export ANTHROPIC_AUTH_TOKEN="your-oauth-token-here"
```

The code will look for these if there's no config file! It's like a secret handshake!
