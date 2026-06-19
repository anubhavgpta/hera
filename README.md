<div align="center">
  <img src="docs/hera_logo.png" alt="Hera" width="320" />
</div>

<div align="center">
  <strong>Paged KV Cache Memory Controller — Circle Layer 0 IP</strong>
</div>

<div align="center">
  <a href="LICENSE">Apache 2.0</a> &nbsp;·&nbsp; Vivado 2018.2 &nbsp;·&nbsp; Artix-7 / UltraScale+
</div>

---

Hera is a synthesizable RTL IP block that offloads KV cache memory management from software to dedicated hardware. It handles page allocation, logical-to-physical mapping, scatter-gather reads across non-contiguous pages, sequential prefetch, LRU eviction, and host control — entirely in silicon, with no CPU involvement on the critical path.

Designed for agentic AI workloads where multiple concurrent sessions share on-chip SRAM and access patterns are irregular across long contexts.

---

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           kv_cache_ctrl (top)           │
                    │                                         │
  Host CPU ─── AXI4-Lite ──► axi4_lite_if                   │
                    │              │  global_enable / reset   │
  Attention ─► wr_req ──────► rw_engine ◄──► block_table    │
  Engine    ◄─ rd_valid             │              │          │
                    │               │         block_allocator │
                    │             SRAM (4 banks, RAMB18)      │
                    │                                         │
                    │   prefetch_ctrl ──► (page prefetch)     │
                    │   eviction_engine ──► evict_valid / IRQ │
                    └─────────────────────────────────────────┘
```

---

## Specifications

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
| Timing (Artix-7 xc7a100t) | WNS +2.079 ns, WHS +0.205 ns — all constraints met, Fmax ≈ 126 MHz |
| BRAM utilization | 116 / 135 tiles (85.9 % of xc7a100t at full parameters) |
| Verification | 41 / 41 checks passing (Vivado xsim 2018.2) |

> **BRAM budget:** at default parameters (256 pages, HEAD\_DIM = 64) Hera consumes 116 of 135 BRAM tiles on the xc7a100t, leaving ≈ 14 % for the rest of the design. Scale parameters down for Artix-7 integration, or target a device with more BRAM capacity. See the [scaling table](#bram-scaling) below.

---

## BRAM Scaling

BRAM consumption grows linearly with `TOTAL_PAGES × HEAD_DIM`. The table below gives representative tile counts on xc7a100t (135 tiles available).

| `TOTAL_PAGES` | `HEAD_DIM` | SRAM footprint | BRAM tiles (est.) | xc7a100t utilisation |
|---|---|---|---|---|
| 64 | 32 | 128 KB | ~29 | ~21 % |
| 128 | 64 | 512 KB | ~58 | ~43 % |
| 256 | 64 | 1 MB | ~116 | ~86 % |
| 512 | 64 | 2 MB | ~232 | > 100 % — target UltraScale+ |
| 256 | 128 | 2 MB | ~232 | > 100 % — target UltraScale+ |

For production LLM accelerators, target **Alveo U50** or **UltraScale+ xcku5p** (2–10× the BRAM capacity of Artix-7). The full register interface, timing characteristics, and parameter API are device-independent.

See [`docs/register_map.md`](docs/register_map.md) for the complete register reference.

---

## Module Overview

| Module | Description |
|---|---|
| `block_allocator` | Circular FIFO free list in LUTRAM. 1-cycle alloc/free. Outputs `pages_free`, `pages_used`, `almost_full`. Saturating 8-bit counters. |
| `block_table` | 2D LUTRAM mapping `(session_id, logical_page)` → `physical_page_id`. 1-cycle registered lookup, write-first semantics, per-entry invalidation. |
| `rw_engine` | Scatter-gather KV read/write with transparent page-boundary crossing. Valid/ready handshake burst output. Session-isolated with hardware enforcement. Scrubs freed pages to zero. |
| `axi4_lite_if` | AXI4-Lite slave register interface. SLVERR on writes to read-only registers or locked configuration. Sticky LOCK register. Silicon watermark in `IP_VERSION`. |
| `prefetch_ctrl` | Per-session sequential access detector. Prefetches the next logical page into a 2-entry buffer on pattern detection. LRU buffer replacement. |
| `eviction_engine` | Triggered on `almost_full`. 256-cycle LRU scan over LUTRAM access counters. Outputs eviction candidate to host and frees the page on ACK after scrub. |
| `kv_cache_ctrl` | Top-level integration. Parameter guards, session quota enforcement, zero-on-free scrub sequencing, session isolation, and security fault latching. |

---

## Security

Hera is hardened for multi-tenant inference workloads where session isolation and tamper resistance are required.

### Session Isolation

Every KV read passes through a hardware ownership check: the physical page's session tag is compared against the requesting session ID on every token in a scatter-gather range. A mismatch returns zeros to the requester (no data leakage) and latches a `sec_fault` that drives an IRQ to the host.

### Zero-on-Free Scrubbing

When a page is released — either by the eviction engine or by an explicit free — `kv_cache_ctrl` directs `rw_engine` to overwrite all tokens in that page with zeros before returning it to the free list. This prevents a new session from observing residual KV data from a previous tenant.

### AXI Access Control

`axi4_lite_if` returns AXI SLVERR (`2'b10`) for:
- Writes to read-only registers: `STATUS`, `EVICT_ADDR`, `IP_VERSION`, `IP_BUILDID`
- Writes to any config register when `LOCK[0]` is set
- Writes to unmapped addresses

### Configuration Lock

The `LOCK` register (`0x1C[0]`) is sticky: once written to 1, it survives soft reset and can only be cleared by a hard reset. This allows firmware to lock down the configuration after boot.

### Session Quota Enforcement

`kv_cache_ctrl` tracks pages allocated per session. A write that would exceed `max_pages_per_session` is denied, `quota_exceeded` latches, and an IRQ fires. Setting `max_pages_per_session` to 0 disables quota enforcement.

### Silicon Watermark

`IP_VERSION` (register `0x20`) is hardcoded to `0x48455241` — the ASCII encoding of `HERA`. The constant is instantiated as a localparam in `kv_cache_ctrl`, ensuring it survives synthesis and can be recovered from a gate-level netlist for IP provenance verification.

---

## Register Map

Full bit-field descriptions, reset values, and initialisation sequence are in [`docs/register_map.md`](docs/register_map.md).

| Address | Name | Access | Description |
|---|---|---|---|
| `0x00` | `CTRL` | RW* | `[0]` global_enable &nbsp; `[1]` soft_reset |
| `0x04` | `SESSION_CFG` | RW* | `[2:0]` active_session_id |
| `0x08` | `PAGE_CFG` | RW* | `[7:0]` max_pages_per_session (0 = unlimited) |
| `0x10` | `STATUS` | RO | `[7:0]` pages_free &nbsp; `[15:8]` pages_used &nbsp; `[16]` almost_full &nbsp; `[17]` evict_pending &nbsp; `[18]` quota_exceeded &nbsp; `[19]` sec_fault |
| `0x14` | `EVICT_ADDR` | RO | `[7:0]` evict_page_id &nbsp; `[10:8]` evict_session_id |
| `0x18` | `IRQ_MASK` | RW | `[0]` mask_almost_full &nbsp; `[1]` mask_evict &nbsp; `[2]` mask_quota &nbsp; `[3]` mask_sec_fault |
| `0x1C` | `LOCK` | RW | `[0]` config_lock — sticky write-once, survives soft_reset |
| `0x20` | `IP_VERSION` | RO | `0x48455241` — ASCII `HERA` silicon watermark |
| `0x24` | `IP_BUILDID` | RO | `0x00000001` — build revision |

\* Returns SLVERR when `LOCK[0]` is set. Writes to `STATUS`, `EVICT_ADDR`, `IP_VERSION`, `IP_BUILDID`, or any unmapped address always return SLVERR.

> **`pages_free` encoding:** the field saturates at `0xFF` when all 256 pages are free, and reads `0x00` when the allocator is exhausted.

---

## Synthesis Results

Out-of-context synthesis targeting Artix-7 xc7a100tcsg324-1 at 100 MHz using Vivado 2018.2. Default parameters: 256 pages, 16 tokens/page, 8 sessions, HEAD\_DIM = 64, DATA\_WIDTH = 16.

```
Timing
  WNS   +2.079 ns   setup — 0 failing endpoints
  WHS   +0.205 ns   hold  — 0 failing endpoints
  Fmax  ~126 MHz

Resource           Used     Available    Utilisation
─────────────────────────────────────────────────────
Slice LUTs        10,191      63,400        16.07 %
Slice Registers   12,533     126,800         9.88 %
Block RAM Tiles      116         135        85.93 %
DSPs                   0         240         0.00 %
```

> **Integration note:** at full parameters, 116 of 135 BRAM tiles on the xc7a100t are consumed. For designs that embed Hera alongside other logic on Artix-7, reduce `TOTAL_PAGES` or `HEAD_DIM` to recover headroom. Production LLM accelerator targets (Alveo U50, UltraScale+ xcku5p) carry 2–10× the BRAM capacity and are not constrained. BRAM and LUTRAM usage scale linearly with `TOTAL_PAGES × HEAD_DIM`.

The full synthesis script is provided at [`synth_hera.tcl`](synth_hera.tcl) for reproducibility.

---

## Simulation

The testbench requires Vivado 2018.2 (xsim) and no other dependencies. Adjust `VIVADO_BIN` at the top of the script if Vivado is installed to a different path.

```bat
cd sim
run_xsim.bat
```

This compiles all RTL and the SystemVerilog testbench, elaborates, and runs to completion. Each check prints `PASS` or `FAIL` inline; a summary box is printed at the end. Expected result: **41 / 41 PASS**.

The log is written to `sim/hera_sim.log`.

---

## Verification Summary

| Test | Checks | Result |
|---|---|---|
| Smoke — reset, enable, single KV write/read | 14 | PASS |
| Stress — 128 writes across all 8 sessions, 16 scoreboard reads | 11 | PASS |
| Security — isolation, quota, LOCK, watermark, SLVERR | 10 | PASS |
| Soft Reset — zero-on-free, re-init, re-write | 6 | PASS |
| **Total** | **41** | **PASS** |

---

## License

Apache License 2.0. See [LICENSE](LICENSE).

---

## Contact

Circle builds inference silicon IP for agentic AI workloads.

anubhavgpta@outlook.com
