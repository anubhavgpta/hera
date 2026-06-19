# Hera

**Paged KV Cache Memory Controller -- Circle Layer 0 IP**

Hera is a synthesizable RTL IP block that replaces software-managed KV cache memory in transformer inference pipelines with a hardware controller. It handles page allocation, logical-to-physical mapping, scatter-gather reads across non-contiguous pages, sequential prefetch, LRU eviction, and host control -- entirely in silicon, with no CPU involvement on the critical path.

Designed for agentic AI workloads where multiple concurrent sessions share on-chip SRAM and access patterns are irregular across long contexts.

---

## Architecture

```
                        +-----------------------------------------+
                        |           kv_cache_ctrl (top)           |
                        |                                         |
  Host CPU --- AXI4-Lite --> axi4_lite_if                        |
                        |       |  global_enable / soft_reset     |
  Attention --> wr_req ------> rw_engine <--> block_table         |
  Engine    <-- rd_valid        |    ^            ^               |
                        |       |    +-- alloc ---+               |
                        |       v             block_allocator      |
                        |     SRAM (4 banks, RAMB18)              |
                        |                                         |
                        |   prefetch_ctrl --> (page prefetch)     |
                        |   eviction_engine --> evict_valid / IRQ |
                        +-----------------------------------------+
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
| Timing (Artix-7 xc7a100t) | WNS +2.079 ns, WHS +0.205 ns -- all constraints met, Fmax ≈ 126 MHz |
| BRAM utilization | 116 / 135 tiles (85.9% of xc7a100t at full parameters) |
| Verification | 102 / 102 xsim checks passing |

---

## Modules

| Module | Description |
|---|---|
| `block_allocator` | Circular FIFO free list in LUTRAM. 1-cycle alloc/free. Outputs `pages_free`, `pages_used`, `almost_full`. |
| `block_table` | 2D LUTRAM mapping `(session_id, logical_page)` to `physical_page_id`. 1-cycle registered lookup, write-first semantics, per-entry invalidation. |
| `rw_engine` | Scatter-gather KV read/write. Transparent page-boundary crossing. Valid/ready handshake burst output. Session-isolated with hardware enforcement. Scrubs freed pages to zero. |
| `axi4_lite_if` | AXI4-Lite slave register interface. SLVERR on writes to RO registers or locked config. LOCK register prevents config changes after boot. Silicon watermark in IP_VERSION. |
| `prefetch_ctrl` | Per-session sequential access detector. Prefetches next logical page into 2-entry buffer on pattern detection. LRU buffer replacement. |
| `eviction_engine` | Triggered on `almost_full`. 256-cycle LRU scan over LUTRAM access counters. Outputs eviction candidate to host, frees page on ACK (after scrub). |
| `kv_cache_ctrl` | Top-level integration. Parameter guards, session quota enforcement, zero-on-free scrub sequencing, session isolation, security fault latching. |

---

## Security Features

Hera is hardened for multi-tenant inference workloads where session isolation and tamper resistance are required.

### Session Isolation Enforcement

Every KV read goes through a hardware ownership check: the physical page's session tag (`page_session_map`) is compared against the requesting session ID. A mismatch:
- Returns zeros to the requester (no data leakage)
- Pulses `sec_fault`, which latches and drives an IRQ to the host

The check fires on every token in a scatter-gather read range, not just the first page.

### Zero-on-Free Scrubbing

When the eviction engine marks a page for release, `kv_cache_ctrl` intercepts the free signal, directs `rw_engine` to overwrite all tokens in that page with zeros, and only then returns the page to the free list. This prevents a new session from observing residual KV data from a previous session.

### AXI Access Control

`axi4_lite_if` returns AXI SLVERR (response `2'b10`) for:
- Writes to read-only registers: STATUS, EVICT_ADDR, IP_VERSION, IP_BUILDID
- Writes to config registers (CTRL, SESSION_CFG, PAGE_CFG) when LOCK is set
- Writes to unmapped addresses

The LOCK register (`0x1C[0]`) is sticky: once set to 1, it survives soft_reset and can only be cleared by a hard reset. This allows firmware to lock down configuration after boot.

### Session Quota Enforcement

`kv_cache_ctrl` tracks pages allocated per session. When a write would exceed `max_pages_per_session`, the allocation is denied, `quota_exceeded` latches, and an IRQ fires. Setting `max_pages_per_session` to 0 disables quota enforcement (unlimited).

### Silicon Watermark

`IP_VERSION` (register `0x20`) is hardcoded to `0x48455241` -- the ASCII encoding of "HERA". The same constant (`HERA_IP_ID`) is instantiated as a localparam in `kv_cache_ctrl`, ensuring it survives synthesis and can be recovered from a gate-level netlist for IP provenance verification.

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

---

## Synthesis Results (Artix-7 xc7a100tcsg324-1, 100 MHz)

Out-of-context synthesis with Vivado 2018.2. Default parameters: 256 pages, 16 tokens/page, 8 sessions, HEAD\_DIM=64, DATA\_WIDTH=16.

```
Timing:   WNS = +2.079 ns  (setup, 100 MHz -- met, 0 failing endpoints)
          WHS = +0.205 ns  (hold -- met)
          Max frequency: ~126 MHz

Resource          Used     Available   Utilisation
Slice LUTs       10,191     63,400       16.07 %
Slice Registers  12,533    126,800        9.88 %
Block RAM Tiles     116        135       85.93 %
DSPs                  0        240        0.00 %
```

> **BRAM note:** 116 of 135 BRAM tiles on the xc7a100t are consumed at full parameters (256 pages × 16 tokens × HEAD\_DIM=64 × 16-bit). Embedding Hera in a larger design on Artix-7 leaves limited BRAM headroom. For production LLM accelerators, target Alveo U50 / UltraScale+ xcku5p where BRAM capacity is 2-10× larger. BRAM and LUTRAM usage scale linearly with `TOTAL_PAGES × HEAD_DIM`.

---

## How to Run Simulation

1. Open Vivado 2018.2 and load `hera.xpr`.
2. In the TCL console:
```tcl
source {C:/Users/Anubhav Gupta/Desktop/Projects/hera/sim/setup_project.tcl}
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
| 0x00 | CTRL | RW* | `[0]` global_enable, `[1]` soft_reset |
| 0x04 | SESSION_CFG | RW* | `[2:0]` active_session_id |
| 0x08 | PAGE_CFG | RW* | `[7:0]` max_pages_per_session (0 = unlimited) |
| 0x10 | STATUS | RO | `[7:0]` pages_free, `[15:8]` pages_used, `[16]` almost_full, `[17]` evict_pending, `[18]` quota_exceeded, `[19]` sec_fault |
| 0x14 | EVICT_ADDR | RO | `[7:0]` evict_page_id, `[10:8]` evict_session_id |
| 0x18 | IRQ_MASK | RW | `[0]` mask_almost_full, `[1]` mask_evict, `[2]` mask_quota, `[3]` mask_sec_fault |
| 0x1C | LOCK | RW | `[0]` config_lock -- sticky write-once, survives soft_reset |
| 0x20 | IP_VERSION | RO | `0x48455241` -- ASCII "HERA" silicon watermark |
| 0x24 | IP_BUILDID | RO | `0x00000001` -- build revision |

*RW registers return SLVERR when LOCK[0] is set.

Writes to STATUS, EVICT_ADDR, IP_VERSION, IP_BUILDID, or any unmapped address return SLVERR.

---

## Roadmap

Hera is Circle's Layer 0 IP block. The full portfolio:

```
Layer 0  Hera                       -- Paged KV Cache Controller       [complete]
Layer 1  Attention Accelerator      -- Fused QKV projection + softmax  [planned]
         Speculative Decoding Engine                                    [planned]
Layer 2  Agentic Inference Subsystem -- Multi-session orchestration     [planned]
Layer 3  Full SoC Reference Design                                      [planned]
```

Each layer is independently licensable. Hera is the foundation every subsequent block builds on.

---

## About Circle

Circle builds inference silicon IP for agentic AI workloads. Business model: hard IP block licensing to SoC vendors and AI chip startups, via upfront license fees and per-unit royalties. Pre-incorporation -- founder stage.

Contact: anubhavgpta@outlook.com
