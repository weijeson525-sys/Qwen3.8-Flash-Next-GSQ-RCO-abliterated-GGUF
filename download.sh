#!/usr/bin/env bash
# Download GGUF weights for this model from Hugging Face.
# Weights are NOT stored in this repo (GitHub single-file limit is 100 MB).
# No token / credential is used or read anywhere in this script.
set -euo pipefail

HF_REPO="SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF"
BASE="https://huggingface.co/$HF_REPO/resolve/main"

# quant|file|bytes|sha256 (LFS oid from the HF file tree)
read -r -d '' QUANTS <<'EOF_QUANTS' || true
IQ2_XS|IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ2_XS-00001-of-00002.gguf|39665015072|4acc3ebb5050d20117bdc77fc39200e709dfe2b2367f3522c95b9112a30aff81
IQ2_XS|IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ2_XS-00002-of-00002.gguf|28800138432|316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113
IQ3_S|IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_S-00001-of-00002.gguf|55063448064|40f369eca301ec6ea318dbb671b3132c26a2f0b89aa5458a7051b33215ee296c
IQ3_S|IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_S-00002-of-00002.gguf|28800138432|316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113
IQ3_XXS|IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_XXS-00001-of-00002.gguf|47342144896|03b11926b41a3d7f7a008882b1bc7a6330a3c9c43d3cad4598d31dc73042fdc5
IQ3_XXS|IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_XXS-00002-of-00002.gguf|28800138432|316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113
Q2_0|Q2_0/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-Q2_0-00001-of-00002.gguf|38021379872|1620faf21c845524cbe38dcbbaf850b8d155c2299df05d8b7bfb43b642c4647e
Q2_0|Q2_0/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-Q2_0-00002-of-00002.gguf|28800138432|316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113
mtp-Q4_0|mtp-Qwen3.8-Flash-Next-Q4_0.gguf|2199652672|70da35359338d15ef5af31f0e0e08998f2a2b3350678be1bbb1a57a376e350c3
mtp-Q8_0|mtp-Qwen3.8-Flash-Next-Q8_0.gguf|4137429312|713b16d7e97246858ebd9a6dec403b1cfc3407d8a539f65401948e20b38b0f91
mtp-q2_0|mtp-q2_0.gguf|889017216|a22206a4d74eafbf31063a84610292535fb3b49af9a339963817fd04aed81e4d
EOF_QUANTS

MMPROJ_FILE="mmproj-Qwen3.8-Flash-Next-BF16.gguf"
MMPROJ_SIZE=907542944
MMPROJ_SHA256="2e788f8c511d8093c7b43cb87b2fd7e14228340318057f8fb20c86df2efe2355"

human_gb() { awk -v b="$1" 'BEGIN { printf "%.1f GB", b/1000000000 }'; }

list_quants() {
  echo "Available quantizations for $HF_REPO:"
  echo "$QUANTS" | awk -F'|' '{tot[$1]+=$3; n[$1]++} END {for (q in tot) printf "  %-55s %2d file(s)  %s\n", q, n[q], ""}' | sort
  echo "$QUANTS" | awk -F'|' '{tot[$1]+=$3} END {for (q in tot) printf "%s|%d\n", q, tot[q]}' | sort | while IFS='|' read -r q tot; do
    printf '  %-55s %s total\n' "$q" "$(human_gb "$tot")"
  done
  echo "  mmproj (vision projector, optional): $MMPROJ_FILE ($(human_gb "$MMPROJ_SIZE"))"
  echo "Default quant: Q2_0"
}

download_one() {
  local file="$1" size="$2" sha="$3"
  echo "  -> $file ($size bytes, sha256 ${sha:0:12}...)"
  curl -L --fail --retry 3 -C - -o "$file" "$BASE/$file"
  local actual; actual=$(wc -c < "$file")
  if [ "$actual" != "$size" ]; then echo "ERROR: size mismatch for $file (expected $size, got $actual)" >&2; rm -f "$file"; exit 1; fi
  local got; got=$(sha256sum "$file" | awk '{print $1}')
  if [ "$got" != "$sha" ]; then echo "ERROR: sha256 mismatch for $file" >&2; rm -f "$file"; exit 1; fi
  echo "     verified: $actual bytes, sha256 OK"
}

download_quant() {
  local quant="$1"
  local rows; rows=$(echo "$QUANTS" | awk -F'|' -v q="$quant" '$1==q')
  if [ -z "$rows" ]; then echo "ERROR: unknown quant '$quant'. Run: ./download.sh --list" >&2; exit 1; fi
  local total; total=$(echo "$rows" | awk -F'|' '{s+=$3} END {print s}')
  echo "Downloading $quant ($total bytes = $(human_gb "$total")) from $HF_REPO"
  echo "Make sure you have at least $(human_gb "$total") free disk space."
  local avail; avail=$(df -P . | awk 'NR==2 {print $4*1024}')
  if [ "$avail" -lt "$total" ]; then echo "ERROR: not enough free disk space (need $total bytes, have $avail)" >&2; exit 1; fi
  echo "$rows" | while IFS='|' read -r _q file size sha; do download_one "$file" "$size" "$sha"; done
  echo "Done: $quant downloaded and verified."
}

download_mmproj() {
  echo "Downloading mmproj $MMPROJ_FILE ($MMPROJ_SIZE bytes = $(human_gb "$MMPROJ_SIZE"))"
  download_one "$MMPROJ_FILE" "$MMPROJ_SIZE" "$MMPROJ_SHA256"
  echo "Done: mmproj downloaded and verified."
}

# Reject unexpected extra arguments: a stray extra arg must never start a download.
if [ "$#" -gt 1 ]; then
  echo "ERROR: too many arguments (expected at most 1). Usage: ./download.sh [QUANT|--list|--mmproj|--help]" >&2
  exit 1
fi

case "${1:-Q2_0}" in
  --list|-l) list_quants ;;
  --mmproj) download_mmproj ;;
  -h|--help)
    echo "Usage: ./download.sh [QUANT]"
    echo "       ./download.sh --list        list all available quants and sizes"
    echo "       ./download.sh --mmproj      download the mmproj vision file only"
    echo "Default QUANT: Q2_0"
    ;;
  *) download_quant "$1" ;;
esac
