import type { PlaybackPlayer } from '../services/PlaybackPlayer';
import { audio } from '@kit.AudioKit';
import { manager, remoteDevice, constant } from '@kit.NearLinkKit';
import { a2dp, connection } from '@kit.ConnectivityKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { logInfo } from './Logger';
import { headphoneIconName } from './HeadphoneIcons';

// Ask only when a selected wireless route needs metadata, at most once per process.
const metadataPermissionsAttempted: Set<string> = new Set<string>();
const DEFAULT_HEADPHONE_ICON: string = 'headphones_fill';
const EARLY_METADATA_RETRY_DELAYS: number[] = [200, 450, 850];
const MAX_BLUETOOTH_METADATA_RETRIES: number = 12;

interface NearLinkHeadphone {
  address: string;
  name: string;
}

function selectedNearLinkName(route: audio.AudioDeviceDescriptor): string {
  const candidates: NearLinkHeadphone[] = [];
  try {
    for (const address of manager.getPairedDevices()) {
      const peer = remoteDevice.createRemoteDevice(address);
      if (peer.getConnectionState() !== constant.ConnectionState.STATE_CONNECTED) continue;
      const category = peer.getDeviceClass() & 0xFF00;
      if (category !== 0x0600 && category !== 0x0800) continue;
      candidates.push({ address: address, name: peer.getDeviceName() });
    }
  } catch (_) { return ''; } // A partial list must never create a false unique candidate.
  if (route.address) {
    const matched = candidates.filter((peer: NearLinkHeadphone) => peer.address.toUpperCase() === route.address.toUpperCase());
    return matched.length === 1 ? matched[0].name : '';
  }
  return candidates.length === 1 ? candidates[0].name : '';
}

/**
 * 蓝牙路由的 name/address 常同时为空（真机实测），耳机名在 dmDeviceInfo 里——
 * 它是运行时字段（SDK typings 无声明）且是纯字符串（仅蓝牙有值，星闪为空串）。
 */
function descriptorBluetoothName(device: audio.AudioDeviceDescriptor): string {
  if (device.name) return device.name;
  try {
    const dm = (device as object as Record<string, Object>)['dmDeviceInfo'];
    if (typeof dm === 'string') return dm;
  } catch (_) {}
  return '';
}

/**
 * 最后一层兜底：播放流式 descriptor 会把蓝牙设备隐藏成 name/address/dmDeviceInfo 全空
 * （真机实测，与 preferred 查询不同，后者 dmDeviceInfo 有名字）。此时若 A2DP 已连接
 * 设备唯一，按它反查名字——与 AudioOutputLab 实验页同源旁证。
 */
function uniqueA2dpPeerName(): string {
  try {
    const connected = a2dp.createA2dpSrcProfile().getConnectedDevices();
    if (connected.length !== 1) return '';
    return connection.getRemoteDeviceName(connected[0]);
  } catch (_) { return ''; }
}

function selectedHeadphone(devices: audio.AudioDeviceDescriptors): audio.AudioDeviceDescriptor | undefined {
  const selected = devices.filter((device: audio.AudioDeviceDescriptor) => isHeadphoneOutput([device]));
  return selected.length === 1 ? selected[0] : undefined;
}

function isBluetoothHeadphone(route: audio.AudioDeviceDescriptor): boolean {
  return route.deviceType === audio.DeviceType.BLUETOOTH_A2DP ||
    route.deviceType === audio.DeviceType.BLUETOOTH_SCO;
}

function headphoneName(route: audio.AudioDeviceDescriptor, preferredName?: () => string): string {
  // NearLink audio descriptors may contain the phone's displayName, not the peer's name.
  if (route.deviceType === audio.DeviceType.NEARLINK) return selectedNearLinkName(route).trim();
  const name = descriptorBluetoothName(route).trim();
  if (name || !isBluetoothHeadphone(route)) return name;
  const preferred = preferredName?.();
  if (preferred) return preferred;
  if (route.address) {
    try { return connection.getRemoteDeviceName(route.address).trim(); } catch (_) { return ''; }
  }
  return uniqueA2dpPeerName().trim();
}

export function outputHeadphoneIcon(devices: audio.AudioDeviceDescriptors): string {
  const route = selectedHeadphone(devices);
  return route ? headphoneIconName(headphoneName(route)) : DEFAULT_HEADPHONE_ICON;
}

function routesConflict(previous: audio.AudioDeviceDescriptor, current: audio.AudioDeviceDescriptor): boolean {
  if (previous.deviceType !== current.deviceType) return true;
  if (previous.address && current.address) return previous.address.toUpperCase() !== current.address.toUpperCase();
  return previous.id > 0 && current.id > 0 && previous.id !== current.id;
}

function sameRoute(previous: audio.AudioDeviceDescriptor, current: audio.AudioDeviceDescriptor): boolean {
  if (routesConflict(previous, current)) return false;
  return (previous.id > 0 && previous.id === current.id) || (!!previous.address && !!current.address);
}

/** Only the selected playback route counts; a connected but unused headset does not. */
export function isHeadphoneOutput(devices: audio.AudioDeviceDescriptors): boolean {
  return devices.some((device: audio.AudioDeviceDescriptor) => {
    const type: audio.DeviceType = device.deviceType;
    return type === audio.DeviceType.WIRED_HEADSET || type === audio.DeviceType.WIRED_HEADPHONES ||
      type === audio.DeviceType.USB_HEADSET || type === audio.DeviceType.BLUETOOTH_A2DP ||
      type === audio.DeviceType.BLUETOOTH_SCO || type === audio.DeviceType.NEARLINK;
  });
}

/** Follow the AVPlayer that actually carries sound, including split DASH audio. */
export class PlaybackAudioOutputMonitor {
  private player: PlaybackPlayer | null = null;
  private listener: ((info: audio.AudioStreamDeviceChangeInfo) => void) | null = null;
  private onChange: (headphones: boolean, icon: string) => void;
  private context: (() => common.UIAbilityContext | undefined) | undefined;
  private devices: audio.AudioDeviceDescriptors = [];
  private iconRoute: audio.AudioDeviceDescriptor | undefined;
  private icon: string = DEFAULT_HEADPHONE_ICON;
  private rendererInfo: audio.AudioRendererInfo | undefined;
  private metadataTimer: number = -1;
  private metadataAttempts: number = 0;
  private generation: number = 0;
  private hasActualRoute: boolean = false;

  constructor(onChange: (headphones: boolean, icon: string) => void,
    context?: () => common.UIAbilityContext | undefined) {
    this.onChange = onChange;
    this.context = context;
  }

  private preferredDevices(): audio.AudioDeviceDescriptors {
    if (!this.rendererInfo) return [];
    try {
      return audio.getAudioManager().getRoutingManager()
        .getPreferredOutputDeviceForRendererInfoSync(this.rendererInfo);
    } catch (_) { return []; }
  }

  private preferredName(route: audio.AudioDeviceDescriptor): string {
    if (!this.hasActualRoute) return '';
    // The preferred descriptor can expose a name hidden by the stream descriptor.
    const preferred = selectedHeadphone(this.preferredDevices());
    return preferred && sameRoute(route, preferred) ? descriptorBluetoothName(preferred).trim() : '';
  }

  private refreshIcon(): void {
    const route = selectedHeadphone(this.devices);
    const nearlink = route?.deviceType === audio.DeviceType.NEARLINK;
    const bluetooth = !!route && isBluetoothHeadphone(route);
    const name = route ? headphoneName(route, () => this.preferredName(route)) : '';
    if (route && name) {
      this.icon = headphoneIconName(name);
      // Keep any identity fields from a richer descriptor when the stream omits them.
      const previous = this.iconRoute;
      this.iconRoute = previous && sameRoute(previous, route) && previous.address && !route.address ? previous : route;
      this.metadataAttempts = 0;
    } else if (!route || (!nearlink && !bluetooth) ||
      (this.metadataAttempts >= EARLY_METADATA_RETRY_DELAYS.length &&
        (!this.iconRoute || !sameRoute(this.iconRoute, route)))) {
      this.clearIcon();
    }
    this.onChange(isHeadphoneOutput(this.devices), this.icon);
    if (nearlink || (bluetooth && !name && this.metadataAttempts < MAX_BLUETOOTH_METADATA_RETRIES)) {
      this.scheduleMetadataPoll(nearlink && !!name);
    } else {
      this.stopMetadataPoll();
    }
    if (nearlink) {
      this.requestMetadata('ohos.permission.ACCESS_NEARLINK');
    } else if (bluetooth && !name) {
      this.requestMetadata('ohos.permission.ACCESS_BLUETOOTH');
    }
  }

  private clearIcon(): void {
    this.icon = DEFAULT_HEADPHONE_ICON;
    this.iconRoute = undefined;
  }

  private async requestMetadata(permission: Permissions): Promise<void> {
    if (!this.context || metadataPermissionsAttempted.has(permission)) return;
    const context = this.context();
    if (!context) return;
    metadataPermissionsAttempted.add(permission);
    const generation = this.generation;
    try {
      await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, [permission]);
      if (this.player && generation === this.generation) this.refreshIcon();
    } catch (_) {}
  }

  private update(devices: audio.AudioDeviceDescriptors, deviceChanged: boolean = false): void {
    const route = selectedHeadphone(devices);
    const previous = selectedHeadphone(this.devices);
    if (!route || (previous && routesConflict(previous, route)) ||
      (this.iconRoute && routesConflict(this.iconRoute, route)) ||
      (deviceChanged && (!this.iconRoute || !sameRoute(this.iconRoute, route)))) {
      this.clearIcon();
      this.stopMetadataPoll();
      this.metadataAttempts = 0;
    }
    this.devices = devices;
    this.refreshIcon();
    logInfo('AudioOutput update devices=', JSON.stringify(devices), '→ icon=', this.icon);
  }

  /** 起播先密集补读三次；蓝牙最多重试 12 次，星闪继续低频刷新。 */
  private scheduleMetadataPoll(slow: boolean): void {
    if (this.metadataTimer >= 0) return;
    const delay = !slow && this.metadataAttempts < EARLY_METADATA_RETRY_DELAYS.length ?
      EARLY_METADATA_RETRY_DELAYS[this.metadataAttempts] : 2500;
    this.metadataTimer = setTimeout(() => {
      this.metadataTimer = -1;
      this.metadataAttempts++;
      this.refreshIcon();
    }, delay);
  }

  private stopMetadataPoll(): void {
    if (this.metadataTimer >= 0) {
      clearTimeout(this.metadataTimer);
      this.metadataTimer = -1;
    }
  }

  bind(player: PlaybackPlayer, fallbackUsage: audio.StreamUsage): void {
    const rendererInfo: audio.AudioRendererInfo = player.audioRendererInfo ?? { usage: fallbackUsage, rendererFlags: 0 };
    if (this.player !== player) {
      this.unbind();
      try {
        audio.getAudioManager().getRoutingManager().declareDeviceTypesCompatibility([audio.DeviceType.NEARLINK]);
      } catch (_) {}
      this.player = player;
      this.rendererInfo = rendererInfo;
      const listener = (info: audio.AudioStreamDeviceChangeInfo): void => {
        if (this.player === player && this.listener === listener) {
          const reason = info.changeReason;
          const deviceChanged = this.hasActualRoute &&
            (reason === audio.AudioStreamDeviceChangeReason.REASON_NEW_DEVICE_AVAILABLE ||
              reason === audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE ||
              reason === audio.AudioStreamDeviceChangeReason.REASON_OVERRODE);
          this.hasActualRoute = true;
          this.update(info.devices, deviceChanged);
        }
      };
      this.listener = listener;
      try { player.on('audioOutputDeviceChangeWithInfo', listener); } catch (_) {}
    } else {
      this.rendererInfo = rendererInfo;
    }
    // Seed before the first AVPlayer event; later binds cannot overwrite its actual route.
    if (this.hasActualRoute) return;
    const devices = this.preferredDevices();
    if (this.player === player && !this.hasActualRoute && devices.length > 0) this.update(devices);
  }

  dispose(): void {
    this.unbind();
    this.clearIcon();
  }

  private unbind(): void {
    const player = this.player;
    const listener = this.listener;
    this.player = null;
    this.listener = null;
    this.generation++;
    this.devices = [];
    this.rendererInfo = undefined;
    this.hasActualRoute = false;
    this.stopMetadataPoll();
    this.metadataAttempts = 0;
    if (player && listener) {
      try { player.off('audioOutputDeviceChangeWithInfo', listener); } catch (_) {}
    }
  }
}
