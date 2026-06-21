# SCTF 2026 — Writeups

Writeups for the two SCTF 2026 challenges I solved.

| Challenge | Category | Notes |
|---|---|---|
| [Chronostasis](./chronostasis/README.md) | Blockchain / DeFi / Misc | TWAP oracle manipulation against an EIP-7540 async LP vault. Pump → snapshot → dump → claim. The non-obvious bit is the oracle's ring-buffer eviction. |
| [The Last Honest Witness](./last-honest-witness/README.md) | Crypto / ZK / Misc | Four-in-one: Franklin–Reiter on `e=3`, small-x ECDSA brute, 40-bit keccak collision, and a Groth16 Poseidon-Merkle witness gated by RSA-with-close-primes (Fermat factoring). |
| [Polynomial Drift](./polynomial-drift/README.md) | — | **UNSOLVED.** Handout binary mirrored only — stripped x86-64 PIE ELF. No writeup, no solver, no flag yet. |

Both were solved on a per-team Anvil instance launched over `nc`. Both writeups document the bits that cost me the most time so the next person doesn't lose it the same way.
