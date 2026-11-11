/**
 * 画质偏好「Wi-Fi / 移动网络」分档 + 手机热点识别。
 *
 * 1. utils/NetworkClass 的纯判定规则（计费口径、热点只认系统结论）；
 * 2. QualityPreferenceService 的两档读写、换网重算、生效值同步；
 * 3. 设置页/入口/播放页的接线（含「手动切画质不回写偏好」）。
 */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const profilePage = read('entry/src/main/ets/pages/ProfilePage.ets');
const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
const videoPage = read('entry/src/main/ets/pages/VideoPlayerPage.ets');
const moduleJson = read('entry/src/main/module.json5');
const classSrc = read('entry/src/main/ets/utils/NetworkClass.ets');
const catalogSrc = read('entry/src/main/ets/utils/QualityCatalog.ets');
const serviceSrc = read('entry/src/main/ets/services/QualityPreferenceService.ets');

function compile(source) {
  return ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
}

function run(source, imports) {
  const context = vm.createContext(Object.assign({ exports: {}, setTimeout, clearTimeout }, imports));
  vm.runInContext(compile(source), context);
  return context.exports;
}

/** 服务文件带 kit 依赖：用 require 垫片把平台 API 换成可控 mock。 */
function loadService(env) {
  const modules = {
    '@kit.NetworkKit': { connection: env.connection },
    '@kit.ConnectivityKit': { wifiManager: env.wifiManager },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
    '@kit.ArkData': { preferences: {} },
    '@kit.AbilityKit': { common: {} },
    '@kit.BasicServicesKit': {},
    '../utils/NetworkClass': run(classSrc, {}),
    '../utils/QualityCatalog': run(catalogSrc, {})
  };
  const context = vm.createContext({
    exports: {},
    AppStorage: env.AppStorage,
    setTimeout,
    clearTimeout,
    require: id => {
      assert.ok(modules[id], 'unexpected import ' + id);
      return modules[id];
    }
  });
  vm.runInContext(compile(serviceSrc), context);
  return context.exports;
}

// ============ 1. 纯判定规则 ============
const nc = run(classSrc, {});

function signals(patch) {
  return Object.assign({
    bearerTypes: [1], meteredHotspot: false, systemMetered: false, wifiProbe: true
  }, patch);
}

const wifiPlain = nc.classifyNetwork(signals({}));
assert.equal(wifiPlain.cls, 'wifi');
assert.equal(wifiPlain.metered, false, '普通 Wi-Fi 不能按移动网络计费');

// 回归用例：家里的路由器开了「按流量计费」，系统的计费位是 true，但不能因此降档。
const homeMeteredFlag = nc.classifyNetwork(signals({ systemMetered: true }));
assert.equal(homeMeteredFlag.cls, 'wifi', '计费标记不等于热点');
assert.equal(homeMeteredFlag.metered, false, '带计费标记的家用 Wi-Fi 仍走 Wi-Fi 档');

const hotspotBySystem = nc.classifyNetwork(signals({ meteredHotspot: true }));
assert.equal(hotspotBySystem.cls, 'hotspot');
assert.equal(hotspotBySystem.metered, true, '系统认定计费热点 → 移动网络档');
assert.match(hotspotBySystem.evidence, /meteredHotspot=1/);

// 问不到系统结论（权限被拒 / 模拟器 / Wi-Fi 关闭）时按普通 Wi-Fi，不拿网关之类去猜。
const probeFailed = nc.classifyNetwork(signals({ wifiProbe: false, meteredHotspot: false, systemMetered: true }));
assert.equal(probeFailed.cls, 'wifi');
assert.equal(probeFailed.metered, false, '探不到热点结论就按 Wi-Fi 档，宁可漏判不误判');
assert.match(probeFailed.evidence, /probe=0/);

// 旧的三套推断必须彻底摘掉，否则计费标记又会把家用 Wi-Fi 判成热点。
assert.doesNotMatch(classSrc, /HOTSPOT_GATEWAYS|hotspotGatewayMatch|restrictedWifi/,
  '网关网段与 isRestricted 推断已废弃');
assert.doesNotMatch(serviceSrc, /getLinkedInfoSync|getConnectionPropertiesSync|isRestricted/,
  '服务层不再采信 Wi-Fi 受限标记与网关');

const cellular = nc.classifyNetwork(signals({ bearerTypes: [0] }));
assert.equal(cellular.cls, 'cellular');
assert.equal(cellular.metered, true);

const ethernet = nc.classifyNetwork(signals({ bearerTypes: [3], systemMetered: true }));
assert.equal(ethernet.cls, 'ethernet');
assert.equal(ethernet.metered, false, '有线网络一律按 Wi-Fi 档，不被系统的计费位带偏');

const both = nc.classifyNetwork(signals({ bearerTypes: [1, 3], meteredHotspot: true }));
assert.equal(both.cls, 'ethernet', '同时有有线时按有线算，热点判定不生效');
assert.equal(both.metered, false);

const none = nc.classifyNetwork(signals({ bearerTypes: [] }));
assert.equal(none.cls, 'none');
assert.equal(none.metered, true, '读不到链路时保守按计费处理');

assert.equal(nc.networkClassLabel('hotspot'), '移动热点');
assert.equal(nc.toNetworkClass('cellular'), 'cellular');
assert.equal(nc.toNetworkClass('nonsense'), 'unknown');

// 档位表
const catalog = run(catalogSrc, {});
assert.equal(catalog.qualityLabel(116), '1080P60');
assert.equal(catalog.qualityLabel(999), '1080P60', '未知 qn 回落默认文案');
assert.equal(catalog.isKnownQuality(64), true);
assert.equal(catalog.isKnownQuality(999), false);
assert.equal(catalog.DEFAULT_QUALITY_QN, 116);
assert.equal(catalog.DEFAULT_CELLULAR_QUALITY_QN, 64, '移动网络档默认 720P');

// ============ 2. 服务行为 ============
(async () => {
  const store = new Map([['defaultVideoQn', 120]]); // 老用户只存过单值：视为 Wi-Fi 档
  const shared = new Map();
  const net = { bearerTypes: [1], metered: false };
  const wifi = { meteredHotspot: false };
  const listeners = [];
  const connection = {
    NetBearType: { BEARER_CELLULAR: 0, BEARER_WIFI: 1, BEARER_BLUETOOTH: 2, BEARER_ETHERNET: 3, BEARER_VPN: 4 },
    getDefaultNetSync: () => ({ netId: 100 }),
    getNetCapabilitiesSync: () => ({ bearerTypes: net.bearerTypes }),
    isDefaultNetMeteredSync: () => net.metered,
    createNetConnection: () => ({
      on: (type, cb) => listeners.push({ type, cb }),
      register: cb => cb(undefined)
    })
  };
  const wifiManager = {
    isMeteredHotspot: () => wifi.meteredHotspot
  };
  const AppStorage = {
    get: key => shared.get(key),
    setOrCreate: (key, value) => shared.set(key, value)
  };
  const { QualityPreferenceService } = loadService({ connection, wifiManager, AppStorage });
  const svc = QualityPreferenceService.getInstance();

  const pref = {
    getSync: (key, fallback) => (store.has(key) ? store.get(key) : fallback),
    putSync: (key, value) => store.set(key, value),
    flushSync: () => {}
  };
  svc.pref = pref;

  svc.initialize({});
  assert.equal(shared.get('videoQnWifi'), 120, '旧键 defaultVideoQn 迁移成 Wi-Fi 档');
  assert.equal(shared.get('videoQnCellular'), 64, '移动网络档缺省 720P');
  assert.equal(shared.get('defaultVideoQn'), 120, 'Wi-Fi 链路生效 Wi-Fi 档');
  assert.equal(shared.get('networkClass'), 'wifi');
  assert.equal(shared.get('networkMetered'), false);
  assert.equal(shared.has('networkGateway'), false, '网关只用于旧的推断，已不再写进 AppStorage');
  assert.equal(listeners.length, 3, '必须监听 capabilities/available/lost 三类事件');

  // 换到蜂窝：生效值立刻切到移动网络档
  net.bearerTypes = [0];
  svc.refresh('test-cellular');
  assert.equal(shared.get('networkClass'), 'cellular');
  assert.equal(shared.get('networkMetered'), true);
  assert.equal(shared.get('defaultVideoQn'), 64, '蜂窝链路生效移动网络档');

  // 连到别人手机的热点：承载是 Wi-Fi，但系统认可费热点 → 必须按移动网络档
  net.bearerTypes = [1];
  wifi.meteredHotspot = true;
  svc.refresh('test-hotspot');
  assert.equal(shared.get('networkClass'), 'hotspot');
  assert.equal(shared.get('networkMetered'), true);
  assert.equal(shared.get('defaultVideoQn'), 64, '热点按移动网络档取流');
  assert.match(QualityPreferenceService.networkDetail('hotspot', true), /移动网络档/);

  // 改移动网络档：当前就在热点上，生效值同步变化并落盘
  svc.setQn('cellular', 80);
  assert.equal(store.get('defaultVideoQnCellular'), 80);
  assert.equal(shared.get('videoQnCellular'), 80);
  assert.equal(shared.get('defaultVideoQn'), 80);

  // 改 Wi-Fi 档：当前链路不走它，生效值不能跟着动
  svc.setQn('wifi', 112);
  assert.equal(store.get('defaultVideoQn'), 112, 'Wi-Fi 档仍写旧键，升级前的值不会被丢');
  assert.equal(shared.get('videoQnWifi'), 112);
  assert.equal(shared.get('defaultVideoQn'), 80, '在热点上改 Wi-Fi 档不影响当前生效值');

  // 回到家里的 Wi-Fi：路由器带「按流量计费」标记（系统 metered=true），也不许判成热点
  net.metered = true;
  wifi.meteredHotspot = false;
  svc.refresh('test-home');
  assert.equal(shared.get('networkClass'), 'wifi', '计费标记不等于热点');
  assert.equal(shared.get('networkMetered'), false);
  assert.equal(shared.get('defaultVideoQn'), 112, '家用 Wi-Fi 仍走 Wi-Fi 档');
  assert.doesNotMatch(QualityPreferenceService.networkDetail('wifi', false), /热点|网关/,
    '设置页不能再拿网关/受限标记当解释');

  // 非法档位直接拒绝，不能把脏值写进偏好
  assert.throws(() => svc.setQn('wifi', 999));
  assert.equal(store.get('defaultVideoQn'), 112);

  // 网络事件 → 防抖后自动重算
  net.bearerTypes = [0];
  const caps = listeners.find(item => item.type === 'netCapabilitiesChange');
  caps.cb({ netHandle: { netId: 100 }, netCap: {} });
  await new Promise(resolve => setTimeout(resolve, 500));
  assert.equal(shared.get('networkClass'), 'cellular', '换网事件必须自动重算');
  assert.equal(shared.get('defaultVideoQn'), 80);

  // 联调覆盖：--ps qualityNetwork
  shared.set('qualityNetworkOverride', 'hotspot');
  svc.refresh('override');
  assert.equal(shared.get('networkClass'), 'hotspot');
  assert.equal(shared.get('defaultVideoQn'), 80, 'override 后按移动网络档');
  shared.delete('qualityNetworkOverride');

  // ============ 3. 接线 ============
  assert.match(profilePage, /@StorageLink\('videoQnWifi'\) videoQnWifi: number = DEFAULT_QUALITY_QN/);
  assert.match(profilePage, /@StorageLink\('videoQnCellular'\) videoQnCellular: number = DEFAULT_CELLULAR_QUALITY_QN/);
  assert.match(profilePage, /Text\('Wi-Fi 画质'\)/);
  assert.match(profilePage, /Text\('移动网络画质'\)/);
  assert.match(profilePage, /\.id\('setting-quality-wifi'\)\.bindMenu\(this\.SettingsOptions\('qualityWifi'\)/);
  assert.match(profilePage, /\.id\('setting-quality-cellular'\)\.bindMenu\(this\.SettingsOptions\('qualityCellular'\)/);
  assert.match(profilePage, /\.id\('setting-quality-network'\)/, '设置页必须显示当前链路判定');
  assert.doesNotMatch(profilePage, /networkGateway/, '设置页不再读网关值');
  assert.match(profilePage, /this\.saveQuality\('wifi', QUALITY_OPTIONS\[index\]\.qn\)/);
  assert.match(profilePage, /this\.saveQuality\('cellular', QUALITY_OPTIONS\[index\]\.qn\)/);
  assert.doesNotMatch(profilePage, /默认播放画质/, '旧的单档设置项已被两档替换');
  assert.match(profilePage, /QualityPreferenceService\.getInstance\(\)\.refresh\('settings-page'\)/,
    '进设置页要重算一次，兜住后台换网');

  assert.match(ability, /QualityPreferenceService\.getInstance\(\)\.initialize\(this\.context\)/);
  assert.ok(ability.indexOf("want.parameters?.['qualityNetwork']") <
    ability.indexOf('QualityPreferenceService.getInstance().initialize'),
    '--ps qualityNetwork 必须在解析之前生效');
  assert.doesNotMatch(ability, /persistProp\('defaultVideoQn'/, '生效值不能持久化，否则会顶掉本次换网判定');
  assert.doesNotMatch(ability, /get\('defaultVideoQn'/, '入口不再自己读单值偏好');

  assert.doesNotMatch(videoPage, /persistProp\('defaultVideoQn'/, '播放页模块加载会顶掉服务写好的值');
  assert.doesNotMatch(videoPage, /setOrCreate\('defaultVideoQn'/, '手动切画质不得回写偏好');

  assert.match(moduleJson, /"ohos\.permission\.GET_WIFI_INFO"/, '热点识别需要 Wi-Fi 信息权限');

  console.log('Quality preference split by network: classification, hotspot detection, buckets and wiring passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
