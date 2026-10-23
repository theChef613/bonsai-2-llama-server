# Depth harness — why this benchmark exists

Most LLM speed claims are measured at or near **depth 0**: a short
prompt, a short generation. Real agent sessions don't live there —
they accumulate tens of thousands of tokens of history, and every
generated token then pays attention over the whole KV cache. Decode
speed falls with depth, and configuration mistakes that are invisible
at depth 0 become obvious at depth 75K.

The numbers that motivated this repo, on the reference rig
(RTX 4070 Super, mixed K q8_0 / V q4_0 KV cache):

| Depth | Decode (tok/s) |
|---|---|
| 0 | 53.9 |
| 18,788 | 41.4 |
| 74,948 | 21.2 |

Same rig, homogeneous q4_0/q4_0 KV: **45.1 tok/s at 74,948** — faster
at 75K than the mixed config was at 19K. A depth-0 benchmark would
have reported both configs as "about 54" and missed the entire story.

## Usage

```powershell
.\depth-harness.ps1              # ~75K tokens (640 repeats)
.\depth-harness.ps1 -Repeats 160 # ~19K tokens
```

The script posts a repeated-paragraph prompt to
`http://127.0.0.1:18080/v1/chat/completions` (override with `-Uri` /
`-Model`) and prints wall time, true prompt-token count, prefill rate,
completion tokens, and decode rate (`PredictedPerSec` — the number to
compare).

## Protocol

- **Run every configuration twice.** The first run after a server
  start pays one-time costs (graph warmup); the second is the steady
  state.
- **Judge prefill from run 1, decode from either run.** An identical
  repeat prompt is largely served from the server's slot prefix cache,
  so run 2's `PromptPerSec` is a cache artifact, not a prefill rate.
  Decode is generated at full depth regardless of how the KV got
  there, so `PredictedPerSec` stays comparable.
- **Change one variable at a time**, and keep the prompt-token count
  in view — a comparison is only valid at matched depth.
