#!/bin/bash
set -e
export PATH="$HOME/.foundry/bin:$PATH"

RPC=${1:?usage: solve.sh RPC SETUP PK}
SETUP=${2:?usage: solve.sh RPC SETUP PK}
PK=${3:?usage: solve.sh RPC SETUP PK}
cd "$(dirname "$0")"

CHALLENGE=$(cast call "$SETUP" "challenge()(address)" --rpc-url "$RPC")
echo "[*] Challenge = $CHALLENGE"

N_HEX=$(cast storage "$SETUP" 1 --rpc-url "$RPC")
E_HEX=$(cast storage "$SETUP" 2 --rpc-url "$RPC")
C_HEX=$(cast storage "$SETUP" 3 --rpc-url "$RPC")
N=$(python3 -c "print(int('$N_HEX', 16))")
E=$(python3 -c "print(int('$E_HEX', 16))")
C=$(python3 -c "print(int('$C_HEX', 16))")
echo "[*] N = $N"
echo "[*] e = $E"
echo "[*] c = $C"

# Compute the WitnessRoot topic hash and fetch via eth_getLogs
TOPIC=$(cast keccak "WitnessRoot(bytes32)")
echo "[*] WitnessRoot topic: $TOPIC"
LOGS=$(python3 - <<PYEOF
import urllib.request, json
body = json.dumps({"jsonrpc":"2.0","method":"eth_getLogs","params":[{"fromBlock":"0x0","toBlock":"latest","topics":["$TOPIC"]}],"id":1}).encode()
req = urllib.request.Request("$RPC", data=body, headers={"Content-Type":"application/json"})
r = json.loads(urllib.request.urlopen(req, timeout=8).read())
for log in r.get('result', []):
    print(log['topics'][1])
PYEOF
)
echo "[*] WitnessRoot raw: $LOGS"
ROOT_HEX=$(echo "$LOGS" | head -1)
if [ -z "$ROOT_HEX" ]; then
  ROOT_HEX=$(cast storage "$CHALLENGE" 3 --rpc-url "$RPC")
fi
ROOT=$(python3 -c "print(int('$ROOT_HEX', 16))")
echo "[*] root = $ROOT"

# Factor N with Fermat
PQ=$(python3 - <<PYEOF
from gmpy2 import mpz, isqrt
n = mpz($N)
a = isqrt(n) + 1
for _ in range(10_000_000):
    diff = a*a - n
    r = isqrt(diff)
    if r*r == diff:
        p, q = a-r, a+r
        if p*q == n:
            print(p, q); break
    a += 1
PYEOF
)
P=$(echo $PQ | awk '{print $1}')
Q=$(echo $PQ | awk '{print $2}')
echo "[*] p = $P"
echo "[*] q = $Q"
if [ -z "$P" ] || [ -z "$Q" ]; then
  echo "[!] Fermat failed"; exit 1
fi

M=$(python3 - <<PYEOF
from gmpy2 import mpz, invert
n=mpz($N); e=mpz($E); c=mpz($C); p=mpz($P); q=mpz($Q)
phi=(p-1)*(q-1); d=invert(e, phi)
print(pow(c, d, n))
PYEOF
)
echo "[*] m = $M"

# Build input.json via poseidon helper
node -e "
const fs = require('fs');
const helper = require('./poseidon_helper.js');
(async () => {
  const r = await helper.merkleData(${P}n, ${Q}n, ${M}n);
  console.log('[*] activeIndex='+r.activeIndex);
  console.log('[*] commitment='+r.commitment.toString());
  console.log('[*] merkleRoot='+r.merkleRoot.toString());
  if (r.merkleRoot.toString() !== '$ROOT') {
    console.error('[!] merkleRoot mismatch: got ' + r.merkleRoot.toString() + ' want $ROOT');
    process.exit(1);
  }
  fs.writeFileSync('/tmp/input.json', JSON.stringify(r.input,null,2));
})();
"

npx snarkjs groth16 fullprove /tmp/input.json zk/LastHonestWitness.wasm \
  zk/LastHonestWitness_final.zkey /tmp/proof.json /tmp/public.json 2>&1 | tail -2
npx snarkjs zkey export soliditycalldata /tmp/public.json /tmp/proof.json > /tmp/calldata.txt

python3 - <<'PYEOF' > /tmp/claim_env.sh
import json
arr = json.loads('[' + open('/tmp/calldata.txt').read().strip() + ']')
proofA, proofB, proofC, signals = arr
fa = lambda a: '[' + ','.join(a) + ']'
fb = lambda a: '[' + ','.join('[' + ','.join(r) + ']' for r in a) + ']'
print(f"PROOF_A='{fa(proofA)}'")
print(f"PROOF_B='{fb(proofB)}'")
print(f"PROOF_C='{fa(proofC)}'")
print(f"SIGNALS='{fa(signals)}'")
print("PAGEA=25774616630246150697727911729")
print("PAGEB_V=28")
print("PAGEB_R=0xc3349965986bd706337e04fd1a6a740e1f759a5d95ec4d2854655fc414ec6402")
print("PAGEB_S=0x432d7ce0d69b4a37abd4504c03aac315e27d666b6720d0624a2d2984cfcd346a")
print("PAGEC_A=3766029120")
print("PAGEC_B=2561833040")
PYEOF
source /tmp/claim_env.sh

cast send "$CHALLENGE" \
  "claim(uint256[2],uint256[2][2],uint256[2],uint256[5],uint256,uint8,bytes32,bytes32,uint256,uint256)" \
  "$PROOF_A" "$PROOF_B" "$PROOF_C" "$SIGNALS" \
  "$PAGEA" "$PAGEB_V" "$PAGEB_R" "$PAGEB_S" "$PAGEC_A" "$PAGEC_B" \
  --rpc-url "$RPC" --private-key "$PK" --legacy 2>&1 | tail -10

echo
echo "[*] isSolved = $(cast call $CHALLENGE 'isSolved()(bool)' --rpc-url $RPC)"
