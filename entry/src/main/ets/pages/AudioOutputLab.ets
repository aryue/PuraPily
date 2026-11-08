import { audio } from '@kit.AudioKit';
import { manager, remoteDevice, constant } from '@kit.NearLinkKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LengthMetrics } from '@kit.ArkUI';
import { HeaderBackButton } from '../components/HeaderBackButton';
import { PageHeader } from '../components/PageHeader';
import { PageSurface } from '../components/PageSurface';
import { PageWallpaper } from '../components/PageWallpaper';
import { pageBackgroundColor } from '../utils/SurfaceColors';

interface NearLinkLabDevice {
  address: string;
  name: string;
  deviceClass: number;
  connectionState: number;
  details: string;
}

interface NearLinkLabSnapshot {
  devices: NearLinkLabDevice[];
  complete: boolean;
  text: string;
}

// Keep result text in observable component properties. Passing plain strings through
// a @Builder into PageSurface's retained content closure freezes its first values.
@Component
struct AudioOutputLabSection {
  @Prop title: string = '';
  @Prop value: string = '';
  @StorageProp('isDarkMode') dark: boolean = false;

  build() {
    PageSurface() {
      Column({ space: 10 }) {
        Text(this.title).fontSize(16).fontWeight(FontWeight.Medium).width('100%')
          .fontColor(this.dark ? '#FFFFFF' : '#17181A')
        Text(this.value).fontSize(12).fontFamily('monospace').width('100%').copyOption(CopyOptions.LocalDevice)
          .fontColor(this.dark ? '#D1D5DC' : '#454B53')
      }.width('100%').padding(16)
    }
  }
}

@Entry
@Component
struct AudioOutputLab {
  @StorageProp('isDarkMode') dark: boolean = false;
  @StorageProp('statusBarHeight') safeTop: number = 0;
  @StorageProp('navIndicatorHeight') safeBottom: number = 0;
  @StorageProp('pageWallpaperEnabled') wallpaper: boolean = false;
  @State private preferred: string = '读取中…';
  @State private streams: string = '读取中…';
  @State private available: string = '读取中…';
  @State private baseline: string = '读取中…';
  @State private compatibility: string = '尚未声明';
  @State private permission: string = '未申请蓝牙权限；名称、地址可能为空或被隐藏';
  @State private updated: string = '';
  @State private nearLinkDevices: string = '请点击“授权读取星闪信息”';
  @State private nearLinkPermission: string = '星闪信息需要 ACCESS_NEARLINK 权限，与蓝牙权限独立';
  @State private matching: string = '等待对照';
  private timer: number = -1;
  private active: boolean = false;
  private busy: boolean = false;
  private generation: number = 0;

  private readNearLink(): NearLinkLabSnapshot {
    const devices: NearLinkLabDevice[] = [];
    let complete: boolean = true;
    try {
      const addresses = manager.getPairedDevices();
      for (const address of addresses) {
        let name: string = '';
        let deviceClass: number = -1;
        let connectionState: number = -1;
        const lines: string[] = [`address=${address}`];
        try {
          const device = remoteDevice.createRemoteDevice(address);
          try { name = device.getDeviceName(); lines.push(`name=${JSON.stringify(name)}`); }
          catch (error) { complete = false; lines.push(`name: ${this.errorText(error as BusinessError)}`); }
          try {
            deviceClass = device.getDeviceClass();
            lines.push(`class=${deviceClass} (0x${deviceClass.toString(16)}) ${constant.DeviceClass[deviceClass] ?? ''}`);
          } catch (error) { complete = false; lines.push(`class: ${this.errorText(error as BusinessError)}`); }
          try {
            connectionState = device.getConnectionState();
            lines.push(`connection=${connectionState} ${constant.ConnectionState[connectionState] ?? ''}`);
          } catch (error) { complete = false; lines.push(`connection: ${this.errorText(error as BusinessError)}`); }
          try { lines.push(`ACB=${device.getAcbState()}（逻辑链路状态，不代表正在播放）`); }
          catch (error) { lines.push(`ACB: ${this.errorText(error as BusinessError)}`); }
          try { lines.push(`deviceInformation=${JSON.stringify(device.getDeviceInformation(), null, 2)}`); }
          catch (error) { lines.push(`deviceInformation: ${this.errorText(error as BusinessError)}`); }
        } catch (error) { complete = false; lines.push(this.errorText(error as BusinessError)); }
        devices.push({ address: address, name: name, deviceClass: deviceClass,
          connectionState: connectionState, details: lines.join('\n') });
      }
      return { devices: devices, complete: complete,
        text: devices.length === 0 ? '已配对设备列表为空' : devices.map((device: NearLinkLabDevice) => device.details).join('\n\n') };
    } catch (error) {
      return { devices: devices, complete: false, text: this.errorText(error as BusinessError) };
    }
  }

  private matchNearLink(outputs: audio.AudioDeviceDescriptors, snapshot: NearLinkLabSnapshot): string {
    const routes = outputs.filter((device: audio.AudioDeviceDescriptor) => device.deviceType === audio.DeviceType.NEARLINK);
    if (routes.length === 0) return '此来源未返回 NEARLINK 输出，不推测星闪设备。';
    const candidates = snapshot.devices.filter((device: NearLinkLabDevice) =>
      device.connectionState === constant.ConnectionState.STATE_CONNECTED &&
      ((device.deviceClass & 0xFF00) === 0x0600 || (device.deviceClass & 0xFF00) === 0x0800));
    if (!snapshot.complete) return '星闪设备信息读取不完整，暂不推测匹配；请检查授权或字段错误。';
    return routes.map((route: audio.AudioDeviceDescriptor): string => {
      const sameAddress = candidates.filter((device: NearLinkLabDevice) =>
        route.address.length > 0 && device.address.toUpperCase() === route.address.toUpperCase());
      if (sameAddress.length === 1) return `音频 id=${route.id}：地址一致 → ${sameAddress[0].name || '未返回名称'}\n` +
        '两侧地址一致；仍需对照真实输出切换验证。';
      if (route.address.length > 0) return `音频 id=${route.id}：未找到唯一地址一致的已连接音频设备，不推测。`;
      if (candidates.length === 1) return `音频 id=${route.id}：推测匹配 → ${candidates[0].name || '未返回名称'}\n` +
        `候选地址=${candidates[0].address}\n依据：NEARLINK 输出 + 唯一已连接音频类设备；音频地址为空，未经精确对应。`;
      return `音频 id=${route.id}：未确定，已连接音频候选 ${candidates.length} 个。\n` +
        candidates.map((device: NearLinkLabDevice) => `${device.name || '未返回名称'} · ${device.address}`).join('\n');
    }).join('\n\n');
  }

  private errorText(error: BusinessError): string {
    return `错误 ${error.code ?? '未知'}：${error.message ?? String(error)}`;
  }

  private deviceText(devices: audio.AudioDeviceDescriptors): string {
    if (devices.length === 0) return '[]（接口未返回设备）';
    return devices.map((device: audio.AudioDeviceDescriptor, index: number): string => {
      const label: string = device.deviceType === audio.DeviceType.NEARLINK ? 'NEARLINK（星闪）' :
        `${audio.DeviceType[device.deviceType] ?? '未知类型'}`;
      return `设备 ${index + 1} · ${label} (${device.deviceType})\n${JSON.stringify(device, null, 2)}\n` +
        `字段核对：name=${JSON.stringify(device.name) ?? 'undefined'}; ` +
        `displayName=${JSON.stringify(device.displayName) ?? 'undefined'}; ` +
        `model=${JSON.stringify(device.model) ?? 'undefined'}; ` +
        `address=${JSON.stringify(device.address) ?? 'undefined'}`;
    }).join('\n\n');
  }

  private readPreferred(): string {
    try {
      return this.deviceText(audio.getAudioManager().getRoutingManager()
        .getPreferredOutputDeviceForRendererInfoSync({ usage: audio.StreamUsage.STREAM_USAGE_MOVIE, rendererFlags: 0 }));
    } catch (error) { return this.errorText(error as BusinessError); }
  }

  onPageShow(): void {
    this.active = true;
    this.baseline = this.readPreferred();
    try {
      audio.getAudioManager().getRoutingManager().declareDeviceTypesCompatibility([audio.DeviceType.NEARLINK]);
      this.compatibility = '已声明 NEARLINK (31)；本进程后续音频查询可返回星闪原始类型';
    } catch (error) { this.compatibility = this.errorText(error as BusinessError); }
    this.refresh();
    if (this.timer < 0) this.timer = setInterval(() => { this.refresh(); }, 1500);
  }

  onPageHide(): void { this.stop(); }
  aboutToDisappear(): void { this.stop(); }

  private stop(): void {
    this.active = false;
    this.generation++;
    if (this.timer >= 0) clearInterval(this.timer);
    this.timer = -1;
  }

  private async refresh(): Promise<void> {
    if (this.busy || !this.active) return;
    this.busy = true;
    const generation = this.generation;
    try {
      const snapshot = this.readNearLink();
      this.nearLinkDevices = snapshot.text;
      const comparisons: string[] = [];
      try {
        const preferred = audio.getAudioManager().getRoutingManager()
          .getPreferredOutputDeviceForRendererInfoSync({ usage: audio.StreamUsage.STREAM_USAGE_MOVIE, rendererFlags: 0 });
        this.preferred = this.deviceText(preferred);
        comparisons.push(`媒体首选路由（不是实际播放证明）\n${this.matchNearLink(preferred, snapshot)}`);
      } catch (error) {
        this.preferred = this.errorText(error as BusinessError);
        comparisons.push(`媒体首选路由读取失败：${this.preferred}`);
      }
      this.matching = comparisons.join('\n\n');
      try {
        this.available = this.deviceText(audio.getAudioManager().getRoutingManager()
          .getDevicesSync(audio.DeviceFlag.OUTPUT_DEVICES_FLAG));
      } catch (error) { this.available = this.errorText(error as BusinessError); }
      try {
        const infos = await audio.getAudioManager().getStreamManager().getCurrentAudioRendererInfoArray();
        if (!this.active || generation !== this.generation) return;
        this.streams = infos.length === 0 ? '[]（当前没有可见播放流，不能据此确认正在使用的设备）' :
          infos.map((info: audio.AudioRendererChangeInfo): string =>
            `streamId=${info.streamId}\nrendererInfo=${JSON.stringify(info.rendererInfo)}\n` +
            this.deviceText(info.deviceDescriptors)).join('\n\n');
        if (infos.length === 0) comparisons.push('没有可见播放流，无法核对实际播放输出。');
        for (const info of infos) {
          comparisons.push(`播放流 ${info.streamId}（归属、播放状态未确认）\n${this.matchNearLink(info.deviceDescriptors, snapshot)}`);
        }
        this.matching = comparisons.join('\n\n');
      } catch (error) {
        if (this.active && generation === this.generation) this.streams = this.errorText(error as BusinessError);
      }
      if (this.active && generation === this.generation) this.updated = new Date().toLocaleTimeString();
    } finally { this.busy = false; }
  }

  private async requestNearLinkPermission(): Promise<void> {
    try {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        this.getUIContext().getHostContext() as common.UIAbilityContext, ['ohos.permission.ACCESS_NEARLINK']);
      if (!this.active) return;
      this.nearLinkPermission = `ACCESS_NEARLINK 授权结果：${JSON.stringify(result.authResults)}（0 为允许）`;
      this.refresh();
    } catch (error) {
      if (this.active) this.nearLinkPermission = this.errorText(error as BusinessError);
    }
  }

  private async requestPermission(): Promise<void> {
    try {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        this.getUIContext().getHostContext() as common.UIAbilityContext, ['ohos.permission.ACCESS_BLUETOOTH']);
      if (!this.active) return;
      this.permission = `ACCESS_BLUETOOTH 授权结果：${JSON.stringify(result.authResults)}（0 为允许）`;
      this.refresh();
    } catch (error) {
      if (this.active) this.permission = this.errorText(error as BusinessError);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      PageWallpaper()
      Scroll() {
        Column({ space: 12 }) {
          Text('每 1.5 秒自动读取，也可手动刷新。连接／断开耳机或切换音频输出后对照下方数值。长按数值可复制。')
            .fontSize(14).fontColor(this.dark ? '#D1D5DC' : '#454B53').width('100%')
          Text('首选路由与可用设备不等于正在播放的输出。播放流可能包含系统内部流，不能全部视为本应用；没有播放流时仅展示查询结果。此页不改变音量、不扫描或切换设备。')
            .fontSize(12).fontColor('#8E8E93').width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(8) } }) {
            Button('立即刷新').onClick(() => { this.refresh(); })
            Button('授权读取蓝牙信息').onClick(() => { this.requestPermission(); })
            Button('授权读取星闪信息').onClick(() => { this.requestNearLinkPermission(); })
          }.width('100%')
          Text(`上次读取：${this.updated || '等待中'}\n${this.permission}`).fontSize(12).fontColor('#8E8E93').width('100%')
          Text(this.nearLinkPermission).fontSize(12).fontColor('#8E8E93').width('100%')
          AudioOutputLabSection({ title: '路由与星闪设备对照 · 实验推测', value: this.matching })
          AudioOutputLabSection({ title: '星闪已配对设备 · 名称／类别／连接／型号', value: this.nearLinkDevices })
          AudioOutputLabSection({ title: '星闪类型声明', value: this.compatibility })
          AudioOutputLabSection({ title: '媒体首选输出 · MOVIE', value: this.preferred })
          AudioOutputLabSection({ title: '播放流及其实际输出设备', value: this.streams })
          AudioOutputLabSection({ title: '可用输出设备 · 连接不代表正在使用', value: this.available })
          AudioOutputLabSection({ title: '本次进入时 · 声明前的媒体首选输出', value: this.baseline })
          Text('本页完整显示接口返回字段，不上传或写入诊断日志。分享数值前可自行遮去设备地址。再次进入时，本进程可能已声明过星闪类型。')
            .fontSize(12).fontColor('#8E8E93').width('100%')
        }.width('100%').constraintSize({ maxWidth: 760 })
          .padding({ top: this.safeTop + 88, bottom: this.safeBottom + 24, left: 16, right: 16 })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Auto)
      PageHeader({ withTabs: false }) {
        Row({ space: 16 }) {
          HeaderBackButton({ onBack: () => { this.getUIContext().getRouter().back(); } })
          Text('音频输出测试').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.dark ? '#FFFFFF' : '#000000')
        }.width('100%').padding({ top: this.safeTop + 16, bottom: 16, left: 16, right: 16 })
      }
    }.width('100%').height('100%')
      .backgroundColor(this.wallpaper ? Color.Transparent : pageBackgroundColor(this.dark))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
