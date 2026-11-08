// Execute the actual framework-independent ArkTS controller with a deterministic clock.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/controlcenter/model/PressController.ets'), 'utf8');
const result = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } });
const exportsObject = {};
vm.runInNewContext(result.outputText, { exports: exportsObject });
const { PressController } = exportsObject;

function fixture() {
  let now = 0;
  let serial = 0;
  let outer = false;
  let inner = false;
  let light = false;
  const tasks = new Map();
  const controller = new PressController({
    schedule(callback, delay) { const id = ++serial; tasks.set(id, { at: now + delay, callback }); return id; },
    cancel(id) { tasks.delete(id); },
    outerChanged(value) { outer = value; },
    contactChanged(value) { light = value; },
    innerChanged(value) { inner = value; }
  });
  return {
    controller,
    advance(ms) {
      const until = now + ms;
      for (;;) {
        const next = [...tasks].filter(([, t]) => t.at <= until).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break;
        const [id, task] = next; now = task.at; tasks.delete(id); task.callback();
      }
      now = until;
    },
    state() { return { outer, inner }; },
    light() { return light; },
    pending() { return tasks.size; }
  };
}

// Touch alone never schedules fill selection, even if held longer than 300ms.
const touch = fixture();touch.controller.down();touch.advance(1000);
assert.deepEqual(touch.state(),{outer:true,inner:false});assert.equal(touch.light(),true);
touch.controller.up();touch.advance(99);assert.equal(touch.light(),true);
touch.advance(1);assert.deepEqual(touch.state(),{outer:false,inner:false});assert.equal(touch.light(),false);
const held = fixture();held.controller.down();held.advance(400);held.controller.startDragging();
assert.deepEqual(held.state(),{outer:false,inner:false});assert.equal(held.light(),true,'Pan restores shell without switching off contact light');
held.advance(99);assert.equal(held.state().inner,false);held.advance(1);assert.equal(held.state().inner,true);
held.advance(30000);assert.deepEqual(held.state(),{outer:false,inner:true});
held.controller.endDragging();assert.equal(held.state().inner,false);assert.equal(held.light(),true);
held.controller.up();held.advance(100);assert.equal(held.light(),false);
// A full-range drag is still short: neither distance nor endpoint forces selection.
for(const elapsed of [0,30,99]){
 const quick=fixture();quick.controller.down();quick.advance(500);quick.controller.startDragging();quick.advance(elapsed);
 quick.controller.endDragging();quick.controller.up();quick.advance(1000);
 assert.deepEqual(quick.state(),{outer:false,inner:false});assert.equal(quick.pending(),0);
}
// Pan cancel must stop a pending fill while touch remains down.
const cancelled=fixture();cancelled.controller.down();cancelled.controller.startDragging();cancelled.advance(50);
cancelled.controller.endDragging();cancelled.advance(500);assert.equal(cancelled.state().inner,false);assert.equal(cancelled.light(),true);
cancelled.controller.up();cancelled.advance(100);
const repress=fixture();repress.controller.down();repress.controller.startDragging();repress.advance(100);
repress.controller.endDragging();repress.controller.up();repress.advance(50);
repress.controller.down();repress.controller.startDragging();repress.advance(50);
assert.equal(repress.light(),true);assert.equal(repress.state().inner,false);
repress.advance(50);assert.equal(repress.state().inner,true);
repress.controller.endDragging();repress.controller.up();repress.controller.up();repress.advance(1000);assert.equal(repress.pending(),0);
const disposed=fixture();disposed.controller.down();disposed.controller.startDragging();disposed.controller.dispose();disposed.advance(1000);
assert.equal(disposed.state().inner,false);assert.equal(disposed.pending(),0);
console.log('PASS: Touch/Pan clocks, shell reset at Pan start, 99/100ms gate, quick full drag, cancel before TouchUp, stationary Pan hold, re-press and disposal');

const frameSource = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/controlcenter/model/IconFrames.ets'), 'utf8');
const frameResult = ts.transpileModule(frameSource, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } });
const frameExports = {};
vm.runInNewContext(frameResult.outputText, { exports: frameExports });
const { IconFrames } = frameExports;
// Normal sun travel excludes the 0..60 and 302..360 overscroll artwork.
assert.equal(IconFrames.sun(0, 128), 61);
assert.equal(IconFrames.sun(1, 128), 301);
assert.equal(IconFrames.sun(1, 272), 301);
assert.equal(IconFrames.volumeLevel(0), 0);
assert.equal(IconFrames.volumeLevel(.32999), 1);
assert.equal(IconFrames.volumeLevel(.33), 2);
assert.equal(IconFrames.volumeLevel(.65999), 2);
assert.equal(IconFrames.volumeLevel(.66), 3);
assert.equal(IconFrames.volumeRestFrame(3), 214);
assert.equal(JSON.stringify(IconFrames.volumeSegment(1, 2)), '[104,140]');
assert.equal(JSON.stringify(IconFrames.volumeSegment(2, 1)), '[140,104]');
assert.equal(JSON.stringify(IconFrames.volumeSegment(0, 3)), '[179,214]');
assert.equal(JSON.stringify(IconFrames.volumeSegment(3, 0)), '[29,0]');
assert.equal(JSON.stringify(IconFrames.volumeSegment(2, 2)), '[]');
console.log('PASS: native sun travel, volume thresholds, rest frames, forward/reverse segments');
