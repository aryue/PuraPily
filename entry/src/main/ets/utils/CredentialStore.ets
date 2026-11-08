import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

interface LoginCredentials { cookie: string; accessKey: string; }
interface CredentialManifest { version: string; parts: number; }

const ROOT_ALIAS = 'bilibili.login.v1';
const encoder = new util.TextEncoder();
let pending: Promise<void> = Promise.resolve();
let sessionEpoch: number = 0;
let startupRestore: Promise<void> | null = null;

/** Start once before routes load; requests may await it without delaying page rendering. */
export function initializeLoginCredentials(context: common.Context): Promise<void> {
  if (!startupRestore) startupRestore = restoreLoginCredentials(context).catch((error: Error) => {
    startupRestore = null;
    throw error;
  });
  return startupRestore;
}

export function loginCredentialsReady(): Promise<void> | null { return startupRestore; }

export function loginCredentialRevision(): number { return sessionEpoch; }

function aliasQuery(alias: string): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, encoder.encodeInto(alias));
  return query;
}

async function readSecret(alias: string): Promise<Uint8Array | null> {
  const query = aliasQuery(alias);
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  try {
    const result = await asset.query(query);
    return result.length > 0 ? result[0].get(asset.Tag.SECRET) as Uint8Array : null;
  } catch (error) {
    if ((error as BusinessError).code === 24000002) return null;
    throw new Error(`安全凭据暂不可读取 (code=${(error as BusinessError).code})`);
  }
}

async function writeSecret(alias: string, value: Uint8Array): Promise<void> {
  const attributes = aliasQuery(alias);
  attributes.set(asset.Tag.SECRET, value);
  attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
  attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
  // Omit IS_PERSISTENT: its default is false, and setting even false requires a persistent-data permission.
  attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
  await asset.add(attributes);
}

function decode(value: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeWithStream(value);
}

async function manifest(): Promise<CredentialManifest | null> {
  const value = await readSecret(ROOT_ALIAS);
  if (!value) return null;
  const result = JSON.parse(decode(value)) as CredentialManifest;
  if (!result.version || !Number.isInteger(result.parts) || result.parts < 1 || result.parts > 128) {
    throw new Error('安全凭据格式无效');
  }
  return result;
}

async function removeParts(previous: CredentialManifest | null): Promise<void> {
  if (!previous) return;
  for (let i = 0; i < previous.parts; i++) {
    try { await asset.remove(aliasQuery(`${ROOT_ALIAS}.${previous.version}.${i}`)); } catch (_) {}
  }
}

/** Asset secrets are limited to 1024 bytes. Publish a new manifest only after every chunk is stored. */
async function persist(credentials: LoginCredentials): Promise<void> {
  const previous = await manifest();
  const bytes = encoder.encodeInto(JSON.stringify(credentials));
  const next: CredentialManifest = { version: util.generateRandomUUID(true), parts: Math.ceil(bytes.length / 1024) };
  if (next.parts > 128) throw new Error('登录凭据过长');
  try {
    for (let i = 0; i < next.parts; i++) {
      await writeSecret(`${ROOT_ALIAS}.${next.version}.${i}`, bytes.slice(i * 1024, (i + 1) * 1024));
    }
    await writeSecret(ROOT_ALIAS, encoder.encodeInto(JSON.stringify(next)));
  } catch (error) {
    await removeParts(next);
    throw new Error(`安全保存登录信息失败 (code=${(error as BusinessError).code})`);
  }
  await removeParts(previous);
}

async function readCredentials(): Promise<LoginCredentials | null> {
  const current = await manifest();
  if (!current) return null;
  const parts: Uint8Array[] = [];
  let length = 0;
  for (let i = 0; i < current.parts; i++) {
    const part = await readSecret(`${ROOT_ALIAS}.${current.version}.${i}`);
    if (!part) throw new Error('安全凭据不完整');
    parts.push(part);
    length += part.length;
  }
  const merged = new Uint8Array(length);
  let offset = 0;
  parts.forEach(part => { merged.set(part, offset); offset += part.length; });
  const result = JSON.parse(decode(merged)) as LoginCredentials;
  if (typeof result.cookie !== 'string' || typeof result.accessKey !== 'string') throw new Error('安全凭据格式无效');
  return result;
}

async function clearLegacy(pref: preferences.Preferences): Promise<void> {
  await pref.delete('biliCookie');
  await pref.delete('biliAccessKey');
  await pref.flush();
}

function publish(credentials: LoginCredentials): void {
  AppStorage.setOrCreate('biliAccessKey', credentials.accessKey);
  AppStorage.setOrCreate('biliCookie', credentials.cookie);
}

function sessionValue(cookie: string, name: string): string {
  for (const part of cookie.split(';')) {
    const pair = part.trim();
    if (pair.startsWith(`${name}=`)) return pair.substring(name.length + 1);
  }
  return '';
}

/** Recover only the current session's protected token; never restore an old account's Cookie. */
export async function getLoginAccessKey(expectedCookie: string): Promise<string> {
  if (!expectedCookie || expectedCookie !== (AppStorage.get<string>('biliCookie') || '')) return '';
  const liveKey = AppStorage.get<string>('biliAccessKey') || '';
  if (liveKey) {
    AppStorage.setOrCreate('biliClientCredentialState', 'live');
    return liveKey;
  }
  const epoch = sessionEpoch;
  let recovered = '';
  await serialize(async () => {
    if (epoch !== sessionEpoch || expectedCookie !== (AppStorage.get<string>('biliCookie') || '')) return;
    const credentials = await readCredentials();
    const session = sessionValue(expectedCookie, 'SESSDATA');
    AppStorage.setOrCreate('biliClientCredentialState', !credentials ? 'protected-missing' :
      !credentials.accessKey ? 'protected-empty' : !session || sessionValue(credentials.cookie, 'SESSDATA') !== session ?
      'protected-session-mismatch' : 'protected-matched');
    if (!credentials || !session || sessionValue(credentials.cookie, 'SESSDATA') !== session) return;
    if (epoch !== sessionEpoch || expectedCookie !== (AppStorage.get<string>('biliCookie') || '')) return;
    recovered = credentials.accessKey;
    if (recovered) AppStorage.setOrCreate('biliAccessKey', recovered);
  });
  return epoch === sessionEpoch && expectedCookie === (AppStorage.get<string>('biliCookie') || '') ? recovered : '';
}

/** Serialize migration/save/logout so a delayed restore cannot undo logout. */
function serialize(action: () => Promise<void>): Promise<void> {
  const result = pending.then(action);
  pending = result.catch(() => {});
  return result;
}

export function saveLoginCredentials(context: common.Context, cookie: string, accessKey: string,
  requireClientKey: boolean = false, expectedRevision: number = -1): Promise<void> {
  if (expectedRevision >= 0 && expectedRevision !== sessionEpoch) return Promise.reject(new Error('登录操作已取消'));
  if (requireClientKey && !accessKey.trim()) return Promise.reject(new Error('TV 登录响应缺少客户端令牌，请重新获取二维码'));
  const epoch = ++sessionEpoch;
  return serialize(async () => {
    if (epoch !== sessionEpoch) throw new Error('登录操作已取消');
    const pref = await preferences.getPreferences(context, 'my_app_settings');
    // A same-account Web cookie refresh must not discard a previously saved TV token.
    let nextAccessKey = accessKey;
    if (!nextAccessKey) {
      const previous = await readCredentials();
      const mid = sessionValue(cookie, 'DedeUserID');
      if (previous && mid && mid === sessionValue(previous.cookie, 'DedeUserID')) nextAccessKey = previous.accessKey;
    }
    const credentials: LoginCredentials = { cookie, accessKey: nextAccessKey };
    await persist(credentials);
    await clearLegacy(pref);
    await pref.put('loginRevoked', false);
    await pref.put('loginCredentialKind', requireClientKey ? 'tv' : nextAccessKey ? 'client' : 'web');
    await pref.flush();
    if (epoch !== sessionEpoch) throw new Error('登录操作已取消');
    publish(credentials);
    if (requireClientKey && AppStorage.get<string>('biliAccessKey') !== credentials.accessKey) {
      throw new Error('客户端令牌未完成恢复，请重试登录');
    }
  });
}

export function restoreLoginCredentials(context: common.Context): Promise<void> {
  const epoch = sessionEpoch;
  return serialize(async () => {
    if (epoch !== sessionEpoch) return;
    const pref = await preferences.getPreferences(context, 'my_app_settings');
    if (await pref.get('loginRevoked', false) as boolean) {
      await clearLegacy(pref);
      // Retry removal of the old protected credentials if the asset service failed during logout.
      try { await persist({ cookie: '', accessKey: '' }); } catch (_) {}
      publish({ cookie: '', accessKey: '' });
      return;
    }
    let credentials = await readCredentials();
    if (!credentials) {
      const cookie = await pref.get('biliCookie', '') as string;
      const accessKey = await pref.get('biliAccessKey', '') as string;
      // An old logged-out installation may still contain an access_key. Do not resurrect it.
      credentials = { cookie, accessKey: cookie ? accessKey : '' };
      await persist(credentials);
    }
    await clearLegacy(pref);
    if (epoch === sessionEpoch) publish(credentials);
  });
}

export function clearLoginCredentials(context: common.Context): Promise<void> {
  sessionEpoch++;
  // Stop new authenticated requests immediately. The persistent empty session is a logout tombstone.
  publish({ cookie: '', accessKey: '' });
  return serialize(async () => {
    const pref = await preferences.getPreferences(context, 'my_app_settings');
    // This non-secret marker prevents a failed asset write from restoring the previous account.
    await pref.put('loginRevoked', true);
    await pref.flush();
    await clearLegacy(pref);
    await persist({ cookie: '', accessKey: '' });
    publish({ cookie: '', accessKey: '' });
  });
}
