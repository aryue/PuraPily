const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const DeviceType = { SPEAKER: 2, WIRED_HEADSET: 3, WIRED_HEADPHONES: 4, BLUETOOTH_SCO: 7, BLUETOOTH_A2DP: 8, USB_HEADSET: 22, NEARLINK: 31 };
const devices = type => [{ deviceType: type }];
let route = devices(DeviceType.SPEAKER), queriedUsage;
const audio = { DeviceType, getAudioManager: () => ({ getRoutingManager: () => ({
  getPreferredOutputDeviceForRendererInfoSync(info) { queriedUsage = info.usage; return route; }
}) }) };
const iconContext = { exports: {}, $r: value => value };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(root+'utils/HeadphoneIcons.ts','utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, iconContext);
const { headphoneIconName, headphoneIconResource } = iconContext.exports;
for (const [names, icon] of [
  [['FreeBuds Pro', 'HUAWEI FreeBuds Pro 5', 'freebudspro3'], '16643'],
  [['FreeBuds 2', 'FREEBUDS 3', 'FreeBuds4', 'FreeBuds 7 悦彰耳机'], '16646'],
  [['FreeBuds 5', 'FreeBuds6'], '16660'],
  [['FreeBuds Studio'], 'roc'], [['FreeArc', 'HUAWEI FreeArc 2'], '16661'],
  [['HUAWEI Glasses', 'smart glasses'], '5888'], [['FreeClip', 'FreeClip2'], '16659'],
  [['FreeBuds 4i', 'FreeBuds5i', 'FreeBuds 6 i', 'FreeBuds 12i'], '16644']
]) for (const name of names) {
  assert.equal(headphoneIconName(name), 'earphone_' + icon, name);
  const resource = headphoneIconResource(headphoneIconName(name));
  assert.equal(resource.type, 20000);
  assert.equal(typeof resource.id, 'number');
}
for (const name of ['', 'unknown', 'Pura X View', 'FreeBuds 20', 'FreeBuds 4E', 'FreeBuds Arc', 'Other headphones']) {
  assert.equal(headphoneIconName(name), 'headphones_fill', name);
}
let peers = [], peerFailure = false;
const manager = { getPairedDevices: () => {
  if (peerFailure) throw Error('permission or query failed');
  return peers.map(peer => peer.address);
} };
const remoteDevice = { createRemoteDevice: address => {
  const peer = peers.find(peer => peer.address === address);
  return { getDeviceName: () => peer.name, getConnectionState: () => peer.state,
    getDeviceClass: () => peer.category };
} };
const timers = new Map(); let timerId = 0;
let resolvePermission, permissionRequests = 0;
const context = { exports: {}, setInterval: fn => { timers.set(++timerId, fn); return timerId; },
  clearInterval: id => timers.delete(id), require: name => {
    if (name.includes('HeadphoneIcons')) return iconContext.exports;
    if (name.includes('nearlink.manager')) return { default: manager };
    if (name.includes('nearlink.remoteDevice')) return { default: remoteDevice };
    if (name.includes('nearlink.constant')) return { default: { ConnectionState: { STATE_CONNECTED: 1 } } };
    if (name.includes('bluetooth.connection')) return { default: { getRemoteDeviceName: () => 'FreeBuds Studio' } };
    if (name.includes('abilityAccessCtrl')) return { default: { createAtManager: () => ({
      requestPermissionsFromUser: () => { permissionRequests++; return new Promise(resolve => { resolvePermission = resolve; }); }
    }) } };
    return { default: audio, audio };
  } };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(root+'utils/PlaybackAudioOutput.ts','utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const { PlaybackAudioOutputMonitor, isHeadphoneOutput, outputHeadphoneIcon } = context.exports;
const nearlinkRoute = [{ deviceType: 31, address: '', name: '', displayName: 'Pura X View' }];
const peer = { address: 'AA:BB:CC:DD:EE:01', name: 'FreeBuds Pro 5', state: 1, category: 0x801 };
peers = [peer];
assert.equal(outputHeadphoneIcon(nearlinkRoute), 'earphone_16643');
assert.equal(outputHeadphoneIcon(devices(2)), 'headphones_fill', 'connected earbuds cannot override speaker route');
peers.push({ ...peer, address: 'AA:BB:CC:DD:EE:02', name: 'FreeClip 2' });
assert.equal(outputHeadphoneIcon(nearlinkRoute), 'headphones_fill', 'ambiguous peers keep generic icon');
assert.equal(outputHeadphoneIcon([{ ...nearlinkRoute[0], address: peer.address.toLowerCase() }]), 'earphone_16643');
assert.equal(outputHeadphoneIcon([{ ...nearlinkRoute[0], address: '00:00:00:00:00:00' }]), 'headphones_fill');
peers = [{ ...peer, state: 3 }];
assert.equal(outputHeadphoneIcon(nearlinkRoute), 'headphones_fill');
peers = [peer]; peerFailure = true;
assert.equal(outputHeadphoneIcon(nearlinkRoute), 'headphones_fill'); peerFailure = false;
assert.equal(outputHeadphoneIcon([{ deviceType: 8, name: 'FreeArc' }]), 'earphone_16661');
assert.equal(outputHeadphoneIcon([{ deviceType: 8, name: '', address: peer.address }]), 'earphone_roc');
assert.equal(isHeadphoneOutput([]), false);
assert.equal(isHeadphoneOutput(devices(DeviceType.SPEAKER)), false);
for (const type of [3,4,7,8,22,31]) assert.equal(isHeadphoneOutput(devices(type)), true);
for (const type of [1,23,24,25,27,28,29]) assert.equal(isHeadphoneOutput(devices(type)), false);
function player(usage) {
  return { audioRendererInfo: usage === undefined ? undefined : { usage }, listener: null, offCount: 0,
    on(type, fn) { assert.equal(type, 'audioOutputDeviceChangeWithInfo'); this.listener = fn; },
    off(type, fn) { assert.equal(fn, this.listener); this.listener = null; this.offCount++; }
  };
}
const updates = [];
const monitor = new PlaybackAudioOutputMonitor(value => updates.push(value));
const main = player(4), splitAudio = player(1);
monitor.bind(main, 4);
assert.equal(updates.at(-1), false); assert.equal(queriedUsage, 4);
const oldListener = main.listener;
main.listener({ devices: devices(4) }); assert.equal(updates.at(-1), true);
main.listener({ devices: devices(2) }); assert.equal(updates.at(-1), false);
route = devices(8);
monitor.bind(splitAudio, 1);
assert.equal(main.offCount, 1); assert.equal(queriedUsage, 1); assert.equal(updates.at(-1), true);
oldListener({ devices: devices(2) }); assert.equal(updates.at(-1), true, 'old video route cannot override split audio');
const activeListener = splitAudio.listener;
monitor.bind(splitAudio, 1); assert.equal(splitAudio.listener, activeListener, 'same player has only one listener');
monitor.dispose(); assert.equal(splitAudio.offCount, 1);
const count = updates.length;
activeListener({ devices: devices(2) }); assert.equal(updates.length, count, 'late callbacks ignored after disposal');
monitor.bind(splitAudio, 1);
activeListener({ devices: devices(2) }); assert.equal(updates.at(-1), true, 'stale callback ignored even after same-player rebind');
monitor.dispose();
route = devices(22);
const fallback = player(); monitor.bind(fallback, 4);
assert.equal(queriedUsage, 4); assert.equal(updates.at(-1), true);
monitor.dispose();
route = nearlinkRoute;
const icons = [];
const iconMonitor = new PlaybackAudioOutputMonitor((headphones, icon) => icons.push([headphones, icon]));
const starPlayer = player(4);
iconMonitor.bind(starPlayer, 4);
assert.equal(icons.at(-1)[1], 'earphone_16643');
assert.equal(timers.size, 1);
peers = [{ ...peer, name: 'FreeClip 2' }];
for (const tick of timers.values()) tick();
assert.equal(icons.at(-1)[1], 'earphone_16659', 'peer metadata refreshes without volume changes');
starPlayer.listener({ devices: devices(2) });
assert.equal(icons.at(-1)[0], false);
assert.equal(timers.size, 0);
iconMonitor.bind(starPlayer, 4);
assert.equal(icons.at(-1)[0], false, 'preferred route cannot overwrite AVPlayer actual route');
iconMonitor.dispose();
assert.equal(timers.size, 0);
(async () => {
  const values = [];
  const permissionMonitor = new PlaybackAudioOutputMonitor((...args) => values.push(args), () => ({}));
  route = devices(2);
  permissionMonitor.bind(player(4), 4);
  assert.equal(permissionRequests, 0, 'speaker output does not request wireless metadata permissions');
  route = nearlinkRoute;
  const permissionPlayer = player(4);
  permissionMonitor.bind(permissionPlayer, 4);
  assert.equal(permissionRequests, 1);
  permissionMonitor.bind(permissionPlayer, 4);
  assert.equal(permissionRequests, 1, 'no repeated prompt while grant is pending');
  permissionMonitor.dispose();
  const count = values.length;
  resolvePermission({ authResults: [0] });
  await Promise.resolve(); await Promise.resolve();
  assert.equal(values.length, count, 'permission callback cannot update disposed player');
  assert.equal(timers.size, 0);
  console.log('PASS: compiled model rules/resources; selected audio route; NearLink candidate/address/ambiguity/disconnect/error cases; permission lifecycle; metadata refresh; DASH handoff; stale callbacks and cleanup.');
})().catch(error => { console.error(error); process.exitCode = 1; });
