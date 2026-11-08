import { webSocket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { getLiveChatConnection, LiveChatMessage } from '../api/LiveApi';
import { logWarn } from '../utils/Logger';

interface LiveChatAuth {
  uid: number;
  roomid: number;
  protover: number;
  platform: string;
  type: number;
  key: string;
  buvid: string;
}

interface LiveChatCommand {
  cmd?: string;
  code?: number;
  info?: Object[];
}

/** 服务端可能在未压缩协商后仍下发 zlib 包，按包头独立解码。 */
export class LiveChatReceiver {
  private socket: webSocket.WebSocket | null = null;
  private generation: number = 0;
  private timer: number = -1;
  private heartbeat: number = -1;
  private watchdog: number = -1;
  private sequence: number = 0;
  private packetStage: string = 'header';
  private buffer: Uint8Array = new Uint8Array(0);
  private incoming: Promise<void> = Promise.resolve();

  private onMessage: (message: LiveChatMessage) => void;
  private onStatus: (status: string) => void;

  constructor(onMessage: (message: LiveChatMessage) => void, onStatus: (status: string) => void) {
    this.onMessage = onMessage;
    this.onStatus = onStatus;
  }

  stop(): void {
    this.generation++;
    clearTimeout(this.timer);
    clearTimeout(this.watchdog);
    clearInterval(this.heartbeat);
    this.timer = this.heartbeat = this.watchdog = -1;
    const socket = this.socket;
    this.socket = null;
    this.buffer = new Uint8Array(0);
    this.incoming = Promise.resolve();
    if (socket) {
      socket.off('open'); socket.off('message'); socket.off('close'); socket.off('error');
      void socket.close().catch(() => {});
    }
  }

  start(roomId: number): void {
    this.stop();
    if (roomId <= 0) return;
    this.onStatus('正在连接弹幕…');
    void this.connect(roomId, this.generation);
  }

  private retry(roomId: number, generation: number): void {
    if (generation !== this.generation) return;
    this.stop();
    const nextGeneration = this.generation;
    this.onStatus('弹幕连接中断，正在重试…');
    this.timer = setTimeout(() => { void this.connect(roomId, nextGeneration); }, 10000);
  }

  private async connect(roomId: number, generation: number): Promise<void> {
    let stage = 'configuration';
    try {
      const config = await getLiveChatConnection(roomId);
      if (generation !== this.generation) return;
      stage = 'socket';
      const socket = webSocket.createWebSocket();
      this.socket = socket;
      const current = (): boolean => generation === this.generation && this.socket === socket;
      socket.on('open', () => {
        if (!current()) return;
        const cookie = AppStorage.get<string>('biliCookie') || '';
        const uid = Number(/(?:^|;\s*)DedeUserID=(\d+)/.exec(cookie)?.[1] || '0');
        const buvid = /(?:^|;\s*)buvid3=([^;]+)/.exec(cookie)?.[1] || AppStorage.get<string>('biliDeviceId') || '';
        const auth: LiveChatAuth = { uid, roomid: roomId, protover: 1, platform: 'web', type: 2, key: config.token, buvid };
        void socket.send(this.packet(7, JSON.stringify(auth))).catch(() => this.retry(roomId, generation));
      });
      socket.on('message', (_error, value: string | ArrayBuffer) => {
        if (!current()) return;
        if (typeof value !== 'string') {
          this.incoming = this.incoming.then(async () => {
            if (current()) await this.receive(value, roomId, generation);
          }).catch((error: Error) => {
            if (!current()) return;
            logWarn(`[LiveChat] 弹幕包解析失败 stage=${this.packetStage} kind=${error instanceof Error ? error.name : 'unknown'}${error instanceof TypeError ? ':' + error.message : ''}`);
            this.retry(roomId, generation);
          });
        }
      });
      socket.on('close', () => { if (current()) { logWarn('[LiveChat] WebSocket closed'); this.retry(roomId, generation); } });
      socket.on('error', (error) => { if (current()) { logWarn(`[LiveChat] WebSocket error code=${error.code}`); this.retry(roomId, generation); } });
      // 没有鉴权响应也必须结束等待，不能永久显示连接中。
      this.watchdog = setTimeout(() => { logWarn('[LiveChat] 鉴权等待超时'); this.retry(roomId, generation); }, 15000);
      const host = config.host_list[0];
      await socket.connect(`wss://${host.host}:${host.wss_port || 443}/sub`, {
        header: { 'Origin': 'https://live.bilibili.com', 'Referer': `https://live.bilibili.com/${roomId}` }
      });
    } catch (_) {
      if (generation === this.generation) logWarn(`[LiveChat] 连接失败阶段=${stage}`);
      this.retry(roomId, generation);
    }
  }

  private packet(operation: number, text: string = ''): ArrayBuffer {
    const body = text ? util.TextEncoder.create().encodeInto(text) : new Uint8Array(0);
    const output = new ArrayBuffer(16 + body.length);
    const view = new DataView(output);
    view.setUint32(0, output.byteLength);
    view.setUint16(4, 16);
    view.setUint16(6, 1);
    view.setUint32(8, operation);
    view.setUint32(12, 1);
    new Uint8Array(output).set(body, 16);
    return output;
  }

  private async inflate(data: Uint8Array): Promise<ArrayBuffer> {
    this.packetStage += '/uncompress';
    const zip = zlib.createZipSync();
    const output = new ArrayBuffer(1024 * 1024);
    const result = await zip.uncompress(output, data.buffer as ArrayBuffer, data.length);
    if (result.status !== 0 || result.destLen <= 0 || result.destLen > output.byteLength) throw new Error('弹幕解压失败或数据过大');
    return output.slice(0, result.destLen);
  }

  private async receive(data: ArrayBuffer, roomId: number, generation: number): Promise<void> {
    this.packetStage = 'header';
    const combined = new Uint8Array(this.buffer.length + data.byteLength);
    combined.set(this.buffer); combined.set(new Uint8Array(data), this.buffer.length);
    this.buffer = new Uint8Array(0);
    if (combined.length > 1024 * 1024) throw new Error('弹幕数据过大');
    let offset = 0;
    while (combined.length - offset >= 16) {
      const view = new DataView(combined.buffer, offset);
      const length = view.getUint32(0), header = view.getUint16(4), version = view.getUint16(6), operation = view.getUint32(8);
      this.packetStage = `op${operation}/v${version}/len${length}/header${header}`;
      if (length < 16 || header < 16 || header > length || length > 1024 * 1024) throw new Error('弹幕包无效');
      if (combined.length - offset < length) break;
      if (operation === 5 && version === 2) {
        const expanded = await this.inflate(combined.slice(offset + header, offset + length));
        if (generation !== this.generation) return;
        await this.receive(expanded, roomId, generation);
      } else if (operation === 8 || operation === 5) {
        if (version > 1) throw new Error('不支持的弹幕压缩协议');
        this.packetStage += '/decode';
        const text = util.TextDecoder.create('utf-8').decodeToString(combined.slice(offset + header, offset + length));
        this.packetStage += '/json';
        const command = JSON.parse(text) as LiveChatCommand;
        this.packetStage += '/dispatch';
        if (operation === 8) {
          if (command.code !== 0) { logWarn(`[LiveChat] 鉴权返回 code=${command.code}`); throw new Error('弹幕鉴权失败'); }
          clearTimeout(this.watchdog);
          this.onStatus('');
          const beat = (): void => {
            if (generation === this.generation && this.socket) {
              void this.socket.send(this.packet(2)).catch(() => this.retry(roomId, generation));
            }
          };
          beat();
          clearInterval(this.heartbeat);
          this.heartbeat = setInterval(beat, 30000);
        } else if (command.cmd?.split(':')[0] === 'DANMU_MSG' && command.info) {
          this.acceptMessage(command.info, roomId);
        }
      }
      offset += length;
    }
    if (generation === this.generation) this.buffer = combined.slice(offset);
  }

  private acceptMessage(info: Object[], roomId: number): void {
    const text = info[1] as string;
    const user = info[2] as Object[];
    if (typeof text !== 'string' || !text || !Array.isArray(user)) return;
    this.onMessage({ id: `live:${roomId}:${++this.sequence}`, nickname: String(user[1] || '观众'), text,
      timeline: new Date().toISOString(), nameColor: '#8BDCEB' });
  }
}
