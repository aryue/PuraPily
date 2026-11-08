const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const path = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/AudioOutputLab.ts';
const nearlink = { deviceType: 31, name: '', displayName: '耳机', model: 'test-model', address: '' };
let resolveStreams;
let fail = false;
const routing = {
  getPreferredOutputDeviceForRendererInfoSync: () => [nearlink],
  getDevicesSync: () => { if (fail) throw { code: 6800301, message: 'test failure' }; return [nearlink]; }
};
const audio = {
  DeviceType: { NEARLINK: 31, 31: 'NEARLINK' }, StreamUsage: { STREAM_USAGE_MOVIE: 4 },
  DeviceFlag: { OUTPUT_DEVICES_FLAG: 1 },
  getAudioManager: () => ({ getRoutingManager: () => routing,
    getStreamManager: () => ({ getCurrentAudioRendererInfoArray: () => new Promise(r => { resolveStreams = r; }) }) })
};
let peers = [];
let peerError = false;
const constant = { ConnectionState: { STATE_CONNECTED: 1 }, DeviceClass: {} };
const manager = { getPairedDevices: () => {
  if (peerError) throw { code: 201, message: 'Permission denied' };
  return peers.map(peer => peer.address);
} };
const remoteDevice = { createRemoteDevice: address => {
  const peer = peers.find(peer => peer.address === address);
  return { getDeviceName: () => peer.name, getDeviceClass: () => peer.deviceClass,
    getConnectionState: () => peer.connectionState, getAcbState: () => 1,
    getDeviceInformation: () => { throw { code: 801, message: 'Not supported' }; } };
} };
let retainedContent;
const texts = [];
class Property {
  constructor(value) { this.value = value; }
  get() { return this.value; }
  set(value) { this.value = value; }
  reset(value) { this.value = value; }
}
class View {
  createStorageProp(_key, value) { return new Property(value); }
  observeComponentCreation2(callback) { callback(1, true); }
  static create() {}
}
class Surface {
  constructor(_parent, params) { retainedContent = params.content; }
}
const ui = new Proxy({}, { get: () => () => {} });
const context = { exports: {}, ViewPU: View, registerNamedRoute() {},
  SynchedPropertySimpleOneWayPU: Property,
  Column: ui, Text: { ...ui, create: value => texts.push(value),
    fontSize() {}, fontWeight() {}, width() {}, fontColor() {}, fontFamily() {}, copyOption() {}, pop() {} },
  FontWeight: {}, CopyOptions: {},
  require: name => {
    if (name.includes('nearlink.manager')) return { default: manager };
    if (name.includes('nearlink.remoteDevice')) return { default: remoteDevice };
    if (name.includes('nearlink.constant')) return { default: constant };
    return { default: audio, PageSurface: Surface };
  } };
const code = ts.transpileModule(fs.readFileSync(path, 'utf8') + '\nexports.Lab = AudioOutputLab; exports.Section = AudioOutputLabSection;', {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
vm.runInNewContext(code, context);
const page = Object.create(context.exports.Lab.prototype);
for (const key of ['streams', 'preferred', 'available', 'updated', 'nearLinkDevices', 'matching']) {
  let value = '';
  page['__' + key] = { get: () => value, set: next => { value = next; } };
}
Object.assign(page, { active: true, busy: false, generation: 0, streams: 'old', updated: '' });
(async () => {
  // Exercise the compiled Text callbacks inside the same retained PageSurface content.
  // Updating data must update an existing card rather than only updating page state.
  const section = new context.exports.Section(undefined, { title: '输出', value: '读取中…' });
  section.initialRender();
  const content = retainedContent;
  content();
  assert.equal(texts.at(-1), '读取中…');
  section.updateStateVars({ title: '输出', value: 'NEARLINK (31) test-model' });
  content();
  assert.equal(texts.at(-1), 'NEARLINK (31) test-model');
  section.updateStateVars({ title: '输出', value: '错误 6800301' });
  content();
  assert.equal(texts.at(-1), '错误 6800301');
  assert.match(page.deviceText([nearlink]), /NEARLINK（星闪） \(31\)/);
  assert.match(page.deviceText([nearlink]), /model="test-model"/);
  assert.match(page.deviceText([nearlink]), /name=""/);
  assert.match(page.deviceText([{ deviceType: 987 }]), /未知类型/);
  const headset = { address: 'AA:BB:CC:DD:EE:01', name: 'Test Earbuds', deviceClass: 0x801, connectionState: 1 };
  peers = [headset, { ...headset, address: 'AA:BB:CC:DD:EE:02', name: 'Keyboard', deviceClass: 0x900 }];
  let snapshot = page.readNearLink();
  assert.equal(snapshot.complete, true, 'optional model API failure does not invalidate connection/class evidence');
  assert.match(snapshot.text, /Test Earbuds/);
  assert.match(snapshot.text, /801.*Not supported/);
  assert.match(page.matchNearLink([nearlink], snapshot), /推测匹配 → Test Earbuds/);
  assert.match(page.matchNearLink([{ deviceType: 2 }], snapshot), /不推测/);
  peers.push({ ...headset, address: 'AA:BB:CC:DD:EE:03', name: 'Other Earbuds' });
  snapshot = page.readNearLink();
  assert.match(page.matchNearLink([nearlink], snapshot), /未确定.*2 个/);
  assert.match(page.matchNearLink([{ ...nearlink, address: headset.address }], snapshot), /地址一致 → Test Earbuds/);
  assert.match(page.matchNearLink([{ ...nearlink, address: '11:22:33:44:55:66' }], snapshot), /不推测/);
  peers = [{ ...headset, connectionState: 3 }];
  assert.match(page.matchNearLink([nearlink], page.readNearLink()), /未确定.*0 个/);
  peerError = true;
  snapshot = page.readNearLink();
  assert.equal(snapshot.complete, false);
  assert.match(page.matchNearLink([nearlink], snapshot), /不完整/);
  peerError = false;
  const first = page.refresh();
  page.active = false; page.generation++;
  resolveStreams([{ streamId: 1, rendererInfo: {}, deviceDescriptors: [nearlink] }]);
  await first;
  assert.equal(page.streams, 'old', 'hidden page ignores late stream response');
  page.active = true; fail = true;
  const second = page.refresh(); resolveStreams([]); await second;
  assert.match(page.streams, /没有可见播放流/);
  assert.match(page.available, /6800301.*test failure/);
  assert.equal(page.busy, false);
  console.log('PASS: compiled audio lab — reactive text; NearLink peer queries; single/multiple/disconnected/non-audio candidates; address comparison; permission/optional API failures; route data and stale response isolation.');
})().catch(error => { console.error(error); process.exitCode = 1; });
