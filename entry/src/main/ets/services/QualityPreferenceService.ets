import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { connection } from '@kit.NetworkKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  NetworkProfile, NetworkSignals, classifyNetwork, networkClassLabel, toNetworkClass
} from '../utils/NetworkClass';
import { DEFAULT_QUALITY_QN, DEFAULT_CELLULAR_QUALITY_QN, isKnownQuality } from '../utils/QualityCatalog';

const DOMAIN: number = 0x0000;
const TAG: string = 'QualityPref';

/**
 * 兼容旧版本的单值偏好：老用户存下的那一档就是「Wi-Fi 档」，
 * 迁移时不要改名，否则升级后画质会被重置回默认值。
 */
const KEY_WIFI: string = 'defaultVideoQn';
const KEY_CELLULAR: string = 'defaultVideoQnCellular';
/** 网络事件会连发（切 Wi-Fi 时 capabilities/netAvailable 各来一次），合并成一次重算。 */
const REFRESH_DEBOUNCE_MS: number = 400;

export type QualityBucket = 'wifi' | 'cellular';

/**
 * 画质偏好按链路分档：Wi-Fi（含以太网/不计费）与移动网络（蜂窝、计费 Wi-Fi、手机热点）。
 *
 * - 单一事实来源是偏好文件里的两档值；AppStorage 的 `defaultVideoQn` 是**当前链路解析后的生效值**，
 *   播放页/列表预取/实例池都只读它，所以换网后不需要改任何调用点。
 * - `initialize()` 必须在首屏列表预取之前同步跑完（EntryAbility.onCreate），
 *   否则冷启首页会先按旧档生成缓存键，等模块加载后画质跳档、预取缓存作废。
 * - 网络切换由 connection 事件驱动重算；播放中的视频不会被改档（页面只在起播时读一次），
 *   只影响下一次取流。
 */
export class QualityPreferenceService {
  private static instance: QualityPreferenceService = new QualityPreferenceService();
  private pref: preferences.Preferences | null = null;
  private wifiQn: number = DEFAULT_QUALITY_QN;
  private cellularQn: number = DEFAULT_CELLULAR_QUALITY_QN;
  private lastRoute: string = '';
  private monitor: connection.NetConnection | null = null;
  private monitoring: boolean = false;
  private refreshTimer: number = -1;
  private readonly onCapsChange: (info: connection.NetCapabilityInfo) => void =
    (_info: connection.NetCapabilityInfo): void => { this.schedule('capabilities'); };
  private readonly onNetChange: (handle: connection.NetHandle) => void =
    (_handle: connection.NetHandle): void => { this.schedule('net'); };

  static getInstance(): QualityPreferenceService { return QualityPreferenceService.instance; }

  /** 冷启动入口：同步读偏好 + 立即按当前链路解析，然后开始监听换网。 */
  initialize(context: common.UIAbilityContext): void {
    if (this.pref === null) {
      try {
        this.pref = preferences.getPreferencesSync(context, { name: 'my_app_settings' });
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'open settings failed: %{public}s', JSON.stringify(error));
      }
    }
    this.readBuckets();
    this.publish('startup', true);
    this.startMonitor();
  }

  /** 重新读一遍偏好并按当前链路解析（设置页进入时调用，兜住「后台期间换过网、但事件没送到」）。 */
  refresh(reason: string): void {
    this.readBuckets();
    this.publish(reason, false);
  }

  /** 设置页改档：写偏好文件 + 立刻重算生效值（当前链路就是这一档时马上生效）。 */
  setQn(bucket: QualityBucket, qn: number): void {
    if (!isKnownQuality(qn)) throw new Error('未知画质档位');
    if (this.pref === null) throw new Error('画质偏好尚未准备好');
    const previousWifi = this.wifiQn;
    const previousCellular = this.cellularQn;
    if (bucket === 'wifi') this.wifiQn = qn; else this.cellularQn = qn;
    try {
      this.pref.putSync(bucket === 'wifi' ? KEY_WIFI : KEY_CELLULAR, qn);
      this.pref.flushSync();
    } catch (error) {
      this.wifiQn = previousWifi;
      this.cellularQn = previousCellular;
      hilog.error(DOMAIN, TAG, 'save %{public}s qn failed: %{public}s', bucket, JSON.stringify(error));
      throw new Error('保存画质偏好失败');
    }
    this.publish('save-' + bucket, true);
  }

  wifiQuality(): number { return this.wifiQn; }
  cellularQuality(): number { return this.cellularQn; }

  /** 当前链路生效的档位。 */
  currentQuality(): number { return this.isMeteredNow() ? this.cellularQn : this.wifiQn; }

  /** 当前链路是否按移动网络计费（UI 只读 AppStorage 的同名键，这里给低层调用方用）。 */
  isMeteredNow(): boolean { return this.profile().metered; }

  /** 设置页文案：当前链路 + 生效档位的一句话说明。 */
  static networkDetail(cls: string, metered: boolean): string {
    if (cls === 'hotspot') return '系统判定为计费热点 · 按移动网络档取流';
    if (cls === 'cellular') return '蜂窝数据 · 按移动网络档取流';
    if (cls === 'ethernet') return '有线网络 · 按 Wi-Fi 档取流';
    if (cls === 'wifi') return '不算移动流量 · 按 Wi-Fi 档取流';
    if (cls === 'none') return '无网络连接 · 暂不取流';
    return metered ? '未知链路 · 按移动网络档保守取流' : '未知链路 · 按 Wi-Fi 档取流';
  }

  static classLabel(cls: string): string { return networkClassLabel(cls); }

  private readBuckets(): void {
    if (this.pref === null) return;
    try {
      const wifi = this.pref.getSync(KEY_WIFI, DEFAULT_QUALITY_QN) as number;
      const cellular = this.pref.getSync(KEY_CELLULAR, DEFAULT_CELLULAR_QUALITY_QN) as number;
      this.wifiQn = isKnownQuality(wifi) ? wifi : DEFAULT_QUALITY_QN;
      this.cellularQn = isKnownQuality(cellular) ? cellular : DEFAULT_CELLULAR_QUALITY_QN;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'read buckets failed: %{public}s', JSON.stringify(error));
    }
  }

  private schedule(reason: string): void {
    if (this.refreshTimer >= 0) clearTimeout(this.refreshTimer);
    this.refreshTimer = setTimeout((): void => {
      this.refreshTimer = -1;
      this.refresh(reason);
    }, REFRESH_DEBOUNCE_MS);
  }

  private startMonitor(): void {
    if (this.monitoring) return;
    try {
      // 事件挂在 createNetConnection() 的实例上（connection 命名空间本身没有 on/off），
      // 必须先 register 才会真正收到回调。
      const monitor = connection.createNetConnection();
      monitor.on('netCapabilitiesChange', this.onCapsChange);
      monitor.on('netAvailable', this.onNetChange);
      monitor.on('netLost', this.onNetChange);
      monitor.register((error: BusinessError): void => {
        if (error) hilog.warn(DOMAIN, TAG, 'watch network failed: %{public}s', JSON.stringify(error));
      });
      this.monitor = monitor;
      this.monitoring = true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'watch network failed: %{public}s', JSON.stringify(error));
    }
  }

  /** 当前链路判定；`--ps qualityNetwork` 仅用于联调（模拟器没有蜂窝/热点）。 */
  private profile(): NetworkProfile {
    const detected = classifyNetwork(this.readSignals());
    const override = toNetworkClass(AppStorage.get<string>('qualityNetworkOverride') ?? '');
    if (override === 'unknown') return detected;
    const metered: boolean = override === 'cellular' || override === 'hotspot';
    return {
      cls: override, metered: metered, meteredHotspot: detected.meteredHotspot,
      evidence: detected.evidence + ' override=' + override
    };
  }

  private readSignals(): NetworkSignals {
    const signals: NetworkSignals = {
      bearerTypes: [], meteredHotspot: false, systemMetered: false, wifiProbe: false
    };
    try {
      const handle = connection.getDefaultNetSync();
      if (handle && handle.netId !== 0) {
        const caps = connection.getNetCapabilitiesSync(handle);
        signals.bearerTypes = caps.bearerTypes ?? [];
        signals.systemMetered = connection.isDefaultNetMeteredSync() === true;
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'route query failed: %{public}s', JSON.stringify(error));
    }
    if (signals.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) this.readWifi(signals);
    return signals;
  }

  /**
   * 热点判定只问系统：`isMeteredHotspot()` 返回当前 Wi-Fi 是否为计费热点。
   * 会抛错：模拟器/无 STA 能力（801）、权限未授予（201）、Wi-Fi 关闭（2501001）——
   * 读不到就按普通 Wi-Fi 走，绝不用网关网段之类的东西去猜（家用路由器计费标记会误判）。
   */
  private readWifi(signals: NetworkSignals): void {
    try {
      signals.meteredHotspot = wifiManager.isMeteredHotspot() === true;
      signals.wifiProbe = true;
    } catch (_error) {
      signals.meteredHotspot = false;
    }
  }

  /**
   * 把两档偏好和当前链路写进 AppStorage。
   * `defaultVideoQn` 是「当前生效档」，所有取流/预取调用点只认它。
   */
  private publish(reason: string, force: boolean): void {
    const profile = this.profile();
    const effective = profile.metered ? this.cellularQn : this.wifiQn;
    try {
      AppStorage.setOrCreate('videoQnWifi', this.wifiQn);
      AppStorage.setOrCreate('videoQnCellular', this.cellularQn);
      AppStorage.setOrCreate('networkClass', profile.cls);
      AppStorage.setOrCreate('networkMetered', profile.metered);
      AppStorage.setOrCreate('defaultVideoQn', effective);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'publish failed: %{public}s', JSON.stringify(error));
    }
    const route = `${profile.cls}|${profile.metered ? 1 : 0}|${this.wifiQn}|${this.cellularQn}`;
    if (!force && route === this.lastRoute) return;
    this.lastRoute = route;
    hilog.info(DOMAIN, TAG,
      'quality %{public}s: cls=%{public}s metered=%{public}d qn=%{public}d wifi=%{public}d cellular=%{public}d %{public}s',
      reason, profile.cls, profile.metered ? 1 : 0, effective, this.wifiQn, this.cellularQn, profile.evidence);
  }
}
