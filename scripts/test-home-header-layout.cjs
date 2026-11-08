const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/HomeHeaderLayout.ets'), 'utf8')
  .replace(/export /g, '').replace(/: number/g, '').replace(/: boolean/g, '');
const f = new Function(source + '; return { homeHeaderContentHeight, homeHeaderTopInset };')();
const expanded = 84;
assert.equal(f.homeHeaderTopInset(39,false,44),39+expanded);
assert.equal(f.homeHeaderTopInset(39,false,0),39+expanded-44);
assert.equal(f.homeHeaderTopInset(39,false,22),39+expanded-22);
assert.equal(f.homeHeaderTopInset(39,true,0),expanded-44);
assert.equal(f.homeHeaderTopInset(-1,false,44),expanded);
assert.equal(f.homeHeaderContentHeight(-10),expanded-44);
assert.equal(f.homeHeaderContentHeight(70),expanded);
console.log('Shared home header: expanded, collapsed, animation midpoint, hidden status bar and bounded heights passed.');
