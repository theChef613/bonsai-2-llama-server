<#
.SYNOPSIS
    Depth benchmark for a local llama-server (Bonsai 2 27B).

.DESCRIPTION
    Builds a long prompt by repeating a fixed paragraph, sends it to the
    server's OpenAI-compatible endpoint, and prints the server's timing
    fields. Inference benchmarks at depth 0 are misleading for LLMs that
    will actually run at tens of thousands of tokens of context: decode
    speed falls as the KV cache grows, and some configurations fall much
    harder than others. This harness measures at ~75K tokens by default,
    which is where the interesting differences live.

    Run each configuration TWICE:
      - Run 1 (cold): prompt processing (prefill) numbers are honest here.
      - Run 2 (warm): judge decode by PredictedPerSec. Note that an
        identical repeat prompt is served largely from the server's slot
        prefix cache, so PromptPerSec on run 2 reflects cache reuse, not
        raw prefill — expect it to look strange. Decode is measured at
        full depth either way and is directly comparable.

.EXAMPLE
    .\depth-harness.ps1
    Default run: 640 repeats ≈ 74,948 tokens with the built-in corpus.

.EXAMPLE
    .\depth-harness.ps1 -Repeats 160
    ~19K tokens — useful for tracing the decode-vs-depth curve.
#>
[CmdletBinding()]
param(
    # Repeats of the corpus paragraph. 640 ≈ 75K tokens; scale linearly.
    [int]$Repeats = 640,
    [string]$Uri = 'http://127.0.0.1:18080/v1/chat/completions',
    [string]$Model = 'bonsai-2-27b',
    [int]$MaxTokens = 300
)

$para = 'The harbour master kept a ledger of every vessel that crossed the bar, noting tonnage, cargo, crew, and the state of the tide. In winter the ink froze in its well and he wrote with a pencil stub instead, pressing hard so the graphite would survive the damp. Ships from three continents anchored in the roads awaiting a pilot, and their crews traded songs, tools, and rumours of wars that had ended months before the news reached them. Nothing in the harbour happened quickly except accidents, and those, the harbour master observed, were merely the past arriving all at once.'

$big = ($para + "`n") * $Repeats
$body = @{
    model      = $Model
    max_tokens = $MaxTokens
    messages   = @(
        @{ role = 'user'; content = ("Read the following passage carefully, then write a one-paragraph summary of it.`n`n" + $big) }
    )
} | ConvertTo-Json -Depth 6

$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-RestMethod -Uri $Uri -Method Post -ContentType 'application/json' -Body $body
$sw.Stop()

[pscustomobject]@{
    TotalSeconds      = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    PromptTokens      = $r.usage.prompt_tokens
    PromptPerSec      = [math]::Round($r.timings.prompt_per_second, 1)
    CompletionTokens  = $r.usage.completion_tokens
    PredictedPerSec   = [math]::Round($r.timings.predicted_per_second, 1)
}
