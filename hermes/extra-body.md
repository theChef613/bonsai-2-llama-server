# Hermes gotcha: `reasoning_effort` doesn't reach custom providers

If you run Bonsai 2 (or any local reasoning model) behind the Hermes
agent framework and Hermes "seems to think too much" even though its
effort is set to medium — this is probably why.

## The trap

Hermes's `config.yaml` has a global setting:

```yaml
agent:
  reasoning_effort: "medium"
```

It looks universal. It isn't. The section's own header comment in the
config scopes that key to **OpenRouter and Nous Portal only**. For a
custom OpenAI-compatible provider — e.g. a local llama-server — Hermes
never puts the value on the wire, and the model runs at its default
effort (for Bonsai 2, that's `xhigh`). No error, no warning; the UI
even displays "Med" while the model receives nothing. Verified the
hard way: live turns kept producing full-length reasoning traces until
the request was inspected directly.

## The fix: per-provider `extra_body`

Hermes's documented mechanism for provider-specific request fields on
custom OpenAI-compatible providers is `extra_body` on the provider
entry. Add it under your `custom_providers` entry:

```yaml
custom_providers:
  - name: local llama
    base_url: http://localhost:18080/v1
    model: bonsai-2-27b
    extra_body:
      reasoning_effort: "medium"
    models:
      bonsai-2-27b: {}
    models_discovered: true
```

(Name yours whatever you like; the load-bearing part is the
`extra_body` stanza at the same indent level as `base_url`/`model`.)

Then restart Hermes so it re-reads the config — closing and reopening
the desktop app is sufficient.

## Verifying

Don't trust the settings label; verify on the wire or by output:

- The model's reasoning traces in the UI should become visibly
  shorter on comparable tasks.
- Server-side, llama-server's `print_timing` log lines show the
  per-task generated-token counts drop versus the old baseline.
- Cross-check with a direct API call if in doubt: the same prompt
  with a top-level `"reasoning_effort": "medium"` field should
  produce a comparably short trace. If the direct call is short and
  the Hermes turn isn't, Hermes still isn't sending it.

## Why this matters beyond Hermes

Any client that "supports reasoning effort" may scope the setting per
provider family. The general rule: if a reasoning model over-thinks
through an agent client, confirm what the client actually sends —
a raw request with `reasoning_effort` to the server takes two minutes
and settles it. (For Bonsai 2 specifically: `medium` works;
`low` is unsupported and silently behaves like `xhigh`.)
