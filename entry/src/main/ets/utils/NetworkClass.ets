/**
 * 网络口径分类（纯计算，不碰系统 API，便于单测）。
 *
 * 画质偏好分「Wi-Fi」与「移动网络」两档，判定依据不是网卡类型而是**这条链路是否按流量计费**：
 * 手机热点走 Wi-Fi 承载，流量却记在别人的蜂窝套餐上，必须按移动网络档取流。
 *
 * 热点只认 `wifiManager.isMeteredHotspot()`（系统自己判定的计费热点）。曾经用过的
 * `WifiLinkedInfo.isRestricted`、`isDefaultNetMeteredSync()`、热点网关网段都撤了：
 * 家里路由器开了「按流量计费」这种标记时前两者会返回 true，把正常 Wi-Fi 误降一档；
 * 网关网段则是纯猜。误判的代价比漏判大，所以只留系统结论。
 *
 * 平台探测在 services/QualityPreferenceService.readSignals()，那里只负责填 NetworkSignals；
 * 判定规则全部集中在本文件，改动规则时同步 scripts/test-quality-network-split.cjs。
 */

export type NetworkClass = 'wifi' | 'hotspot' | 'cellular' | 'ethernet' | 'none' | 'unknown';

/** 与 connection.NetBearType 的取值一致；本文件不引平台库，故自带一份。 */
const BEARER_CELLULAR: number = 0;
const BEARER_WIFI: number = 1;
const BEARER_ETHERNET: number = 3;

/** 平台原始信号：由 QualityPreferenceService 采集，任一字段读取失败时保持默认值。 */
export interface NetworkSignals {
  /** connection.getNetCapabilitiesSync().bearerTypes。 */
  bearerTypes: number[];
  /** wifiManager.isMeteredHotspot()：系统认定当前 Wi-Fi 是计费热点——热点的唯一依据。 */
  meteredHotspot: boolean;
  /**
   * connection.isDefaultNetMeteredSync()：系统把当前链路标为按流量计费。
   * 只作为**认不出的承载类型**的兜底（VPN 等），不参与 Wi-Fi 判定：
   * 家用路由器被标成计费网络时它也是 true，跟着走会把正常 Wi-Fi 降档。
   */
  systemMetered: boolean;
  /** isMeteredHotspot() 是否真的问到了（模拟器、无 STA 能力、权限被拒时为 false）。 */
  wifiProbe: boolean;
}

export interface NetworkProfile {
  cls: NetworkClass;
  /** true = 按移动网络计费，画质走「移动网络」档。 */
  metered: boolean;
  meteredHotspot: boolean;
  /** 证据串：写日志用。 */
  evidence: string;
}

export function classifyNetwork(signals: NetworkSignals): NetworkProfile {
  const wifi = signals.bearerTypes.includes(BEARER_WIFI);
  const cellular = signals.bearerTypes.includes(BEARER_CELLULAR);
  const ethernet = signals.bearerTypes.includes(BEARER_ETHERNET);
  // 以太网和 Wi-Fi 同时存在时按有线算：热点判定只对纯 Wi-Fi 链路生效。
  const hotspot = wifi && !ethernet && signals.meteredHotspot;

  let cls: NetworkClass = 'unknown';
  let metered = signals.systemMetered;
  if (signals.bearerTypes.length === 0) {
    cls = 'none';
    // 拿不到链路信息时按计费处理：宁可画质低一点，也不要在后台偷偷跑流量。
    metered = true;
  } else if (cellular) {
    cls = 'cellular';
    metered = true;
  } else if (ethernet) {
    cls = 'ethernet';
    // 有线一律视为不计费：桌面/电视场景按 Wi-Fi 档走。
    metered = false;
  } else if (wifi) {
    cls = hotspot ? 'hotspot' : 'wifi';
    metered = hotspot;
  }

  const evidence = `bearers=${JSON.stringify(signals.bearerTypes)} meteredHotspot=${signals.meteredHotspot ? 1 : 0}` +
    ` probe=${signals.wifiProbe ? 1 : 0} systemMetered=${signals.systemMetered ? 1 : 0}`;
  return { cls: cls, metered: metered, meteredHotspot: signals.meteredHotspot, evidence: evidence };
}

export function networkClassLabel(cls: string): string {
  if (cls === 'wifi') return 'Wi-Fi';
  if (cls === 'hotspot') return '移动热点';
  if (cls === 'cellular') return '移动网络';
  if (cls === 'ethernet') return '以太网';
  if (cls === 'none') return '无网络';
  return '未知网络';
}

/** 字符串 → 类别（联调参数、AppStorage 里的值都要过一遍，非法值按 unknown）。 */
export function toNetworkClass(value: string): NetworkClass {
  if (value === 'wifi') return 'wifi';
  if (value === 'hotspot') return 'hotspot';
  if (value === 'cellular') return 'cellular';
  if (value === 'ethernet') return 'ethernet';
  if (value === 'none') return 'none';
  return 'unknown';
}
