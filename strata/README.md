# ⚠️ Strata-specific files

**These files only work with the [Strata](https://github.com/Niko1221/Strata) engine.** llama.cpp, LM Studio, Ollama and vLLM cannot load them — the architecture tag is `qwen4exp-mtp`, which is Strata's own, and `rt/` is Strata's runtime layout rather than a GGUF.

## Why they exist

The upstream GSQ-RCO GGUF ships **no MTP head**, so a draft layer has to be extracted from the BF16 checkpoint. These are the files Strata runs for speculative decoding.

## What is in here

| Path | Size | What it is |
|---|---|---|
| `mtp-q2_0.gguf` | 847 MB | The MTP block packed as a Strata GGUF (`qwen4exp-mtp`, 31 `mtp.*` tensors). Small tensors stay BF16/F32, the expert matrices are Q2_0. This is the file you feed to `tools/mtp_rt.py`. |
| `rt/` | 786 MB | The runtime layout Strata actually loads (`dense.bin`, `experts.bin`, `draft_vocab.bin`, `dense.txt`). Point `--mtp` at this directory. |

## ⚠️ Provenance — this draft head is NOT abliterated

The MTP block was extracted from the **stock `Qwen/Qwen3.8-Flash-Next` BF16 checkpoint** (360 GB across 131 shards; the 31 `mtp.*` tensors live in 28 of them), pinned at revision `de4b8e4d43b917e7706784d8bb445c9af86a3540`. The abliteration in this repository does **not** apply to it — the ablation only rewrites the "write-to-residual-stream" projections of the 48 main layers, and no abliterated MTP head is published anywhere. Treat it as the upstream draft layer, not as an abliterated one.

## Migrating an existing Strata installation

**Build a separate main-model native pack from this repository's GGUF files for your selected tier.** Do not reuse a native pack built from the official GSQ-RCO model. The transplant changes tensor offsets, and the old pack's `native_experts.txt` no longer matches the SC117 files. This can stop startup with:

```text
ArenaExpertSource: the pack's native_experts.txt does not match the model
```

From your Strata installation directory, run this PowerShell example, replacing both paths with your own:

```powershell
.\.venv\Scripts\python.exe .\tools\iq_pack.py --gguf "C:\models\SC117\IQ3_S\Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_S-00001-of-00002.gguf" --out "C:\strata\Strata-data\packs\sc117_iq3_s"
```

Keep both downloaded shards in the same directory with their original filenames; `iq_pack.py` automatically finds the second shard. Use a new output directory and retain the official pack so you can switch back.

Update your model configuration:

- `--pack`: the new SC117 native pack directory.
- `tokenizer`: the new pack's `tokenizer` directory.
- `--native`: SC117's first GGUF shard.
- `--ple-gguf`: SC117's second GGUF shard.
- `--mtp`: this repository's `strata/rt` directory; it is separate from the main-model native pack.
- With vision enabled, `vision.model`: SC117's first shard. The existing upstream `mmproj-Qwen3.8-Flash-Next-BF16.gguf` projector can be reused.

Keep your existing tuning parameters as a starting point. [ghit72 reported successful loading on Strata v0.1.38 after rebuilding the pack](https://huggingface.co/SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF/discussions/1); this is a community startup report, not a new evaluation of model responses.

## Reproducing it

Both steps are ordinary Strata tools; nothing here is hand-made:

```bash
python tools/mtp_fetch.py fetch --out mtp                       # HTTP Range, MTP tensors only
python tools/mtp_pack.py  --src mtp --experts q2_0 --out mtp/mtp-q2_0.gguf
python tools/mtp_rt.py    --gguf mtp/mtp-q2_0.gguf --out mtp/rt
```

Then in a Strata config: `--mtp mtp/rt`.

If you do not use Strata, ignore this folder and use `mtp-Qwen3.8-Flash-Next-Q8_0.gguf` in the repository root instead — that one is a standard `qwen4exp` GGUF and works as a llama.cpp draft model (`llama-cli -md`).
