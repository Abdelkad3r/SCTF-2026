# Challenge source — for reference

The handout for Chronostasis. Mirrored here so a reader can follow the
writeup without bouncing back to the org's repo.

- `src/Setup.sol` — deploys the tokens, pools, oracle, and vault, mints LP,
  and records `initialVaultLPBalance` for the `isSolved` check.
- `src/oracle/TWAPOracle.sol` — the ring-buffer oracle. `_consult` is the
  function whose anchor-outside-window bug the exploit relies on.
- `src/vault/AsyncLPVault.sol` — EIP-7540-style async LP vault with split
  request/claim that pays out against two different prices.
- `src/lib/uniswapv2/*` — vendored UniV2 (factory, pair, router, ERC20).

Nothing in here is patched. The exploit (`../exploit.sh`) runs against an
unmodified deployment of this exact tree.
