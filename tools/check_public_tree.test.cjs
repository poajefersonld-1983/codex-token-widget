const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
function fixture(run) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(),'codex-public-scan-test-'));
  try { run(root); } finally {
    if (!path.resolve(root).startsWith(path.join(os.tmpdir(),'codex-public-scan-test-'))) throw new Error('Unsafe test cleanup');
    fs.rmSync(root,{recursive:true,force:true});
  }
}
function check(root) { return spawnSync(process.execPath,[path.join(__dirname,'check_public_tree.cjs'),root],{encoding:'utf8'}); }
test('clean source passes',()=>fixture(root=>{
  fs.writeFileSync(path.join(root,'example.cjs'),'console.log("public source");');
  assert.equal(check(root).status,0);
}));
test('authentication file is blocked without printing its content',()=>fixture(root=>{
  fs.writeFileSync(path.join(root,'auth.json'),JSON.stringify({test:'SYNTHETIC-PRIVATE-VALUE'}));
  const result=check(root); assert.equal(result.status,1);
  assert.equal((result.stdout+result.stderr).includes('SYNTHETIC-PRIVATE-VALUE'),false);
}));
test('key pattern in source is blocked and masked',()=>fixture(root=>{
  const synthetic='sk-'+'synthetic'.repeat(4);
  fs.writeFileSync(path.join(root,'example.cjs'),synthetic);
  const result=check(root); assert.equal(result.status,1);
  assert.equal((result.stdout+result.stderr).includes(synthetic),false);
}));
test('private profile directory is blocked',()=>fixture(root=>{
  fs.mkdirSync(path.join(root,'profile')); assert.equal(check(root).status,1);
}));
