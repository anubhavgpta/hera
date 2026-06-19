# Hera Register Map

Base address is set by the integrator via the AXI4-Lite slave port.
All registers are 32-bit wide. Unimplemented bits read as zero.

---

## Register Summary

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x00` | [`CTRL`](#ctrl--0x00) | RW\* | Global enable and soft reset |
| `0x04` | [`SESSION_CFG`](#session_cfg--0x04) | RW\* | Active session select |
| `0x08` | [`PAGE_CFG`](#page_cfg--0x08) | RW\* | Per-session page quota |
| `0x10` | [`STATUS`](#status--0x10) | RO | Allocator and fault status |
| `0x14` | [`EVICT_ADDR`](#evict_addr--0x14) | RO | Eviction candidate address |
| `0x18` | [`IRQ_MASK`](#irq_mask--0x18) | RW | Interrupt enable mask |
| `0x1C` | [`LOCK`](#lock--0x1c) | RW | Configuration lock |
| `0x20` | [`IP_VERSION`](#ip_version--0x20) | RO | Silicon watermark |
| `0x24` | [`IP_BUILDID`](#ip_buildid--0x24) | RO | Build revision |

\* Writes to `CTRL`, `SESSION_CFG`, and `PAGE_CFG` return AXI SLVERR when `LOCK[0]` is set.  
Writes to any read-only register or unmapped address always return SLVERR.

---

## Register Descriptions

### CTRL — `0x00`

Global controller enable and soft reset.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 31:2 | — | — | 0 | Reserved |
| 1 | `soft_reset` | RW\* | 0 | Pulse high to issue a soft reset. The block_allocator re-initialises over 256 cycles. Wait at least 270 cycles before issuing new KV operations. LOCK is not cleared by soft reset. |
| 0 | `global_enable` | RW\* | 0 | Set to 1 to enable KV write and read operations. While 0, all KV requests are silently ignored. |

---

### SESSION_CFG — `0x04`

Selects the active session context for subsequent KV operations and quota checks.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 31:3 | — | — | 0 | Reserved |
| 2:0 | `active_session_id` | RW\* | 0 | Session ID for the next KV write or read (0–7). |

---

### PAGE_CFG — `0x08`

Per-session page quota. Applied to the session selected by `SESSION_CFG`.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 31:8 | — | — | 0 | Reserved |
| 7:0 | `max_pages_per_session` | RW\* | 0 | Maximum pages that may be allocated to the active session. 0 disables quota enforcement (unlimited). When a write would exceed this limit, the allocation is denied, `STATUS.quota_exceeded` latches, and an IRQ fires. |

---

### STATUS — `0x10`

Read-only snapshot of allocator and fault state. Fault flags are sticky and cleared only by soft or hard reset.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 31:20 | — | — | 0 | Reserved |
| 19 | `sec_fault` | RO | 0 | Latches when a cross-session page access is detected. Drives IRQ when `IRQ_MASK.mask_sec_fault` is 0. |
| 18 | `quota_exceeded` | RO | 0 | Latches when a KV write is denied due to quota. Drives IRQ when `IRQ_MASK.mask_quota` is 0. |
| 17 | `evict_pending` | RO | 0 | High while the eviction engine is waiting for host acknowledgement. |
| 16 | `almost_full` | RO | 0 | High when free pages ≤ 16. Drives IRQ when `IRQ_MASK.mask_almost_full` is 0. |
| 15:8 | `pages_used` | RO | 0 | Number of pages currently allocated across all sessions (0–255). |
| 7:0 | `pages_free` | RO | 0xFF | Number of free pages available for allocation. Saturates at `0xFF` when all 256 pages are free. Reads `0x00` when the allocator is exhausted. |

---

### EVICT_ADDR — `0x14`

Address of the eviction candidate produced by the LRU eviction engine. Valid only when `STATUS.evict_pending` is high.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 31:11 | — | — | 0 | Reserved |
| 10:8 | `evict_session_id` | RO | 0 | Session that owns the candidate page. |
| 7:0 | `evict_page_id` | RO | 0 | Physical page ID of the candidate. |

The host acknowledges the eviction by asserting the evict ACK signal on the eviction interface. The controller then scrubs the page and returns it to the free list.

---

### IRQ_MASK — `0x18`

Interrupt enable mask. A bit set to 1 suppresses the corresponding IRQ line. All interrupts are enabled by default (reset value 0).

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 31:4 | — | — | 0 | Reserved |
| 3 | `mask_sec_fault` | RW | 0 | 1 = suppress IRQ on security fault. |
| 2 | `mask_quota` | RW | 0 | 1 = suppress IRQ on quota exceeded. |
| 1 | `mask_evict` | RW | 0 | 1 = suppress IRQ on eviction pending. |
| 0 | `mask_almost_full` | RW | 0 | 1 = suppress IRQ on almost full. |

---

### LOCK — `0x1C`

Sticky configuration lock. Once set, only a hard reset (external `rst_n` assertion) can clear it.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 31:1 | — | — | 0 | Reserved |
| 0 | `config_lock` | RW | 0 | Write 1 to lock `CTRL`, `SESSION_CFG`, and `PAGE_CFG`. Subsequent writes to those registers return SLVERR. Survives soft reset. Write 1 only; clearing requires hard reset. |

---

### IP_VERSION — `0x20`

Silicon watermark. Hardcoded in RTL; survives synthesis and is recoverable from a gate-level netlist.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 31:0 | `ip_version` | RO | `0x48455241` | ASCII encoding of `HERA`. Used for IP provenance verification. |

---

### IP_BUILDID — `0x24`

Build revision identifier.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 31:0 | `ip_buildid` | RO | `0x00000001` | Monotonically incrementing build number. |

---

## Interrupt Behaviour

A single IRQ output is driven by the logical OR of all unmasked interrupt sources:

```
irq = (almost_full  & ~mask_almost_full)
    | (evict_pending & ~mask_evict)
    | (quota_exceeded & ~mask_quota)
    | (sec_fault     & ~mask_sec_fault)
```

The IRQ is level-high and remains asserted until the source flag is cleared (by reset) or masked.

---

## Initialisation Sequence

```
1. Assert rst_n low for ≥ 2 clock cycles (hard reset).
2. Write SESSION_CFG, PAGE_CFG, IRQ_MASK as required.
3. Optionally write LOCK[0] = 1 to freeze configuration.
4. Write CTRL[0] = 1 (global_enable).
5. Wait ≥ 270 clock cycles for block_allocator initialisation.
6. Begin issuing KV write / read operations.
```

After a soft reset (`CTRL[1]` pulse), repeat steps 4–6. LOCK state is preserved.
