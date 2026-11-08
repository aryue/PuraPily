// Run the actual SDK-compiled NativeSlider with a fake animation clock.
// Build the app first. No copy of its interaction logic is used here.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.join(__dirname, '..');
function compile(source) {
  return ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  }}).outputText;
}
function model(name) {
  const result = {};
  vm.runInNewContext(compile(fs.readFileSync(path.join(root,
    `entry/src/main/ets/controlcenter/model/${name}.ets`), 'utf8')), { exports: result });
  return result;
}
let serial = 0;
let now = 0;
let rtl = false;
const timeouts = new Map();
const intervals = new Map();
const animations = [];
let nativeAvailable = false;
let snapshotCalls = 0;
const nativeTargets = [];
const context = { animateTo(options, callback) { callback(); if (options.onFinish) animations.push(options); } };
class View {
  constructor() { this.watches = new Map(); }
  declareWatch(name, callback) { this.watches.set(name, callback); }
  getUIContext() { return context; }
}
class Property {
  constructor(value, owner, name) { this.value = value; this.owner = owner; this.name = name; }
  get() { return this.value; }
  set(value) {
    const changed = this.value !== value;
    this.value = value;
    if (changed) this.owner.watches.get(this.name)?.call(this.owner);
  }
}
const exportsObject = {};
const source = fs.readFileSync(path.join(root,
  'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/controlcenter/components/NativeSlider.ts'), 'utf8');
vm.runInNewContext(compile(source + '\nexports.NativeSlider = NativeSlider; exports.FirmwareIcon = FirmwareIcon;'), {
  exports: exportsObject, ViewPU: View,
  CanvasRenderingContext2D: class {}, RenderingContextSettings: class {},
  SynchedPropertySimpleTwoWayPU: Property, SynchedPropertySimpleOneWayPU: Property,
  SynchedPropertyObjectOneWayPU: Property, Date: { now: () => now },
  ObservedPropertySimplePU: Property, ObservedPropertyObjectPU: Property,
  registerNamedRoute() {}, DisturbanceFieldShape: { RECT: 0 }, Curve: { EaseOut: 'EaseOut' },
  setTimeout(callback, delay) { const id = ++serial; timeouts.set(id, { at: now + delay, callback }); return id; },
  clearTimeout(id) { timeouts.delete(id); },
  setInterval(callback) { const id = ++serial; intervals.set(id, callback); return id; },
  clearInterval(id) { intervals.delete(id); },
  require(name) {
    if (name.includes('/material/NativeCollapse&')) return { NativeCollapse: {
      create(frame) { if(!nativeAvailable)throw new Error('unsupported runtime'); nativeTargets.push(frame);return {native:true,frame}; },
      clear() {return {cleared:true};}
    }};
    if (name.includes('/model/IconFrames&')) return model('IconFrames');
    if (name.includes('/model/SdfKeyframes&')) return model('SdfKeyframes');
    if (name.includes('/model/NativeJellyMotion&')) {
      const result={};
      vm.runInNewContext(compile(fs.readFileSync(path.join(root,'entry/src/main/ets/controlcenter/model/NativeJellyMotion.ets'),'utf8')),
        {exports:result,require(){return model('SdfKeyframes');}});
      return result;
    }
    if (name.includes('/model/PressController&')) return model('PressController');
    if (name.includes('/model/ParticleGeometry&')) return model('ParticleGeometry');
    if (name.includes('/model/JellyMotion&')) {
      const result = {};
      vm.runInNewContext(compile(fs.readFileSync(path.join(root, 'entry/src/main/ets/controlcenter/model/JellyMotion.ets'), 'utf8')),
        { exports: result, require() { return model('SdfKeyframes'); } });
      return result;
    }
    if (name.includes('/material/JellyRenderer&')) return { JellyRenderer: class {
      resize() {} setIcon(...args) { this.lastIcon=args; } capture() { snapshotCalls++; return false; } frame() {} clear() {} dispose() {}
    } };
    if (name.includes('/particles/ParticleMaterial&')) return { ParticleMaterial: { rate() { return 0.6; } } };
    if (name === '@ohos:i18n') return { default: { isRTL() { return rtl; }, System: { getAppPreferredLanguage() { return 'test'; } } } };
    if (name === '@native:ohos.curves') return { default: {
      interpolatingSpring() {}, springMotion() {}, responsiveSpringMotion() {}
    } };
    return {};
  }
});
function advance(ms) {
  now += ms;
  for (const [id, task] of [...timeouts]) if (task.at <= now) { timeouts.delete(id); task.callback(); }
}
function tick() { for (const callback of intervals.values()) callback(); }
function event(offsetX, x = 12, velocityX = 20) {
  return { offsetX, offsetY: 0, velocityX, velocityY: 0, fingerList: [{ localX: x, localY: 32 }] };
}
const slider = new exportsObject.NativeSlider(undefined, { value: 0.5 });
slider.aboutToAppear();
assert.equal(slider.uiValue, 64);
slider.begin(event(2, 9));
advance(100);
assert.equal(slider.chosen, true);
assert.equal(slider.fields[0].center.x, 9, 'first ripple must use finger, not progress');
slider.move(event(32, 25)); // Exactly 30 must not trigger a new field.
tick();
assert.equal(slider.fields.length, 1);
slider.move(event(33, 27));
tick();
assert.equal(slider.fields.length, 2);
assert.equal(slider.fields[1].center.x, 27);
assert.equal(slider.velocity, 150);
for (let i = 0; i < 100; i++) tick();
assert.equal(slider.fields.length, 2, 'stationary hold must not manufacture ripples');
slider.move(event(34, 200));
assert.equal(slider.fingerX, 27, 'out-of-track touch preserves last ripple position');
slider.end();
const staleFade = animations.at(-1);
assert.equal(staleFade.duration, 600);
assert.equal(intervals.size, 0);
slider.begin(event(0, 60));
staleFade.onFinish();
assert.equal(slider.showParticles, true, 'old fade completion must not hide a new drag');
assert.equal(slider.particleOpacity, 1);
slider.value = 0.5;
slider.end();
animations.at(-1).onFinish();
assert.equal(slider.showParticles, false);
rtl = true;
slider.begin(event(0, 64));
slider.move(event(32, 65));
assert.equal(slider.value, 0.25, 'RTL pan reverses the progress delta');
slider.aboutToDisappear();
assert.equal(intervals.size, 0);
assert.equal(timeouts.size, 0);

function verticalEvent(offsetY, y = 72, velocityY = -20) {
  return { offsetX: 0, offsetY, velocityX: 0, velocityY, fingerList: [{ localX: 32, localY: y }] };
}
// Keep RTL enabled: it must not reverse the vertical progress direction.
const vertical = new exportsObject.NativeSlider(undefined, { value: 0.5, vertical: true });
vertical.aboutToAppear();
assert.equal(vertical.widthVp(), 64);
assert.equal(vertical.heightVp(), 144);
assert.equal(vertical.uiValue, 64);
vertical.begin(verticalEvent(0, 80));
advance(100);
assert.equal(vertical.chosen, true);
assert.equal(vertical.innerZoomX, 64 / 48);
assert.equal(vertical.innerZoomY, 144 / 128);
assert.equal(vertical.fields[0].center.x, 32);
assert.equal(vertical.fields[0].center.y, 80);
assert.equal(vertical.fields[0].region.size.width, 64);
assert.equal(vertical.fields[0].region.size.height, 144);
vertical.move(verticalEvent(-32, 48));
assert.equal(vertical.value, 0.75, 'upward drag increases even in RTL');
assert.equal(vertical.velocity, -150, 'upward physical velocity drives vy negative');
tick();
assert.equal(vertical.fields[1].center.y, 48, 'vertical ripple uses the actual finger Y');
vertical.move(verticalEvent(16, 96, 30));
assert.equal(vertical.value, 0.375, 'downward drag decreases');
assert.equal(vertical.velocity, 150);
vertical.move(verticalEvent(20, 200, 30));
assert.equal(vertical.fingerY, 96, 'vertical out-of-track touch preserves prior ripple Y');
vertical.end();
const previousFade = animations.at(-1);
vertical.begin(verticalEvent(0, 60));
previousFade.onFinish();
assert.equal(vertical.showParticles, true);
vertical.end();
animations.at(-1).onFinish();
assert.equal(vertical.showParticles, false);
vertical.tap(verticalEvent(0, 8));
assert.equal(vertical.value, 1);
vertical.tap(verticalEvent(0, 72));
assert.equal(vertical.value, 0.5);
vertical.tap(verticalEvent(0, 136));
assert.equal(vertical.value, 0);
vertical.aboutToDisappear();

const longVertical = new exportsObject.NativeSlider(undefined, { value: 0.5, vertical: true, wide: true });
longVertical.aboutToAppear();
assert.equal(longVertical.heightVp(), 312);
assert.equal(longVertical.uiValue, 136);
longVertical.tap(verticalEvent(0, 20));
assert.equal(longVertical.value, 1);
longVertical.tap(verticalEvent(0, 292));
assert.equal(longVertical.value, 0);
longVertical.aboutToDisappear();
assert.equal(intervals.size, 0);
assert.equal(timeouts.size, 0);
console.log('PASS: compiled horizontal/vertical NativeSlider, up/down direction, vy, touch-centered ripples, hold, bounds, tap endpoints, long track, RTL, fade re-entry and cleanup');

nativeAvailable=true;
const native = new exportsObject.NativeSlider(undefined,{value:.5,vertical:true});
native.aboutToAppear();
assert.equal(native.nativeJellyReady,true);
const snapshotsBefore=snapshotCalls;
native.begin(verticalEvent(0,90));
assert.equal(native.nativeJellyPrepared,true,'Identity effect must exist before the first spring');
assert.equal(native.nativeJellyActive,false);
assert.equal(nativeTargets.length,2,'Probe plus preinstalled identity, before the 300ms entry');
assert.equal(JSON.stringify(nativeTargets[1]),JSON.stringify(model('SdfKeyframes').SdfKeyframes.identity));
assert.equal(native.jellyCaptureMode,false,'Native route must retain live content');
advance(300);
assert.equal(native.nativeJellyActive,true);
assert.equal(native.jellyShowing,false);
assert.equal(nativeTargets.length,3,'Probe, identity seed, first target only; later stages remain cancellable');
assert.equal(native.buttonZoom,1,'Pan must restore shell scale before SDF starts');
assert.equal(native.nativeBaseScale,1);
advance(367);
assert.equal(nativeTargets.length,5);
assert.equal(snapshotCalls,snapshotsBefore,'Native route must never capture components');
native.end();advance(100);
assert.equal(native.buttonZoom,1,'Release keeps the original Pan base scale');
advance(233);
animations.findLast(a=>a.delay===0 && a.onFinish).onFinish();
assert.equal(native.nativeJellyActive,false);
assert.equal(native.nativeJellyEffect.cleared,true);
assert.equal(native.nativeJellyPrepared,false);
assert.equal(native.buttonZoom,1,'Clear must restore identity, not a stale pressed scale');
native.aboutToDisappear();
assert.equal(timeouts.size,0);
console.log('PASS: compiled NativeSlider selects native route, no snapshots, three targets and explicit final clear');

const shortNative = new exportsObject.NativeSlider(undefined,{value:.5,vertical:true});
shortNative.aboutToAppear();shortNative.begin(verticalEvent(0,90));
assert.equal(shortNative.nativeJellyPrepared,true);
advance(120);shortNative.end();
assert.equal(shortNative.nativeJellyPrepared,false,'A short press must clear the prepared filter');
assert.equal(shortNative.nativeJellyEffect.cleared,true);
advance(500);assert.equal(shortNative.nativeJellyActive,false);
shortNative.aboutToDisappear();assert.equal(timeouts.size,0);
console.log('PASS: identity filter is prepared before the native entry and removed after an early release');

// Run linked-value updates without any touch event: the light follows the
// rendered liquid boundary, and repeated updates extend the feedback lifetime.
const external = new exportsObject.NativeSlider(undefined,{value:.5,vertical:true,kind:'sun',levelLight:true});
external.aboutToAppear();assert.equal(external.chosen,false);
const externalSnapshots=snapshotCalls;
external.value=.25;advance(100);
assert.equal(external.chosen,true);assert.equal(external.sourceX(),32);assert.equal(external.sourceY(),108);
external.lightX=-999;external.lightY=999;
assert.equal(external.sourceX(),32);assert.equal(external.sourceY(),108,'Light must ignore touch coordinates');
advance(300);external.value=.75;
assert.equal(external.sourceY(),36);
advance(400);assert.equal(external.chosen,true,'New external update must cancel the old expiry');
advance(200);assert.equal(external.chosen,false);
advance(100);assert.equal(external.lightIntensity,0);
external.adjusting=true;advance(100);
external.value=0;assert.equal(external.sourceY(),144);
external.value=1;assert.equal(external.sourceY(),0);
advance(2000);assert.equal(external.chosen,true,'Explicit adjusting keeps feedback active without new values');
external.adjusting=false;advance(100);assert.equal(external.lightIntensity,0);
external.value=.6;external.aboutToDisappear();assert.equal(timeouts.size,0,'Unmount cancels external feedback and press tasks');
assert.equal(snapshotCalls,externalSnapshots,'External native feedback must not capture component bitmaps');
console.log('PASS: liquid-relative light independent of touch; external value pulse/retrigger, sustained adjusting, endpoints and cleanup');

// Icon choice must not determine the motion of the ordinary matched pair.
nativeAvailable=true;
const pair=['volume','sun'].map(kind=>new exportsObject.NativeSlider(undefined,{value:.5,vertical:true,kind,brightnessMotion:true}));
const pairSnapshots=snapshotCalls;
for(const s of pair){s.aboutToAppear();assert.equal(s.nativeJellyReady,true);s.begin(verticalEvent(0,90));assert.equal(s.nativeJellyPrepared,true);}
advance(300);
for(const s of pair)assert.equal(s.nativeJellyActive,true);
assert.equal(JSON.stringify(pair[0].nativeJellyEffect.frame),JSON.stringify(pair[1].nativeJellyEffect.frame));
advance(367);
assert.equal(JSON.stringify(pair[0].nativeJellyEffect.frame),JSON.stringify(pair[1].nativeJellyEffect.frame));
assert.equal(pair[0].buttonZoom,pair[1].buttonZoom);
assert.equal(snapshotCalls,pairSnapshots);
for(const s of pair){s.jellyEnabled=false;assert.equal(s.nativeJellyActive,false);s.end();s.aboutToDisappear();}
assert.equal(timeouts.size,0);assert.equal(intervals.size,0);
const legacyVolume=new exportsObject.NativeSlider(undefined,{value:.5,vertical:true,kind:'volume'});
legacyVolume.aboutToAppear();assert.equal(legacyVolume.nativeJellyReady,false,'Unmaintained/default volume profile keeps its previous behavior');legacyVolume.aboutToDisappear();
nativeAvailable=false;
const fallbackVolume=new exportsObject.NativeSlider(undefined,{value:.5,vertical:true,kind:'volume',brightnessMotion:true});
fallbackVolume.aboutToAppear();fallbackVolume.begin(verticalEvent(0,90));advance(300);
assert.equal(fallbackVolume.jellyShowing,true);
assert.equal(fallbackVolume.jellyRenderer.lastIcon[3],false,'Volume fallback must never substitute the sun vector');
fallbackVolume.aboutToDisappear();assert.equal(timeouts.size,0);assert.equal(intervals.size,0);
console.log('PASS: matched volume/brightness native entry, frames, scale, shared disable and cleanup; volume icon fallback and legacy profile preserved');

// A remote controller drives all feedback without begin/move/end or TouchEvent.
nativeAvailable=true;
for(const kind of ['volume','sun']) {
 const s=new exportsObject.NativeSlider(undefined,{value:.5,vertical:true,kind,levelLight:true,brightnessMotion:true,
  adjustmentMotion:{sequence:0,delta:0,velocity:0}});
 s.aboutToAppear();assert.equal(s.feedbackActive,false);assert.equal(s.showParticles,false);
 const snaps=snapshotCalls;s.adjusting=true;
 assert.equal(s.nativeJellyPrepared,true);assert.equal(s.showParticles,true);assert.equal(s.fields.length,1);
 const generation=s.particleGeneration;
 s.value=.8;s.adjustmentMotion={sequence:1,delta:.3,velocity:.8};
 assert.equal(s.particleGeneration,generation,'Updates must not restart the entry');assert.equal(s.velocity,-150);
 assert.ok(Math.abs(s.accumulated-38.4)<1e-9,'Explicit motion must not be double-counted by value watch');
 advance(140);tick();assert.equal(s.fields.length,2);
 advance(160);assert.equal(s.nativeJellyActive,true);assert.equal(s.dragging,false);
 advance(367);assert.equal(JSON.stringify(s.nativeJellyEffect.frame),JSON.stringify(model('SdfKeyframes').SdfKeyframes.enter[2]));
 const fields=s.fields.length;advance(1000);tick();
 assert.equal(s.nativeJellyActive,true);assert.equal(s.chosen,true);assert.equal(s.fields.length,fields,'Hold must not invent waves');assert.equal(s.velocity,0);
 s.value=1;s.adjustmentMotion={sequence:2,delta:.3,velocity:.7};
 s.value=1;s.adjustmentMotion={sequence:3,delta:.3,velocity:.5};
 tick();assert.equal(s.value,1);assert.equal(s.fields.length,fields+1,'Motion continues at clamped value');
 s.adjustmentMotion={sequence:3,delta:1,velocity:1};tick();assert.equal(s.fields.length,fields+1,'Duplicate motion samples are ignored');
 s.adjusting=false;assert.equal(s.feedbackActive,false);assert.equal(s.particleOpacity,0);assert.equal(s.rippleTimer,-1);
 const fade=animations.findLast(a=>a.duration===600&&a.onFinish);
 advance(333);const exit=animations.findLast(a=>a.delay===0&&a.onFinish);
 s.adjusting=true;exit.onFinish();fade.onFinish();
 assert.equal(s.feedbackActive,true);assert.equal(s.nativeJellyActive,true);assert.equal(s.showParticles,true);
 assert.equal(snapshotCalls,snaps,'Remote native feedback must remain live, without snapshots');
 s.aboutToDisappear();assert.equal(timeouts.size,0);assert.equal(intervals.size,0);
}
const mountedHeld=new exportsObject.NativeSlider(undefined,{value:.5,vertical:true,kind:'volume',levelLight:true,brightnessMotion:true,adjusting:true});
mountedHeld.aboutToAppear();assert.equal(mountedHeld.nativeJellyReady,true);assert.equal(mountedHeld.nativeJellyPrepared,true,'Capability probe must precede initially active feedback');
mountedHeld.aboutToDisappear();assert.equal(timeouts.size,0);assert.equal(intervals.size,0);
console.log('PASS: remote volume/sun start-update-hold-end, real motion at endpoints, no double count, stale exit/fade protection, live SDF and cleanup');

const displayOnly=new exportsObject.NativeSlider(undefined,{value:.5,vertical:true,kind:'sun',levelLight:true,touchEnabled:false});
displayOnly.aboutToAppear();displayOnly.begin(verticalEvent(0,90));displayOnly.move(verticalEvent(-50,30));displayOnly.tap(verticalEvent(0,20));
assert.equal(displayOnly.value,.5);assert.equal(displayOnly.feedbackActive,false);assert.equal(displayOnly.dragging,false);
displayOnly.adjusting=true;advance(300);assert.equal(displayOnly.nativeJellyActive,true,'Display-only mode must still accept external feedback');
displayOnly.adjusting=false;displayOnly.aboutToDisappear();assert.equal(timeouts.size,0);assert.equal(intervals.size,0);
console.log('PASS: display-only slider ignores direct gestures but retains complete external feedback');

// Reproduce a delayed touch, then one-swipe-to-end under the selection delay.
for(const elapsed of [0,30,99]){
 const s=new exportsObject.NativeSlider(undefined,{value:.1,vertical:true});s.aboutToAppear();
 s.directContact=true;s.contact().down();advance(500);assert.equal(s.chosen,false);assert.equal(s.buttonZoom,1.1);
 s.begin(verticalEvent(0,130));assert.equal(s.buttonZoom,1);assert.equal(s.lightIntensity,1);
 s.move(verticalEvent(-128,2));assert.equal(s.value,1);advance(elapsed);s.end();
 assert.equal(s.directContact,true);assert.equal(s.feedbackActive,false);assert.equal(s.chosen,false);
 advance(500);assert.equal(s.chosen,false);assert.equal(s.nativeJellyActive,false);assert.equal(s.nativeJellyPrepared,false);
 s.directContact=false;s.end();advance(100);assert.equal(s.lightIntensity,0);
 s.aboutToDisappear();assert.equal(timeouts.size,0);assert.equal(intervals.size,0);
}
const staleMotion=new exportsObject.NativeSlider(undefined,{value:.5,vertical:true,levelLight:true,adjustmentMotion:{sequence:0,delta:0,velocity:0}});
staleMotion.aboutToAppear();staleMotion.value=.7;staleMotion.adjustmentMotion={sequence:1,delta:.2,velocity:1};
advance(1000);assert.equal(staleMotion.feedbackActive,false,'Explicit motion received outside active Pan must not restart feedback');
staleMotion.aboutToDisappear();
console.log('PASS: late Pan after long touch, quick full-range adjustment, Pan end before TouchUp cancels fill/SDF, stale external samples cannot restart');

const tapOnly=new exportsObject.NativeSlider(undefined,{value:.5,vertical:true,levelLight:true});tapOnly.aboutToAppear();
tapOnly.tap(verticalEvent(0,80));advance(1000);assert.equal(tapOnly.feedbackActive,false);assert.equal(tapOnly.nativeJellyActive,false);
assert.equal(tapOnly.chosen,false,'Tap write after TouchUp is not an external adjustment pulse');tapOnly.aboutToDisappear();
console.log('PASS: direct tap does not turn its own value watcher into delayed external feedback');

// Playback mounts its display after recognizing a vertical gesture. A shared
// contact/adjustment flag must still select the same 1x shell as reference Pan.
for (const kind of ['volume', 'sun']) {
 const s = new exportsObject.NativeSlider(undefined, { value: .5, vertical: true, kind,
  levelLight: true, brightnessMotion: true, touchEnabled: false, pressing: true, adjusting: true,
  adjustmentMotion: { sequence: 0, delta: 0, velocity: 0 } });
 s.aboutToAppear();
 assert.equal(s.buttonZoom, 1);
 assert.equal(s.lightIntensity, 1);
 advance(99); assert.equal(s.chosen, false);
 s.adjusting = false; s.pressing = false;
 advance(1); assert.equal(s.chosen, false, 'Early release cancels the pending selection');
 advance(400); assert.equal(s.nativeJellyActive, false); assert.equal(s.lightIntensity, 0);
 s.pressing = true; advance(500);
 assert.equal(s.buttonZoom, 1.1); assert.equal(s.chosen, false);
 s.adjusting = true; assert.equal(s.buttonZoom, 1);
 advance(100); assert.equal(s.chosen, true);
 s.adjustmentMotion = { sequence: 1, delta: .3, velocity: 1 }; s.value = 1;
 advance(200); assert.equal(s.nativeJellyActive, true);
 s.adjusting = false; s.pressing = false; s.aboutToDisappear();
 assert.equal(timeouts.size, 0); assert.equal(intervals.size, 0);
}
console.log('PASS: playback mount during drag stays 1x; short drag cancels selection/SDF, pure contact stays white, repeated dragging and disposal');

// Exercise actual compiled Lottie frame selection and press/release recoloring.
for (const kind of ['volume', 'sun']) {
 const icon = new exportsObject.FirmwareIcon(undefined, { value: 0, kind });
 const calls = [];
 icon.loaded = true;
 icon.animationItem = {
  goToAndStop(frame) { calls.push(['frame', frame]); },
  setSpeed(speed) { calls.push(['speed', speed]); },
  playSegments(segment) { calls.push(['segment', Array.from(segment)]); },
  changeColor(color) { calls.push(['color', Array.from(color)]); }
 };
 icon.refresh();
 assert.equal(calls.at(-1)[1], kind === 'volume' ? 0 : 61);
 if (kind === 'volume') {
  for (const [value, segment] of [[.001,[0,29]],[.33,[104,140]],[.66,[179,214]],[.33,[214,179]],[0,[29,0]]]) {
   icon.value = value;
   assert.deepEqual(calls.at(-1), ['segment', segment]);
  }
 } else {
  icon.value = 1; assert.deepEqual(calls.at(-1), ['frame',301]);
  icon.value = .5; assert.deepEqual(calls.at(-1), ['frame',181]);
 }
 icon.ink = true;
 assert.ok(calls.some(call => call[0] === 'color' && call[1].join() === '0,0,0,1'));
 icon.ink = false;
 assert.ok(calls.some(call => call[0] === 'color' && call[1].join() === '255,255,255,1'));
}
console.log('PASS: compiled Lottie icons select volume transition segments in both directions, brightness frames, and dark/white press/release colors');
