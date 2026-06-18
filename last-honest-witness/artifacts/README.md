# Last Honest Witness — artifacts

Everything you need to run the solve against a per-team Anvil instance.

## Layout

```
solve.sh                 # main runner — reads N, e, c, root from chain, factors with
                         # Fermat, decrypts m, builds the input.json, runs snarkjs, posts
                         # the claim. Pages A/B/C answers are baked in (they're
                         # deployment-independent — see top-level writeup).
poseidon_helper.js       # circomlibjs Poseidon + 32-leaf Merkle builder. Domain-tags
                         # 1..6 match the circuit's hash construction.
poseidon_brute.js        # small helper for the Page B brute (kept for reference).
merkle_helper.py         # thin Python wrapper around poseidon_helper.js.
package.json             # circomlibjs + snarkjs + gmpy2-free deps.
foundry.toml             # cast/forge config.
challenge/
  Challenge.sol          # on-chain verifier — for reference.
  Groth16Verifier.sol    # auto-generated Groth16 verifier — for reference.
zk/
  LastHonestWitness.circom        # circuit source
  LastHonestWitness.wasm          # compiled witness generator
  LastHonestWitness_final.zkey    # proving key
  verification_key.json           # for off-chain sanity check
```

## Run

```bash
npm install                                      # circomlibjs + snarkjs
./solve.sh <RPC> <SETUP> <PRIVATE_KEY>
```

`<RPC>` and `<SETUP>` come from the challenge launcher (nc menu, port 5000 on
the SCTF infra). `<PRIVATE_KEY>` is whichever anvil account you want the
100 ETH swept to — `claim()` pays `msg.sender`.

## Requirements

- `cast` (foundry)
- `node` (≥18) + `npm`
- `python3` with `gmpy2` (used by `solve.sh` for the Fermat factoring + RSA
  decrypt; could be swapped for pure-Python `math.isqrt` if you don't want
  the dep)

## Notes

- Sample-run reference values are in the top-level writeup. If your run
  produces an `m` other than `474401937379412746004845`, something went
  wrong reading storage — the `RECIPIENT_COMMITMENT` constant in
  `Challenge.sol` pins `m` to that value across every deployment.
- `solve.sh` writes `/tmp/input.json`, `/tmp/proof.json`, `/tmp/public.json`,
  `/tmp/calldata.txt`. They're gitignored.
