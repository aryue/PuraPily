import type { PlaybackPlayer } from '../services/PlaybackPlayer';
import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';
import { manager, remoteDevice, constant } from '@kit.NearLinkKit';
import { connection } from '@kit.ConnectivityKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { headphoneIconName } from './HeadphoneIcons';

// Ask only when a selected wireless route needs metadata, at most once per process.
const metadataPermissionsAttempted: Set<string> = new Set<string>();

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

export function outputHeadphoneIcon(devices: audio.AudioDeviceDescriptors): string {
  const selected = devices.filter((device: audio.AudioDeviceDescriptor) => isHeadphoneOutput([device]));
  if (selected.length !== 1) return 'headphones_fill';
  const route = selected[0];
  // NearLink audio descriptors may contain the phone's displayName, not the peer's name.
  if (route.deviceType === audio.DeviceType.NEARLINK) return headphoneIconName(selectedNearLinkName(route));
  let name = route.name || '';
  if (!name && route.address && (route.deviceType === audio.DeviceType.BLUETOOTH_A2DP ||
    route.deviceType === audio.DeviceType.BLUETOOTH_SCO)) {
    try { name = connection.getRemoteDeviceName(route.address); } catch (_) {}
  }
  return headphoneIconName(name);
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
  private metadataTimer: number = -1;
  private generation: number = 0;
  private hasActualRoute: boolean = false;

  constructor(onChange: (headphones: boolean, icon: string) => void,
    context?: () => common.UIAbilityContext | undefined) {
    this.onChange = onChange;
    this.context = context;
  }

  private publish(): void {
    this.onChange(isHeadphoneOutput(this.devices), outputHeadphoneIcon(this.devices));
  }

  private async requestMetadata(permission: Permissions): Promise<void> {
    if (!this.context || metadataPermissionsAttempted.has(permission)) return;
    const context = this.context();
    if (!context) return;
    metadataPermissionsAttempted.add(permission);
    const generation = this.generation;
    try {
      await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, [permission]);
      if (this.player && generation === this.generation) this.publish();
    } catch (_) {}
  }

  private update(devices: audio.AudioDeviceDescriptors): void {
    this.devices = devices;
    this.publish();
    const nearlink = devices.some((device: audio.AudioDeviceDescriptor) => device.deviceType === audio.DeviceType.NEARLINK);
    if (nearlink) {
      this.requestMetadata('ohos.permission.ACCESS_NEARLINK');
      if (this.metadataTimer < 0) this.metadataTimer = setInterval(() => { this.publish(); }, 2500);
    } else {
      if (this.metadataTimer >= 0) clearInterval(this.metadataTimer);
      this.metadataTimer = -1;
      if (devices.some((device: audio.AudioDeviceDescriptor) => !device.name &&
        (device.deviceType === audio.DeviceType.BLUETOOTH_A2DP || device.deviceType === audio.DeviceType.BLUETOOTH_SCO))) {
        this.requestMetadata('ohos.permission.ACCESS_BLUETOOTH');
      }
    }
  }

  bind(player: PlaybackPlayer, fallbackUsage: audio.StreamUsage): void {
    if (this.player !== player) {
      this.dispose();
      try {
        audio.getAudioManager().getRoutingManager().declareDeviceTypesCompatibility([audio.DeviceType.NEARLINK]);
      } catch (_) {}
      this.player = player;
      const listener = (info: audio.AudioStreamDeviceChangeInfo): void => {
        if (this.player === player && this.listener === listener) {
          this.hasActualRoute = true;
          this.update(info.devices);
        }
      };
      this.listener = listener;
      try { player.on('audioOutputDeviceChangeWithInfo', listener); } catch (_) {}
    }
    // Seed before the first AVPlayer event; later binds cannot overwrite its actual route.
    if (this.hasActualRoute) return;
    try {
      const rendererInfo: audio.AudioRendererInfo = player.audioRendererInfo ?? { usage: fallbackUsage, rendererFlags: 0 };
      const devices: audio.AudioDeviceDescriptors = audio.getAudioManager().getRoutingManager()
        .getPreferredOutputDeviceForRendererInfoSync(rendererInfo);
      if (this.player === player && !this.hasActualRoute) this.update(devices);
    } catch (_) {}
  }

  dispose(): void {
    const player = this.player;
    const listener = this.listener;
    this.player = null;
    this.listener = null;
    this.generation++;
    this.devices = [];
    this.hasActualRoute = false;
    if (this.metadataTimer >= 0) clearInterval(this.metadataTimer);
    this.metadataTimer = -1;
    if (player && listener) {
      try { player.off('audioOutputDeviceChangeWithInfo', listener); } catch (_) {}
    }
  }
}
