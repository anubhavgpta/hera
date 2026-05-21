# Vera

**Paged KV Cache Memory Controller — Circle Layer 0 IP**

Vera is a synthesizable RTL IP block that replaces software-managed KV cache memory in transformer inference pipelines with a hardware controller. It handles page allocation, logical-to-physical mapping, scatter-gather reads across non-contiguous pages, sequential prefetch, LRU eviction, and host control — entirely in silicon, with no CPU involvement on the critical path.

Designed for agentic AI workloads where multiple concurrent sessions share on-chip SRAM and access patterns are irregular across long contexts.

---

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │           kv_cache_ctrl (top)           │
                        │                                         │
  Host CPU ─── AXI4-Lite ──► axi4_lite_if                        │
                        │       │  global_enable / soft_reset     │
  Attention ──► wr_req ─────► rw_engine ◄──► block_table         │
  Engine    ◄── rd_valid        │    ▲            ▲               │
                        │       │    └── alloc ───┤               │
                        │       ▼             block_allocator      │
                        │     SRAM (4 banks, RAMB18)              │
                        │                                         │
                        │   prefetch_ctrl ──► (page prefetch)     │
                        │   eviction_engine ──► evict_valid / IRQ │
                        └─────────────────────────────────────────┘
```

---

## Key Specifications

| Parameter | Value |
|---|---|
| Total pages | 256 |
| Page size | 16 tokens |
| Head dimension | 64 |
| Data width | FP16 (16-bit) |
| Concurrent sessions | 8 |
| SRAM banks | 4 (interleaved by `page_id mod 4`) |
| Default SRAM footprint | 1 MB |
| Host interface | AXI4-Lite, 32-bit |
| Target clock | 100 MHz |
| Timing (Artix-7 xc7a35t) | WNS +2.13 ns, WHS +0.076 ns — all constraints met |
| BRAM utilization | 87 RAMB18 tiles (87% of xc7a35t, scales to Alveo U50) |
| Verification | 102 / 102 xsim checks passing |

---

## Modules

| Module | Description |
|---|---|
| `block_allocator` | Circular FIFO free list in LUTRAM. 1-cycle alloc/free. Outputs `pages_free`, `pages_used`, `almost_full`. |
| `block_table` | 2D LUTRAM mapping `(session_id, logical_page)` → `physical_page_id`. 1-cycle registered lookup, write-first semantics, per-entry invalidation. |
| `rw_engine` | Scatter-gather KV read/write. Transparent page-boundary crossing. Valid/ready handshake burst output. Session-isolated. |
| `axi4_lite_if` | AXI4-Lite slave register interface. Register map: CTRL, SESSION_CFG, PAGE_CFG, STATUS, EVICT_ADDR, IRQ_MASK. Live STATUS readback, IRQ output. |
| `prefetch_ctrl` | Per-session sequential access detector. Prefetches next logical page into 2-entry buffer on pattern detection. LRU buffer replacement. |
| `eviction_engine` | Triggered on `almost_full`. 256-cycle LRU scan over LUTRAM access counters. Outputs eviction candidate to host, frees page on ACK. |
| `kv_cache_ctrl` | Top-level integration. Wires all sub-modules, instantiates 4-bank BRAM, maintains `page_session_map`, arbitrates shared resources. |

---

## Verification Results

| Module | Checks | Result |
|---|---|---|
| `block_allocator` | 14 / 14 | PASS |
| `block_table` | 11 / 11 | PASS |
| `rw_engine` | 16 / 16 | PASS |
| `axi4_lite_if` | 20 / 20 | PASS |
| `prefetch_ctrl` | 18 / 18 | PASS |
| `eviction_engine` | 7 / 7 | PASS |
| `kv_cache_ctrl` (integration) | 16 / 16 | PASS |
| **Total** | **102 / 102** | **PASS** |

Integration test coverage includes: single-token write/read, multi-session end-to-end isolation, capacity fill with eviction path, AXI register readback, and soft reset suppression.

---

## Synthesis Results (Artix-7 xc7a35tcpg236-1)

```
Timing:   WNS = +2.131 ns  (setup, 100 MHz — met)
          WHS = +0.076 ns  (hold — met)
          Failing endpoints: 0

LUT (Logic):   8,229 / 20,800   (39.6%)
Flip-Flops:   17,186 / 41,600   (41.3%)
BRAM Tiles:       43.5 / 50     (87.0%)
DSPs:              0 / 90       (0%)
```

> The Artix-7 xc7a35t is a validation device. LUTRAM overflow (due to 256-page table + LRU counters) is expected at full parameters. Production deployment targets Alveo U50 / UltraScale+ xcku5p. BRAM and LUTRAM scale linearly with `TOTAL_PAGES` and `HEAD_DIM` — reduce parameters for Artix-7 fit validation.

---

## How to Run Simulation

1. Open Vivado 2018.2 and load `vera.xpr`.
2. In the TCL console:
```tcl
source {C:/Users/Anubhav Gupta/Desktop/Projects/vera/sim/setup_project.tcl}
run_sim tb_block_allocator
run_sim tb_block_table
run_sim tb_rw_engine
run_sim tb_axi4_lite_if
run_sim tb_prefetch_eviction
run_sim tb_kv_cache_ctrl
```
Each testbench prints per-check PASS/FAIL and a final summary to the TCL console.

---

## Register Map

| Address | Name | Access | Description |
|---|---|---|---|
| 0x00 | CTRL | RW | `[0]` global_enable, `[1]` soft_reset |
| 0x04 | SESSION_CFG | RW | `[2:0]` active_session_id |
| 0x08 | PAGE_CFG | RW | `[7:0]` max_pages_per_session |
| 0x10 | STATUS | RO | `[7:0]` pages_free, `[15:8]` pages_used, `[16]` almost_full, `[17]` evict_pending |
| 0x14 | EVICT_ADDR | RO | `[7:0]` evict_page_id, `[10:8]` evict_session_id |
| 0x18 | IRQ_MASK | RW | `[0]` mask_almost_full, `[1]` mask_evict |

---

## Roadmap

Vera is Circle's Layer 0 IP block. The full portfolio:

```
Layer 0  Vera                       — Paged KV Cache Controller       [complete]
Layer 1  Attention Accelerator      — Fused QKV projection + softmax  [planned]
         Speculative Decoding Engine                                   [planned]
Layer 2  Agentic Inference Subsystem — Multi-session orchestration     [planned]
Layer 3  Full SoC Reference Design                                     [planned]
```

Each layer is independently licensable. Vera is the foundation every subsequent block builds on.

---

## About Circle

Circle builds inference silicon IP for agentic AI workloads. Business model: hard IP block licensing to SoC vendors and AI chip startups, via upfront license fees and per-unit royalties. Pre-incorporation — founder stage.

Contact: [your email]
