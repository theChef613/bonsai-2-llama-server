# llama-server from the PrismML-Eng llama.cpp fork — REQUIRED for
# Bonsai 2 ternary GGUF packs.
#
# Stock llama.cpp rejects PTQ1_0/PQ2_0 as unknown tensor types (and
# silently produces garbage with Q2_0): the Hadamard activation
# runtime and the ternary kernels live only in the PrismML-Eng fork.
# Do NOT run Bonsai 2 files on the ghcr.io/ggml-org/llama.cpp image.
#
# This image uses the fork's prebuilt Linux CUDA 12.8 binaries
# (release prism-b10787-73bfe6c) on an NVIDIA CUDA runtime base.
# If the container exits with a missing-.so error, the log names the
# library — add it to the apt line below and rebuild.

FROM nvidia/cuda:12.8.1-runtime-ubuntu24.04

ARG PRISM_TAG=prism-b10787-73bfe6c

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates libgomp1 \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/llama.tar.gz \
      "https://github.com/PrismML-Eng/llama.cpp/releases/download/${PRISM_TAG}/llama-${PRISM_TAG}-bin-linux-cuda-12.8-x64.tar.gz" \
 && mkdir -p /opt/llama \
 && tar -xzf /tmp/llama.tar.gz -C /opt/llama --strip-components=1 \
 && rm /tmp/llama.tar.gz

ENV LD_LIBRARY_PATH=/opt/llama

ENTRYPOINT ["/opt/llama/llama-server"]
