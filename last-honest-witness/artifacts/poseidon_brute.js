const circomlibjs = require('circomlibjs');

(async () => {
  const poseidon = await circomlibjs.buildPoseidon();
  const F = poseidon.F;
  const TARGET = '9377985761090098792458769157668700179213141594497154267610801610404565099971';
  
  const t0 = Date.now();
  const PRINT = 200000;
  let last = 0;
  
  // Search several specific ranges:
  // 1. low 24-bit
  // 2. high bytes spelling out patterns
  // 3. specific bit patterns like 2^k + small offset
  
  console.log('Phase 1: 0..2^24');
  for (let m = 0n; m < (1n << 24n); m++) {
    if (F.toString(poseidon([1n, m])) === TARGET) {
      console.log('★ FOUND:', m.toString());
      process.exit(0);
    }
    if (m % BigInt(PRINT) === 0n && m > 0n) {
      console.log(`  m=${m}, ${((Date.now()-t0)/1000).toFixed(1)}s, rate=${(Number(m)/(Date.now()-t0)*1000).toFixed(0)}/s`);
    }
  }
  console.log('Phase 1 done in', (Date.now()-t0)/1000, 's');
})();
