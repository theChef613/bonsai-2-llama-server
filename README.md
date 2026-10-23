# Bonsai 2 27B llama-server — tuned Docker config

A ready-to-run `llama-server` setup for **PrismML Ternary Bonsai 2 27B**
that is **2.1× faster at real-world context depths** than the obvious
configuration — because of one non-obvious flag interaction, documented
below and measured, not theorized.

## The headline discovery

**Set `--cache-type-k` and `--cache-type-v` to the *same* type.**

The PrismML fork's CUDA build has no FlashAttention vector kernel for a
*mixed* KV pair (e.g. K `q8_0` / V `q4_0`). With a mixed pair, every
attention step silently converts K/V to f16 on the fly — the server log
even labels the path "slow". Short-prompt benchmarks barely notice.
At the context depths an agent actually lives at, it costs half your
decode speed.

Measured on an RTX 4070 Super (12 GB), 128K context, ~75K-token prompt
(74,948 tokens; harness in [`bench/`](bench/)):

| KV cache (K / V) | Decode (tok/s) | Prefill (tok/s) | VRAM used |
|---|---|---|---|
| q8_0 / q4_0 (mixed) | 21.2 | 980 | 11,646 MiB |
| **q4_0 / q4_0** (this config) | **44.1** | **1,008** | **10,492 MiB** |
| q8_0 / q8_0 | 40.8 | 958 | 11,780 MiB |

(q4_0/q4_0 figures are medians of 3 from a 2026-10-23 re-baseline;
the best single run was 45.1 tok/s.)

Both homogeneous pairs take the fast path. `q4_0/q4_0` is the default
here because it is the fastest *and* frees ~1.4 GiB — on a 12 GB card
that headroom is the difference between "fits" and "OOM when something
else wants the GPU". A long-context summary-quality spot check under
q4 K came back accurate and detailed. If you have VRAM to spare and
prefer maximum K fidelity, `q8_0/q8_0` is also fast — just never mix.

For reference, depth-0 decode on this rig is ~54 tok/s, and under the
mixed config decode fell with depth: 53.9 @ 0 → 41.4 @ ~19K → 21.2 @
~75K tokens. **Benchmark at depth** — a depth-0 number would never have
shown the problem. In production agent use (a ~73K-token working
session), the mixed config sustained ~19.7 tok/s; the tuned config
sustains ~42 tok/s at the same depths.

## The model

- **PrismML Ternary Bonsai 2 27B** — a 27B-parameter model with ternary
  weights (~1.7 bits per weight), 262K native context. The PTQ1_0 GGUF
  is a ~5.9 GB file that behaves like a much larger model on disk- and
  bandwidth-constrained hardware.
- The PTQ1_0 pack is the faster decode pack on Ada-generation cards
  per PrismML's own throughput table, and the smaller resident.
- **Hard requirement: the PrismML-Eng llama.cpp fork.** Stock
  llama.cpp cannot load PTQ1_0 (unknown tensor type); the ternary
  kernels exist only in the fork. The Dockerfile pins the fork's
  prebuilt CUDA 12.8 release `prism-b10787` (the latest release as of
  2026-10-22) — no source build needed.

## Hardware

Measured on: **RTX 4070 Super, 12 GB VRAM**, Docker Desktop on
Windows (the config is plain Docker Compose; Linux hosts work the
same).

- **16 GB+ cards:** `q8_0/q8_0` KV fits comfortably; you can also
  raise `-c` toward the model's native 262K.
- **8 GB cards (untested here):** lower `-c` (e.g. 32768 or 65536)
  and keep q4_0/q4_0 KV — KV size scales linearly with context
  (~2.3 GiB at 128K with q4/q4, computed from the GGUF metadata).
- An NVIDIA GPU with a recent driver and the NVIDIA Container Toolkit
  is required; the compose file reserves one GPU via Docker's
  `deploy.resources` device syntax.

## Quickstart

1. Install Docker and the NVIDIA Container Toolkit.
2. Download the model into `./models/`:

   ```bash
   # from https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF
   hf download prism-ml/Ternary-Bonsai-2-27B-GGUF \
     Ternary-Bonsai-2-27B-PTQ1_0.gguf --local-dir models
   ```

   (or just grab the file with a browser and drop it in `models/`).
3. Start it:

   ```bash
   docker compose up -d --build
   ```

   First model load takes roughly a minute.
4. Check it's up and serving under the alias `bonsai-2-27b`:

   ```bash
   curl http://127.0.0.1:18080/v1/models
   ```

5. Point any OpenAI-compatible client at
   `http://127.0.0.1:18080/v1` with model name `bonsai-2-27b`.

The host port is bound to **127.0.0.1 only** — llama-server has no
API-key auth in this config, so don't rebind it to a LAN interface
unless you put an authenticating proxy in front of it.

## Reasoning effort

Bonsai 2 **thinks at `xhigh` by default**, and for agent workloads the
reasoning trace is most of the tokens a turn generates — in early
testing, an un-capped turn burned a 3,000-token budget entirely inside
its reasoning (12,011 characters) without ever answering. The model
supports `medium`; **`low` is not supported and silently behaves like
`xhigh`**.

Send it as a standard field, per request:

```json
{ "model": "bonsai-2-27b", "reasoning_effort": "medium", "...": "..." }
```

Measured effect on a reasoning-heavy probe: reasoning shrank from
12,011 characters (never finished) to 2,790 characters, completing in
2,803 tokens total. Medium is a real quality trade on hard problems —
keep `xhigh` available for the turns that deserve it — but as a
default for routine agent turns it is the single biggest wall-clock
win after the KV fix.

> **Using the Hermes agent framework?** Its global `reasoning_effort`
> config key does *not* reach custom providers. See
> [`hermes/extra-body.md`](hermes/extra-body.md) for the gotcha and
> the `extra_body` fix.

(This config also sets the fork's server-side `--reasoning-budget 2048`
hard cap as a backstop: if a client ever stops sending effort — an
update, a provider switch, a malformed request — the server still
arrests reasoning at 2,048 tokens. Gate-tested 2026-10-23: 10/10
runaway traces arrested at the cap with complete answers delivered;
long answers are not truncated (the budget meters reasoning only);
tool calls stayed well-formed after capped traces. It costs nothing
on well-behaved turns.)

## Tuning notes

- **Context (`-c 131072`):** sized for a 12 GB card with this KV
  config: ~5.7 GiB weights + ~2.3 GiB KV (computed from GGUF
  metadata) + runtime buffers ≈ 10.2 GiB measured resident. Halving
  context roughly halves KV.
- **Slots:** no `--parallel` is set, so the server runs its default
  4 slots over one unified KV pool (`kv_unified`). A single heavy
  session occupies one slot; small side calls (title generation,
  summarizers) land on others and finish fast. Don't split the pool
  unless you know why.
- **`--sleep-idle-seconds 900`:** unloads the model after 15 idle
  minutes, returning ~10 GiB to the system; the next request pays a
  ~1-minute reload. Remove it if your agent can't tolerate that.
- **Sampling defaults** (temp 1.0, top-p 0.95, top-k 20, min-p 0.05)
  are server-side fallbacks; per-request values from the client win.
- **Reproduce the numbers** with [`bench/depth-harness.ps1`](bench/)
  before and after any change, at ~75K tokens, twice per config.

## Measured and rejected

Three plausible levers were measured on this rig on 2026-10-23 and
rejected — recorded here so nobody has to re-run them:

- **Batch geometry (`-b 4096` / `-ub 1024`):** cold prefill 1,006
  tok/s (baseline 1,008), decode 42.9, +384 MiB VRAM. No gain.
- **`--spec-type ngram-simple`:** draft acceptance 6–18%, decode
  −2% on both prose and structured JSON. Prompt-lookup drafting
  needs output that echoes the prompt; agent workloads paraphrase
  and invent instead.
- **PQ2_0 pack:** cold prefill 1,041 tok/s (not the ~2× PrismML's
  throughput table suggests), decode at 75K 40.2 (vs 44.1),
  VRAM 11,632 MiB. On this fork build and card the larger pack is
  purely a tax; PTQ1_0 stays.

**Depth price list** (this config): decode is 52.5 tok/s at ~25K
tokens of context, 48.5 at ~50K, 44.1 at ~75K, and a cold refill
of those histories takes ~19 s / ~48 s / ~74 s. Living shallower
is worth roughly +4 tok/s per 25K — the cheapest remaining lever
is session hygiene, a client-side habit rather than a flag.

## License

MIT — see [LICENSE](LICENSE). The Bonsai 2 model itself is distributed
by PrismML under its own terms; this repo contains only configuration.
