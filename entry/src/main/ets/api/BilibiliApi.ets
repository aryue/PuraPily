// 部分实现基于 yunshang-bili (https://github.com/chunwcc/yunshang-bili) 修改
// Copyright (c) 2026 chunwcc
// SPDX-License-Identifier: MIT

import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlaybackStartup, PlaybackSpan } from '../utils/PlaybackStartup';
import { selectDashVideo } from '../utils/DashQuality';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { logInfo, logWarn, logError, errMsg } from '../utils/Logger';
import { RecommendItem } from '../model/RecommendItem';
import { firstPreferredResults } from '../utils/PlaybackRequests';
import { PlaybackDeadline } from '../utils/PlaybackDeadline';
import { preferSameQualityMerged } from '../utils/MergedPlaybackPolicy';
import { isLoginRedirectUrl, resolveLoginRedirect } from '../utils/LoginUrlPolicy';
import { AppSign, BiliRequest, WbiSign } from '../utils/SignUtils';
import { PlaybackProgress } from '../utils/PlaybackProgress';
import { extractCsrfFromCookie } from './FeedbackService';
import { getLoginAccessKey, loginCredentialsReady } from '../utils/CredentialStore';
import { mergeLoginCookies, hasLoginSession, loginCookiesFromUrl, classifyLoginVerification,
  LoginVerificationState, loginCookiesFromResponse, loginHeaderValues } from '../utils/LoginCookie';
import { PlaybackWarmPlayer } from '../services/PlaybackWarmPlayer';
import { IjkPrewarm } from '../services/IjkPrewarm';

// ============================================
// 限流缓解：全局请求间隔控制 + 参数轮换
// ============================================

/** 上次 API 请求的时间戳 */
let lastApiRequestTime = 0;

/** 请求间最小间隔（毫秒），加大间隔 + 随机抖动可显著减少限流 */
const MIN_REQUEST_INTERVAL_MS = 1500;

/** 抖动比例（±30%），避免固定间隔被识别 */
const JITTER_RATIO = 0.3;

/** 限流冷却时间戳：被 412 后在此时间前禁止任何请求 */
let rateLimitCooldownUntil = 0;

/** 限流冷却时长（毫秒） */
const RATE_LIMIT_COOLDOWN_MS = 60000;

/** 检查是否处于限流冷却期，是则返回剩余等待毫秒数，否则返回 0 */
function getRateLimitCooldown(): number {
  const remaining = rateLimitCooldownUntil - Date.now();
  return remaining > 0 ? remaining : 0;
}

/** 触发限流冷却 */
function triggerRateLimitCooldown(): void {
  rateLimitCooldownUntil = Date.now() + RATE_LIMIT_COOLDOWN_MS;
  logWarn(`[RateLimit] 触发限流冷却 ${RATE_LIMIT_COOLDOWN_MS / 1000}s`);
}

/**
 * 通用请求节流：最小间隔 3s + 随机抖动
 * 适用于推荐、搜索等非评论类 API
 */
async function throttleRequest(): Promise<void> {
  await doThrottle(MIN_REQUEST_INTERVAL_MS, 'general');
}

/** 评论类 API 上次请求时间戳（独立节流，间隔更短） */
let lastCommentRequestTime = 0;

/** 回复类 API 上次请求时间戳（独立节流，间隔更宽松，防止楼中楼扫荡触发限流） */
let lastReplyRequestTime = 0;

/**
 * 动态类 API 上次请求时间戳（独立节流）
 * ⚠️ 动态页「点左侧 UP 栏选人 / 切分类」是**用户手动触发**的操作，实测用全局 1.5s 桶时
 *    连点两个 UP 会变成"第二个要等 1.6~1.8s"（请求间隔实测 1610ms / 1794ms）——
 *    用户感知就是"点了半天才加载"。这里单独给一个更短的间隔，与首页/评论等其它请求互不排队。
 */
let lastDynamicRequestTime = 0;

/** 动态类请求最小间隔（毫秒）：600ms + 抖动 */
const MIN_DYNAMIC_INTERVAL_MS = 600;

/** 动态类请求节流：用户手动触发，间隔可以比通用桶短得多 */
async function dynamicThrottleRequest(): Promise<void> {
  await doThrottle(MIN_DYNAMIC_INTERVAL_MS, 'dynamic');
}

/**
 * 评论类请求节流：最小间隔 800ms + 随机抖动
 * 评论 API 单独用更短间隔，解决评论区加载卡顿问题
 */
async function commentThrottleRequest(): Promise<void> {
  await doThrottle(800, 'comment');
}

/** Dynamic detail must not sit in the shared minute-long cooldown queue. */
async function tryDynamicCommentThrottle(): Promise<boolean> {
  if (getRateLimitCooldown() > 0) return false;
  const now = Date.now();
  const delay = Math.max(0, lastCommentRequestTime + 800 - now);
  lastCommentRequestTime = now + delay;
  if (delay > 0) await new Promise<void>((resolve: Function) => setTimeout(resolve, delay));
  return getRateLimitCooldown() === 0;
}

/**
 * 回复类请求节流：最小间隔 1200ms + 随机抖动
 * 回复 API 用更宽松间隔，防止展开楼中楼时连续请求触发限流
 */
async function replyThrottleRequest(): Promise<void> {
  await doThrottle(1200, 'reply');
}

/**
 * 通用节流逻辑
 * @param minInterval 最小请求间隔（毫秒）
 * @param label 日志标签
 */
async function doThrottle(minInterval: number, label: string): Promise<void> {
  // 先检查限流冷却（全局共享）
  const cooldownRemaining = getRateLimitCooldown();
  if (cooldownRemaining > 0) {
    logWarn(`[throttle/${label}] 限流冷却中，等待 ${cooldownRemaining}ms`);
    await new Promise<void>((resolve: Function) => setTimeout(resolve, cooldownRemaining));
    rateLimitCooldownUntil = 0; // 冷却结束
  }
  
  // 根据 label 选择独立的时间戳
  let lastTime: number;
  let setLastTime: (t: number) => void;
  if (label === 'comment') {
    lastTime = lastCommentRequestTime;
    setLastTime = (t: number) => { lastCommentRequestTime = t; };
  } else if (label === 'reply') {
    lastTime = lastReplyRequestTime;
    setLastTime = (t: number) => { lastReplyRequestTime = t; };
  } else if (label === 'dynamic') {
    lastTime = lastDynamicRequestTime;
    setLastTime = (t: number) => { lastDynamicRequestTime = t; };
  } else {
    lastTime = lastApiRequestTime;
    setLastTime = (t: number) => { lastApiRequestTime = t; };
  }
  
  const now = Date.now();
  const elapsed = now - lastTime;
  const jitter = Math.floor(minInterval * JITTER_RATIO * (Math.random() * 2 - 1));
  const effectiveInterval = minInterval + jitter;
  if (elapsed < effectiveInterval) {
    const waitMs = effectiveInterval - elapsed;
    await new Promise<void>((resolve: Function) => setTimeout(resolve, waitMs));
  }
  setLastTime(Date.now());
}

/** 轮换的 User-Agent 列表（Android + iOS 混合） */
const UA_LIST: string[] = [
  'Mozilla/5.0 (Linux; Android 10; ONEPLUS A6000) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36 BiliApp/6740300',
  'Mozilla/5.0 (Linux; Android 11; SM-G998B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Mobile Safari/537.36 BiliApp/6750400',
  'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Mobile Safari/537.36 BiliApp/6760500',
  'Mozilla/5.0 (Linux; Android 13; Xiaomi13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36 BiliApp/6770600',
  'Mozilla/5.0 (Linux; Android 14; Find X7 Ultra) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 BiliApp/6780700',
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 BiliApp/6790800',
  'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1 BiliApp/6730200',
  'Mozilla/5.0 (Linux; Android 14; Redmi K70 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36 BiliApp/6800900',
];

/** 轮换的 x-bili-aurora 列表 */
const AURORA_LIST: string[] = [
  '8d3d9e0c2f1b4a5c6d7e8f9a0b1c2d3e',
  '1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d',
  'e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2',
  'b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7',
  'c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4',
];

/** 轮换的 x-bili-aurora-zone 列表 */
const ZONE_LIST: string[] = ['sh001', 'sh002', 'sz001', 'bj001', 'gz001'];

/** 轮换的 Referer 列表 */
const REFERER_LIST: string[] = [
  'https://www.bilibili.com/',
  'https://www.bilibili.com/video/',
  'https://m.bilibili.com/',
  'https://m.bilibili.com/video/',
  'https://www.bilibili.com/index/',
];

/** 轮换的 Accept-Language 列表 */
const LANG_LIST: string[] = [
  'zh-CN,zh;q=0.9',
  'zh-CN,zh;q=0.9,en;q=0.8',
  'zh-CN,zh;q=0.9,en-US;q=0.8',
  'zh-CN,zh;q=0.8,en;q=0.6',
  'zh-CN,zh;q=0.9,en;q=0.5',
];

/** 获取随机请求头参数 */
function getRotatedHeaders(): Record<string, Object> {
  const idx = Math.floor(Math.random() * UA_LIST.length);
  return {
    'User-Agent': UA_LIST[idx % UA_LIST.length],
    'Referer': REFERER_LIST[idx % REFERER_LIST.length],
    'Origin': 'https://www.bilibili.com',
    'Cookie': getCookieHeader(),
    'x-bili-aurora': AURORA_LIST[idx % AURORA_LIST.length],
    'x-bili-aurora-zone': ZONE_LIST[idx % ZONE_LIST.length],
    'Accept-Language': LANG_LIST[Math.floor(Math.random() * LANG_LIST.length)],
    'Accept-Encoding': 'gzip, deflate, br',
  };
}


interface ApiResponse<T> {
  code: number;
  message?: string;
  data?: T;
}

interface VideoListResponse {
  list?: Array<Record<string, Object>>;
  item?: Array<Record<string, Object>>;
}

interface DurlItem {
  url: string;
}

export interface DashVideoItem {
  id: number;
  baseUrl: string;
  codecid: number; // 编码：7=AVC(H.264), 12=HEVC(H.265), 13=AV1
  // ⭐ DASH 转播站需要完整元数据（MPD 生成与探测依赖）
  backupUrl?: string[];
  bandwidth?: number;
  width?: number;
  height?: number;
  frameRate?: string;
  sar?: string;
  startWithSap?: number;
  contentLength?: number;
  base_url?: string;
  backup_url?: string[];
  frame_rate?: string;
  start_with_sap?: number;
  content_length?: number;
}

export interface DashAudioItem {
  id: number;
  baseUrl: string;
  backupUrl?: string[];
  bandwidth?: number;
  contentLength?: number;
  base_url?: string;
  backup_url?: string[];
  content_length?: number;
}

interface DashData {
  video?: Array<DashVideoItem>;
  audio?: Array<DashAudioItem>;
  timelength?: number;
}

interface PlayUrlData {
  durl?: Array<DurlItem>;
  dash?: DashData;
  accept_quality?: Array<number>;
  accept_description?: Array<string>;
  quality?: number;
  /** ⭐ 视频总时长（毫秒，B 站 playurl 返回在外层，非 dash 内） */
  timelength?: number;
  /** ⭐ 服务端记录的上次观看位置（毫秒，仅登录且该 cid 有观看记录时返回） */
  last_play_time?: number;
}

interface PlayUrlResponse {
  code: number;
  message?: string;
  data?: PlayUrlData;
}

// ========== 搜索接口类型定义 ==========
interface OwnerInfo {
  name: string;
  face: string;
}

interface StatInfo {
  view: number;
  danmaku: number;
  like: number;
}

interface SearchPageInfo {
  cid: number;
}

// 番剧搜索评分对象（media_score）：{ user_count: 评分人数, score: 评分 }
interface SearchMediaScore {
  user_count?: number;
  score?: number;
}

interface SearchResultItem {
  bvid: string;
  title: string;
  pubdate: number;
  owner: OwnerInfo;
  pic: string;
  stat: StatInfo;
  cid: number;
  pages?: Array<SearchPageInfo>;
  // 搜索接口实际返回的扁平字段（无 stat/owner 嵌套对象时的回退字段）
  play?: number;
  video_review?: number;
  author?: string;

  // 直播专用字段
  roomid?: number;
  uname?: string;
  face?: string;
  uface?: string;     // live_room 搜索结果头像字段名
  live_status?: number;
  online?: number;      // 直播间观看人数
  room_screenshot?: string;
  keyframe?: string;
  user_cover?: string;

  // 番剧/媒资专用字段
  media_id?: number;
  season_id?: number;   // ⭐ 番剧季id（/pgc/view/web/season 只认这个，media_id 不通用）
  ep_id?: number;       // ⭐ 最新分集 id（部分搜索场景可直接用于取流）
  cover?: string;
  staff?: string;           // 番剧搜索：制作团队（部分结果无 author）
  season_type_name?: string; // 番剧搜索：类型名（番剧/国创/电影等）
  ep_size?: number;         // 番剧搜索：集数
  media_score?: SearchMediaScore; // 番剧搜索：评分对象
  pubtime?: number;         // 番剧搜索：开播时间（时间戳）

  // 专栏专用字段
  id?: number;
  images?: string[];
  view?: number;
  like?: number;
  // 用户搜索专用字段
  mid?: number;
  fans?: number;
  upic?: string;
  videos?: number;
  usign?: string;
  is_followed?: number;  // B站搜索API自带的关注状态：0=未关注, 1=已关注
}

/**
 * 搜索类型
 */
export type SearchType = 'video' | 'live_user' | 'media_bangumi' | 'media_ft' | 'article' | 'bili_user';

/**
 * 视频搜索排序选项
 */
export type SearchOrder = 'totalrank' | 'click' | 'pubdate' | 'dm' | 'stow';

/**
 * 获取排序选项中文标签
 */
export function getSearchOrderLabel(order: string): string {
  switch (order) {
    case 'totalrank': return '综合';
    case 'click': return '最多播放';
    case 'pubdate': return '最新发布';
    case 'dm': return '最多弹幕';
    case 'stow': return '最多收藏';
    default: return order;
  }
}

/**
 * 视频排序选项列表（用于排序栏渲染）
 */
export const SEARCH_ORDER_KEYS: SearchOrder[] = ['totalrank', 'click', 'pubdate', 'dm', 'stow'];

/**
 * 搜索类型中文标签映射
 */
export interface SearchTypeLabelMap {
  video: string;
  live_user: string;
  media_bangumi: string;
  media_ft: string;
  article: string;
  bili_user: string;
}

/**
 * 获取搜索类型中文标签
 */
export function getSearchTypeLabel(type: string): string {
  switch (type) {
    case 'all': return '综合';
    case 'video': return '视频';
    case 'live_user': return '直播';
    case 'media_bangumi': return '番剧';
    case 'media_ft': return '影视';
    case 'article': return '专栏';
    case 'bili_user': return '用户';
    default: return type;
  }
}

interface SearchListResponse {
  result?: SearchResultItem[];
  numResults?: number;
  page?: number;
  pagesize?: number;
}

// ========== 视频详情接口定义 ==========
export interface VideoDetailOwner {
  mid: number;
  name: string;
  face: string;
}

export interface VideoDetailStat {
  aid: number;
  view: number;
  danmaku: number;
  reply: number;
  favorite: number;
  coin: number;
  share: number;
  like: number;
  dislike: number;
}

// 用户互动状态（是否已点赞、投币、收藏）
export interface UserInteractionStatus {
  like: boolean;      // 是否已点赞
  coin: number;       // 投币数量（0表示未投币）
  favorite: boolean;  // 是否已收藏
}

export interface VideoDimension {
  width: number;
  height: number;
  rotate?: number;
}

export interface VideoPageItem {
  dimension?: VideoDimension;
  cid: number;
  page: number;
  part: string;
  duration: number;
  cover?: string;  // ⭐ 分集封面（PGC 分集有；UGC 多P 用 first_frame）
}

// ========== UGC 合集类型 ==========

/** 合集分集关联视频统计 */
export interface SeasonArcStat {
  view?: number;
  danmaku?: number;
}

/** 合集分集关联视频信息 */
export interface SeasonArc {
  pic?: string;
  duration?: number;
  stat?: SeasonArcStat;
}

/** 合集分集分P信息 */
export interface SeasonPage {
  cid?: number;
  page?: number;
  part?: string;
  duration?: number;
}

/** 合集分集（Episode） */
export interface SeasonEpisode {
  id?: number;
  aid?: number;
  cid?: number;
  bvid?: string;
  title?: string;
  cover?: string;
  badge?: string;
  duration?: number;
  arc?: SeasonArc;
  page?: SeasonPage;
  pages?: Array<SeasonPage>;
}

/** 合集分区（Section） */
export interface SeasonSection {
  seasonId?: number;
  id?: number;
  title?: string;
  type?: number;
  episodes?: Array<SeasonEpisode>;
}

/** 合集统计 */
export interface SeasonStat {
  view?: number;
  danmaku?: number;
  reply?: number;
  favorite?: number;
  coin?: number;
  share?: number;
  like?: number;
}

/** UGC 合集 */
export interface UgcSeason {
  id?: number;
  title?: string;
  cover?: string;
  mid?: number;
  intro?: string;
  signState?: number;
  attribute?: number;
  sections?: Array<SeasonSection>;
  stat?: SeasonStat;
  epCount?: number;
  /** view 接口原始字段（snake_case）；解析时必须归一到 epCount，否则运行时永远是 undefined */
  ep_count?: number;
  seasonType?: number;
  isPaySeason?: boolean;
  enableVt?: number;
}

/** 视频详情原始 pages 元素（B站 view 接口透传结构，含首帧封面） */
interface RawViewPage {
  dimension?: VideoDimension;
  cid?: number;
  page?: number;
  part?: string;
  duration?: number;
  first_frame?: string;
}

// 用户互动状态（需要登录后才会返回）
export interface VideoDetailReqUser {
  dislike?: boolean;
  like?: boolean;      // 是否已点赞
  coin?: number;       // 投币数量
  favorite?: boolean;  // 是否已收藏
}

export interface VideoIntroTag {
  tag_id: number;
  tag_name: string;
}

export interface VideoIntroOwner {
  fans?: number;
}

export interface VideoArgueInfo {
  argue_msg?: string;
}

export interface VideoIntroCard {
  card?: VideoIntroOwner;
  archive_count?: number;
}

export async function getVideoIntroCard(mid: number): Promise<VideoIntroCard | null> {
  try {
    const result = await requestWithCookie<VideoIntroCard>(`https://api.bilibili.com/x/web-interface/card?mid=${mid}`);
    return result.code === 0 ? result.data || null : null;
  } catch (_error) { return null; }
}

export async function getVideoIntroTags(bvid: string): Promise<VideoIntroTag[]> {
  try {
    const result = await requestWithCookie<VideoIntroTag[]>(`https://api.bilibili.com/x/tag/archive/tags?bvid=${encodeURIComponent(bvid)}`);
    return result.code === 0 ? result.data || [] : [];
  } catch (_error) { return []; }
}

export interface VideoRights {
  no_reprint?: number;
}

export interface VideoDetail {
  dimension?: VideoDimension;
  bvid: string;
  aid: number;
  title: string;
  desc: string;
  pic: string;
  pubdate: number;
  ctime: number;
  duration: number;
  owner: VideoDetailOwner;
  stat: VideoDetailStat;
  cid?: number;           // 首P的cid
  pages?: Array<VideoPageItem>;
  // 用户互动状态（需要登录后才会返回）
  req_user?: VideoDetailReqUser;
  argue_info?: VideoArgueInfo;
  rights?: VideoRights;
  // ⭐ UGC 合集
  ugc_season?: UgcSeason;
}

export interface VideoDetailResponse {
  code: number;
  message?: string;
  data?: VideoDetail;
}

// ========== 评论接口定义 ==========
export interface LevelInfo {
  current_level: number;
}

export interface CommentMember {
  mid: string;
  uname: string;
  avatar: string;
  level_info?: LevelInfo;
}

// 表情映射项
export interface EmoteItem {
  id: number;
  text: string;      // 表情文本，如 "[doge]"
  url: string;       // 表情图片URL
}

// 评论图片
export interface CommentPicture {
  img_src: string;   // 图片URL
  img_width: number;
  img_height: number;
}

export interface CommentContent {
  message: string;
  plat?: number;
  device?: string;
  emote?: Record<string, EmoteItem>;     // 表情映射表
  pictures?: CommentPicture[];            // 评论图片列表
}

/** 评论操作属性（IP 属地在 reply_control.location，登录态才下发） */
export interface CommentReplyControl {
  max_line?: number;
  time_desc?: number;
  support_share?: boolean;
  translation_switch?: number;
  /** 登录态下返回，如 "IP属地: 上海" / "上海" */
  location?: string;
}

export interface CommentItem {
  rpid: number;
  oid: number;
  type: number;
  mid: number;
  root: number;
  parent: number;
  dialog: number;
  count: number;
  rcount: number;
  state: number;
  fansgrade?: number;
  attr?: number;
  ctime: number;
  like: number;
  action: number;
  member: CommentMember;
  content: CommentContent;
  /** IP 属地，如 "上海"（接口只返回属地，不返回完整 IP） */
  ip_location?: string;
  /** 新接口字段名：location（格式 "IP属地：xx"），旧字段 ip_location 已很少下发 */
  location?: string;
  /** B 站现行字段位置：reply_control.location（登录态才返回） */
  reply_control?: CommentReplyControl;
  replies?: CommentItem[];
}

export interface CommentPage {
  num: number;
  size: number;
  count: number;
  acount: number;
}

export interface CommentCursor {
  is_end: boolean;
  next: number;
}

export interface CommentData {
  cursor?: CommentCursor;
  replies?: CommentItem[];
  page?: CommentPage;
  root?: CommentItem;
}

export interface CommentListResponse {
  code: number;
  message?: string;
  data?: CommentData;
}

/** getVideoComments 新版 API 返回结果 */
export interface VideoCommentsResult {
  comments: CommentItem[];
  nextCursor: number;
  isEnd: boolean;
}

// ============================================

function getCookieHeader(): string {
  const cookie = mergeLoginCookies([AppStorage.get<string>('biliCookie') || '']);
  const deviceId = getDeviceId();
  // Preserve the server's device cookie; never append duplicate or undefined fingerprints.
  return mergeLoginCookies([deviceId ? `buvid3=${deviceId}` : '', cookie]);
}

async function requestWithCookie<T>(url: string): Promise<ApiResponse<T>> {
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Cookie': getCookieHeader()
      },
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode !== 200) {
      throw new Error(`HTTP ${response.responseCode}`);
    }
    const result = response.result as string;
    const jsonData: ApiResponse<T> = JSON.parse(result);
    return jsonData;
  } finally {
    httpRequest.destroy();
  }
}

export async function getPopularVideos(page: number = 1, pageSize: number = 30): Promise<RecommendItem[]> {
  // 使用WBI签名的热门API
  const params: Record<string, string> = {} as Record<string, string>;
  params['pn'] = page.toString();
  params['ps'] = pageSize.toString();

  try {
    const queryStr = await AppSign.generateWebParams(params);
    const url = `https://api.bilibili.com/x/web-interface/popular?${queryStr}`;
    logInfo(`请求热门视频接口: ${url.substring(0, 150)}...`);
    const jsonData = await requestWithCookie<VideoListResponse>(url);
    if (jsonData.code !== 0) {
      logWarn(`热门视频接口返回 code=${jsonData.code}`);
      return [];
    }
    let list = jsonData.data?.list;
    if (!list && jsonData.data?.item) {
      list = jsonData.data.item;
    }
    if (!list) return [];
    const result: RecommendItem[] = [];
    for (let i = 0; i < list.length; i++) {
      const item = RecommendItem.fromPopularApi(list[i]);
      if (item.id) result.push(item);
    }
    logInfo(`热门视频接口返回 ${result.length} 条数据`);
    return result;
  } catch (err) {
    logError(`请求热门视频异常: ${errMsg(err)}`);
    return [];
  }
}

/**
 * 推荐请求状态管理
 * ⭐ fresh_idx 必须递增，否则会返回重复内容
 */
class RecommendStateManager {
  private static instance: RecommendStateManager | null = null;

  /** fresh_idx - 刷新索引，每次请求递增 */
  private freshIdx: number = 1;
  /** brush - 刷次，与 fresh_idx 同步 */
  private brush: number = 1;

  static getInstance(): RecommendStateManager {
    if (!RecommendStateManager.instance) {
      RecommendStateManager.instance = new RecommendStateManager();
    }
    return RecommendStateManager.instance;
  }

  /** 获取当前 fresh_idx */
  getFreshIdx(): number {
    return this.freshIdx;
  }

  /** 获取当前 brush */
  getBrush(): number {
    return this.brush;
  }

  /** 递增索引（每次请求后调用） */
  increment(): void {
    this.freshIdx++;
    this.brush++;
  }

  /** 重置索引 */
  reset(): void {
    this.freshIdx = 1;
    this.brush = 1;
  }
}

/**
 * 从 Cookie 中提取用户 mid（DedeUserID）
 * ⭐ 关键：X-Bili-Mid 是服务器识别用户的核心标识
 */
function extractMidFromCookie(cookie: string): string {
  if (!cookie) return '0';
  const match = cookie.match(/DedeUserID=(\d+)/);
  return match && match[1] ? match[1] : '0';
}

/**
 * 获取带用户身份的请求头
 * ⭐ X-Bili-Mid 是个性化推荐的关键
 */
function getBiliRequestHeaders(): Record<string, string> {
  const cookie = getCookieHeader();
  const mid = extractMidFromCookie(cookie);

  const headers: Record<string, string> = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36',
    'Referer': 'https://www.bilibili.com/',
    'Origin': 'https://www.bilibili.com',
    'Cookie': cookie
  };

  // ⭐ 关键：添加用户身份标识（个性化推荐必需）
  if (mid !== '0') {
    headers['X-Bili-Mid'] = mid;
  }

  return headers;
}

/**
 * 获取推荐视频列表
 * @param freshIdx 刷新索引（必须传入，每次刷新/加载更多时递增）
 * @param pageSize 每页数量
 *
 * ⭐ 关键参数说明：
 * - fresh_idx: 刷新索引，必须递增才能获取不同内容
 * - fresh_idx_1h: 小时级分页索引
 * - brush: 刷次，与 fresh_idx 同步
 * - fetch_row: 累计加载行数
 * - fresh_type: 4 = 刷新推荐
 * - feed_version: V8 = 推荐算法版本
 *
 * ⭐ 调用者必须在每次请求成功后自己递增 freshIdx！
 */
export async function getRecommendVideos(freshIdx: number, pageSize: number = 30): Promise<RecommendItem[]> {
  const actualFreshIdx = freshIdx;
  const actualBrush = freshIdx;
  const fetchRow = (actualFreshIdx - 1) * pageSize;  // 累计加载行数

  try {
    // ⭐ 完整的推荐参数（参考 PiliPlus）
    const params: Record<string, string> = {};
    params['ps'] = pageSize.toString();
    params['fresh_idx'] = actualFreshIdx.toString();       // 刷新索引
    params['fresh_idx_1h'] = actualFreshIdx.toString();    // 小时级分页索引
    params['brush'] = actualBrush.toString();              // 刷次
    params['fetch_row'] = fetchRow.toString();             // 累计加载行数
    params['fresh_type'] = '4';                            // 刷新推荐
    params['version'] = '1';
    params['feed_version'] = 'V8';                         // 推荐算法版本
    params['homepage_ver'] = '1';                          // 首页版本
    params['web_location'] = '1430650';                    // 页面位置标识

    const queryStr = await AppSign.generateWebParams(params);
    const url = `https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd?${queryStr}`;

    // ⭐ 使用带用户身份的请求头
    const httpRequest = http.createHttp();
    const headers = getBiliRequestHeaders();

    logInfo(`[推荐] fresh_idx=${actualFreshIdx}, brush=${actualBrush}, X-Bili-Mid=${headers['X-Bili-Mid'] || '未登录'}`);

    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 10000,
      readTimeout: 10000
    });

    httpRequest.destroy();

    if (response.responseCode !== 200) {
      logWarn(`推荐接口 HTTP ${response.responseCode}，返回空数据`);
      return [];
    }

    const jsonData: ApiResponse<VideoListResponse> = JSON.parse(response.result as string);
    if (jsonData.code !== 0) {
      logWarn(`推荐接口返回 code=${jsonData.code}，返回空数据`);
      return [];
    }

    let list = jsonData.data?.list;
    if (!list && jsonData.data?.item) {
      list = jsonData.data.item;
    }
    if (!list) {
      logWarn('推荐接口返回数据为空');
      return [];
    }

    const result: RecommendItem[] = [];
    for (let i = 0; i < list.length; i++) {
      const item = RecommendItem.fromPopularApi(list[i]);
      if (item.id) result.push(item);
    }

    // ⭐ 不再自动递增！让调用者完全控制 fresh_idx
    // 调用者应该在请求成功后自己递增索引

    logInfo(`[推荐] 返回 ${result.length} 条数据，fresh_idx=${actualFreshIdx}`);
    return result;
  } catch (err) {
    logError(`请求推荐视频异常: ${errMsg(err)}，返回空数据`);
    return [];
  }
}

/**
 * 重置推荐索引（用于强制刷新）
 */
export function resetRecommendIndex(): void {
  RecommendStateManager.getInstance().reset();
  logInfo('[推荐] 索引已重置');
}

/**
 * 获取当前推荐索引
 */
export function getCurrentRecommendIndex(): number {
  return RecommendStateManager.getInstance().getFreshIdx();
}

/**
 * 播放URL返回结果
 */
export interface PlayUrlResult {
  url: string;       // 视频URL（FLV或DASH视频轨）
  mediaUserAgent?: string;
  mediaReferer?: string;
  audioUrl?: string;  // 可选：DASH音频轨（需要第二个AVPlayer播放）
  actualQn: number;   // 服务器实际返回的画质
  acceptQuality?: number[];     // 服务器允许的画质 qn 列表（用于动态生成清晰度弹窗）
  acceptDescription?: string[]; // 服务器返回的画质描述（与官方版对齐）
  /** ⭐ DASH 双流完整元数据（转播站拼 MPD 用；仅 DASH 返回时携带） */
  dash?: DashFullInfo;
  /**
   * ⭐ 服务端记录的上次观看位置（毫秒，未登录/无记录/非首页请求时为 0）
   *   来源：UGC `/x/player/wbi/playurl` 的 data.last_play_time；
   *        PGC `/pgc/player/web/v2/playurl` 的 result.play_view_business_info.user_status.watch_progress.current_watch_progress
   *   用途：**按集**恢复播放位置（番剧/影视多集续播的关键：每集各有自己的续播点，
   *        不依赖历史列表的 progress，也不需要跨集传参）
   */
  lastPlayTimeMs?: number;
}

/**
 * ⭐ DASH 双流完整信息（供 DashPlayerBridge 拼 MPD）
 */
export interface DashFullInfo {
  /** 视频轨全量列表（含 带宽/宽高/frameRate/sar 等） */
  videoStreams: Array<DashVideoItem>;
  /** 音频轨全量列表 */
  audioStreams: Array<DashAudioItem>;
  /** 时长（毫秒，playurl 返回） */
  timelength: number;
  /** 实际画质 */
  quality: number;
}

/** Keep the reported quality, direct video URL and bridge rendition in agreement. */
function normalizeDashQuality(result: PlayUrlResult, requestedQn: number): PlayUrlResult {
  if (!result.dash || !result.audioUrl || !result.url) return result;
  const returnedQn = result.dash.quality || result.actualQn || requestedQn;
  const selected = selectDashVideo(result.dash.videoStreams,
    requestedQn > 0 ? Math.min(requestedQn, returnedQn) : returnedQn);
  if (selected) {
    result.url = selected.baseUrl;
    result.actualQn = selected.id;
    result.dash.quality = selected.id;
  }
  return result;
}

function normalizeFetchDashQuality(result: FetchPlayUrlResult, requestedQn: number): FetchPlayUrlResult {
  if (result.durlUrl || !result.dashInfo || !result.dashAudioUrl || !result.dashVideoUrl) return result;
  const normalized = normalizeDashQuality({ url: result.dashVideoUrl, audioUrl: result.dashAudioUrl,
    actualQn: result.actualQn, dash: result.dashInfo }, requestedQn);
  result.dashVideoUrl = normalized.url;
  result.actualQn = normalized.actualQn;
  return result;
}

/**
 * 单次请求播放地址，返回 FLV(durl) 和 DASH 视频 URL
 */
interface FetchPlayUrlResult {
  durlUrl: string;
  dashVideoUrl: string;
  dashAudioUrl: string;
  actualQn: number; // 实际返回的画质qn
  acceptQuality: number[]; // B站允许的画质列表
  acceptDescription: string[]; // B站允许的画质描述
  /** ⭐ 完整 DASH 元数据（供转播站拼 MPD） */
  dashInfo: DashFullInfo | null;
  route?: string;
}

/** 同一视频的三路探测共享续播点；每次取流独立创建，避免不同视频并发串号。 */
interface LastPlayTimeProbe {
  ms: number;
}

/**
 * ⭐ 把探测到的续播点挂到取流结果上
 * @param result 取流结果
 * @param probe 本次取流的续播点
 */
function attachLastPlayTime(result: PlayUrlResult, probe: LastPlayTimeProbe): PlayUrlResult {
  if (probe.ms > 0) {
    result.lastPlayTimeMs = probe.ms;
    logInfo(`[PlayURL] 服务端续播点 → ${probe.ms}ms`);
  }
  return result;
}

async function tryFetchPlayUrl(bvid: string, cid: number, qn: number, fnval: number, probe?: LastPlayTimeProbe): Promise<FetchPlayUrlResult> {
  const profile = PlaybackStartup.span('playurl-web-' + fnval);
  const params: Record<string, string> = {};
  params[/^\d+$/.test(bvid) ? 'avid' : 'bvid'] = bvid;
  params['cid'] = cid.toString();
  params['qn'] = qn.toString();
  params['fnval'] = fnval.toString();
  params['fnver'] = '0';
  params['fourk'] = '1';
  // Native playback needs the full DASH quality catalogue; HTML5 limits it to MP4.
  params['platform'] = 'pc';
  params['high_quality'] = '1';
  profile?.mark('sign-start');
  const queryStr = await AppSign.generateWebParams(params);
  profile?.mark('sign-end');
  const url = `https://api.bilibili.com/x/player/wbi/playurl?${queryStr}`;
  logInfo(`[WbiAPI] 请求: ${url.substring(0, 120)}...`);
  const httpRequest = http.createHttp();
  try {
    profile?.mark('http-start');
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
        'Cookie': getCookieHeader()
      },
      connectTimeout: 10000,
      readTimeout: 10000
    });
    profile?.network(response);

    if (response.responseCode !== 200) {
      if (response.responseCode === 412) notePlayUrlThrottle();
      logError(`tryFetchPlayUrl HTTP错误: ${response.responseCode}, qn=${qn}, fnval=${fnval}`);
      return { durlUrl: '', dashVideoUrl: '', dashAudioUrl: '', actualQn: 0, acceptQuality: [], acceptDescription: [], dashInfo: null };
    }

    const jsonData: PlayUrlResponse = JSON.parse(response.result as string);
    if (jsonData.code !== 0) {
      logWarn(`tryFetchPlayUrl API错误: code=${jsonData.code}, qn=${qn}, fnval=${fnval}`);
      return { durlUrl: '', dashVideoUrl: '', dashAudioUrl: '', actualQn: 0, acceptQuality: [], acceptDescription: [], dashInfo: null };
    }

    clearPlayUrlThrottle();
    // ⭐ 记录服务端返回的续播点（登录且该 cid 有观看记录时才有值；0 不覆盖）
    const lastPlayMs: number = jsonData.data?.last_play_time ?? 0;
    if (lastPlayMs > 0 && probe) {
      probe.ms = lastPlayMs;
    }

    // 日志：B站实际返回的画质信息
    const acceptQn = jsonData.data?.accept_quality as Array<number> | undefined;
    const acceptDesc = jsonData.data?.accept_description as Array<string> | undefined;
    const actualQn = jsonData.data?.quality as number | undefined;
    logInfo(`[PlayURL] 请求qn=${qn}, 实际qn=${actualQn}, 可用画质列表=${JSON.stringify(acceptQn)}, 描述=${JSON.stringify(acceptDesc)}`);

    let durlUrl = '';
    let dashVideoUrl = '';
    let dashAudioUrl = '';
    // ⭐ 完整 DASH 元数据（MpdBuilder 需要全量字段）
    let dashInfo: DashFullInfo | null = null;
    const dashRaw = jsonData.data?.dash;

    // FLV 流（音视频合并）
    if (jsonData.data?.durl && jsonData.data.durl.length === 1) {
      durlUrl = jsonData.data.durl[0].url || '';
    }

    // DASH 流（视频+音频分离）
    if (dashRaw?.video && dashRaw.video.length > 0) {
      const videoList = dashRaw.video;
      // ⭐ 优先选非 AV1 视频轨（设备解码器不支持 AV1）
      const nonAv1 = videoList.filter((v: DashVideoItem) => v.codecid !== 13);
      const usableList = nonAv1.length > 0 ? nonAv1 : videoList;
      usableList.sort((a: DashVideoItem, b: DashVideoItem) => b.id - a.id);
      dashVideoUrl = usableList[0].baseUrl || '';
    }
    if (dashRaw?.audio && dashRaw.audio.length > 0) {
      const audioList = dashRaw.audio;
      audioList.sort((a, b) => b.id - a.id);
      dashAudioUrl = audioList[0].baseUrl || '';
    }
    // ⭐ 携带完整列表（不分流选择，MPD 生成器自行挑）
    if (dashRaw?.video && dashRaw.video.length > 0 && dashRaw.audio && dashRaw.audio.length > 0) {
      const info: DashFullInfo = {
        videoStreams: dashRaw.video,
        audioStreams: dashRaw.audio,
        timelength: jsonData.data?.timelength || dashRaw.timelength || 0,
        quality: actualQn || 0
      };
      dashInfo = info;
    }

    return { durlUrl, dashVideoUrl, dashAudioUrl, actualQn: actualQn ?? 0, acceptQuality: acceptQn ?? [], acceptDescription: acceptDesc ?? [], dashInfo: dashInfo };
  } catch (err) {
    logError(`tryFetchPlayUrl异常: ${err}, qn=${qn}, fnval=${fnval}`);
    return { durlUrl: '', dashVideoUrl: '', dashAudioUrl: '', actualQn: 0, acceptQuality: [], acceptDescription: [], dashInfo: null };
  } finally {
    profile?.end();
    httpRequest.destroy();
  }
}

// ==================== 播放地址内存缓存（二次进入同视频免整链请求） ====================
const PLAYURL_CACHE_TTL: number = 60000; // 缓存有效期 60 秒

interface PlayUrlCacheEntry {
  result: PlayUrlResult;
  at: number;
}

const playUrlCache: Map<string, PlayUrlCacheEntry> = new Map();

// 412 是 B 站的风控响应。被撞到之后如果继续按原来的「双路并行 + 4 档降级」打，
// 只会撞得更狠：一次取流最多 6 个请求，列表预取 8 条就变成几十个。
// 这里做指数退避：冷却期内只走单路、不降级；成功后立刻解除。
let playUrlBlockUntil: number = 0;
let playUrlBlockStrikes: number = 0;

function notePlayUrlThrottle(): void {
  playUrlBlockStrikes = Math.min(playUrlBlockStrikes + 1, 5);
  const delay: number = Math.min(30000, 2000 * Math.pow(2, playUrlBlockStrikes - 1));
  playUrlBlockUntil = Date.now() + delay;
  logWarn(`[PlayURL] 命中 412 风控，退避 ${delay}ms（连续 ${playUrlBlockStrikes} 次）`);
}

function clearPlayUrlThrottle(): void {
  if (playUrlBlockStrikes > 0) logInfo('[PlayURL] 412 退避解除');
  playUrlBlockStrikes = 0;
  playUrlBlockUntil = 0;
}

function playUrlThrottled(): boolean {
  return Date.now() < playUrlBlockUntil;
}
const playUrlInflight: Map<string, Promise<PlayUrlResult>> = new Map();
let playUrlCredential: string = '';

function syncPlayUrlCredential(): string {
  const credential = AppStorage.get<string>('biliCookie') || '';
  if (credential !== playUrlCredential) {
    hilog.warn(0x0000, 'PlayURLKey', 'CRED-CHANGED clear cache size=%{public}d', playUrlCache.size);
    playUrlCache.clear();
    playUrlInflight.clear();
    playUrlCredential = credential;
  }
  return credential;
}

/** 缓存键: "bvid_cid_qn" */
function playUrlCacheKey(bvid: string, cid: number, qn: number): string {
  const kernel = AppStorage.get<string>('playbackKernel') === 'ijk' ? 'ijk' : 'system';
  return `${bvid}_${cid}_${qn}_${kernel}`;
}

/**
 * 画质容错：同一条视频若已缓存过一份「包含目标画质流」的结果，就直接复用。
 * 起播链路上的 qn 来自多个入口（列表预取 / 播放页 / 续播恢复 / 自动降级），
 * 只要两边算出的 qn 不同，精确键必然 miss —— 数据明明已经在手里却要重新请求，
 * 这就是之前 url@212ms 的来源。
 */
function findCompatiblePlayUrl(bvid: string, cid: number, qn: number, maxAgeMs: number): PlayUrlResult | null {
  if (qn <= 0) return null;
  const kernel: string = AppStorage.get<string>('playbackKernel') === 'ijk' ? 'ijk' : 'system';
  const prefix: string = `${bvid}_${cid}_`;
  const suffix: string = `_${kernel}`;
  const now: number = Date.now();
  let best: PlayUrlResult | null = null;
  let bestAt: number = 0;
  playUrlCache.forEach((entry: PlayUrlCacheEntry, key: string) => {
    // CID uniquely identifies a part; AV/BV aliases share its prepared source.
    if ((!key.startsWith(prefix) && !(cid > 0 && key.endsWith(`_${cid}_${qn}${suffix}`))) || !key.endsWith(suffix)) return;
    if (now - entry.at >= maxAgeMs) return;
    const streams = entry.result.dash?.videoStreams;
    const sameQuality: boolean = key.endsWith(`_${cid}_${qn}${suffix}`);
    if (!entry.result.url || (!sameQuality && (!streams || !streams.some((item: DashVideoItem) => item.id === qn)))) return;
    if (entry.at > bestAt) {
      bestAt = entry.at;
      best = entry.result;
    }
  });
  return best;
}

/** 播放失败/切画质时作废缓存（下次请求强制重新取流） */
export function invalidatePlayUrlCache(bvid: string, cid: number, qn?: number): void {
  syncPlayUrlCredential();
  if (qn !== undefined) {
    const aliasSuffix: string = `_${cid}_${qn}_`;
    playUrlCache.forEach((_entry: PlayUrlCacheEntry, key: string) => {
      if (cid > 0 && key.includes(aliasSuffix)) playUrlCache.delete(key);
    });
    playUrlCache.delete(playUrlCacheKey(bvid, cid, qn));
    playUrlInflight.forEach((_task: Promise<PlayUrlResult>, key: string) => {
      if (key === playUrlCacheKey(bvid, cid, qn) || (cid > 0 && key.includes(aliasSuffix))) playUrlInflight.delete(key);
    });
    logInfo(`[PlayURL] 作废缓存 (${bvid}_${cid}_${qn})`);
    return;
  }
  const prefix = `${bvid}_${cid}_`;
  playUrlInflight.forEach((_value: Promise<PlayUrlResult>, key: string) => {
    if (key.startsWith(prefix) || (cid > 0 && key.includes(`_${cid}_`))) playUrlInflight.delete(key);
  });
  const keysToDelete: string[] = [];
  playUrlCache.forEach((_v, k: string) => {
    if (k.startsWith(prefix) || (cid > 0 && k.includes(`_${cid}_`))) {
      keysToDelete.push(k);
    }
  });
  for (const k of keysToDelete) {
    playUrlCache.delete(k);
  }
  logInfo(`[PlayURL] 作废缓存 (${bvid}_${cid}, 共${keysToDelete.length}条)`);
}

/**
 * 获取播放地址并保留完整画质目录。常规画质在有限等待内优先使用同画质单文件合流；
 * 高帧率/HDR 等继续使用完整 DASH。仅完整取流失败时进入既有合流兜底。
 */
export async function getVideoPlayUrl(bvid: string, cid: number, qn: number = 116,
  maxCacheAgeMs: number = PLAYURL_CACHE_TTL): Promise<PlayUrlResult> {
  const profile = PlaybackStartup.span('playurl-consumer');
  const credentialsReady = loginCredentialsReady();
  if (credentialsReady) {
    try { await credentialsReady; } catch (error) { profile?.end(); throw error as Error; }
  }
  const credential = syncPlayUrlCredential();
  // aid 与 BV 入口归一，点击预取与播放页共用同一进行中的请求。
  if (/^\d+$/.test(bvid) && cid <= 0) {
    const detail = await getVideoDetail(bvid);
    if (credential !== (AppStorage.get<string>('biliCookie') || '')) { profile?.end(); throw new Error('playback session changed'); }
    if (detail?.bvid) return getVideoPlayUrl(detail.bvid, cid || detail.cid || detail.pages?.[0]?.cid || 0, qn, maxCacheAgeMs).finally(() => profile?.end());
  }
  const key = playUrlCacheKey(bvid, cid, qn);
  const cached = playUrlCache.get(key);
  const allowAge: number = Math.min(PLAYURL_CACHE_TTL, Math.max(0, maxCacheAgeMs));
  if (cached && (Date.now() - cached.at) < allowAge) {
    hilog.debug(0x0000, 'PlayURLKey', 'HIT %{public}s age=%{public}dms', key, Date.now() - cached.at);
    logInfo(`[PlayURL] 命中缓存 (${key})，跳过API请求`);
    profile?.mark('cache-hit'); profile?.end();
    return cached.result;
  }
  hilog.debug(0x0000, 'PlayURLKey', 'MISS %{public}s age=%{public}dms ttl=%{public}dms size=%{public}d',
    key, cached ? Date.now() - cached.at : -1, allowAge, playUrlCache.size);
  const compatible: PlayUrlResult | null = findCompatiblePlayUrl(bvid, cid, qn, allowAge);
  if (compatible !== null) {
    hilog.info(0x0000, 'PlayURLKey', 'ALT %{public}s actualQn=%{public}d', key, compatible.actualQn || 0);
    profile?.mark('cache-alt'); profile?.end();
    return compatible;
  }
  const pending = playUrlInflight.get(key);
  if (pending) { profile?.mark('inflight'); return pending.finally(() => profile?.end()); }
  const started = Date.now();
  const probe: LastPlayTimeProbe = { ms: 0 };
  const preferDual = AppStorage.get<string>('playbackKernel') === 'ijk';
  const task: Promise<PlayUrlResult> = new PlaybackDeadline(12000).wait(getVideoPlayUrlRaw(bvid, cid, qn, probe, preferDual), '获取播放地址').then((result: PlayUrlResult) => {
    if (credential !== (AppStorage.get<string>('biliCookie') || '')) throw new Error('playback session changed');
    normalizeDashQuality(result, qn);
    hilog.debug(0x0000, 'PlayerQuality', 'request=%{public}d returned=%{public}d options=%{public}s',
      qn, result.actualQn || 0, JSON.stringify(result.acceptQuality || []));
    attachLastPlayTime(result, probe);
    if (result.url && playUrlInflight.get(key) === task) {
      playUrlCache.set(key, { result: result, at: Date.now() });
      while (playUrlCache.size > 64) playUrlCache.delete(playUrlCache.keys().next().value!);
    }
    hilog.debug(0x0000, 'PlayURLKey', 'DONE %{public}s %{public}dms', key, Date.now() - started);
    logInfo(`[Startup] playurl ${key} ${Date.now() - started}ms`);
    return result;
  }).finally(() => {
    if (playUrlInflight.get(key) === task) playUrlInflight.delete(key);
  });
  playUrlInflight.set(key, task);
  return task.finally(() => profile?.end());
}

/** 点击卡片时预取详情和播放地址，不创建播放器；播放页会复用请求。 */
export function prefetchVideoPlayback(id: string, cid: number, qn: number): void {
  if (!id) return;
  PlaybackStartup.navigation();
  // 点击瞬间先登记预热意向：playurl 一回来就开始建转播站（探测/MPD/首段落在转场期间）。
  // 页面侧 take() 用的是同一个 id，因此即使预热还没真正开跑也能等到它。
  // 点击即开始准备完整播放实例（转播站 + 播放器 prepare），页面命中就只做 surface 改绑。
  // 已有 BV/CID 时，取流不再排在详情之后；详情仍供简介与评论复用。
  if (/^(BV[0-9A-Za-z]+|[0-9]+)$/.test(id) && cid > 0) {
    getVideoPlayUrl(id, cid, qn)
      .then((result: PlayUrlResult) => {
        // 复用列表的有界前缀任务；续播时前缀直接对准目标分片，未完成也由播放线程接管同一份数据。
        // 本地进度优先（列表阶段就能用），没有就退回 playurl 返回的服务端续播点。
        const resume: number = PlaybackProgress.prewarmPosition(id, cid, result.lastPlayTimeMs ?? 0);
        IjkPrewarm.warm(result, resume);
        PlaybackWarmPlayer.get().start(cid, result);
      })
      .catch((error: Error) => { logWarn(`[Startup] 预取失败: ${error.message}`); });
    prefetchVideoDetail(id);
    return;
  }
  getVideoDetail(id).then((detail: VideoDetail | null) => {
    if (!detail?.bvid) return undefined;
    const realCid: number = cid || detail.cid || detail.pages?.[0]?.cid || 0;
    return getVideoPlayUrl(detail.bvid, realCid, qn)
      .then((result: PlayUrlResult) => {
        const resume: number = PlaybackProgress.prewarmPosition(detail.bvid, realCid, result.lastPlayTimeMs ?? 0);
        IjkPrewarm.warm(result, resume);
        PlaybackWarmPlayer.get().start(realCid, result);
      });
  }).catch((error: Error) => { logWarn(`[Startup] 预取失败: ${error.message}`); });
}

/**
 * 列表阶段只提前取播放地址：填进 playUrlCache，不建播放器、不下载任何媒体字节。
 *
 * 首页有 PlaybackListPrefetch 提前把地址备好（点击时 `url@20~67ms`）；搜索、合集等
 * 入口只有「点击瞬间」的 prefetchVideoPlayback，于是取流 API 的 RTT 直接计进首帧
 * （真机实测 `url@190~252ms`）。这里在结果回来后把前几条的地址先取好，点击时
 * getVideoPlayUrl 直接 HIT，把这段等待藏到用户浏览列表的时间里。
 *
 * ⚠️ 绝不触发 IjkPrewarm / PlaybackWarmPlayer：媒体字节的投机预热受 NetworkGate
 *    的预算与门控约束（512KiB/任务、1152KiB/30s、4 槽），不能借这个入口绕开。
 *    并发 2、上限 6 条，和列表预取同量级，避免搜索翻页时打爆取流接口触发 412 风控。
 */
export function prefetchPlayUrlsOnly(items: RecommendItem[], qn: number, limit: number = 6): void {
  const targets: RecommendItem[] = items.filter((item: RecommendItem) =>
    /^(BV[0-9A-Za-z]+|[0-9]+)$/.test(item.id)).slice(0, limit);
  logInfo(`[PlayURL] 列表地址预取 ${targets.length} 条 qn=${qn}`);
  let index: number = 0;
  let running: number = 0;
  const pump = (): void => {
    while (running < 2 && index < targets.length) {
      const item: RecommendItem = targets[index++];
      running++;
      // ⚠️ 搜索 API 的条目通常只有 bvid、没有 cid（播放器要点开后才由详情补齐）。
      //    第一版要求 cid>0，结果整批被过滤、一个请求都没发。这里把
      //    「详情 → cid → 取流」这条原本点击后才串行的链提前跑完；详情本身有
      //    缓存和 inflight 去重，缓存键与播放页 getVideoPlayUrl 完全一致。
      const task: Promise<PlayUrlResult | null> = (item.cid || 0) > 0
        ? getVideoPlayUrl(item.id, item.cid, qn)
        : getVideoDetail(item.id).then((detail: VideoDetail | null) => {
          const cid: number = detail?.cid || detail?.pages?.[0]?.cid || 0;
          const bvid: string = detail?.bvid || item.id;
          return cid > 0 ? getVideoPlayUrl(bvid, cid, qn) : null;
        });
      task.catch(() => {}).finally(() => {
        running--;
        pump();
      });
    }
  };
  pump();
}

/** Full-capability DASH probes race to the requested quality; merged streams are a fallback. */
async function getVideoPlayUrlRaw(bvid: string, cid: number, qn: number, probe: LastPlayTimeProbe, preferDual: boolean): Promise<PlayUrlResult> {
  let actualBvid: string = bvid;
  let actualCid: number = cid;
  
  // ⭐ 如果 bvid 是 numeric aid（App API 的项没有 bvid），先从 getVideoDetail 获取真实 bvid
  const isNumericAid: boolean = /^\d+$/.test(bvid);
  if (isNumericAid && actualCid <= 0) {
    logInfo(`[getVideoPlayUrl] bvid 是 numeric aid=${bvid}，尝试从 getVideoDetail 获取真实 bvid`);
    const detail = await getVideoDetail(bvid);
    if (detail && detail.bvid) {
      actualBvid = detail.bvid;
      logInfo(`[getVideoPlayUrl] 获取到真实 bvid: ${actualBvid}`);
    } else {
      logWarn(`[getVideoPlayUrl] 无法获取真实 bvid，尝试直接用 aid`);
    }
    if (detail && detail.aid) {
      // 使用从详情获取的 cid（但保留传入的 cid，除非为 0）
      if (actualCid === 0 && detail.cid) {
        actualCid = detail.cid;
      }
    }
  }
  // A merged response must never replace the full DASH quality catalogue.
  // Probe standard qualities in parallel; do not delay HDR/high-frame-rate startup.
  const mergedProbe: Promise<PlayUrlResult | null> | null = !preferDual && [16, 32, 64, 80, 112].includes(qn)
    ? tryFetchPlayUrlWebRoute(actualBvid, actualCid, qn, 1).then((merged: FetchPlayUrlResult): PlayUrlResult | null => {
      return merged.durlUrl ? { url: merged.durlUrl, actualQn: merged.actualQn } : null;
    }).catch(() => null) : null;
  // 3536 = DASH + 4K + HDR + Dolby + 8K, excluding AV1 and the legacy merged-stream bit.
  const empty: FetchPlayUrlResult = { durlUrl: '', dashVideoUrl: '', dashAudioUrl: '', actualQn: 0,
    acceptQuality: [], acceptDescription: [], dashInfo: null };
  const throttled: boolean = playUrlThrottled();
  const routes: Array<Promise<FetchPlayUrlResult>> = [
    tryFetchPlayUrlMobile(actualBvid, actualCid, qn, 3536, probe)
      .then((result: FetchPlayUrlResult) => normalizeFetchDashQuality(result, qn)),
  ];
  if (!throttled) {
    routes.push(tryFetchPlayUrlWebRoute(actualBvid, actualCid, qn, 3536, probe)
      .then((result: FetchPlayUrlResult) => normalizeFetchDashQuality(result, qn)));
  }
  const probeResults = await firstPreferredResults<FetchPlayUrlResult>(routes, empty, (item: FetchPlayUrlResult) => item.actualQn >= qn &&
    !!(item.durlUrl || (item.dashVideoUrl && item.dashAudioUrl)),
    (item: FetchPlayUrlResult) => !!(item.durlUrl || (item.dashVideoUrl && item.dashAudioUrl)));
  const playable = probeResults.filter((item: FetchPlayUrlResult) =>
    !!(item.durlUrl || (item.dashVideoUrl && item.dashAudioUrl)))
    .sort((a: FetchPlayUrlResult, b: FetchPlayUrlResult) => b.actualQn - a.actualQn);
  if (playable.length > 0) {
    const ready = playable[0];
    const selection = PlaybackStartup.span('playurl-selection');
    selection?.mark(ready.route || 'wbi');
    selection?.mark('quality', ready.actualQn);
    selection?.end();
    const selected: PlayUrlResult = { url: ready.durlUrl || ready.dashVideoUrl,
      audioUrl: ready.durlUrl ? undefined : ready.dashAudioUrl,
      actualQn: ready.actualQn, acceptQuality: ready.acceptQuality, acceptDescription: ready.acceptDescription,
      mediaUserAgent: ready.route === 'app-hd' ?
        'Mozilla/5.0 BiliDroid/8.43.0 (bbcallen@gmail.com) os/android model/android mobi_app/android_hd build/8430300' : undefined,
      mediaReferer: ready.route === 'app-hd' ? '' : undefined,
      dash: ready.durlUrl ? undefined : ready.dashInfo || undefined };
    return mergedProbe && !ready.durlUrl ? preferSameQualityMerged(selected, mergedProbe) : selected;
  }

  // Only try merged streams when neither full-capability route provides video with audio.
  // Preserve any full catalogue even when the fallback stream itself advertises fewer qualities.
  const catalog = probeResults.slice().sort((a: FetchPlayUrlResult, b: FetchPlayUrlResult) =>
    b.acceptQuality.length - a.acceptQuality.length)[0];
  if (playUrlThrottled()) {
    // 冷却期不做降级重试：4 档降级只会把风控撞得更久。
    logWarn('[PlayURL] 412 冷却中，跳过降级重试');
    return { url: '', actualQn: 0, acceptQuality: [], acceptDescription: [] };
  }
  const fallbackQualities: number[] = [qn];
  for (const lower of [64, 32, 16]) {
    if (lower < qn) fallbackQualities.push(lower);
  }
  for (const fallbackQn of fallbackQualities) {
    const fallback = await tryFetchPlayUrl(actualBvid, actualCid, fallbackQn, 1, probe);
    if (fallback.durlUrl) {
      const metadata = catalog.acceptQuality.length > 0 ? catalog : fallback;
      return { url: fallback.durlUrl, actualQn: fallback.actualQn,
        acceptQuality: metadata.acceptQuality, acceptDescription: metadata.acceptDescription };
    }
  }
  return { url: '', actualQn: 0, acceptQuality: [], acceptDescription: [] };
}

// ==================== 番剧/影视（PGC）取流与季信息 ====================

/**
 * ⭐ PGC 观看进度（毫秒）——result.play_view_business_info.user_status.watch_progress
 *   这是番剧/影视**按集**续播的权威来源：请求哪一集，就返回哪一集自己的观看位置，
 *   不依赖历史列表 progress，也不需要跨集传参。
 */
interface PgcWatchProgress {
  /** 当前分集的观看位置（毫秒） */
  current_watch_progress?: number;
  /** 上次观看的分集 id / 集数（跨集"继续观看"用） */
  last_ep_id?: number;
  last_ep_index?: number;
}

interface PgcUserStatus {
  watch_progress?: PgcWatchProgress;
}

interface PgcPlayViewBusinessInfo {
  user_status?: PgcUserStatus;
}

// PGC playurl 响应：数据在 result.video_info（结构与 UGC 的 data 相同）
interface PgcVideoInfoResult {
  video_info?: PlayUrlData;
  /** ⭐ 播放页业务信息（登录后带该分集的续播点） */
  play_view_business_info?: PgcPlayViewBusinessInfo;
}

interface PgcPlayUrlResponse {
  code: number;
  message?: string;
  result?: PgcVideoInfoResult;
}

/**
 * 分集信息（ep）
 */
export interface PgcEpisode {
  id?: number;        // ep_id
  aid?: number;       // ⭐ 分集 aid（番剧评论 oid 用 aid，不能用 ep_id！）
  bvid?: string;      // ⭐ 分集自己的 bvid：番剧每集是独立稿件，字幕接口按 bvid 定位作品
  cid?: number;
  title?: string;
  cover?: string;
  long_title?: string;
  badge?: string;
  duration?: number;  // 单集时长（秒）
}

/**
 * PGC 季统计原始结构（/pgc/view/web/season 的 stat 字段，与 UGC 命名不同）
 * 注意：PGC 用复数字段：views=播放量, danmakus=弹幕, likes=点赞, coins=投币
 */
export interface PgcSeasonRawStat {
  views?: number;
  danmakus?: number;
  likes?: number;
  coins?: number;
  favorite?: number;
  reply?: number;
}

/**
 * PGC 季统计（语义化字段，解析时从 raw 映射）
 */
export interface PgcSeasonStat {
  view: number;       // 播放量（raw.views）
  danmaku: number;    // 弹幕数（raw.danmakus）
  like: number;       // 点赞（raw.likes）
  favorite: number;
  coin: number;       // 投币（raw.coins）
  reply: number;
}

/**
 * PGC 制作方信息（up_info）
 */
export interface PgcUpInfo {
  mid: number;
  uname: string;
  avatar: string;
}

interface PgcPublishRaw {
  pub_time?: string;      // "2020-07-25 10:00:00"
  pub_time_show?: string;
}

/** ⭐ 关联季简要信息（/pgc/view/web/season 的 result.seasons 子项） */
interface PgcSeasonBrief {
  season_id?: number;
  season_title?: string;
}

/** ⭐ 分区信息（/pgc/view/web/season 的 result.section 子项，如 PV/预告/花絮） */
interface PgcSectionItem {
  title?: string;
  episodes?: Array<PgcEpisode>;
}

interface PgcSeasonResult {
  season_id?: number;
  title?: string;
  cover?: string;
  desc?: string;
  publish_date?: string;      // "2020-07-25"
  publish?: PgcPublishRaw;
  actors?: string;
  staff?: string;
  stat?: PgcSeasonRawStat;
  up_info?: PgcUpInfo;
  episodes?: Array<PgcEpisode>;
  // ⭐ 关联季列表（同一系列的其他季；未开播季 episodes 为空时可从中找有正片的季）
  seasons?: Array<PgcSeasonBrief>;
  // ⭐ 分区列表（未开播季正片为空时，PV/预告分集在此，可播放）
  section?: Array<PgcSectionItem>;
}

interface PgcSeasonResponse {
  code: number;
  message?: string;
  result?: PgcSeasonResult;
}

/**
 * 番剧季信息（含分集列表）
 */
export interface PgcSeasonInfo {
  seasonId: number;
  title: string;
  cover: string;
  desc: string;
  pubdate: number;
  actors: string;
  staff: string;
  stat: PgcSeasonStat;
  upInfo: PgcUpInfo;
  episodes: Array<PgcEpisode>;
  // ⭐ 关联季 id 列表（未开播季 episodes 为空时，从中找第一个有正片的季播放）
  relatedSeasonIds: Array<number>;
}

/**
 * 获取番剧/影视（PGC）播放地址
 * 接口：/pgc/player/web/v2/playurl（返回结构 result.video_info，与 UGC 的 data 同构）
 * @param epId 分集 ep_id（必需）
 * @param cid 分集 cid
 * @param qn 目标画质，默认 116
 * @param seasonId 季 id（可选，部分接口要求）
 * @returns PlayUrlResult：url=视频流（FLV 合并流或 DASH 视频轨），audioUrl=DASH 音频轨（分离时）
 */
export async function getPgcPlayUrl(epId: number, cid: number, qn: number = 116, seasonId: number = 0): Promise<PlayUrlResult> {
  const params: Record<string, string> = {};
  params['ep_id'] = epId.toString();
  if (seasonId > 0) {
    params['season_id'] = seasonId.toString();
  }
  if (cid > 0) {
    params['cid'] = cid.toString();
  }
  params['qn'] = qn.toString();
  // ⭐ fnval=3536（去掉 AV1 位 512）：设备解码器不支持 AV1，请求时不索取 AV1 码流
  params['fnval'] = '3536'; // FLV + DASH + HDR/4K/杜比/8K（不含 AV1）
  params['fnver'] = '0';
  params['fourk'] = '1';
  // ⭐ try_look 仅未登录时携带（免登录试看）；登录用户携带会强制限制画质，
  // 导致大会员高清（1080P60/4K/杜比）无法返回 —— 与官方/PiliPlus 行为对齐
  const biliCookie = AppStorage.get<string>('biliCookie') || '';
  if (!biliCookie.includes('SESSDATA')) {
    params['try_look'] = '1';
  }
  params['gaia_source'] = 'pre-load';
  params['web_location'] = '1315873';
  let queryStr: string;
  try {
    queryStr = await AppSign.generateWebParams(params);
  } catch (_e) {
    logWarn(`[getPgcPlayUrl] WBI签名失败，使用未签名请求: ${_e}`);
    queryStr = `ep_id=${epId}&cid=${cid}&qn=${qn}&fnval=3536&fnver=0&fourk=1&try_look=1&gaia_source=pre-load&web_location=1315873`;
  }
  const url = `https://api.bilibili.com/pgc/player/web/v2/playurl?${queryStr}`;
  logInfo(`[PgcPlayUrl] 请求 ep_id=${epId} cid=${cid} qn=${qn} season_id=${seasonId}`);
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
        'Cookie': getCookieHeader()
      },
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode !== 200) {
      logError(`[getPgcPlayUrl] HTTP错误: ${response.responseCode}`);
      return { url: '', actualQn: 0, acceptQuality: [], acceptDescription: [] };
    }
    const jsonData: PgcPlayUrlResponse = JSON.parse(response.result as string);
    if (jsonData.code !== 0) {
      logWarn(`[getPgcPlayUrl] API错误: code=${jsonData.code}, message=${jsonData.message}`);
      return { url: '', actualQn: 0, acceptQuality: [], acceptDescription: [] };
    }
    const info = jsonData.result?.video_info;
    if (info === undefined) {
      logWarn('[getPgcPlayUrl] result.video_info 为空');
      return { url: '', actualQn: 0, acceptQuality: [], acceptDescription: [] };
    }
    const acceptQn: Array<number> = info.accept_quality ?? [];
    const acceptDesc: Array<string> = info.accept_description ?? [];
    // ⭐ 该集的服务端续播点（毫秒）：番剧/影视多集续播的关键——每集各有自己的进度
    const pgcProgressMs: number = jsonData.result?.play_view_business_info?.user_status?.watch_progress?.current_watch_progress ?? 0;
    if (pgcProgressMs > 0) {
      logInfo(`[getPgcPlayUrl] 该集续播点 ${pgcProgressMs}ms`);
    }
    // FLV 合并流（音视频一体，AVPlayer 原生支持）
    if (info.durl && info.durl.length === 1) {
      logInfo(`[getPgcPlayUrl] FLV qn=${info.quality}`);
      return { url: info.durl[0].url || '', actualQn: info.quality || 0, acceptQuality: acceptQn, acceptDescription: acceptDesc, lastPlayTimeMs: pgcProgressMs };
    }
    // DASH 分离流（视频轨 + 音频轨）
    if (info.dash?.video && info.dash.video.length > 0) {
      const videoList = info.dash.video;
      // ⭐ 优先选非 AV1 视频轨（设备解码器不支持 AV1：VID_DEC_ERR-unsupport video decoder type）
      const nonAv1 = videoList.filter((v: DashVideoItem) => v.codecid !== 13);
      const usableList = nonAv1.length > 0 ? nonAv1 : videoList;
      usableList.sort((a: DashVideoItem, b: DashVideoItem) => b.id - a.id);
      let audioUrl = '';
      if (info.dash.audio && info.dash.audio.length > 0) {
        const audioList = info.dash.audio;
        audioList.sort((a: DashAudioItem, b: DashAudioItem) => b.id - a.id);
        audioUrl = audioList[0].baseUrl || '';
      }
      logInfo(`[getPgcPlayUrl] DASH qn=${info.quality}, 视频码流=${usableList[0].codecid === 13 ? 'AV1' : (usableList[0].codecid === 12 ? 'HEVC' : 'AVC')}, 音频=${audioUrl ? '有' : '无'}`);
      let pgcDash: DashFullInfo | undefined;
      if (info.dash?.video && info.dash.video.length > 0 && info.dash.audio && info.dash.audio.length > 0) {
        const fullInfo: DashFullInfo = {
          videoStreams: info.dash.video,
          audioStreams: info.dash.audio,
          timelength: info.timelength || info.dash.timelength || 0,
          quality: info.quality || 0
        };
        pgcDash = fullInfo;
      }
      return normalizeDashQuality({ url: usableList[0].baseUrl || '', audioUrl: audioUrl, actualQn: info.quality || 0, acceptQuality: acceptQn, acceptDescription: acceptDesc, dash: pgcDash, lastPlayTimeMs: pgcProgressMs }, qn);
    }
    logError('[getPgcPlayUrl] 未找到任何可用流');
    return { url: '', actualQn: 0, acceptQuality: [], acceptDescription: [] };
  } catch (err) {
    logError(`[getPgcPlayUrl] 异常: ${err}`);
    return { url: '', actualQn: 0 };
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 获取番剧单集信息（按 ep_id）
 * 接口：/pgc/season/episode/web/info?ep_id=xxx
 * 用于 PGC 播放时 cid 缺失的兜底（搜索结果只带 mediaId，季信息里第一集通常含 cid）
 * @param epId 分集 ep_id
 * @returns 分集信息或 null（失败）
 */
export async function getPgcEpisodeInfo(epId: number): Promise<PgcEpisode | null> {
  const url = `https://api.bilibili.com/pgc/season/episode/web/info?ep_id=${epId}`;
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
        'Cookie': getCookieHeader()
      },
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode !== 200) {
      logError(`[getPgcEpisodeInfo] HTTP错误: ${response.responseCode}`);
      return null;
    }
    const jsonData: ApiResponse<PgcEpisode> = JSON.parse(response.result as string);
    if (jsonData.code !== 0) {
      logWarn(`[getPgcEpisodeInfo] API错误: code=${jsonData.code}, message=${jsonData.message}`);
      return null;
    }
    const ep = jsonData.data;
    if (ep === undefined || ep.id === undefined) {
      logWarn('[getPgcEpisodeInfo] data 为空');
      return null;
    }
    logInfo(`[getPgcEpisodeInfo] ep_id=${ep.id}, cid=${ep.cid}, title=${ep.title}`);
    return ep;
  } catch (err) {
    logError(`[getPgcEpisodeInfo] 异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 获取番剧季信息（含分集列表）
 * 接口：/pgc/view/web/season?season_id=xxx
 * 若 season_id 请求失败（-404，常见于拿到的是 media_id），回退 /pgc/view/web/media?media_id=xxx
 * @param seasonId 季 id 或媒资 id（搜索结果优先用 season_id，其他入口可能是 media_id）
 * @returns PgcSeasonInfo 或 null（失败）
 */
export async function getPgcSeasonInfo(seasonId: number): Promise<PgcSeasonInfo | null> {
  // 先按 season_id 查询
  let info: PgcSeasonInfo | null = await fetchPgcSeasonByPath('season', seasonId);
  // ⭐ 未开播季（如间谍过家家第三季）无正片时，fetchPgcSeasonByPath 已用 section（PV/预告）分集填充 episodes，
  // 因此这里直接返回该季的 PV，而不是跳到其他季
  if (info) {
    return info;
  }
  // ⭐ 回退：按 media_id 查询（/pgc/view/web/media 接口）
  logInfo(`[getPgcSeasonInfo] season_id 查询失败，回退 media_id=${seasonId}`);
  info = await fetchPgcSeasonByPath('media', seasonId);
  return info;
}

/**
 * 按 ep_id 查询所属季信息（/pgc/view/web/season?ep_id=xxx）
 * ⭐ 动态页番剧动态只有 ep_id（season_id=0）时用：季接口 ep_id 查询返回完整分集（episodes 含 cid）
 * @param epId 分集 id
 * @returns PgcSeasonInfo 或 null（失败）
 */
export async function getPgcSeasonInfoByEpId(epId: number): Promise<PgcSeasonInfo | null> {
  return await fetchPgcSeasonByPath('ep', epId);
}

/**
 * 解析 PGC 日期字符串为 Unix 时间戳（秒）
 * 支持 "2020-07-25" 与 "2020-07-25 10:00:00" 两种格式
 * @param dateStr 日期字符串
 * @returns 秒级时间戳；解析失败返回 0
 */
function parsePgcDateToTs(dateStr: string): number {
  if (!dateStr) return 0;
  const parts = dateStr.split(' ');
  const dateParts = parts[0].split('-');
  if (dateParts.length < 3) return 0;
  const y = parseInt(dateParts[0]);
  const m = parseInt(dateParts[1]);
  const d = parseInt(dateParts[2]);
  if (isNaN(y) || isNaN(m) || isNaN(d)) return 0;
  let h = 0, min = 0, s = 0;
  if (parts.length > 1) {
    const timeParts = parts[1].split(':');
    if (timeParts.length > 0) h = parseInt(timeParts[0]) || 0;
    if (timeParts.length > 1) min = parseInt(timeParts[1]) || 0;
    if (timeParts.length > 2) s = parseInt(timeParts[2]) || 0;
  }
  const ts = Date.UTC(y, m - 1, d, h, min, s);
  return isNaN(ts) ? 0 : Math.floor(ts / 1000);
}

/**
 * 按指定路径查询番剧季信息（season / media）
 * @param kind 'season' 用 season_id 查询；'media' 用 media_id 查询
 */
async function fetchPgcSeasonByPath(kind: string, id: number): Promise<PgcSeasonInfo | null> {
  // ⭐ kind: 'season' → ?season_id=、'media' → ?media_id=、'ep' → ?ep_id=（季接口支持 ep_id 查询，web 实证）
  let url: string = '';
  if (kind === 'media') {
    url = `https://api.bilibili.com/pgc/view/web/media?media_id=${id}`;
  } else if (kind === 'ep') {
    url = `https://api.bilibili.com/pgc/view/web/season?ep_id=${id}`;
  } else {
    url = `https://api.bilibili.com/pgc/view/web/season?season_id=${id}`;
  }
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
        'Cookie': getCookieHeader()
      },
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode !== 200) {
      logError(`[getPgcSeasonInfo(${kind})] HTTP错误: ${response.responseCode}`);
      return null;
    }
    const jsonData: PgcSeasonResponse = JSON.parse(response.result as string);
    if (jsonData.code !== 0) {
      logWarn(`[getPgcSeasonInfo(${kind})] API错误: code=${jsonData.code}, message=${jsonData.message}`);
      return null;
    }
    const result = jsonData.result;
    if (result === undefined) {
      logWarn(`[getPgcSeasonInfo(${kind})] result 为空`);
      return null;
    }
    // ⭐ 解析 stat（PGC 用复数字段：views=播放量, danmakus=弹幕, likes=点赞, coins=投币）
    const rawStat = result.stat;
    let parsedStat: PgcSeasonStat = { view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, reply: 0 };
    if (rawStat) {
      parsedStat = {
        view: rawStat.views || 0,
        danmaku: rawStat.danmakus || 0,
        like: rawStat.likes || 0,
        favorite: rawStat.favorite || 0,
        coin: rawStat.coins || 0,
        reply: rawStat.reply || 0
      };
    }
    // ⭐ 解析首播时间：publish_date 形如 "2020-07-25"，publish.pub_time 形如 "2020-07-25 10:00:00"
    let parsedPubdate = 0;
    const pubDateStr = (result.publish_date || '').trim();
    if (pubDateStr) {
      parsedPubdate = parsePgcDateToTs(pubDateStr);
    }
    if (parsedPubdate <= 0 && result.publish && result.publish.pub_time) {
      parsedPubdate = parsePgcDateToTs((result.publish.pub_time || '').trim());
    }
    // ⭐ 解析 up_info（制作方）
    let parsedUpInfo: PgcUpInfo = { mid: 0, uname: '', avatar: '' };
    if (result.up_info) {
      parsedUpInfo = {
        mid: result.up_info.mid || 0,
        uname: result.up_info.uname || '',
        avatar: result.up_info.avatar || ''
      };
    }
    // ⭐ 解析正片分集；未开播季正片为空时，回退到 section（PV/预告）的分集播放
    let parsedEpisodes: Array<PgcEpisode> = result.episodes || [];
    if (parsedEpisodes.length === 0 && result.section && result.section.length > 0) {
      const pvEps: Array<PgcEpisode> = [];
      for (let i = 0; i < result.section.length; i++) {
        const secEps = result.section[i].episodes || [];
        for (let j = 0; j < secEps.length; j++) {
          pvEps.push(secEps[j]);
        }
      }
      if (pvEps.length > 0) {
        parsedEpisodes = pvEps;
        logInfo(`[getPgcSeasonInfo(${kind})] 季 ${result.season_id || id}「${result.title || ''}」无正片，取 ${pvEps.length} 个 PV/预告分集`);
      }
    }
    const info: PgcSeasonInfo = {
      seasonId: result.season_id || id,
      title: result.title || '',
      cover: result.cover || '',
      desc: result.desc || '',
      pubdate: parsedPubdate,
      actors: result.actors || '',
      staff: result.staff || '',
      stat: parsedStat,
      upInfo: parsedUpInfo,
      episodes: parsedEpisodes,
      // ⭐ 关联季 id 列表（供未开播季回退查找）
      relatedSeasonIds: (result.seasons || [])
        .map((s: PgcSeasonBrief) => s.season_id || 0)
        .filter((sid: number) => sid > 0 && sid !== (result.season_id || id))
    };
    logInfo(`[getPgcSeasonInfo(${kind})] 季 ${info.seasonId}「${info.title}」共 ${info.episodes.length} 集, 播放=${info.stat.view}, 弹幕=${info.stat.danmaku}, 点赞=${info.stat.like}, 投币=${info.stat.coin}, 首播=${info.pubdate}, 制作方=${info.upInfo.uname}`);
    return info;
  } catch (err) {
    logError(`[getPgcSeasonInfo(${kind})] 异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

// ==================== 搜索视频 ====================
export async function searchVideos(
  keyword: string,
  page: number = 1,
  pageSize: number = 20
): Promise<RecommendItem[]> {
  const encodedKeyword = encodeURIComponent(keyword);
  const url = `https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=${encodedKeyword}&page=${page}&pagesize=${pageSize}`;
  try {
    const jsonData = await requestWithCookie<SearchListResponse>(url);
    if (jsonData.code !== 0) {
      logWarn(`搜索接口返回 code=${jsonData.code}`);
      return [];
    }
    const list = jsonData.data?.result;
    if (!list || list.length === 0) return [];

    const results: RecommendItem[] = [];
    for (const obj of list) {
      const item = new RecommendItem();
      item.id = obj.bvid as string;
      // 标题去除搜索高亮 HTML 标签（如 <em class="keyword">xxx</em>）
      item.title = (obj.title as string || '').replace(/<[^>]+>/g, '');
      const pic = obj.pic as string;
      item.coverUrl = pic ? (pic.startsWith('http') ? pic : `https:${pic}`) : '';
      // 搜索接口实际字段：play / video_review / author（无 stat/owner 嵌套对象）
      item.playCount = (obj.play as number) || 0;
      item.danmakuCount = (obj.video_review as number) || 0;
      item.ownerName = (obj.author as string) || '';
      item.pubdate = (obj.pubdate as number) || 0;

      // 尝试获取 cid
      let cidValue = obj.cid as number;
      if (!cidValue) {
        const pages = obj.pages;
        if (pages && pages.length > 0) {
          cidValue = pages[0].cid as number;
        }
      }
      item.cid = cidValue || 0;

      // 只要有 bvid 就加入列表，cid 可以在播放时动态获取
      if (item.id) {
        results.push(item);
      } else {
        logWarn(`搜索视频缺少 bvid`);
      }
    }
    logInfo(`搜索"[已省略]"返回 ${results.length} 条结果`);
    return results;
  } catch (err) {
    logError(`搜索请求异常: ${err}`);
    return [];
  }
}

/**
 * 解码 HTML 实体（如 &#x... 或 &amp; 等）
 */
function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&#x([0-9a-fA-F]+);/g, (_match: string, hex: string) => {
      return String.fromCodePoint(parseInt(hex, 16));
    })
    .replace(/&#(\d+);/g, (_match: string, code: string) => {
      return String.fromCodePoint(parseInt(code, 10));
    })
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

/**
 * 按类型搜索（通用搜索接口）
 * @param keyword 搜索关键词
 * @param searchType 搜索类型：video / live_user / media_bangumi / article
 * @param page 页码
 * @param pageSize 每页条数
 * @returns 转换后的 RecommendItem 数组
 */
export async function searchByType(
  keyword: string,
  searchType: string,
  page: number = 1,
  pageSize: number = 20,
  order: string = 'totalrank'
): Promise<RecommendItem[]> {
  const encodedKeyword = encodeURIComponent(keyword);
  // ⭐ 搜索接口现在需要 WBI 签名和完整请求头（否则返回 412）
  const params: Record<string, string> = {
    'search_type': searchType,
    'keyword': keyword,
    'page': page.toString(),
    'page_size': pageSize.toString()
  };
  // 视频类型支持排序参数，其他类型忽略
  if (searchType === 'video') {
    params['order'] = order;
  }
  let queryStr: string;
  try {
    queryStr = await AppSign.generateWebParams(params);
  } catch (_e) {
    logWarn(`[searchByType] WBI签名失败，使用未签名请求: ${_e}`);
    queryStr = `search_type=${searchType}&keyword=${encodedKeyword}&page=${page}&page_size=${pageSize}`;
  }
  const url = `https://api.bilibili.com/x/web-interface/wbi/search/type?${queryStr}`;
  const httpRequest = http.createHttp();
  try {
    const headers = getBiliRequestHeaders();
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: headers as Record<string, string | Object>,
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode !== 200) {
      throw new Error(`HTTP ${response.responseCode}`);
    }
    const result = response.result as string;
    const jsonData: ApiResponse<SearchListResponse> = JSON.parse(result);
    if (jsonData.code !== 0) {
      logWarn(`搜索接口(${searchType})返回 code=${jsonData.code}`);
      // 部分类型可能 data.result 不存在，返回空不算失败
    }
    const list = jsonData.data?.result as SearchResultItem[] | undefined;
    if (!list || list.length === 0) {
      logInfo(`搜索"[已省略]"（${searchType}）无结果`);
      return [];
    }

    const results: RecommendItem[] = [];
    for (const obj of list) {
      const item = new RecommendItem();
      // 统一处理：不同类型使用不同的 id 字段
      if (searchType === 'live_user') {
        item.id = obj.roomid ? `live_${obj.roomid}` : '';
        // uname 包含 HTML 高亮标签 + 实体，先清标签再解码
        item.ownerName = decodeHtmlEntities((obj.uname as string || '').replace(/<[^>]+>/g, ''));
        // face 可能是协议相对 URL（//i0.hdslb.net/...）
        const faceUrl = (obj.uface as string) || (obj.face as string) || '';
        item.ownerFace = faceUrl.startsWith('//') ? `https:${faceUrl}` : faceUrl;
        // 直播封面字段：优先实时截图
        const liveCover = (obj.room_screenshot as string) || (obj.keyframe as string) || (obj.cover as string) || (obj.user_cover as string) || '';
        item.coverUrl = liveCover ? (liveCover.startsWith('//') ? `https:${liveCover}` : liveCover.startsWith('http') ? liveCover : `https:${liveCover}`) : '';
        // 用 pubdate 存 live_status（1=直播中）
        item.pubdate = (obj.live_status as number) || 0;
        item.online = (obj.online as number) || 0;
        // 标题去除搜索高亮 HTML 标签并解码实体
        item.title = decodeHtmlEntities((obj.title as string || '').replace(/<[^>]+>/g, ''));
      } else if (searchType === 'media_bangumi' || searchType === 'media_ft') {
        // ⭐ 影视（media_ft）与番剧（media_bangumi）同属 PGC 媒资，字段结构一致
        // ⭐ 用 season_id 优先：/pgc/view/web/season 接口只认 season_id，media_id 会返回 -404
        const bangumiSeasonId = (obj.season_id as number) || (obj.media_id as number) || 0;
        item.id = bangumiSeasonId > 0 ? `media_${bangumiSeasonId}` : '';
        // 番剧/影视搜索结果无 author 字段，用 season_type_name（国创/番剧/电影等）作为主标签
        item.ownerName = (obj.season_type_name as string) || (obj.author as string) || '';
        // 标题去除搜索高亮 HTML 标签
        item.title = (obj.title as string || '').replace(/<[^>]+>/g, '');
        // 封面图：pic 或 cover
        const picUrl = (obj.pic as string) || (obj.cover as string) || '';
        item.coverUrl = picUrl ? (picUrl.startsWith('http') ? picUrl : `https:${picUrl}`) : '';
        item.pubdate = (obj.pubdate as number) || (obj.pubtime as number) || 0;
        // ⭐ 番剧/影视搜索无 play 播放量字段：集数/评分存专用字段，卡片上显示「N集 / X分」
        item.pgcEpSize = (obj.ep_size as number) || 0;
        if (obj.media_score) {
          const ms = obj.media_score;
          item.pgcScore = ms.score || 0; // 评分（如 9.6）
        }
        // 记录最新分集 ep_id（播放时可优先直接取流）
        if (obj.ep_id) {
          item.cid = obj.ep_id as number; // ⭐ 复用 cid 字段暂存 ep_id（播放页按 isPgc 分支读取）
        }
      } else if (searchType === 'article') {
        item.id = obj.id ? `article_${obj.id}` : '';
        item.ownerName = (obj.author as string) || '';
        item.playCount = (obj.view as number) || 0;
        // 标题去除搜索高亮 HTML 标签
        item.title = (obj.title as string || '').replace(/<[^>]+>/g, '');
        // 封面图：取 images 数组第一张或 pic
        const articlePic = (obj.pic as string) || ((obj.images as string[]) || [])[0] || '';
        item.coverUrl = articlePic ? (articlePic.startsWith('http') ? articlePic : `https:${articlePic}`) : '';
        item.pubdate = (obj.pubdate as number) || 0;
      } else if (searchType === 'bili_user') {
        item.id = obj.mid ? `user_${obj.mid}` : '';
        // uname 可能包含 HTML 实体
        item.ownerName = decodeHtmlEntities((obj.uname as string) || '');
        // upic 可能无协议前缀（//i0.hdslb.com/...）
        const upicUrl = (obj.upic as string) || '';
        item.ownerFace = upicUrl.startsWith('//') ? `https:${upicUrl}` : upicUrl;
        item.ownerMid = (obj.mid as number)?.toString() || '';
        item.title = (obj.usign as string || '').replace(/<[^>]+>/g, '');
        item.playCount = (obj.fans as number) || 0;
        item.danmakuCount = (obj.videos as number) || 0;
        item.pubdate = 0; // 用户无时间概念
        // B站搜索API自带 is_followed 字段（0=未关注, 1=已关注）
        item.isFollowed = (obj.is_followed as number) === 1;
      } else {
        // video 类型
        item.id = obj.bvid as string;
        item.ownerName = decodeHtmlEntities((obj.author as string) || '');
        item.playCount = (obj.play as number) || 0;
        item.danmakuCount = (obj.video_review as number) || 0;
        item.cid = (obj.cid as number) || 0;
        item.title = (obj.title as string || '').replace(/<[^>]+>/g, '');
        const vPic = (obj.pic as string) || '';
        item.coverUrl = vPic ? (vPic.startsWith('http') ? vPic : `https:${vPic}`) : '';
        item.pubdate = (obj.pubdate as number) || 0;
      }

      if (item.id) {
        results.push(item);
      }
    }
    logInfo(`搜索"[已省略]"（${searchType}）返回 ${results.length} 条结果`);
    return results;
  } catch (err) {
    logError(`搜索请求异常(${searchType}): ${err}`);
    return [];
  }
}

// ==================== 专用直播搜索（使用 live 子域名 API，返回数据含封面图） ====================
interface LiveSearchItem {
  roomid?: number;
  uid?: number;
  uname?: string;
  face?: string;
  cover?: string;
  title?: string;
  live_status?: number;
  online?: number;
  keyframe?: string;
  user_cover?: string;
  tags?: string;
  area_name?: string;
  parent_area_name?: string;
}

interface LiveSearchData {
  list?: LiveSearchItem[];
}

export async function searchLive(
  keyword: string,
  page: number = 1,
  pageSize: number = 20
): Promise<RecommendItem[]> {
  await doThrottle(1000, 'searchLive');
  // 使用 Web WBI 签名接口搜索直播间（无需 access_key，只需要 Cookie）
  const params: Record<string, string> = {} as Record<string, string>;
  params.search_type = 'live_room';
  params.keyword = keyword;
  params.page = page.toString();
  params.page_size = pageSize.toString();
  let queryStr: string;
  try {
    queryStr = await AppSign.generateWebParams(params);
  } catch (_e) {
    logWarn(`[searchLive] WBI签名失败，使用未签名请求: ${_e}`);
    queryStr = `search_type=live_room&keyword=${encodeURIComponent(keyword)}&page=${page}&page_size=${pageSize}`;
  }
  const url = `https://api.bilibili.com/x/web-interface/wbi/search/type?${queryStr}`;
  const httpRequest = http.createHttp();
  try {
    const headers = getBiliRequestHeaders();
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: headers as Record<string, string | Object>,
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode !== 200) {
      logWarn(`[searchLive] HTTP ${response.responseCode}`);
      return [];
    }
    const result = response.result as string;
    // 使用 SearchListResponse 解析（与 searchByType 共用）
    const jsonData: ApiResponse<SearchListResponse> = JSON.parse(result);
    if (jsonData.code !== 0) {
      logWarn(`[searchLive] code=${jsonData.code}`);
      return [];
    }
    const list = jsonData.data?.result as SearchResultItem[] | undefined;
    if (!list || list.length === 0) {
      logInfo(`[searchLive] "[已省略]" 无直播结果`);
      return [];
    }

    const results: RecommendItem[] = [];
    for (const obj of list) {
      const item = new RecommendItem();
      item.id = obj.roomid ? `live_${obj.roomid}` : '';
      item.ownerName = decodeHtmlEntities((obj.uname as string || '').replace(/<[^>]+>/g, ''));
      const faceUrl = (obj.uface as string) || (obj.face as string) || '';
      item.ownerFace = faceUrl.startsWith('//') ? `https:${faceUrl}` : faceUrl;
      // 封面优先 room_screenshot（实时截图），其次 keyframe，再次静态 cover
      const liveCover = (obj.room_screenshot as string) || (obj.keyframe as string) || (obj.cover as string) || (obj.user_cover as string) || '';
      item.coverUrl = liveCover ? (liveCover.startsWith('//') ? `https:${liveCover}` : liveCover.startsWith('http') ? liveCover : `https:${liveCover}`) : '';
      item.pubdate = (obj.live_status as number) || 0;
      item.online = (obj.online as number) || 0;
      item.title = decodeHtmlEntities((obj.title as string || '').replace(/<[^>]+>/g, ''));
      item.ownerMid = (obj.mid as number)?.toString() || '';
      if (item.id) {
        results.push(item);
      }
    }
    logInfo(`[searchLive] "[已省略]" 返回 ${results.length} 条`);
    return results;
  } catch (err) {
    logError(`[searchLive] 请求异常: ${err}`);
    return [];
  } finally {
    httpRequest.destroy();
  }
}

// ==================== Web 版直播搜索（无需 access_key，用桌面端 Cookie 即可） ====================
interface LiveWebSearchItem {
  roomid?: number;
  uid?: number;
  uname?: string;
  face?: string;
  title?: string;
  cover?: string;
  live_status?: number;
  online?: number;
  tags?: string;
  area_name?: string;
  parent_area_name?: string;
  keyframe?: string;
  user_cover?: string;
}

interface LiveWebSearchData {
  list?: LiveWebSearchItem[];
  num?: number;
}

export async function searchLiveWeb(
  keyword: string,
  page: number = 1,
  pageSize: number = 20
): Promise<RecommendItem[]> {
  await doThrottle(1000, 'searchLiveWeb');
  const encodedKeyword = encodeURIComponent(keyword);
  // Web 直播搜索接口，用桌面端请求头即可
  const url = `https://api.live.bilibili.com/xlive/web-interface/v1/search?key=${encodedKeyword}&page=${page}&page_size=${pageSize}`;
  const httpRequest = http.createHttp();
  try {
    const headers = getBiliRequestHeaders();
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: headers as Record<string, string | Object>,
      connectTimeout: 10000,
      readTimeout: 10000,
    });
    if (response.responseCode !== 200) {
      logWarn(`[searchLiveWeb] HTTP ${response.responseCode}`);
      return [];
    }
    const result = response.result as string;
    const jsonData: ApiResponse<LiveWebSearchData> = JSON.parse(result);
    if (jsonData.code !== 0) {
      logWarn(`[searchLiveWeb] code=${jsonData.code}`);
      return [];
    }
    const list = jsonData.data?.list;
    if (!list || list.length === 0) {
      logInfo(`[searchLiveWeb] "[已省略]" 无直播结果`);
      return [];
    }

    const results: RecommendItem[] = [];
    for (const obj of list) {
      const item = new RecommendItem();
      item.id = obj.roomid ? `live_${obj.roomid}` : '';
      item.ownerName = decodeHtmlEntities((obj.uname || '').replace(/<[^>]+>/g, ''));
      const faceUrl = obj.face || '';
      item.ownerFace = faceUrl.startsWith('//') ? `https:${faceUrl}` : faceUrl;
      const coverUrl = (obj.cover || obj.keyframe || obj.user_cover || '');
      item.coverUrl = coverUrl.startsWith('//') ? `https:${coverUrl}` : coverUrl.startsWith('http') ? coverUrl : coverUrl ? `https:${coverUrl}` : '';
      item.pubdate = obj.live_status || 0;
      item.title = decodeHtmlEntities((obj.title || '').replace(/<[^>]+>/g, ''));
      results.push(item);
    }
    logInfo(`[searchLiveWeb] "[已省略]" 返回 ${results.length} 条`);
    return results;
  } catch (err) {
    logError(`[searchLiveWeb] 请求异常: ${err}`);
    return [];
  } finally {
    httpRequest.destroy();
  }
}

// ==================== 获取视频详细信息（使用原生http，避免泛型错误） ====================
export async function getVideoInfo(bvid: string): Promise<RecommendItem | null> {
  const url = `https://api.bilibili.com/x/web-interface/view?bvid=${bvid}`;
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Cookie': getCookieHeader()
      },
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode !== 200) {
      logError(`获取视频信息 HTTP 错误: ${response.responseCode}`);
      return null;
    }
    const result = response.result as string;
    const jsonData = JSON.parse(result) as Record<string, ESObject>;
    if (jsonData['code'] !== 0) {
      logWarn(`获取视频信息失败: code=${jsonData['code']}`);
      return null;
    }
    const data = jsonData['data'] as Record<string, ESObject>;
    if (data && data['cid']) {
      const item = new RecommendItem();
      item.id = bvid;
      item.cid = data['cid'] as number;
      item.title = data['title'] as string;
      item.coverUrl = data['pic'] as string;
      return item;
    }
    return null;
  } catch (err) {
    logError(`获取视频信息异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 使用移动端API获取播放地址（支持1080P+）
 * 参考PiliPlus的实现，使用AppSign签名




// ==================== 扫码登录 API ====================

/** 生成二维码响应 */
interface QrCodeGenerateResult {
  url: string;
  qrcode_key: string;
  _cookies?: string;  // generate 阶段返回的初始 Cookie（内部使用）
}

/**
 * 生成登录二维码
 * 返回 qrcode_key（用于轮询）、url（二维码内容）和初始Cookie
 */
export async function generateLoginQrCode(): Promise<QrCodeGenerateResult | null> {
  const url = 'https://passport.bilibili.com/x/passport-login/web/qrcode/generate';
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/'
      },
      connectTimeout: 10000,
      readTimeout: 10000
    });

    if (response.responseCode !== 200) {
      logError(`生成二维码HTTP错误: ${response.responseCode}`);
      return null;
    }

    const jsonData: ApiResponse<QrCodeGenerateResult> = JSON.parse(response.result as string);
    if (jsonData.code !== 0 || !jsonData.data) {
      logError(`生成二维码API错误: code=${jsonData.code}, message=${jsonData.message}`);
      return null;
    }

    // 保存 generate 阶段返回的初始 Cookie（用于后续 poll 请求携带）
    const initialCookies = loginCookiesFromResponse(response.cookies, response.header as Record<string, Object>);
    jsonData.data._cookies = initialCookies;

    logInfo('二维码生成成功');
    return jsonData.data;
  } catch (err) {
    logError(`生成二维码异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}



/**
 * 生成Trace ID（用于请求追踪）
 */




/** 轮询状态码含义 */
export enum QrCodeStatus {
  ERROR = -1,           // 服务端拒绝或登录响应不完整
  SUCCESS = 0,          // 登录成功
  EXPIRED = 86038,      // 二维码已过期
  NOT_SCANNED = 86101,  // 未扫码
  SCANNED = 86090       // 已扫码，等待确认
}

/** 轮询结果 */
export interface QrCodePollResult {
  status: QrCodeStatus;
  cookies: string;       // 登录成功后提取的完整Cookie字符串
  accessKey?: string;    // 登录成功后提取的移动端 access_key
  message?: string;
}

/**
 * 轮询扫码登录状态
 * @param qrcodeKey 生成二维码时返回的 key
 * @param initialCookies generate 阶段返回的初始 Cookie（用于保持会话）
 */
export async function pollQrCodeStatusApi(qrcodeKey: string, initialCookies: string = ''): Promise<QrCodePollResult> {
  const pollUrl = `https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=${encodeURIComponent(qrcodeKey)}`;
  const httpRequest = http.createHttp();
  try {
    // 构建请求头，携带初始 Cookie 以保持服务端会话
    const reqHeader: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Referer': 'https://www.bilibili.com/'
    };
    if (initialCookies) {
      reqHeader['Cookie'] = mergeLoginCookies([initialCookies]);
    }

    const response = await httpRequest.request(pollUrl, {
      method: http.RequestMethod.GET,
      header: reqHeader,
      connectTimeout: 8000,
      readTimeout: 8000
    });

    if (response.responseCode !== 200) {
      return { status: QrCodeStatus.NOT_SCANNED, cookies: '' };
    }

    const jsonData = JSON.parse(response.result as string) as ApiResponse<Object>;
    const dataObj = jsonData.data as Record<string, Object>;

    // 真正的扫码状态码在 data.code 中，而非外层的 jsonData.code
    // 外层 code=0 仅表示 API 调用成功，data.code 才是扫码状态：
    //   0     = 登录成功（此时 data.url 携带跨域跳转链接，内含 Cookie）
    //   86090 = 已扫码，等待手机确认
    //   86101 = 未扫码
    //   86038 = 二维码已过期
    const scanCode: number = (dataObj && typeof dataObj['code'] === 'number') ? dataObj['code'] as number : QrCodeStatus.NOT_SCANNED;

    logInfo(`[QR登录] 扫码状态: ${scanCode}`);

    // 只有 data.code === 0 才是真正的登录成功
    if (scanCode === QrCodeStatus.SUCCESS) {
      let cookies = '';
      let accessKey = '';

      // 获取 data.url（跨域跳转链接）
      const redirectUrl: string = (dataObj && dataObj['url'] as string) || '';

      // 提取 access_key（移动端 API 凭证）
      if (redirectUrl) {
        const akMatch = redirectUrl.match(/[?&]access_key=([^&]+)/);
        if (akMatch && akMatch[1]) {
          accessKey = decodeURIComponent(akMatch[1]);
        } else {
          logInfo('[QR登录] redirectUrl中未找到access_key参数');
        }
      }

      // 方式1：从 data.url 的 query 参数中提取 Cookie
      if (redirectUrl) {
        cookies = parseCookiesFromUrl(redirectUrl);
      }

      // 方式2：请求 crossDomain 链接获取 Set-Cookie
      cookies = mergeLoginCookies([initialCookies, cookies,
        loginCookiesFromResponse(response.cookies, response.header as Record<string, Object>)]);
      if (!hasLoginSession(cookies) && redirectUrl) {
        try {
          logInfo(`[QR登录] 尝试请求crossDomain链接...`);
          cookies = mergeLoginCookies([cookies, await fetchCookiesFromCrossDomain(redirectUrl, cookies)]);
        } catch (e) {
          logWarn(`crossDomain请求失败: ${e}`);
        }
      }

      logInfo(`[QR登录] Cookie长度=${cookies.length}, 有会话=${hasLoginSession(cookies)}`);
      return { status: QrCodeStatus.SUCCESS, cookies, accessKey };
    }

    logInfo(`[QR登录] 扫码状态: code=${scanCode}, message=${(dataObj && dataObj['message']) || ''}`);
    return { status: scanCode as QrCodeStatus, cookies: '' };
  } catch (err) {
    logError(`轮询扫码状态异常: ${err}`);
    return { status: QrCodeStatus.NOT_SCANNED, cookies: '' };
  } finally {
    httpRequest.destroy();
  }
}



// ======================== TV端二维码登录（返回access_key） ========================

interface TvQrGenerateResult {
  url: string;
  auth_code: string;
}

/**
 * 生成TV端登录二维码
 * TV端登录使用 /x/passport-tv-login/qrcode/auth_code
 * 返回含有 auth_code 的二维码 URL，扫码成功后直接返回 access_token（即 access_key）
 */
export async function generateTvLoginQrCode(): Promise<QrCodeGenerateResult | null> {
  // TV端生成二维码需 POST 请求，参数在 body 中（不拼接在 URL 上）
  const bodyParams: Record<string, string> = {} as Record<string, string>;
  bodyParams['local_id'] = '0';
  bodyParams['platform'] = 'android';
  bodyParams['mobi_app'] = 'android_hd';
  bodyParams['ts'] = String(Math.floor(Date.now() / 1000));
  await AppSign.signParams(bodyParams, 'android_hd');
  const formBody = Object.keys(bodyParams).map(key => `${key}=${encodeURIComponent(bodyParams[key])}`).join('&');
  const url = 'https://passport.bilibili.com/x/passport-tv-login/qrcode/auth_code';
  logInfo('[TV-QR] 请求登录接口');
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(
      url,
      {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.135 Mobile Safari/537.36'
        },
        extraData: formBody,
        connectTimeout: 10000,
        readTimeout: 10000
      }
    );
    if (response.responseCode !== 200) {
      logError(`[TV-QR] 生成HTTP错误: ${response.responseCode}`);
      return null;
    }
    const jsonData: ApiResponse<TvQrGenerateResult> = JSON.parse(response.result as string);
    if (jsonData.code !== 0 || !jsonData.data) {
      logError(`[TV-QR] 生成API错误: code=${jsonData.code}, msg=${jsonData.message || ''}`);
      return null;
    }
    const authCode: string = jsonData.data.auth_code;
    const qrUrl: string = jsonData.data.url;
    logInfo('[TV-QR] 二维码生成成功');
    return {
      url: qrUrl,
      qrcode_key: authCode // 复用 qrcode_key 存储 auth_code
    };
  } catch (err) {
    logError(`[TV-QR] 生成异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 轮询TV端扫码登录状态
 * 登录成功后直接返回 access_token，同时响应头会设置 SESSDATA cookie
 */
export async function pollTvQrCodeStatusApi(authCode: string): Promise<QrCodePollResult> {
  const params: Record<string, string> = {} as Record<string, string>;
  params['auth_code'] = authCode;
  params['local_id'] = '0';
  params['ts'] = String(Math.floor(Date.now() / 1000));
  // TV端轮询也使用android_hd appkey（保持一致，确保access_key兼容）
  await AppSign.signParams(params, 'android_hd');
  const body = Object.keys(params).map(key => `${key}=${encodeURIComponent(params[key])}`).join('&');
  const url = 'https://passport.bilibili.com/x/passport-tv-login/qrcode/poll';
  logInfo('[TV-QR] 请求登录接口');
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(
      url,
      {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.135 Mobile Safari/537.36'
        },
        extraData: body,
        connectTimeout: 8000,
        readTimeout: 8000
      }
    );
    if (response.responseCode !== 200) {
      logError(`[TV-QR] 轮询HTTP错误: ${response.responseCode}`);
      return { status: QrCodeStatus.NOT_SCANNED, cookies: '' };
    }
    const rawBody = response.result as string;
    const jsonData = JSON.parse(rawBody) as ApiResponse<Record<string, Object>>;

    // B站 TV 端轮询 API 返回格式: {"code": 状态码, "data": {..."}}
    //   code=0        → 登录成功，data.access_token 存在
    //   code=86090    → 已扫码待确认
    //   code=86101    → 未扫码
    //   code=86038    → 二维码已过期
    const scanCode: number = jsonData.code;

    if (scanCode === 0) {
      // 登录成功!
      const dataObj = jsonData.data;
      const tokenInfo = dataObj?.['token_info'] as Record<string, Object> | undefined;
      const rawAccessToken = dataObj?.['access_token'] || tokenInfo?.['access_token'];
      const accessToken: string = typeof rawAccessToken === 'string' ? rawAccessToken.trim() : '';
      if (!accessToken) {
        logError(`[TV-QR] 登录成功但无access_token`);
        return { status: QrCodeStatus.ERROR, cookies: '', message: 'TV 授权响应缺少客户端令牌，请重新获取二维码' };
      }
      logInfo('[TV-QR] 扫码已确认，收到用户令牌');

      // 从 data.cookie_info.cookies 提取 Cookie（TV端 API 返回格式）
      // 格式: {"cookie_info":{"cookies":[{"name":"SESSDATA","value":"xxx"},...]}}
      let responseCookies: string = loginCookiesFromResponse(response.cookies, response.header as Record<string, Object>);
      if (dataObj) {
        const cookieInfo: Record<string, Object> = dataObj['cookie_info'] as Record<string, Object>;
        if (cookieInfo) {
          const cookies: Object[] = cookieInfo['cookies'] as Object[];
          if (cookies && cookies.length > 0) {
            const parts: string[] = [];
            for (let i: number = 0; i < cookies.length; i++) {
              const c = cookies[i] as Record<string, Object>;
              const name: string = c['name'] as string || '';
              const value: string = c['value'] as string || '';
              if (name && value) {
                parts.push(`${name}=${value}`);
              }
            }
            if (parts.length > 0) {
              responseCookies = mergeLoginCookies([responseCookies, parts.join('; ')]);
              logInfo(`[TV-QR] 从cookie_info提取Cookie成功，长度=${responseCookies.length}`);
            }
          }
        }
      }

      // ⚠️ TV 登录的 cookie_info 通常只有 SESSDATA 而没有 bili_jct（Web CSRF 校验必需），
      //    bili_jct 只出现在 data.url 的 crossDomain 参数里——必须合并进 Cookie，
      //    否则上传图片等 Web 接口全部 -111「CSRF 校验失败」且重登无效
      if (dataObj) {
        const tvUrl: string = (dataObj['url'] as string) || '';
        if (tvUrl) {
          const urlCookies: string = parseCookiesFromUrl(tvUrl);
          if (urlCookies) {
            const existingNames: string[] = responseCookies.split(';')
              .map((s: string): string => s.trim().split('=')[0]);
            const merged: string[] = responseCookies ? [responseCookies] : [];
            for (const part of urlCookies.split(';')) {
              const name: string = part.trim().split('=')[0];
              if (name && existingNames.indexOf(name) < 0) {
                merged.push(part.trim());
              }
            }
            responseCookies = merged.join('; ');
            logInfo(`[TV-QR] 合并url中的Cookie字段，含bili_jct=${responseCookies.indexOf('bili_jct') >= 0}`);
          }
        }
      }
      return {
        status: QrCodeStatus.SUCCESS,
        cookies: responseCookies,
        accessKey: accessToken
      };
    }
    const tvStatusMap: Record<number, QrCodeStatus> = {
      86039: QrCodeStatus.NOT_SCANNED, // 新版API"未扫码"
      86090: QrCodeStatus.SCANNED,
      86101: QrCodeStatus.NOT_SCANNED, // 旧版API"未扫码"
      86038: QrCodeStatus.EXPIRED
    };
    if (tvStatusMap[scanCode] === undefined) {
      logWarn(`[TV-QR] 授权被拒绝: code=${scanCode}, message=${jsonData.message || ''}`);
      return { status: QrCodeStatus.ERROR, cookies: '', message: `TV 授权失败：${jsonData.message || '服务器拒绝'}（${scanCode}）` };
    }
    return {
      status: tvStatusMap[scanCode] ?? QrCodeStatus.NOT_SCANNED,
      cookies: ''
    };
  } catch (err) {
    logError(`[TV-QR] 轮询异常: ${err}`);
    return { status: QrCodeStatus.NOT_SCANNED, cookies: '' };
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 从已有的 Cookie 会话中获取 access_key（移动端 API 凭证）
 * 使用 /x/passport-login/web/sso/list 接口，从返回的 SSO URL 中提取 access_key
 * 适用于已通过 Web 方式登录（有 SESSDATA）但没有 access_key 的用户
 * @returns 成功返回 access_key，失败返回空字符串
 */
export async function refreshAccessKeyFromCookie(): Promise<string> {
  try {
    const cookie = AppStorage.get<string>('biliCookie') || '';
    if (!cookie || !cookie.includes('SESSDATA')) {
      logWarn('[AccessKey] 没有有效的 Cookie（缺少SESSDATA），无法获取 access_key');
      return '';
    }

    const url = 'https://passport.bilibili.com/x/passport-login/web/sso/list';
    const httpRequest = http.createHttp();
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Cookie': cookie,
        'Referer': 'https://www.bilibili.com/'
      },
      connectTimeout: 8000,
      readTimeout: 8000
    });
    httpRequest.destroy();

    // A delayed SSO response must not restore credentials after logout or an account switch.
    if (cookie !== (AppStorage.get<string>('biliCookie') || '')) return '';

    if (response.responseCode !== 200) {
      logWarn(`[AccessKey] SSO请求失败: HTTP ${response.responseCode}`);
      return '';
    }

    const jsonData = JSON.parse(response.result as string) as ApiResponse<Object>;
    if (jsonData.code !== 0) {
      logWarn(`[AccessKey] SSO返回错误: code=${jsonData.code}`);
      return '';
    }

    const dataObj = jsonData.data as Record<string, Object>;
    const ssoList: string[] = (dataObj['sso'] as string[]) || [];

    for (const ssoUrl of ssoList) {
      const akMatch = ssoUrl.match(/[?&]access_key=([^&]+)/);
      if (akMatch && akMatch[1]) {
        const accessKey: string = decodeURIComponent(akMatch[1]);
        logInfo('[AccessKey] 已获取移动端凭据');
        AppStorage.setOrCreate('biliAccessKey', accessKey);
        return accessKey;
      }
    }

    logWarn('[AccessKey] SSO URL中未找到access_key参数');
    return '';
  } catch (err) {
    logError(`[AccessKey] 获取失败: ${err}`);
    return '';
  }
}

/**
 * 生成Trace ID（用于请求追踪）
 */



/**
 * 请求 crossDomain 链接以获取服务器 Set-Cookie（终极兜底）
 */
async function fetchCookiesFromCrossDomain(url: string, initialCookies: string = ''): Promise<string> {
  let current = url;
  let cookies = mergeLoginCookies([initialCookies]);
  // Follow explicitly so intermediate Set-Cookie headers are not discarded by
  // the native client's automatic redirects. Validate every hop before sending.
  for (let hop = 0; hop < 5; hop++) {
    if (!isLoginRedirectUrl(current)) throw new Error('登录跳转地址不可信');
    const request = http.createHttp();
    try {
      const response = await request.request(current, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.bilibili.com/',
          'Cookie': cookies
        },
        maxRedirects: 0,
        connectTimeout: 10000,
        readTimeout: 10000
      });
      const headers = response.header as Record<string, Object>;
      cookies = mergeLoginCookies([cookies, loginCookiesFromResponse(response.cookies, headers)]);
      if (response.responseCode < 300 || response.responseCode >= 400) return cookies;
      const location = loginHeaderValues(headers, 'location')[0] || '';
      if (!location) return cookies;
      current = resolveLoginRedirect(current, location);
      if (!isLoginRedirectUrl(current)) {
        if (hasLoginSession(cookies)) return cookies;
        throw new Error('登录跳转地址不可信');
      }
      cookies = mergeLoginCookies([cookies, parseCookiesFromUrl(current)]);
    } finally { request.destroy(); }
  }
  return cookies;
}

/** Every failure returns a fresh unusable result. */
function emptyPlayUrlResult(): FetchPlayUrlResult {
  return { durlUrl: '', dashVideoUrl: '', dashAudioUrl: '', actualQn: 0,
    acceptQuality: [], acceptDescription: [], dashInfo: null };
}

/** App JSON uses snake_case; the bridge consumes one normalized stream model. */
function normalizeDashWireFields(dash?: DashData): void {
  dash?.video?.forEach((video: DashVideoItem) => {
    video.baseUrl = video.baseUrl || video.base_url || '';
    video.backupUrl = video.backupUrl || video.backup_url;
    video.frameRate = video.frameRate || video.frame_rate;
    video.startWithSap = video.startWithSap ?? video.start_with_sap;
    video.contentLength = video.contentLength ?? video.content_length;
  });
  dash?.audio?.forEach((audio: DashAudioItem) => {
    audio.baseUrl = audio.baseUrl || audio.base_url || '';
    audio.backupUrl = audio.backupUrl || audio.backup_url;
    audio.contentLength = audio.contentLength ?? audio.content_length;
  });
}

/** Shared response parsing for the signed App and compatible Web endpoints. */
async function fetchPlayUrlEndpoint(url: string, headers: Record<string, string>, profile: PlaybackSpan | null,
  sessionCookie: string, qn: number, fnval: number, probe?: LastPlayTimeProbe): Promise<FetchPlayUrlResult> {
  const httpRequest = http.createHttp();
  try {
    profile?.mark('http-start');
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET, header: headers, connectTimeout: 10000, readTimeout: 10000
    });
    profile?.network(response);
    if (sessionCookie !== (AppStorage.get<string>('biliCookie') || '')) return emptyPlayUrlResult();
    if (response.responseCode !== 200) return emptyPlayUrlResult();
      const jsonData: PlayUrlResponse = JSON.parse(response.result as string);
      profile?.mark('api-code', jsonData.code);
      if (jsonData.code !== 0) {
        logWarn(`tryFetchPlayUrlMobile API错误: code=${jsonData.code}, message=${jsonData.message}, qn=${qn}, fnval=${fnval}`);
        return { durlUrl: '', dashVideoUrl: '', dashAudioUrl: '', actualQn: 0, acceptQuality: [], acceptDescription: [], dashInfo: null };
      }

      if (probe && (jsonData.data?.last_play_time || 0) > 0) probe.ms = jsonData.data!.last_play_time!;
      // 日志：B站实际返回的画质信息
      const acceptQn = jsonData.data?.accept_quality as Array<number> | undefined;
      const acceptDesc = jsonData.data?.accept_description as Array<string> | undefined;
      const actualQn = jsonData.data?.quality as number | undefined;
      logInfo(`[MobileAPI] 请求qn=${qn}, 实际qn=${actualQn}, 可用画质列表=${JSON.stringify(acceptQn)}, 描述=${JSON.stringify(acceptDesc)}`);

      let durlUrl = '';
      let dashVideoUrl = '';
      let dashAudioUrl = '';
      let dashInfo: DashFullInfo | null = null;
      const dashRaw = jsonData.data?.dash;
      normalizeDashWireFields(dashRaw);

      // FLV 流（音视频合并）
      if (jsonData.data?.durl && jsonData.data.durl.length === 1) {
        durlUrl = jsonData.data.durl[0].url || '';
      }

      // DASH 流（视频+音频分离）
      if (dashRaw?.video && dashRaw.video.length > 0) {
        const videoList = dashRaw.video;
        // ⭐ 优先选非 AV1 视频轨（设备解码器不支持 AV1）
        const nonAv1 = videoList.filter((v: DashVideoItem) => v.codecid !== 13);
        const usableList = nonAv1.length > 0 ? nonAv1 : videoList;
        usableList.sort((a: DashVideoItem, b: DashVideoItem) => b.id - a.id);
        dashVideoUrl = usableList[0].baseUrl || '';
      }
      if (dashRaw?.audio && dashRaw.audio.length > 0) {
        const audioList = dashRaw.audio;
        audioList.sort((a, b) => b.id - a.id);
        dashAudioUrl = audioList[0].baseUrl || '';
      }
      if (dashRaw?.video && dashRaw.video.length > 0 && dashRaw.audio && dashRaw.audio.length > 0) {
        const info: DashFullInfo = {
          videoStreams: dashRaw.video,
          audioStreams: dashRaw.audio,
          timelength: jsonData.data?.timelength || dashRaw.timelength || 0,
          quality: actualQn || 0
        };
        dashInfo = info;
      }

      return { durlUrl, dashVideoUrl, dashAudioUrl, actualQn: actualQn ?? 0, acceptQuality: acceptQn ?? [], acceptDescription: acceptDesc ?? [], dashInfo: dashInfo,
        route: url.startsWith('https://app.bilibili.com/') ? 'app-hd' : 'web-compat' };
  } finally { httpRequest.destroy(); }
}

/** Signed HD App endpoint; wrong/missing signatures are rejected by the server (-3). */
async function tryFetchPlayUrlMobile(bvid: string, cid: number, qn: number, fnval: number, probe?: LastPlayTimeProbe): Promise<FetchPlayUrlResult> {
  const profile = PlaybackStartup.span('playurl-app-hd');
  const sessionCookie = AppStorage.get<string>('biliCookie') || '';
  try {
    if (!AppSign.hasConfiguredKey('android_hd')) {
      profile?.mark('disabled-unconfigured');
      return emptyPlayUrlResult();
    }
    // A known AV/CID already contains everything required by the App endpoint.
    const inputs = await Promise.all([/^\d+$/.test(bvid) && cid > 0
      ? Promise.resolve<VideoDetail | null>(null) : getVideoDetail(bvid), getLoginAccessKey(sessionCookie)]);
    const detail = inputs[0] as VideoDetail | null;
    const accessKey = inputs[1] as string;
    const aid: string = /^\d+$/.test(bvid) ? bvid : String(detail?.aid || '');
    if (sessionCookie !== (AppStorage.get<string>('biliCookie') || '') || !aid) return emptyPlayUrlResult();
    const params: Record<string, string> = {
      'aid': aid, 'cid': String(cid), 'qn': String(qn), 'fnval': String(fnval),
      'fnver': '0', 'fourk': '1', 'force_host': '2', 'otype': 'json', 'platform': 'android',
      'mobi_app': 'android_hd', 'device': 'pad', 'build': '8430300',
      'ts': String(Math.floor(Date.now() / 1000))
    };
    if (accessKey) params['access_key'] = accessKey;
    profile?.mark('account-token', accessKey ? 1 : 0);
    profile?.mark('sign-start');
    await AppSign.signParams(params, 'android_hd');
    profile?.mark('sign-end');
    if (sessionCookie !== (AppStorage.get<string>('biliCookie') || '')) return emptyPlayUrlResult();
    const query = Object.keys(params).sort().map((key: string): string =>
      `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`).join('&');
    return await fetchPlayUrlEndpoint('https://app.bilibili.com/x/playurl?' + query, {
      'User-Agent': 'Mozilla/5.0 BiliDroid/8.43.0 (bbcallen@gmail.com) os/android model/android mobi_app/android_hd build/8430300',
      'Cookie': getCookieHeader()
    }, profile, sessionCookie, qn, fnval, probe);
  } catch (error) {
    logWarn('[PlayURLApp] signed request failed');
    return emptyPlayUrlResult();
  } finally { profile?.end(); }
}

/** Independent fallback; never reported as App-signed playback. */
async function tryFetchPlayUrlCompat(bvid: string, cid: number, qn: number, fnval: number, probe?: LastPlayTimeProbe): Promise<FetchPlayUrlResult> {
  const profile = PlaybackStartup.span('playurl-web-compat');
  const sessionCookie = AppStorage.get<string>('biliCookie') || '';
  try {
    const query = `${/^\d+$/.test(bvid) ? 'avid' : 'bvid'}=${encodeURIComponent(bvid)}&cid=${cid}&qn=${qn}&fnval=${fnval}&fnver=0&fourk=1&platform=pc&high_quality=1`;
    return await fetchPlayUrlEndpoint('https://api.bilibili.com/x/player/playurl?' + query, {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Referer': 'https://www.bilibili.com/', 'Origin': 'https://www.bilibili.com', 'Cookie': getCookieHeader()
    }, profile, sessionCookie, qn, fnval, probe);
  } catch (error) {
    logWarn('[PlayURLCompat] request failed', error);
    return emptyPlayUrlResult();
  } finally { profile?.end(); }
}

/** App races WBI; preserve compatible Web playback when WBI is unavailable. */
async function tryFetchPlayUrlWebRoute(bvid: string, cid: number, qn: number, fnval: number, probe?: LastPlayTimeProbe): Promise<FetchPlayUrlResult> {
  let result = emptyPlayUrlResult();
  try { result = await tryFetchPlayUrl(bvid, cid, qn, fnval, probe); } catch (_) {}
  if (result.durlUrl || (result.dashVideoUrl && result.dashAudioUrl)) return result;
  return tryFetchPlayUrlCompat(bvid, cid, qn, fnval, probe);
}

/**
 * 生成Trace ID（用于请求追踪）
 */
function generateTraceId(): string {
  const timestamp = Date.now().toString(16);
  const random = Math.random().toString(16).substring(2, 10);
  return `${timestamp}:${random}:0:0`;
}

/**
 * 获取设备ID（模拟buvid3）
 */
/**
 * 从 Cookie 中提取 DedeUserID（B站用户唯一标识）
 * 用于设置 X-Bili-Mid 请求头，使移动端 API 识别已登录用户
 */
function getBiliMid(): string {
  const cookie = AppStorage.get<string>('biliCookie') || '';
  // 从 cookie 中提取 DedeUserID=xxx
  const match = cookie.match(/DedeUserID=([^;]+)/);
  const mid = match ? match[1] : '0';
  logInfo(`[getBiliMid] DedeUserID=${mid}, Cookie长度=${cookie.length}, 包含DedeUserID=${cookie.includes('DedeUserID')}`);
  return mid;
}

function getDeviceId(): string {
  // 尝试从AppStorage获取设备ID
  let deviceId = AppStorage.get<string>('biliDeviceId');
  if (!deviceId) {
    // 生成标准格式的 buvid3：{8位hex}-{4位hex}-{4位hex}-{4位hex}-{12位hex}infoc
    const hex = (len: number): string => {
      let s = '';
      for (let i = 0; i < len; i++) {
        s += Math.floor(Math.random() * 16).toString(16);
      }
      return s;
    };
    deviceId = `${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}infoc`;
    AppStorage.setOrCreate('biliDeviceId', deviceId);
  }
  return deviceId;
}

/**
 * 从 B站跨域跳转 URL 中提取 Cookie 字段
 * URL 格式: https://passport.bilibili.com/.../crossDomain?SESSDATA=xxx&bili_jct=yyy&DedeUserID=zzz&...
 */
function parseCookiesFromUrl(url: string): string {
  try {
    return loginCookiesFromUrl(url);
  } catch (e) {
    logError(`解析URL Cookie失败: ${e}`);
    return '';
  }
}

/**
 * 获取视频详细信息（包括描述、统计数据、UP主信息等）
 * @param bvid 视频BV号
 * @returns 视频详细信息，失败时返回null
 */
async function fetchVideoDetail(bvid: string): Promise<VideoDetail | null> {
  const profile = PlaybackStartup.span('detail-network');
  // 如果 bvid 是纯数字（aid），使用 aid= 参数而非 bvid=
  const isNumericAid: boolean = /^\d+$/.test(bvid);
  let url: string;
  if (isNumericAid) {
    url = `https://api.bilibili.com/x/web-interface/view?aid=${bvid}`;
    logInfo(`[getVideoDetail] 使用 aid 参数: ${bvid}`);
  } else {
    url = `https://api.bilibili.com/x/web-interface/view?bvid=${bvid}`;
  }
  const httpRequest = http.createHttp();
  try {
    profile?.mark('http-start');
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Referer': `https://www.bilibili.com/video/${bvid}`,
        'Origin': 'https://www.bilibili.com',
        'Cookie': getCookieHeader(),
        'X-Bili-Mid': getBiliMid(),
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
      },
      connectTimeout: 10000,
      readTimeout: 10000
    });
    profile?.network(response);
    if (response.responseCode !== 200) {
      logError(`获取视频详情 HTTP 错误: ${response.responseCode}`);
      return null;
    }
    const result = response.result as string;
    const jsonData: VideoDetailResponse = JSON.parse(result);
    if (jsonData.code !== 0) {
      logWarn(`获取视频详情失败: code=${jsonData.code}, message=${jsonData.message}`);
      return null;
    }
    // 调试：打印 req_user 字段
    logInfo(`[getVideoDetail] req_user: ${JSON.stringify(jsonData.data?.req_user)}`);
    // ⭐ UGC 多P：映射 pages 并填入首帧封面（原始透传 first_frame → cover，供选集弹窗显示）
    const detail = jsonData.data;
    if (detail && detail.pages && detail.pages.length > 0) {
      const rawPages = detail.pages as RawViewPage[];
      const mappedPages: VideoPageItem[] = [];
      for (const p of rawPages) {
        mappedPages.push({
          cid: p.cid || 0,
          page: p.page || 0,
          part: p.part || '',
          duration: p.duration || 0,
          cover: p.first_frame || '',
          dimension: p.dimension
        });
      }
      detail.pages = mappedPages;
    }
    // ⭐ UGC 合集解析
    if (detail && detail.ugc_season) {
      const rawSeason = detail.ugc_season as UgcSeason;
      // ⭐ view 接口返回的是 snake_case（ep_count / season_type / is_pay_season），
      //   接口类型写的是 camelCase，不做归一运行时全是 undefined（合集行 x/y 的分母会退化成当前分区集数）。
      if (rawSeason.epCount === undefined && typeof rawSeason.ep_count === 'number') {
        rawSeason.epCount = rawSeason.ep_count;
      }
      logInfo(`[getVideoDetail] UGC合集: id=${rawSeason.id}, title=${rawSeason.title}, sections=${rawSeason.sections?.length ?? 0}, epCount=${rawSeason.epCount}`);
    }
    return detail || null;
  } catch (err) {
    logError(`获取视频详情异常: ${err}`);
    return null;
  } finally {
    profile?.end();
    httpRequest.destroy();
  }
}

// ⭐⭐⭐ 视频详情缓存 + 进行中请求去重（专治"进播放页慢"）
// 背景：getVideoDetail 原来每次调用都新建 http.createHttp() 走一次网络，而"进播放页"的第一帧
//   必须等详情里的 cid（拿不到 cid 就不能发 playurl）。于是形成串行等待：
//     详情 RTT(≈90~150ms) → playurl RTT(≈135ms) → 平台 prepare(≈500ms)
//   这段完全没有和"页面转场 / 播放器初始化"重叠，用户看到的就是明显白等。
// 现在：
//   1) 详情按 key 缓存（TTL 5 分钟），命中即 0 网络；
//   2) 同 key 请求在飞时复用同一个 Promise —— 来源页点卡片时的预热 + 播放页 loadD 只会打一次网络；
//   3) 成功后按"请求 key / 返回的 bvid / aid"三键回填，所以 aid 入口拿到的详情，
//      播放页再用 bvid 查也能命中（省掉 initFromAid 之后 loadD 的第二次 view 请求）。
interface VideoDetailCacheEntry {
  detail: VideoDetail | null;
  at: number;
}

const videoDetailCache: Map<string, VideoDetailCacheEntry> = new Map();
const videoDetailInflight: Map<string, Promise<VideoDetail | null>> = new Map();
const VIDEO_DETAIL_CACHE_TTL: number = 5 * 60 * 1000;

/** 归一化缓存键：纯数字视为 aid，加前缀避免与 bvid 撞键 */
function videoDetailKey(idOrAid: string): string {
  const s: string = (idOrAid ?? '').trim();
  if (!s) return '';
  return /^\d+$/.test(s) ? `aid:${s}` : s;
}

/**
 * ⭐ 预热视频详情（fire-and-forget）：在来源页"点卡片"时调用，
 *   把这次 RTT 藏在页面转场与播放器初始化（约 500ms 平台耗时）里。
 */
export function prefetchVideoDetail(idOrAid: string): void {
  if (!idOrAid) return;
  getVideoDetail(idOrAid).catch((e: Error) => {
    logWarn(`[prefetchVideoDetail] 预热失败(忽略): ${e.message}`);
  });
}

/** 失效详情缓存（不传参 = 全清） */
export function invalidateVideoDetailCache(idOrAid?: string): void {
  if (!idOrAid) {
    videoDetailCache.clear();
    return;
  }
  videoDetailCache.delete(videoDetailKey(idOrAid));
}

/**
 * ⭐ 带缓存 + 请求去重的视频详情（对外与原 getVideoDetail 完全同签名）
 */
export async function getVideoDetail(idOrAid: string): Promise<VideoDetail | null> {
  const profile = PlaybackStartup.span('detail-consumer');
  const key: string = videoDetailKey(idOrAid);
  if (!key) { profile?.end(); return null; }

  const cached: VideoDetailCacheEntry | undefined = videoDetailCache.get(key);
  if (cached !== undefined && (Date.now() - cached.at) < VIDEO_DETAIL_CACHE_TTL) {
    logInfo(`[getVideoDetail] 命中缓存: ${key}`);
    profile?.mark('cache-hit'); profile?.end();
    return cached.detail;
  }
  const flying: Promise<VideoDetail | null> | undefined = videoDetailInflight.get(key);
  if (flying !== undefined) {
    logInfo(`[getVideoDetail] 复用进行中的请求: ${key}`);
    profile?.mark('inflight'); return flying.finally(() => profile?.end());
  }

  const task: Promise<VideoDetail | null> = fetchVideoDetail(idOrAid).then((d: VideoDetail | null) => {
    videoDetailInflight.delete(key);
    const at: number = Date.now();
    videoDetailCache.set(key, { detail: d, at: at });
    if (d) {
      if (d.bvid) videoDetailCache.set(videoDetailKey(d.bvid), { detail: d, at: at });
      if (d.aid) videoDetailCache.set(videoDetailKey(String(d.aid)), { detail: d, at: at });
    }
    return d;
  }).catch((e: Error) => {
    videoDetailInflight.delete(key);
    logError(`[getVideoDetail] 请求异常: ${e.message}`);
    return null;
  });
  videoDetailInflight.set(key, task);
  return task.finally(() => profile?.end());
}

/** Bilibili CDN 图片缩放：仅 hdslb.com 域名追加 @Ww 缩放参数（其他 URL 原样返回） */
function resizeHdslbImage(url: string, width: number): string {
  if (!url || !url.includes('hdslb.com')) {
    return url;
  }
  // ⚠️ 原实现 `!url.includes('@')`：URL 已带后缀时**整段跳过压缩** → 原图被整张解码
  //    → 先剥掉旧后缀（仅当 '@' 在最后一个 '/' 之后）再挂显示尺寸
  const at: number = url.indexOf('@');
  const base: string = (at > url.lastIndexOf('/') && url.indexOf('?') < 0) ? url.substring(0, at) : url;
  return base + `@${width}w`;
}

export async function getRelatedVideos(bvid: string): Promise<RecommendItem[]> {
  if (!bvid) return [];
  const url = `https://api.bilibili.com/x/web-interface/archive/related?bvid=${bvid}`;
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Referer': `https://www.bilibili.com/video/${bvid}`,
        'Origin': 'https://www.bilibili.com',
        'Cookie': getCookieHeader(),
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
      },
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode !== 200) {
      logError(`[getRelatedVideos] HTTP错误: ${response.responseCode}`);
      return [];
    }
    const result = response.result as string;
    const jsonData: Record<string, Object> = JSON.parse(result);
    const code = jsonData['code'] as number;
    if (code !== 0) {
      logWarn(`[getRelatedVideos] API错误: code=${code}, message=${jsonData['message']}`);
      return [];
    }
    const dataArray = jsonData['data'] as Array<Record<string, Object>>;
    if (!dataArray || dataArray.length === 0) {
      return [];
    }
    const items: RecommendItem[] = [];
    for (const obj of dataArray) {
      const item = RecommendItem.fromPopularApi(obj);
      if (item.id || item.aid > 0) {
        // ⭐ 封面缩放：推荐卡片仅 ~120×68vp，原图(1080p+)解码与起播抢解码线程
        item.coverUrl = resizeHdslbImage(item.coverUrl, 672);
        items.push(item);
      }
      if (items.length >= 20) break;
    }
    logInfo(`[getRelatedVideos] bvid=${bvid} 获取到 ${items.length} 个相关视频`);
    return items;
  } catch (err) {
    logError(`[getRelatedVideos] 异常: ${err}`);
    return [];
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 用户对视频的互动状态
 */
export interface VideoUserStatus {
  dislike?: boolean;
  like: boolean;
  coin: number;
  favorite: boolean;
}

/**
 * 收藏状态响应数据
 */
interface FavStatusData {
  favoured: boolean;
}

/**
 * 投币状态响应数据
 */
interface CoinStatusData {
  coin?: number;
  multiply?: number;
}

/**
 * 获取用户对视频的互动状态（点赞、投币、收藏）
 * 当视频详情API不返回req_user时，使用此API单独查询
 * @param bvid 视频BV号
 * @param aid 视频AV号（投币和收藏查询需要）
 * @returns 用户互动状态
 */
/** view 接口重定向响应（PGC 分集 bvid 反查 ep_id 用） */
interface PgcRedirectResponse {
  code: number;
  data?: PgcRedirectData;
}

interface PgcRedirectData {
  redirect_url?: string;
}

/**
 * 用 bvid 反查 PGC（番剧/影视）分集 ep_id
 * B 站 view 接口对 PGC 分集 bvid 返回 data.redirect_url（如 "//www.bilibili.com/bangumi/play/ep4723795"）
 * 用于历史记录页：v2 历史接口的 PGC 记录无 epId，但可凭 bvid 反查（不依赖先播放过番剧）
 * @param bvid 稿件 bvid（v2 历史接口返回的 PGC 分集 bvid）
 * @returns ep_id（非 PGC 或解析失败返回 0）
 */
export async function getPgcEpIdByBvid(bvid: string): Promise<number> {
  if (!bvid) return 0;
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(
      `https://api.bilibili.com/x/web-interface/view?bvid=${bvid}`,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': `https://www.bilibili.com/video/${bvid}`,
          'Cookie': getCookieHeader()
        },
        connectTimeout: 10000,
        readTimeout: 10000
      }
    );
    if (response.responseCode !== 200) return 0;
    const jsonData: PgcRedirectResponse = JSON.parse(response.result as string) as PgcRedirectResponse;
    if (jsonData.code !== 0) return 0;
    const redirectUrl: string = jsonData.data?.redirect_url ?? '';
    if (!redirectUrl) return 0;
    // redirect_url 形如 "//www.bilibili.com/bangumi/play/ep4723795" → 提取 4723795
    const epIdx = redirectUrl.indexOf('/ep');
    if (epIdx < 0) return 0;
    let epId: number = 0;
    for (let i = epIdx + 3; i < redirectUrl.length; i++) {
      const c = redirectUrl.charCodeAt(i);
      if (c >= 48 && c <= 57) {
        epId = epId * 10 + (c - 48);
      } else {
        break;
      }
    }
    logInfo(`[getPgcEpIdByBvid] bvid=${bvid} redirect_url=${redirectUrl} → epId=${epId}`);
    return epId;
  } catch (e) {
    logWarn(`[getPgcEpIdByBvid] 异常: ${e}`);
    return 0;
  } finally {
    httpRequest.destroy();
  }
}

export async function getVideoUserStatus(bvid: string, aid?: number): Promise<VideoUserStatus | null> {
  const httpRequest = http.createHttp();
  const sessionCookie = AppStorage.get<string>('biliCookie') || '';
  const headers: Record<string, string> = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    'Referer': `https://www.bilibili.com/video/${bvid}`,
    'Cookie': getCookieHeader(),
    'X-Bili-Mid': getBiliMid()
  };

  // 默认状态
  let isLiked = false;
  let coinCount = 0;
  let isFavorited = false;

  try {
    // App 详情包含点踩状态；Web 的 has/like 无法恢复“不喜欢”的选中态。
    const accessKey = await getLoginAccessKey(sessionCookie);
    if (sessionCookie !== (AppStorage.get<string>('biliCookie') || '')) return null;
    if (accessKey && aid && aid > 0) {
      const appParams: Record<string, string> = {
        'aid': String(aid), 'access_key': accessKey, 'mobi_app': 'android_hd',
        'platform': 'android', 'build': '8430300', 'ts': String(Math.floor(Date.now() / 1000))
      };
      await AppSign.signParams(appParams, 'android_hd');
      const query = Object.keys(appParams).map((key: string): string =>
        `${encodeURIComponent(key)}=${encodeURIComponent(appParams[key])}`).join('&');
      const appResponse = await httpRequest.request(`https://app.bilibili.com/x/v2/view?${query}`, {
        method: http.RequestMethod.GET, header: {
          'User-Agent': 'Mozilla/5.0 BiliDroid/8.43.0 (bbcallen@gmail.com) os/android model/android mobi_app/android_hd build/8430300',
          'Cookie': sessionCookie
        }, connectTimeout: 10000, readTimeout: 10000
      });
      if (sessionCookie !== (AppStorage.get<string>('biliCookie') || '')) return null;
      if (appResponse.responseCode === 200) {
        const appState = JSON.parse(appResponse.result as string) as ApiResponse<VideoDetail>;
        const user = appState.data?.req_user;
        if (appState.code === 0 && user) {
          return { like: !!user.like, dislike: !!user.dislike, coin: user.coin || 0, favorite: !!user.favorite };
        }
        logWarn(`[互动状态] App查询失败 code=${appState.code} user=${!!user}`);
      }
    }
    // 1. 查询点赞状态
    const archiveQuery = aid && aid > 0 ? `aid=${aid}` : /^[1-9][0-9]*$/.test(bvid) ? `aid=${bvid}` : `bvid=${encodeURIComponent(bvid)}`;
    const likeUrl = `https://api.bilibili.com/x/web-interface/archive/has/like?${archiveQuery}`;
    const likeResponse = await httpRequest.request(likeUrl, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 10000,
      readTimeout: 10000
    });

    if (likeResponse.responseCode === 200) {
      const likeData = JSON.parse(likeResponse.result as string) as ApiResponse<number>;
      if (likeData.code === 0) {
        isLiked = likeData.data === 1;
      }
    }

    // 2. 查询投币状态（需要aid）
    logInfo(`[getVideoUserStatus] aid=${aid}, 是否查询投币=${!!aid}`);
    if (aid) {
      // 尝试新的投币状态API
      const coinUrl = `https://api.bilibili.com/x/web-interface/archive/coins?aid=${aid}`;
      logInfo(`[getVideoUserStatus] 投币API URL: ${coinUrl}`);
      const coinResponse = await httpRequest.request(coinUrl, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 10000
      });

      logInfo(`[getVideoUserStatus] 投币API HTTP: ${coinResponse.responseCode}`);
      if (coinResponse.responseCode === 200) {
        const coinResultStr = coinResponse.result as string;
        logInfo(`[getVideoUserStatus] 投币API原始返回: ${coinResultStr}`);
        const coinResult: ApiResponse<number | CoinStatusData> = JSON.parse(coinResultStr);
        logInfo(`[getVideoUserStatus] 投币API返回: code=${coinResult.code}, data=${JSON.stringify(coinResult.data)}`);
        if (coinResult.code === 0) {
          // data可能是数字、{coin: number} 或 {multiply: number}
          const data = coinResult.data;
          if (typeof data === 'number') {
            coinCount = data || 0;
          } else if (data) {
            // 尝试解析不同格式
            const dataStr = JSON.stringify(data);
            const parsedData = JSON.parse(dataStr) as CoinStatusData;
            if (typeof parsedData.coin === 'number') {
              coinCount = parsedData.coin || 0;
            } else if (typeof parsedData.multiply === 'number') {
              // multiply表示已投币数量
              coinCount = parsedData.multiply || 0;
            }
          }
          logInfo(`[getVideoUserStatus] 解析投币数: ${coinCount}`);
        } else {
          logWarn(`[getVideoUserStatus] 投币API业务错误: code=${coinResult.code}, message=${coinResult.message}`);
        }
      } else {
        logError(`[getVideoUserStatus] 投币API HTTP错误: ${coinResponse.responseCode}`);
      }

      // 3. 查询收藏状态（需要aid）
      const favUrl = `https://api.bilibili.com/x/v2/fav/video/favoured?aid=${aid}`;
      const favResponse = await httpRequest.request(favUrl, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 10000
      });

      if (favResponse.responseCode === 200) {
        const favData = JSON.parse(favResponse.result as string) as ApiResponse<FavStatusData>;
        if (favData.code === 0 && favData.data) {
          isFavorited = favData.data.favoured || false;
        }
      }
    }

    logInfo(`[getVideoUserStatus] 已点赞=${isLiked}, 已投币=${coinCount}, 已收藏=${isFavorited}`);
    const status: VideoUserStatus = { like: isLiked, coin: coinCount, favorite: isFavorited };
    return sessionCookie === (AppStorage.get<string>('biliCookie') || '') ? status : null;
  } catch (err) {
    logError(`[getVideoUserStatus] 异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 获取视频评论（使用新版 reply/main API，支持排序模式）
 * @param aid 视频aid（可通过VideoDetail中的aid获取）
 * @param cursor 分页游标，0=第一页，后续使用前次返回的 nextCursor
 * @param pageSize 每页数量，默认20
 * @param mode 排序模式：3=最热，2=最新，默认3
 * @returns 评论结果；被限流返回 null
 */
/**
 * ⭐ 通用评论列表内核（视频 type=1 / 动态 type=17 共用，别各写一份）
 * @param oidStr 评论区对象 id：**字符串**（视频=aid，动态=19 位 dyn_id_str，后者超精度绝不能 parseInt）
 * @param commentType 评论区类型：视频=1，动态=17
 */
async function getCommentsByType(oidStr: string, commentType: number, cursor: number,
  pageSize: number, mode: number, failFast: boolean = false,
  shouldContinue: () => boolean = () => true): Promise<VideoCommentsResult | null> {
  if (!shouldContinue() || (failFast && getRateLimitCooldown() > 0)) return null;
  // 使用新版 main API（支持 mode=2 时间排序 / mode=3 热度排序）
  // ⭐ WBI 签名的新版接口（B 站 web 端使用，登录态下才下发 IP 属地）；签名失败/被拒时回退旧接口
  let url: string;
  let isWbiUrl: boolean = false;
  try {
    const wbiParams: Record<string, string> = {};
    wbiParams['type'] = `${commentType}`;
    wbiParams['oid'] = oidStr;
    wbiParams['mode'] = `${mode}`;
    wbiParams['next'] = `${cursor}`;
    wbiParams['ps'] = `${pageSize}`;
    url = `https://api.bilibili.com/x/v2/reply/wbi/main?${await AppSign.generateWebParams(wbiParams)}`;
    isWbiUrl = true;
  } catch (err) {
    logWarn(`[getComments] WBI签名失败，使用旧接口: ${err}`);
    url = `https://api.bilibili.com/x/v2/reply/main?type=${commentType}&oid=${oidStr}&mode=${mode}&next=${cursor}&ps=${pageSize}`;
  }

  // 限流重试：最多5次，间隔递增（3s→6s→12s→24s→48s）
  const maxRetries = failFast ? 1 : 5;
  let retryDelay = 3000;

  for (let retry = 0; retry <= maxRetries; retry++) {
    if (!shouldContinue()) return null;
    if (retry > 0 && !failFast) {
      logWarn(`[getVideoComments] 第${retry}次重试，等待${retryDelay}ms`);
      await new Promise<void>((resolve: Function) => setTimeout(resolve, retryDelay));
      retryDelay *= 2; // 指数退避 3s→6s→12s→24s→48s
    }

    const httpRequest = http.createHttp();
    try {
      // 评论类请求使用独立短间隔节流
      if (failFast) {
        if (!(await tryDynamicCommentThrottle())) return null;
      } else {
        await commentThrottleRequest();
      }
      if (!shouldContinue()) return null;
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: getRotatedHeaders(),
        connectTimeout: 10000,
        readTimeout: 10000
      });
      logInfo(`[getVideoComments] HTTP: ${response.responseCode}`);

      // 412 = 限流，需要重试
      if (response.responseCode === 412) {
        logError(`[getVideoComments] 被限流(412)，${!failFast && retry < maxRetries ? '准备重试' : '结束本次请求'}`);
        triggerRateLimitCooldown();
        if (!failFast && retry < maxRetries) {
          continue;
        }
        return null; // 返回 null 表示限流
      }

      if (response.responseCode !== 200) {
        logError(`获取评论 HTTP 错误: ${response.responseCode}`);
        if (failFast) return null;
        return { comments: [], nextCursor: 0, isEnd: true };
      }

      const result = response.result as string;
      const jsonData: CommentListResponse = JSON.parse(result);
      logInfo(`[getVideoComments] code=${jsonData.code}`);
      if (jsonData.code !== 0) {
        logWarn(`获取评论失败: code=${jsonData.code}, message=${jsonData.message}`);
        if (jsonData.code === -101) {
          logError('[getComments] 账号未登录或Cookie失效');
        } else if (jsonData.code === -502 || jsonData.code === -504) {
          logError('[getComments] 网关错误，可能是API限流');
        } else if (jsonData.code === -404) {
          // ⚠️ 评论区不存在（多为 oid/type 配错，如动态的评论挂在稿件上而非动态本体）：
          //    重试只会白等几十秒并继续 -404，直接结束（并在日志里留痕便于定位参数）
          logWarn(`[getComments] 评论区不存在(-404)，放弃重试: type=${commentType}, oid=${oidStr}`);
          return { comments: [], nextCursor: 0, isEnd: true };
        }
        // WBI 接口被拒（如 -352 风控）时回退旧接口重试一次
        if (isWbiUrl) {
          isWbiUrl = false;
          url = `https://api.bilibili.com/x/v2/reply/main?type=${commentType}&oid=${oidStr}&mode=${mode}&next=${cursor}&ps=${pageSize}`;
          logWarn('[getComments] WBI接口返回异常，切换旧版接口重试');
          continue;
        }
        if (failFast) return null;
        return { comments: [], nextCursor: 0, isEnd: true };
      }
      const replies = jsonData.data?.replies || [];
      const nextCursor = jsonData.data?.cursor?.next || 0;
      const isEnd = jsonData.data?.cursor?.is_end ?? true;
      logInfo(`[getVideoComments] 返回${replies.length}条评论, mode=${mode}, isEnd=${isEnd}`);

      const cookieHasSess = (AppStorage.get<string>('biliCookie') ?? '').includes('SESSDATA');
      logInfo(`[getVideoComments] SESSDATA=${cookieHasSess}`);
      for (let i = 0; i < replies.length && i < 5; i++) {
        const c = replies[i];
        logInfo(`[getVideoComments] 评论${i}: rpid=${c.rpid}, rcount=${c.rcount}, ip_location=${c.ip_location ?? '无'}, location=${c.location ?? '无'}, reply_control.location=${c.reply_control?.location ?? '无'}, replies=${c.replies?.length || 0}`);
      }
      return { comments: replies, nextCursor, isEnd };
    } catch (err) {
      logError(`获取评论异常: ${err}`);
      if (failFast) return null;
      if (retry < maxRetries) {
        continue; // 网络异常也重试
      }
      return { comments: [], nextCursor: 0, isEnd: true };
    } finally {
      httpRequest.destroy();
    }
  }
  return { comments: [], nextCursor: 0, isEnd: true };
}

/** 视频评论（type=1，oid=aid） */
export async function getVideoComments(aid: number, cursor: number, pageSize: number = 20, mode: number = 3): Promise<VideoCommentsResult | null> {
  return getCommentsByType(`${aid}`, 1, cursor, pageSize, mode);
}

/**
 * 动态评论（默认 type=17；**视频/专栏类动态要传该项的 `commentType`**）
 * ⚠️ 动态 id 是 19 位，超出 number 精度，所以本函数只收字符串、不做 parseInt；
 *    调用方直接传 `SpaceDynamicItem.commentIdStr` + `commentType` 最稳。
 */
export async function getDynComments(oidStr: string, cursor: number, pageSize: number = 20,
  mode: number = 3, commentType: number = 17,
  shouldContinue: () => boolean = () => true): Promise<VideoCommentsResult | null> {
  return getCommentsByType(oidStr, commentType, cursor, pageSize, mode, true, shouldContinue);
}

/**
 * 评论定位：根据根评论 rpid 查找其在评论列表中的页码
 * B站 web 端点击消息通知跳转时使用此接口定位评论所在页
 * @param aid 视频 aid
 * @param rootId 根评论 rpid（消息通知中的 comment_root_id）
 * @returns 定位结果：包含该评论的页码 cursor，或 null 表示失败
 */
export async function getCommentAnchor(aid: number, rootId: number): Promise<number | null> {
  const url = `https://api.bilibili.com/x/v2/reply/anchor?type=1&oid=${aid}&root=${rootId}`;
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: getRotatedHeaders(),
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode === 200) {
      const jsonData = JSON.parse(response.result as string) as Record<string, Object>;
      if (jsonData['code'] === 0) {
        const data = jsonData['data'] as Record<string, Object> | null;
        if (data) {
          const cursor = (data['cursor'] as number) || 0;
          logInfo(`[getCommentAnchor] aid=${aid}, rootId=${rootId}, cursor=${cursor}`);
          return cursor;
        }
      } else {
        logWarn(`[getCommentAnchor] code=${jsonData['code']}, message=${jsonData['message']}`);
      }
    } else {
      logWarn(`[getCommentAnchor] HTTP ${response.responseCode}`);
    }
  } catch (err) {
    logError(`[getCommentAnchor] 异常: ${err}`);
  } finally {
    httpRequest.destroy();
  }
  return null;
}

/**
 * 获取评论回复（楼中楼，带限流重试）
 * @param aid 视频aid
 * @param root 根评论rpid
 * @param page 页码，从1开始
 * @param pageSize 每页数量，默认20
 * @returns 回复列表，失败时返回空数组；被限流返回 null
 */
/**
 * ⭐ 通用二级回复内核（视频 type=1 / 动态 type=17 共用）
 * @param oidStr 评论区对象 id（**字符串**，动态为 19 位 dyn_id_str）
 * @param commentType 1=视频，17=动态
 */
async function getRepliesByType(oidStr: string, commentType: number, root: number,
  page: number, pageSize: number): Promise<CommentItem[] | null> {
  // 使用移动端回复API
  const url = `https://api.bilibili.com/x/v2/reply/reply?type=${commentType}&oid=${oidStr}&root=${root}&pn=${page}&ps=${pageSize}`;
  
  // 限流重试：最多5次
  const maxRetries = 5;
  let retryDelay = 3000;
  
  for (let retry = 0; retry <= maxRetries; retry++) {
    if (retry > 0) {
      logWarn(`[getCommentReplies] 第${retry}次重试，等待${retryDelay}ms`);
      await new Promise<void>((resolve: Function) => setTimeout(resolve, retryDelay));
      retryDelay *= 2;
    }
    
    const httpRequest = http.createHttp();
    try {
      // 回复类请求使用独立宽松节流（1200ms），防止楼中楼连续请求触发限流
      await replyThrottleRequest();
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: getRotatedHeaders(),
        connectTimeout: 10000,
        readTimeout: 10000
      });
      logInfo(`[getCommentReplies] HTTP: ${response.responseCode}`);
      
      if (response.responseCode === 412) {
        logError(`[getCommentReplies] 被限流(412)，${retry < maxRetries ? '准备重试' : '已达最大重试次数'}`);
        triggerRateLimitCooldown();
        if (retry < maxRetries) {
          continue;
        }
        return null;
      }
      
      if (response.responseCode !== 200) {
        logError(`获取评论回复 HTTP 错误: ${response.responseCode}`);
        return [];
      }
      
      const result = response.result as string;
      const jsonData: CommentListResponse = JSON.parse(result);
      logInfo(`[getCommentReplies] code=${jsonData.code}`);
      if (jsonData.code !== 0) {
        logWarn(`获取评论回复失败: code=${jsonData.code}, message=${jsonData.message}`);
        return [];
      }
      const replies = jsonData.data?.replies || [];
      for (let i = 0; i < replies.length && i < 3; i++) {
        logInfo(`[getCommentReplies] 回复${i}: rpid=${replies[i].rpid}, ip_location=${replies[i].ip_location ?? '无'}, location=${replies[i].location ?? '无'}, reply_control.location=${replies[i].reply_control?.location ?? '无'}`);
      }
      logInfo(`[getCommentReplies] 返回${replies.length}条`);
      return replies;
    } catch (err) {
      logError(`获取评论回复异常: ${err}`);
      if (retry < maxRetries) {
        continue;
      }
      return [];
    } finally {
      httpRequest.destroy();
    }
  }
  return [];
}

/** 视频二级回复（type=1，oid=aid） */
export async function getCommentReplies(aid: number, root: number, page: number = 1, pageSize: number = 20): Promise<CommentItem[] | null> {
  return getRepliesByType(`${aid}`, 1, root, page, pageSize);
}

/** 动态二级回复（默认 type=17，视频/专栏类动态传 commentType） */
export async function getDynCommentReplies(oidStr: string, root: number, page: number = 1,
  pageSize: number = 20, commentType: number = 17): Promise<CommentItem[] | null> {
  return getRepliesByType(oidStr, commentType, root, page, pageSize);
}

/** 评论详情结果（根评论 + 回复列表） */
export interface CommentDetailResult {
  rootComment: CommentItem | null;
  replies: CommentItem[];
  totalCount: number;
}

/**
 * 获取评论详情（根评论 + 回复列表）
 * 用于从消息通知跳转到评论详情页时，通过 aid + rootId 加载完整评论数据
 * @param aid 视频 aid
 * @param rootId 根评论 rpid
 * @param page 页码，从1开始
 * @param pageSize 每页数量，默认20
 */
export async function getCommentDetail(aid: number, rootId: number, page: number = 1, pageSize: number = 20): Promise<CommentDetailResult | null> {
  const url = `https://api.bilibili.com/x/v2/reply/reply?type=1&oid=${aid}&root=${rootId}&pn=${page}&ps=${pageSize}`;
  const maxRetries = 3;
  let retryDelay = 3000;

  for (let retry = 0; retry <= maxRetries; retry++) {
    if (retry > 0) {
      logWarn(`[getCommentDetail] 第${retry}次重试，等待${retryDelay}ms`);
      await new Promise<void>((resolve: Function) => setTimeout(resolve, retryDelay));
      retryDelay *= 2;
    }

    const httpRequest = http.createHttp();
    try {
      await replyThrottleRequest();
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: getRotatedHeaders(),
        connectTimeout: 10000,
        readTimeout: 10000
      });

      if (response.responseCode === 412) {
        logError(`[getCommentDetail] 被限流(412)`);
        triggerRateLimitCooldown();
        if (retry < maxRetries) {
          continue;
        }
        return null;
      }

      if (response.responseCode !== 200) {
        logError(`[getCommentDetail] HTTP ${response.responseCode}`);
        return null;
      }

      const jsonData: CommentListResponse = JSON.parse(response.result as string);
      if (jsonData.code !== 0) {
        logWarn(`[getCommentDetail] code=${jsonData.code}, message=${jsonData.message}`);
        return null;
      }

      const data = jsonData.data;
      if (!data) {
        return null;
      }

      const rootComment = data.root ?? null;
      const replies = data.replies ?? [];
      const totalCount = data.page?.count ?? rootComment?.rcount ?? replies.length;

      logInfo(`[getCommentDetail] root rpid=${rootComment?.rpid ?? 0}, replies=${replies.length}, total=${totalCount}`);
      return { rootComment, replies, totalCount };
    } catch (err) {
      logError(`[getCommentDetail] 异常: ${err}`);
      if (retry < maxRetries) {
        continue;
      }
      return null;
    } finally {
      httpRequest.destroy();
    }
  }
  return null;
}

interface CommentDialogFloor {
  next?: number;
  is_end?: boolean;
  min_floor?: number;
  max_floor?: number;
  size?: number;
}

interface CommentDialogData {
  replies?: CommentItem[];
  cursor?: CommentDialogFloor;
  dialog?: CommentDialogFloor;
}

export interface CommentDialogResult {
  ok: boolean;
  message: string;
  replies: CommentItem[];
  nextFloor: number;
  hasMore: boolean;
}

/** 获取服务端对话树，使用楼层游标分页，不按已加载的普通回复自行拼接对话。 */
export async function getCommentDialog(oid: number, root: number, dialog: number,
  minFloor: number = 0, pageSize: number = 20, type: number = 1): Promise<CommentDialogResult> {
  const request = http.createHttp();
  try {
    await replyThrottleRequest();
    const response = await request.request(
      `https://api.bilibili.com/x/v2/reply/dialog/cursor?type=${type}&oid=${oid}&root=${root}&dialog=${dialog}&min_floor=${minFloor}&size=${pageSize}`, {
        method: http.RequestMethod.GET,
        header: getRotatedHeaders(),
        connectTimeout: 10000,
        readTimeout: 10000
      });
    if (response.responseCode !== 200) {
      if (response.responseCode === 412) triggerRateLimitCooldown();
      return { ok: false, message: '对话加载失败，点击重试', replies: [], nextFloor: minFloor, hasMore: false };
    }
    const result = JSON.parse(response.result as string) as ApiResponse<CommentDialogData>;
    if (result.code !== 0 || !result.data) {
      logWarn(`[getCommentDialog] code=${result.code}`);
      return { ok: false, message: result.code === -101 ? '请先登录后查看对话' : (result.message || '对话暂不可用'),
        replies: [], nextFloor: minFloor, hasMore: false };
    }
    const replies = result.data.replies ?? [];
    const nextFloor = result.data.cursor?.next ?? (result.data.cursor?.max_floor !== undefined
      ? result.data.cursor.max_floor + 1 : minFloor);
    const lastFloor = result.data.dialog?.max_floor;
    const hasMore = result.data.cursor?.is_end !== true && replies.length > 0 && nextFloor > minFloor &&
      (lastFloor !== undefined ? nextFloor <= lastFloor : replies.length >= pageSize);
    logInfo(`[getCommentDialog] replies=${replies.length}, floor=${minFloor}->${nextFloor}, more=${hasMore}`);
    return { ok: true, message: '', replies: replies, nextFloor: nextFloor, hasMore: hasMore };
  } catch (error) {
    logWarn(`[getCommentDialog] 请求失败: ${error}`);
    return { ok: false, message: '网络异常，点击重试', replies: [], nextFloor: minFloor, hasMore: false };
  } finally {
    request.destroy();
  }
}

// ==================== 评论写入接口 ====================

/** 发表评论/回复结果 */
export interface AddCommentResult {
  ok: boolean;
  code: number;
  message: string;
}

/**
 * 发表一级评论或回复评论
 * @param oid 视频 aid
 * @param message 评论内容
 * @param root 一级评论为 0；回复时为根评论 rpid
 * @param parent 一级评论为 0；回复时为被回复的评论/回复 rpid
 */
/**
 * ⭐ 通用发评论内核（视频 type=1 / 动态 type=17 共用）
 * @param oidStr 评论区对象 id（**字符串**，动态为 19 位 dyn_id_str）
 */
async function addCommentByType(oidStr: string, commentType: number, message: string,
  root: number, parent: number, picturesJson?: string): Promise<AddCommentResult> {
  const url = 'https://api.bilibili.com/x/v2/reply/add';
  const httpRequest = http.createHttp();
  try {
    const cookie = getCookieHeader();
    const csrf = extractCsrfFromCookie(cookie);
    if (!csrf) {
      logError('[addComment] 缺少CSRF token，请先登录');
      return { ok: false, code: -101, message: '账号未登录或Cookie失效' };
    }

    let formData = `oid=${oidStr}&type=${commentType}&root=${root}&parent=${parent}&message=${encodeURIComponent(message)}&platform=web&csrf=${csrf}`;
    const pictures = picturesJson || '';
    if (pictures) {
      formData += `&pictures=${encodeURIComponent(pictures)}`;
    }

    const response = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
        'Cookie': cookie,
        'X-Bili-Mid': getBiliMid()
      },
      extraData: formData,
      connectTimeout: 10000,
      readTimeout: 10000
    });

    if (response.responseCode !== 200) {
      logError(`[addVideoComment] HTTP 错误: ${response.responseCode}`);
      return { ok: false, code: response.responseCode as number, message: `网络错误(${response.responseCode})` };
    }

    const result = response.result as string;
    const jsonData = JSON.parse(result) as ApiResponse<Object>;
    if (jsonData.code !== 0) {
      const msg = jsonData.message || '';
      if (jsonData.code === -101) {
        logWarn(`[addVideoComment] 未登录: code=-101`);
        return { ok: false, code: -101, message: '账号未登录或Cookie失效，请重新登录' };
      }
      logWarn(`[addVideoComment] 发表失败: code=${jsonData.code}, message=${msg}`);
      return { ok: false, code: jsonData.code as number, message: msg || '发表失败，请稍后再试' };
    }

    logInfo(`[addComment] 成功: oid=${oidStr}, type=${commentType}, root=${root}, parent=${parent}`);
    return { ok: true, code: 0, message: '' };
  } catch (err) {
    logError(`[addVideoComment] 异常: ${err}`);
    return { ok: false, code: -1, message: '网络异常，请稍后再试' };
  } finally {
    httpRequest.destroy();
  }
}

/** 视频发评论（type=1，oid=aid；oid 为数字，保持老签名不变） */
export async function addVideoComment(oid: number, message: string, root: number, parent: number, picturesJson?: string): Promise<AddCommentResult> {
  return addCommentByType(`${oid}`, 1, message, root, parent, picturesJson);
}

/**
 * 动态发评论 / 回复（默认 type=17；视频/专栏类动态传 commentType）
 * @param root 根评论 rpid（发一级评论传 0）
 * @param parent 被回复的评论 rpid（发一级评论传 0）
 * @param commentType 评论区类型码（SpaceDynamicItem.commentType）
 */
export async function addDynComment(oidStr: string, message: string, root: number, parent: number,
  picturesJson?: string, commentType: number = 17): Promise<AddCommentResult> {
  return addCommentByType(oidStr, commentType, message, root, parent, picturesJson);
}

/** 评论/回复点赞结果（动态点赞 setDynamicLike 复用同一结构） */
export interface CommentLikeResult {
  ok: boolean;
  code: number;
  message: string;
}

/**
 * 点赞/取消点赞评论或回复（web 端 /x/v2/reply/action，需登录 CSRF，无需 WBI）
 * @param oid 评论区对象 id（视频评论为 aid）
 * @param rpid 评论/回复 id
 * @param like true=点赞，false=取消
 * @param type 评论区类型（视频=1）
 */
export async function setCommentLike(oid: number, rpid: number, like: boolean, type: number = 1): Promise<CommentLikeResult> {
  // ⚠️ 视频评论 oid 是 aid（数字）；动态评论 oid 是 19 位 dyn_id_str —— 后者只能用 setDynCommentLike
  const oidStr: string = `${oid}`;
  return setCommentLikeByType(oidStr, type, rpid, like);
}

/** Report a specific comment/reply only after the user chooses a reason. */
export async function reportComment(oid: number, rpid: number, type: number, reason: number): Promise<string> {
  const cookie = getCookieHeader();
  const csrf = extractCsrfFromCookie(cookie);
  if (!csrf) return '请先登录';
  if (oid <= 0 || rpid <= 0) return '无法获取该评论信息';
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.bilibili.com/x/v2/reply/report', {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': cookie,
        'Referer': 'https://www.bilibili.com/', 'Origin': 'https://www.bilibili.com', 'X-Bili-Mid': getBiliMid() },
      extraData: `oid=${oid}&rpid=${rpid}&type=${type}&reason=${reason}&content=${encodeURIComponent('其他违规内容')}&csrf=${csrf}`,
      connectTimeout: 10000, readTimeout: 10000
    });
    if (response.responseCode !== 200) return '举报提交失败，请稍后重试';
    const result = JSON.parse(response.result as string) as ApiResponse<Object>;
    return result.code === 0 ? '举报已提交' : result.message || '举报提交失败，请稍后重试';
  } catch (_) { return '网络异常，请稍后重试'; }
  finally { request.destroy(); }
}

/** 评论点踩/取消点踩，与点赞接口使用相同鉴权。 */
export async function setCommentDislike(oid: number, rpid: number, dislike: boolean, type: number = 1): Promise<CommentLikeResult> {
  return setCommentLikeByType(`${oid}`, type, rpid, dislike, true);
}

/** 动态评论/回复点赞（默认 type=17；视频/专栏类动态传 commentType） */
export async function setDynCommentLike(oidStr: string, rpid: number, like: boolean, commentType: number = 17): Promise<CommentLikeResult> {
  return setCommentLikeByType(oidStr, commentType, rpid, like);
}

/** ⭐ 通用评论点赞内核（视频 type=1 / 动态 type=17 共用；oid 用字符串避免动态 id 精度丢失） */
async function setCommentLikeByType(oidStr: string, type: number, rpid: number, like: boolean, dislike: boolean = false): Promise<CommentLikeResult> {
  const url = dislike ? 'https://api.bilibili.com/x/v2/reply/hate' : 'https://api.bilibili.com/x/v2/reply/action';
  const httpRequest = http.createHttp();
  try {
    const cookie = getCookieHeader();
    const csrf = extractCsrfFromCookie(cookie);
    if (!csrf) {
      logError('[setCommentLike] 缺少CSRF token，请先登录');
      return { ok: false, code: -101, message: '账号未登录或Cookie失效' };
    }

    const formData = `oid=${oidStr}&type=${type}&rpid=${rpid}&action=${like ? 1 : 0}&csrf=${csrf}`;

    const response = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
        'Cookie': cookie,
        'X-Bili-Mid': getBiliMid()
      },
      extraData: formData,
      connectTimeout: 10000,
      readTimeout: 10000
    });

    if (response.responseCode !== 200) {
      logError(`[setCommentLike] HTTP 错误: ${response.responseCode}`);
      return { ok: false, code: response.responseCode as number, message: `网络错误(${response.responseCode})` };
    }

    const result = response.result as string;
    const jsonData = JSON.parse(result) as ApiResponse<Object>;
    if (jsonData.code !== 0) {
      const msg = jsonData.message || '';
      logWarn(`[setCommentLike] 点赞失败: code=${jsonData.code}, message=${msg}`);
      return { ok: false, code: jsonData.code as number, message: msg || '操作失败，请稍后再试' };
    }

    logInfo(`[setCommentLike] ${like ? '点赞' : '取消点赞'}成功: oid=${oidStr}, rpid=${rpid}`);
    return { ok: true, code: 0, message: '' };
  } catch (err) {
    logError(`[setCommentLike] 异常: ${err}`);
    return { ok: false, code: -1, message: '网络异常，请稍后再试' };
  } finally {
    httpRequest.destroy();
  }
}

/** 发送弹幕结果 */
export interface SendDanmakuResult {
  ok: boolean;
  dmid: number;      // 成功后 B 站返回的弹幕 ID
  code: number;
  message: string;
}

/** /x/v2/dm/post 返回的 data 结构 */
interface DmPostData {
  dmid?: number;
}

/**
 * 发送视频弹幕（web 端 /x/v2/dm/post，需登录 CSRF）
 * @param cid 视频分P cid（接口的 oid 字段）
 * @param bvid 稿件 bvid
 * @param msg 弹幕文本（≤100字）
 * @param progress 当前播放进度（毫秒），即弹幕在视频中出现的时间
 * @param mode B站弹幕模式：1=滚动 4=底部 5=顶部
 * @param color 弹幕颜色 RGB（默认白色 16777215）
 */
export async function sendDanmakuVideo(cid: number, bvid: string, msg: string, progress: number, mode: number = 1, color: number = 16777215, fontSize: number = 25): Promise<SendDanmakuResult> {
  const url = 'https://api.bilibili.com/x/v2/dm/post';
  const httpRequest = http.createHttp();
  try {
    const cookie = getCookieHeader();
    const csrf = extractCsrfFromCookie(cookie);
    if (!csrf) {
      logError('[sendDanmakuVideo] 缺少CSRF token，请先登录');
      return { ok: false, dmid: 0, code: -101, message: '账号未登录或Cookie失效' };
    }

    const formData = `type=1&oid=${cid}&msg=${encodeURIComponent(msg)}&mode=${mode}&bvid=${encodeURIComponent(bvid)}`
      + `&progress=${progress}&color=${color}&fontsize=${fontSize}&pool=0&rnd=${Date.now() * 1000}`
      + `&platform=web&csrf=${csrf}&checkbox_type=0`;

    const response = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
        'Cookie': cookie,
        'X-Bili-Mid': getBiliMid()
      },
      extraData: formData,
      connectTimeout: 10000,
      readTimeout: 10000
    });

    if (response.responseCode !== 200) {
      logError(`[sendDanmakuVideo] HTTP 错误: ${response.responseCode}`);
      return { ok: false, dmid: 0, code: response.responseCode as number, message: `网络错误(${response.responseCode})` };
    }

    const result = response.result as string;
    const jsonData = JSON.parse(result) as ApiResponse<DmPostData>;
    if (jsonData.code !== 0) {
      const errMsg = jsonData.message || '';
      if (jsonData.code === -101) {
        logWarn('[sendDanmakuVideo] 未登录: code=-101');
        return { ok: false, dmid: 0, code: -101, message: '账号未登录或Cookie失效，请重新登录' };
      }
      logWarn(`[sendDanmakuVideo] 发送失败: code=${jsonData.code}, message=${errMsg}`);
      return { ok: false, dmid: 0, code: jsonData.code as number, message: errMsg || '发送失败，请稍后再试' };
    }

    const dmid = Number(jsonData.data?.dmid ?? 0);
    logInfo(`[sendDanmakuVideo] 成功: cid=${cid}, dmid=${dmid}`);
    return { ok: true, dmid, code: 0, message: '' };
  } catch (err) {
    logError(`[sendDanmakuVideo] 异常: ${err}`);
    return { ok: false, dmid: 0, code: -1, message: '网络异常，请稍后再试' };
  } finally {
    httpRequest.destroy();
  }
}

/** 评论图片上传结果 */
export interface CommentImageUploadResult {
  url: string;
  width: number;
  height: number;
}

/**
 * 上传评论图片到 B 站图床
 * ⚠️ 用已验证的 upload_bfs（/x/v2/reply/upload 实测 404）；字段与返回沿用
 *    ImGrpcService.uploadChatImage 同套（file_up/category/daily/biz/im/csrf，
 *    data.image_url/宽高），真机验证若评论侧拒收再调整 biz
 * @param filePath 沙箱内图片文件绝对路径（先拷贝到沙箱再传）
 * @param mimeType 图片 MIME（image/jpeg | image/png | image/gif）
 * @param ext 文件扩展名（jpg | png | gif）
 * @returns 上传结果；失败返回 null
 */
export async function uploadCommentImage(filePath: string, mimeType: string, ext: string): Promise<CommentImageUploadResult | null> {
  const httpRequest = http.createHttp();
  try {
    const cookie = getCookieHeader();
    const csrf = extractCsrfFromCookie(cookie);
    if (!csrf) {
      logError('[uploadCommentImage] 缺少CSRF token，请先登录');
      return null;
    }
    // ⚠️ 手动拼 multipart 报文：@ohos.net.http 的 multiFormDataList 在设备上发送的表单
    //    字段缺失（服务端收不到 csrf 字段 → -111），改为完全自控报文（同 ImGrpcService）
    //    图床上传用已验证的 upload_bfs（/x/v2/reply/upload 实测 404）；
    //    biz 沿用 IM 的 im（URL 同为 hdslb 图床，评论侧接受），真机验证有异议再调
    const encoder = new util.TextEncoder();
    const boundary = '----ArkBiliCommentUploadBoundary3f8a2d61';
    const src = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    const stat = fileIo.statSync(filePath);
    const fileBytes = new ArrayBuffer(stat.size);
    fileIo.readSync(src.fd, fileBytes);
    fileIo.closeSync(src);
    const fileArr = new Uint8Array(fileBytes);
    const head = encoder.encode(
      `--${boundary}\r\nContent-Disposition: form-data; name="file_up"; filename="comment_${Date.now()}.${ext}"\r\nContent-Type: ${mimeType}\r\n\r\n`);
    const tail = encoder.encode(
      `\r\n--${boundary}\r\nContent-Disposition: form-data; name="category"\r\n\r\ndaily` +
      `\r\n--${boundary}\r\nContent-Disposition: form-data; name="biz"\r\n\r\nim` +
      `\r\n--${boundary}\r\nContent-Disposition: form-data; name="csrf"\r\n\r\n${csrf}` +
      `\r\n--${boundary}--\r\n`);
    const body = new Uint8Array(head.length + fileArr.length + tail.length);
    body.set(head, 0);
    body.set(fileArr, head.length);
    body.set(tail, head.length + fileArr.length);
    const response = await httpRequest.request('https://api.bilibili.com/x/dynamic/feed/draw/upload_bfs', {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': `multipart/form-data; boundary=${boundary}`,
        'Cookie': cookie,
        'Referer': 'https://www.bilibili.com/video/',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      },
      extraData: body.buffer,
      connectTimeout: 15000,
      readTimeout: 30000
    });
    if (response.responseCode !== 200) {
      logWarn(`[uploadCommentImage] HTTP ${response.responseCode}`);
      return null;
    }
    const resultStr: string = typeof response.result === 'string' ? response.result : String(response.result);
    const json = JSON.parse(resultStr) as Record<string, Object>;
    if ((json['code'] as number) !== 0) {
      logWarn(`[uploadCommentImage] 失败: code=${json['code']}, msg=${json['message']}`);
      return null;
    }
    const data = json['data'] as Record<string, Object>;
    const imageUrl: string = (data['image_url'] as string) || '';
    if (!imageUrl) {
      logWarn(`[uploadCommentImage] 响应缺 image_url`);
      return null;
    }
    const result: CommentImageUploadResult = { url: '', width: 0, height: 0 };
    result.url = imageUrl.startsWith('http://') ? `https://${imageUrl.substring(7)}` : imageUrl;
    result.width = (data['image_width'] as number) || 0;
    result.height = (data['image_height'] as number) || 0;
    return result;
  } catch (err) {
    logError(`[uploadCommentImage] 异常: ${errMsg(err)}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

// ==================== 用户信息接口 ====================
export interface UserInfo {
  isLogin: boolean;
  mid: number;
  uname: string;
  face: string;
}

/**
 * 获取当前登录用户信息
 * @returns 用户信息，失败返回null；被限流返回null
 */
export interface LoginSessionStatus {
  state: LoginVerificationState;
  reason: string;
}

/** Passport success and profile availability are separate states. Never discard a
 * newly issued session merely because nav is rate limited or temporarily offline. */
export async function verifyLoginSession(cookie: string): Promise<LoginSessionStatus> {
  if (!hasLoginSession(cookie)) return { state: 'rejected', reason: '登录响应缺少 SESSDATA，请重新扫码' };
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.bilibili.com/x/web-interface/nav', {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Cookie': mergeLoginCookies([cookie])
      },
      usingCache: false,
      connectTimeout: 8000,
      readTimeout: 8000
    });
    if (response.responseCode !== 200) {
      return { state: 'unavailable', reason: `账号资料接口 HTTP ${response.responseCode}` };
    }
    const body = JSON.parse(response.result as string) as ApiResponse<UserInfo>;
    const state = classifyLoginVerification(response.responseCode, body.code, body.data?.isLogin === true);
    return { state, reason: state === 'rejected' ? `登录会话未通过校验（code=${body.code}），请重新扫码` : `账号资料接口 code=${body.code}` };
  } catch (_err) {
    return { state: 'unavailable', reason: '账号资料接口暂时不可用' };
  } finally {
    request.destroy();
  }
}

export async function getUserInfo(loginCookie?: string): Promise<UserInfo | null> {
  const url = 'https://api.bilibili.com/x/web-interface/nav';

  // 限流重试：最多3次，指数退避 2s→4s→8s
  const maxRetries = 3;
  let retryDelay = 2000;

  for (let retry = 0; retry <= maxRetries; retry++) {
    if (retry > 0) {
      logWarn(`[getUserInfo] 第${retry}次重试，等待${retryDelay}ms`);
      await new Promise<void>((resolve: Function) => setTimeout(resolve, retryDelay));
      retryDelay *= 2;
    }

    const httpRequest = http.createHttp();
    try {
      await throttleRequest();
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.com/',
          'Cookie': loginCookie !== undefined ? mergeLoginCookies([loginCookie]) : getCookieHeader()
        },
        connectTimeout: 10000,
        readTimeout: 10000
      });

      // 412 = 限流，需要重试
      if (response.responseCode === 412) {
        logError(`[getUserInfo] 被限流(412)，${retry < maxRetries ? '准备重试' : '已达最大重试次数'}`);
        triggerRateLimitCooldown();
        if (retry < maxRetries) {
          continue;
        }
        return null;
      }

      if (response.responseCode !== 200) {
        logError(`获取用户信息 HTTP 错误: ${response.responseCode}`);
        return null;
      }

      const result = response.result as string;
      const jsonData = JSON.parse(result) as ApiResponse<UserInfo>;

      if (jsonData.code !== 0) {
        logWarn(`获取用户信息失败: code=${jsonData.code}`);
        return null;
      }

      return jsonData.data || null;
    } catch (err) {
      logError(`获取用户信息异常: ${err}`);
      if (retry < maxRetries) {
        continue;
      }
      return null;
    } finally {
      httpRequest.destroy();
    }
  }
  return null;
}

/**
 * 关注状态响应
 */
export interface FollowStatus {
  attribute: number;  // 0:未关注, 1:已关注, 2:被拉黑
}

// ⭐ 关注列表缓存（单次拉取后缓存，关注/取关后清空）
let _followedMidsSingleton: Set<number> | null = null;

/** 清空关注列表缓存（关注/取关后调用） */
export function clearFollowedMidsCache(): void {
  _followedMidsSingleton = null;
}

/**
 * 查询指定用户是否被当前用户关注
 * 使用 /x/web-interface/card 接口（x/relation 接口已失效，返回 -400）
 * 
 * 响应格式：
 * {
 *   "code": 0,
 *   "data": {
 *     "card": { ... },        // 用户名片信息
 *     "following": true,      // ⭐ 关注状态在 data.following，不在 card 内！
 *     ...
 *   }
 * }
 */
interface CardData {
  like_num?: number;
  card?: Object;
  following: boolean;
}

interface CardResponse {
  code: number;
  data?: CardData;
}

export async function getFollowStatus(mid: number): Promise<boolean> {
  const url = `https://api.bilibili.com/x/web-interface/card?mid=${mid}`;
  logInfo(`[getFollowStatus] 开始查询 mid=${mid}`);
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: getBiliRequestHeaders(),
      connectTimeout: 5000,
      readTimeout: 5000
    });
    if (response.responseCode === 200) {
      const raw = response.result as string;
      const data = JSON.parse(raw) as CardResponse;
      if (data.code === 0 && data.data) {
        const following = data.data.following;
        logInfo(`[getFollowStatus] mid=${mid}, following=${following}`);
        // B站API可能返回 true/false 或 0/1，统一转数字判断
        return Number(following) === 1;
      }
      logWarn(`[getFollowStatus] mid=${mid}, API错误 code=${data.code}`);
    } else {
      logWarn(`[getFollowStatus] mid=${mid}, HTTP ${response.responseCode}`);
    }
  } catch (e) {
    logWarn(`[getFollowStatus] mid=${mid} 异常: ${e}`);
  } finally {
    httpRequest.destroy();
  }
  return false;
}

/**
 * 按 mid 获取用户头像 URL
 * 使用 /x/web-interface/card 接口（返回 data.card.face）
 * @param mid 用户 mid
 * @returns 头像 URL；失败返回空串
 */
export async function getUserFaceByMid(mid: number): Promise<string> {
  if (!mid || mid <= 0) {
    return '';
  }
  try {
    // ⚠️ /x/web-interface/card 裸请求与 WBI 均返回 412 风控；改用项目验证可用的 /x/space/wbi/acc/info
    const info = await getUserSpaceInfo(mid);
    if (info && info.face) {
      return info.face;
    }
    logWarn(`[getUserFaceByMid] mid=${mid}, 空间信息无 face`);
  } catch (e) {
    logWarn(`[getUserFaceByMid] mid=${mid} 异常: ${errMsg(e)}`);
  }
  return '';
}

/**
 * 获取当前用户关注的 UP 主 mid 集合
 * 使用 /x/relation/followings 接口
 */
interface FollowingItem {
  mid: number;
}

interface FollowingsListData {
  list: FollowingItem[];
}

// batchCheckFollowStatus 和 checkSingleFollowStatus 已移除（触发风控 code=-352）
// 改用本地 AppStorage 持久化缓存来恢复关注状态

export async function getFollowedMids(): Promise<Set<number>> {
  if (_followedMidsSingleton) {
    logInfo(`[getFollowedMids] 返回缓存，共 ${_followedMidsSingleton.size} 个`);
    return _followedMidsSingleton;
  }

  const myMidStr = getBiliMid();
  const myMid = parseInt(myMidStr, 10);
  if (!myMid || isNaN(myMid)) {
    logWarn('[getFollowedMids] 无法获取当前用户 mid');
    return new Set();
  }

  const followedMids = new Set<number>();
  const pageSize = 50;
  let page = 1;
  let hasMore = true;

  while (hasMore) {
    await throttleRequest();
    const url = `https://api.bilibili.com/x/relation/followings?vmid=${myMid}&ps=${pageSize}&pn=${page}`;
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: getBiliRequestHeaders(),
        connectTimeout: 10000,
        readTimeout: 10000
      });

      if (response.responseCode !== 200) {
        logWarn(`[getFollowedMids] HTTP错误: ${response.responseCode}，已获取 ${followedMids.size} 个`);
        break;
      }

      const jsonData = JSON.parse(response.result as string) as ApiResponse<FollowingsListData>;
      if (jsonData.code !== 0) {
        logWarn(`[getFollowedMids] API错误: code=${jsonData.code}，已获取 ${followedMids.size} 个`);
        break;
      }

      const list = jsonData.data?.list;
      if (!list || list.length === 0) {
        hasMore = false;
      } else {
        for (const item of list) {
          if (item.mid) {
            followedMids.add(item.mid);
          }
        }
        if (list.length < pageSize) {
          hasMore = false;
        } else {
          page++;
        }
      }
    } catch (e) {
      logError(`[getFollowedMids] 异常: ${e}`);
      hasMore = false;
    } finally {
      httpRequest.destroy();
    }
  }

  logInfo(`[getFollowedMids] 完成，共获取 ${followedMids.size} 个关注`);
  // 成功获取到数据后缓存（避免 API 失败时缓存空结果）
  if (followedMids.size > 0) {
    _followedMidsSingleton = followedMids;
  }
  return followedMids;
}

/**
 * 修改关系状态（关注/取关/拉黑等）
 * @param mid UP主的mid
 * @param act 操作: 1=关注, 2=取关
 * @returns 是否成功
 */
export async function modifyRelation(mid: number, act: 1 | 2 | 5 | 6): Promise<boolean> {
  const url = 'https://api.bilibili.com/x/relation/modify';
  const httpRequest = http.createHttp();
  try {
    // 获取CSRF token
    const cookie = getCookieHeader();
    const csrf = extractCsrfFromCookie(cookie);
    if (!csrf) {
      logError('[modifyRelation] 缺少CSRF token，请先登录');
      return false;
    }
    
    const formData = `fid=${mid}&act=${act}&re_src=11&csrf=${csrf}`;
    
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Cookie': getCookieHeader(),
        'X-Bili-Mid': getBiliMid()
      },
      extraData: formData,
      connectTimeout: 10000,
      readTimeout: 10000
    });

    if (response.responseCode !== 200) {
      logError(`修改关注状态 HTTP 错误: ${response.responseCode}`);
      return false;
    }

    const result = response.result as string;
    const jsonData = JSON.parse(result) as ApiResponse<Object>;

    if (jsonData.code !== 0) {
      // code=22014: "已经关注用户，无法重复关注" — 对于关注操作而言就是成功
      if (jsonData.code === 22014 && act === 1) {
        logInfo(`[modifyRelation] 已经关注过该用户: mid=${mid}`);
        return true;
      }
      logWarn(`修改关注状态失败: code=${jsonData.code}, message=${jsonData.message}`);
      return false;
    }

    logInfo(`[modifyRelation] 成功: mid=${mid}, act=${act}`);
    return true;
  } catch (err) {
    logError(`修改关系状态异常: ${err}`);
    return false;
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 修改关注状态
 * @param mid UP主的mid
 * @param act 操作: 1=关注, 2=取关
 * @returns 是否成功
 */
export async function modifyFollow(mid: number, act: 1 | 2): Promise<boolean> {
  return modifyRelation(mid, act);
}

/**
 * 拉黑UP主
 * @param mid UP主的mid
 * @returns 是否成功
 */
export async function blacklistUploader(mid: number): Promise<boolean> {
  return modifyRelation(mid, 5);
}

/**
 * 取消拉黑UP主
 * @param mid UP主的mid
 * @returns 是否成功
 */
export async function unblacklistUploader(mid: number): Promise<boolean> {
  return modifyRelation(mid, 6);
}

// ========== 用户空间相关接口 ==========

export interface OfficialVerify {
  type: number;
  desc: string;
}

export interface PendantInfo {
  image: string;
  name: string;
}

export interface UpSpaceList {
  vlist: UpSpaceVideoItem[];
}

export interface UpSpacePageInfo {
  pn: number;
  ps: number;
  count: number;
}

/**
 * 用户空间信息（头像、签名、等级等）
 */
export interface UpSpaceInfo {
  mid: number;
  name: string;
  face: string;
  sign: string;           // 个人签名
  level: number;          // 等级
  sex: string;            // 性别
  top_photo: string;      // 个人主页头图
  ip_location?: string;
  birthday?: string;
  official_verify: OfficialVerify;
  pendant?: PendantInfo;
  following: number;      // 0=未关注, 1=已关注（当前请求用户是否关注了该用户）
  is_followed: number;    // x/space/wbi/acc/info 实际返回的是 is_followed
}

interface UpSpaceInfoResponse {
  code: number;
  message: string;
  data?: UpSpaceInfo;
}

/**
 * 用户关系统计数据
 */
export interface UpRelationStat {
  mid: number;
  following: number;      // 关注数
  follower: number;       // 粉丝数
  whitelist: number;
}

interface UpRelationStatResponse {
  code: number;
  message: string;
  data?: UpRelationStat;
}

/**
 * 用户空间视频列表中的单个视频
 */
export interface UpSpaceVideoItem {
  aid: number;
  bvid: string;
  title: string;
  pic: string;
  duration: number;       // 秒
  play: number;           // 播放数
  danmaku: number;        // 弹幕数
  pubdate: number;        // 发布时间戳
  description: string;
}

/** Web 空间接口使用 length/created/video_review，统一为页面使用的字段。 */
interface UpSpaceRawVideoItem extends UpSpaceVideoItem {
  length?: string;
  created?: number;
  video_review?: number;
}

function normalizeSpaceVideoData(data: UpSpaceVideoData): UpSpaceVideoData {
  const videos = data.list.vlist.map((item: UpSpaceVideoItem): UpSpaceVideoItem => {
    const raw = item as UpSpaceRawVideoItem;
    let duration = Number(raw.duration);
    if (!Number.isFinite(duration) || duration <= 0) {
      const parts = (raw.length || '').split(':');
      duration = 0;
      for (const part of parts) {
        const value = Number(part);
        if (!Number.isFinite(value) || value < 0) { duration = 0; break; }
        duration = duration * 60 + value;
      }
    }
    return {
      aid: raw.aid, bvid: raw.bvid, title: raw.title, pic: raw.pic,
      duration: duration, play: raw.play || 0,
      danmaku: raw.danmaku ?? raw.video_review ?? 0,
      pubdate: raw.pubdate || raw.created || 0,
      description: raw.description || ''
    };
  });
  return { list: { vlist: videos }, page: data.page };
}

/**
 * 用户空间视频列表返回
 */
export interface UpSpaceVideoData {
  list: UpSpaceList;
  page: UpSpacePageInfo;
}

interface UpSpaceVideoResponse {
  code: number;
  message: string;
  data?: UpSpaceVideoData;
}

/**
 * 获取用户空间基本信息
 * @param mid 用户mid
 * @returns 用户空间信息
 */
export async function getUserSpaceInfo(mid: number): Promise<UpSpaceInfo | null> {
  await throttleRequest();
  // 使用WBI签名端点
  const params: Record<string, string> = {};
  params['mid'] = mid.toString();
  let queryStr: string;
  try {
    queryStr = await AppSign.generateWebParams(params);
  } catch (_e) {
    logWarn(`[getUserSpaceInfo] WBI签名失败，使用未签名请求: ${_e}`);
    queryStr = 'mid=' + mid.toString();
  }
  const url = 'https://api.bilibili.com/x/space/wbi/acc/info?' + queryStr;
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: getBiliRequestHeaders(),
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode === 200) {
      const data = JSON.parse(response.result as string) as UpSpaceInfoResponse;
      if (data.code === 0 && data.data) {
        return data.data;
      }
      // 遇到限流，等待后重试（最多重试1次）
      if (data.code === -799) {
        logWarn('[getUserSpaceInfo] 被限流，等待3秒后重试...');
        await new Promise<void>(resolve => setTimeout(resolve, 3000));
        await throttleRequest();
        const retryResp = await httpRequest.request(url, {
          method: http.RequestMethod.GET,
          header: getBiliRequestHeaders(),
          connectTimeout: 10000,
          readTimeout: 10000
        });
        if (retryResp.responseCode === 200) {
          const retryData = JSON.parse(retryResp.result as string) as UpSpaceInfoResponse;
          if (retryData.code === 0 && retryData.data) {
            return retryData.data;
          }
          logWarn(`[getUserSpaceInfo] 重试后依然出错: code=${retryData.code}, msg=${retryData.message}`);
        }
        return null;
      }
      logWarn(`[getUserSpaceInfo] API错误: code=${data.code}, msg=${data.message}`);
    } else {
      logError(`[getUserSpaceInfo] HTTP错误: ${response.responseCode}`);
    }
    return null;
  } catch (err) {
    logError(`[getUserSpaceInfo] 异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 获取用户关系统计（粉丝数、关注数）
 * @param mid 用户mid
 * @returns 关系统计
 */
export async function getUserRelationStat(mid: number): Promise<UpRelationStat | null> {
  await throttleRequest();
  const url = `https://api.bilibili.com/x/relation/stat?vmid=${mid}`;
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: getBiliRequestHeaders(),
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode === 200) {
      const data = JSON.parse(response.result as string) as UpRelationStatResponse;
      if (data.code === 0 && data.data) {
        return data.data;
      }
      logWarn(`[getUserRelationStat] API错误: code=${data.code}, msg=${data.message}`);
    } else {
      logError(`[getUserRelationStat] HTTP错误: ${response.responseCode}`);
    }
    return null;
  } catch (err) {
    logError(`[getUserRelationStat] 异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 获取用户发布的视频列表
 * @param mid 用户mid
 * @param page 页码（从1开始）
 * @param pageSize 每页数量，默认30
 * @param order 排序方式：pubdate=最新发布, click=最多播放, stow=最多收藏（默认最新发布）
 * @returns 视频列表数据
 */
export async function getUserSpaceVideos(mid: number, page: number = 1, pageSize: number = 30,
  order: string = 'pubdate', keyword: string = ''): Promise<UpSpaceVideoData | null> {
  await throttleRequest();
  // 使用WBI签名端点
  const params: Record<string, string> = {};
  params['mid'] = mid.toString();
  params['pn'] = page.toString();
  params['ps'] = pageSize.toString();
  params['order'] = order;
  if (keyword.trim()) params['keyword'] = keyword.trim();
  let queryStr: string;
  try {
    queryStr = await AppSign.generateWebParams(params);
  } catch (_e) {
    logWarn(`[getUserSpaceVideos] WBI签名失败，使用未签名请求: ${_e}`);
    // WBI签名失败时，直接使用参数拼接
    queryStr = 'mid=' + mid.toString() + '&pn=' + page.toString() + '&ps=' + pageSize.toString() + '&order=' + order;
    if (keyword.trim()) queryStr += '&keyword=' + encodeURIComponent(keyword.trim());
  }
  const url = 'https://api.bilibili.com/x/space/wbi/arc/search?' + queryStr;
  logInfo('[getUserSpaceVideos] WBI请求: ' + url.substring(0, 150));
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: getBiliRequestHeaders(),
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode === 200) {
      const rawResult = response.result as string;
      logInfo(`[getUserSpaceVideos] 原始响应(前300字): ${rawResult.substring(0, 300)}`);
      const data = JSON.parse(rawResult) as UpSpaceVideoResponse;
      if (data.code === 0 && data.data) {
        logInfo(`[getUserSpaceVideos] 成功: 视频数=${data.data.page.count}, 列表长度=${data.data.list.vlist.length}`);
        return normalizeSpaceVideoData(data.data);
      }
      // 遇到限流，使用循环重试（最多3次，每次递增等待）
      if (data.code === -799) {
        let retryResult: UpSpaceVideoData | null = null;
        for (let retry = 1; retry <= 3; retry++) {
          const waitMs = 3000 + retry * 2000; // 5s, 7s, 9s
          logWarn(`[getUserSpaceVideos] 第${retry}次重试，等待${waitMs}ms...`);
          await new Promise<void>(resolve => setTimeout(resolve, waitMs));
          await throttleRequest();
          const retryResp = await httpRequest.request(url, {
            method: http.RequestMethod.GET,
            header: getBiliRequestHeaders(),
            connectTimeout: 10000,
            readTimeout: 10000
          });
          if (retryResp.responseCode === 200) {
            const retryData = JSON.parse(retryResp.result as string) as UpSpaceVideoResponse;
            if (retryData.code === 0 && retryData.data) {
              retryResult = normalizeSpaceVideoData(retryData.data);
              break;
            }
            if (retryData.code !== -799) {
              logWarn(`[getUserSpaceVideos] 非限流错误 code=${retryData.code}, msg=${retryData.message}`);
              break;
            }
            logWarn(`[getUserSpaceVideos] 第${retry}次仍被限流`);
          } else {
            logError(`[getUserSpaceVideos] 第${retry}次HTTP错误: ${retryResp.responseCode}`);
            break;
          }
        }
        return retryResult;
      }
      logWarn(`[getUserSpaceVideos] API错误: code=${data.code}, msg=${data.message}`);
    } else {
      logError(`[getUserSpaceVideos] HTTP错误: ${response.responseCode}`);
    }
    return null;
  } catch (err) {
    logError(`[getUserSpaceVideos] 异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

/** App 空间头图与 Web top_photo 独立，含用户设置和默认日夜背景。 */
export interface UpSpaceImages {
  imgUrl?: string;
  night_imgurl?: string;
}

interface UpAppSpaceTag {
  type?: string;
  title?: string;
}

interface UpAppSpaceCard {
  mid?: string;
  name?: string;
  face?: string;
  sign?: string;
  sex?: string;
  birthday?: string;
  fans?: number;
  attention?: number;
  likes?: UpAppSpaceLikes;
  level_info?: UpAppSpaceLevel;
  official_verify?: OfficialVerify;
  relation?: UpAppSpaceRelation;
  space_tag?: UpAppSpaceTag[];
  ip_location?: string;
}

interface UpAppSpaceLikes { like_num?: number; }
interface UpAppSpaceLevel { current_level?: number; }
interface UpAppSpaceRelation { is_follow?: number; }

interface UpAppSpaceData {
  images?: UpSpaceImages;
  card?: UpAppSpaceCard;
}

interface UpAppSpaceResponse {
  code: number;
  data?: UpAppSpaceData;
}

/** App card supplies statistics and location tags even when Web endpoints fail. */
export function mergeUpSpaceProfile(mid: number, webInfo: UpSpaceInfo | null,
  webRelation: UpRelationStat | null, webCard: CardData | null, app: UpAppSpaceData | null): UpSpaceInitData {
  const card = app?.card;
  const location = card?.space_tag?.find((tag: UpAppSpaceTag) => tag.type === 'location')?.title?.trim();
  const ipLocation = location || card?.ip_location || webInfo?.ip_location || '';
  let info = webInfo;
  if (card) {
    info = {
      mid: mid, name: card.name ?? webInfo?.name ?? '', face: card.face ?? webInfo?.face ?? '',
      sign: card.sign ?? webInfo?.sign ?? '', sex: card.sex ?? webInfo?.sex ?? '',
      level: card.level_info?.current_level ?? webInfo?.level ?? 0,
      birthday: card.birthday || webInfo?.birthday || '',
      top_photo: webInfo?.top_photo || '', ip_location: ipLocation,
      official_verify: card.official_verify ?? webInfo?.official_verify ?? { type: -1, desc: '' },
      pendant: webInfo?.pendant,
      following: webInfo?.following ?? 0, is_followed: webInfo?.is_followed ?? 0
    };
  }
  let relation = webRelation;
  if (card?.fans !== undefined && card.attention !== undefined) {
    relation = { mid: mid, follower: card.fans, following: card.attention, whitelist: webRelation?.whitelist ?? 0 };
  }
  const appFollow = card?.relation?.is_follow;
  return {
    images: app?.images ?? null, info: info, relation: relation,
    likes: card?.likes?.like_num ?? webCard?.like_num ?? null,
    isFollowed: appFollow !== undefined ? appFollow === 1 : (webCard !== null ? Number(webCard.following) === 1 : Number(webInfo?.is_followed) === 1)
  };
}

/** 只显示用户头图；接口自带的默认日夜背景视为空，再尝试其它来源。 */
export function resolveSpaceHeaderImage(images: UpSpaceImages | null, dark: boolean, webPhoto: string): string {
  const day = images?.imgUrl?.trim() || '';
  const night = images?.night_imgurl?.trim() || '';
  const candidates = dark ? [night, day] : [day, night];
  // App 明确返回默认头图时表示未设置，不能再被旧 Web 默认图覆盖。
  if (!day && !night) candidates.push(webPhoto.trim());
  for (const url of candidates) {
    if (!url) continue;
    // App 即使没有自定义头图也会返回这对默认图，不能据此判定用户设置了背景。
    if (/\/bfs\/activity-plat\/static\/9bdd988aed64a23976d6d5494533a450\/(tDojHPi2LG|5A10HwGd3)\.jpg(?:[@?].*)?$/.test(url)) continue;
    if (url.startsWith('//')) return 'https:' + url;
    if (url.startsWith('http://')) return 'https://' + url.substring(7);
    if (url.startsWith('bfs/')) return 'https://i0.hdslb.com/' + url;
    return url;
  }
  return '';
}

/** 手机端资料统一请求，复用已有登录凭证以获取属地等完整字段。 */
async function getUpAppSpaceData(mid: number): Promise<UpAppSpaceData | null> {
  const request = http.createHttp();
  try {
    const params: Record<string, string> = {};
    params['vmid'] = mid.toString();
    params['build'] = '8430300';
    params['mobi_app'] = 'android_hd';
    params['platform'] = 'android';
    params['ts'] = Math.floor(Date.now() / 1000).toString();
    const accessKey = AppStorage.get<string>('biliAccessKey') || '';
    if (accessKey) params['access_key'] = accessKey;
    await AppSign.signParams(params, 'android_hd');
    const query = Object.keys(params).sort().map((key: string) =>
      encodeURIComponent(key) + '=' + encodeURIComponent(params[key])).join('&');
    const response = await request.request('https://app.bilibili.com/x/v2/space?' + query, {
      method: http.RequestMethod.GET,
      header: getBiliRequestHeaders(),
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode === 200) {
      const result = JSON.parse(response.result as string) as UpAppSpaceResponse;
      if (result.code === 0 && result.data) {
        logInfo(`[UpSpace] App资料 mid=${mid}, appAuth=${!!accessKey}, webAuth=${hasLoginSession(getCookieHeader())}, card=${!!result.data.card}, day=${!!result.data.images?.imgUrl}, night=${!!result.data.images?.night_imgurl}, location=${!!result.data.card?.space_tag?.find((tag: UpAppSpaceTag) => tag.type === 'location')}`);
        return result.data;
      }
      logWarn(`[getUpAppSpaceData] API错误: code=${result.code}`);
    }
  } catch (error) {
    logWarn(`[getUpAppSpaceData] 请求失败: ${errMsg(error)}`);
  } finally {
    request.destroy();
  }
  return null;
}

/**
 * 合并后的空间初始化数据
 */
export interface UpSpaceInitData {
  images: UpSpaceImages | null;
  likes: number | null;
  info: UpSpaceInfo | null;
  relation: UpRelationStat | null;
  isFollowed: boolean;
}

/**
 * 获取用户空间初始化数据（并行加载UP主信息+关系统计+关注状态）
 * 代替原来的3次串行请求，节省至少3秒的节流等待时间
 * 同时读取 App 日夜头图，所有 HTTP 请求并行发起，互不阻塞
 */
export async function getUpSpaceInitData(mid: number): Promise<UpSpaceInitData> {
  logInfo('[UpSpace] 并行加载空间初始化数据 mid=' + mid);
  // 构建WBI签名的请求URL
  const infoParams: Record<string, string> = {};
  infoParams['mid'] = mid.toString();
  let infoQueryStr: string;
  try {
    infoQueryStr = await AppSign.generateWebParams(infoParams);
  } catch (_e) {
    infoQueryStr = 'mid=' + mid.toString();
  }
  const infoUrl = 'https://api.bilibili.com/x/space/wbi/acc/info?' + infoQueryStr;
  const statUrl = `https://api.bilibili.com/x/relation/stat?vmid=${mid}`;
  const cardUrl = `https://api.bilibili.com/x/web-interface/card?mid=${mid}`;
  const headers = getBiliRequestHeaders();

  // Web 资料、统计、名片与 App 头图同时发起
  const p1 = doUpSpaceInfoReq(infoUrl, headers);
  const p2 = doUpRelationStatReq(statUrl, headers);
  const p3 = doUpFollowStatusReq(cardUrl, headers);
  const p4 = getUpAppSpaceData(mid);

  const info: UpSpaceInfo | null = await p1;
  const relation: UpRelationStat | null = await p2;
  const card: CardData | null = await p3;
  const app: UpAppSpaceData | null = await p4;
  return mergeUpSpaceProfile(mid, info, relation, card, app);
}

/** 内部：请求UP主空间信息（无节流） */
async function doUpSpaceInfoReq(url: string, headers: Record<string, string>): Promise<UpSpaceInfo | null> {
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode === 200) {
      const data = JSON.parse(response.result as string) as UpSpaceInfoResponse;
      if (data.code === 0 && data.data) {
        return data.data;
      }
      logWarn(`[doUpSpaceInfoReq] API错误: code=${data.code}, msg=${data.message}`);
    } else {
      logError(`[doUpSpaceInfoReq] HTTP错误: ${response.responseCode}`);
    }
  } catch (err) {
    logWarn(`[doUpSpaceInfoReq] 请求失败: ${err}`);
  } finally {
    httpRequest.destroy();
  }
  return null;
}

/** 内部：请求用户关系统计（无节流） */
async function doUpRelationStatReq(url: string, headers: Record<string, string>): Promise<UpRelationStat | null> {
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode === 200) {
      const data = JSON.parse(response.result as string) as UpRelationStatResponse;
      if (data.code === 0 && data.data) {
        return data.data;
      }
      logWarn(`[doUpRelationStatReq] API错误: code=${data.code}, msg=${data.message}`);
    } else {
      logError(`[doUpRelationStatReq] HTTP错误: ${response.responseCode}`);
    }
  } catch (err) {
    logWarn(`[doUpRelationStatReq] 请求失败: ${err}`);
  } finally {
    httpRequest.destroy();
  }
  return null;
}

/** 内部：请求关注状态（无节流） */
async function doUpFollowStatusReq(url: string, headers: Record<string, string>): Promise<CardData | null> {
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 5000,
      readTimeout: 5000
    });
    if (response.responseCode === 200) {
      const data = JSON.parse(response.result as string) as CardResponse;
      if (data.code === 0 && data.data) {
        return data.data;
      }
      logWarn(`[doUpFollowStatusReq] API错误: code=${data.code}`);
    } else {
      logWarn(`[doUpFollowStatusReq] HTTP ${response.responseCode}`);
    }
  } catch (err) {
    logWarn(`[doUpFollowStatusReq] 异常: ${err}`);
  } finally {
    httpRequest.destroy();
  }
  return null;
}

// ══════════════════════════════════════════════════════════════
// UP主空间动态（x/polymer/web-dynamic/v1/feed/space）
// ══════════════════════════════════════════════════════════════

/** 动态-作者模块原始结构 */
interface DynRawAuthor {
  mid?: number;
  name?: string;
  face?: string;
  pub_ts?: number;
  /** ⭐ B 站新版发布时间（可能为秒级时间戳字符串，或"08-15"等相对文本；pub_ts=0 时兜底用） */
  pub_time?: string;
}

/** 动态-正文描述原始结构 */
interface DynRawDesc {
  text?: string;
  orig_text?: string;
  rich_text_nodes?: DynRawRichTextNode[];
  /** ⭐ 发布时间戳（秒级）：module_author.pub_ts 缺失时的兜底来源（B 站动态标准字段） */
  timestamp?: number;
}

/** B 站 EMOJI 节点表情信息（icon_url 为表情图片地址，用于表情渲染） */
interface DynRawEmojiInfo {
  icon_url?: string;
  text?: string;
  size?: number;
}

/** 动态-富文本节点原始结构（图文动态正文在 rich_text_nodes 数组中） */
interface DynRawRichTextNode {
  type?: string;
  text?: string;
  orig_text?: string;
  /** ⭐ B 站 EMOJI 节点：含表情图片 url（RICH_TEXT_NODE_TYPE_EMOJI 时存在，用于表情渲染） */
  emoji?: DynRawEmojiInfo;
  /** ⭐ @某人 / BV号 等节点的业务 id：AT 节点是 mid（B 站有时给数字有时给字符串，统一转成数字） */
  rid?: number | string;
}

/** 动态正文分段（文字段 / 表情段 / @某人 / #话题#）：表情段含 emoteUrl，渲染为表情图片 */
export interface DynTextSegment {
  text: string;
  emoteUrl?: string;
  /** ⭐ 分段类型：'at'(@某人) / 'topic'(#话题#) / 'text'(普通文字，缺省)。用于渲染样式与点击交互 */
  kind?: string;
  /** ⭐ @ 节点的用户 mid（点击进 TA 的空间用） */
  mid?: number;
}

/** 动态-视频统计原始结构 */
interface DynRawStat {
  play?: number;
  danmaku?: number;
}

/** 动态-视频信息原始结构（MAJOR_TYPE_ARCHIVE） */
interface DynRawArchive {
  aid?: number;
  bvid?: string;
  title?: string;
  cover?: string;
  desc?: string;
  duration_text?: string;
  stat?: DynRawStat;
}

/** 动态-图片项原始结构（MAJOR_TYPE_DRAW） */
interface DynRawDrawItem {
  src?: string;
  width?: number;
  height?: number;
}

/** 动态-图片列表原始结构 */
interface DynRawDraw {
  items?: DynRawDrawItem[];
}

/** 动态-通用卡片原始结构（MAJOR_TYPE_COMMON：专栏/活动/小程序） */
interface DynRawCommon {
  title?: string;
  desc?: string;
  cover?: string;
  jump_url?: string;
}

/** 动态-major（主内容）原始结构 */
interface DynRawMajor {
  type?: string;
  archive?: DynRawArchive;
  draw?: DynRawDraw;
  common?: DynRawCommon;
  article?: DynRawArticle;
  pgc?: DynRawArticle;
  season?: DynRawArticle;
  opus?: DynRawOpus;
}

/** 动态-专栏文章（MAJOR_TYPE_ARTICLE，番剧/专栏分类用）原始结构 */
interface DynRawArticle {
  title?: string;
  desc?: string;
  cover?: string;
  jump_url?: string;
  /** ⭐ 番剧季 id（major.pgc/season 专用：跳转播放页优先用 season_id 走季接口取 cid） */
  season_id?: number;
  /** ⭐ 分集 id（major.pgc/season 专用：season_id 缺失时用 ep_id 兜底） */
  ep_id?: number;
}

/** 动态-图文（MAJOR_TYPE_OPUS，新版图文动态）图片项原始结构 */
interface DynRawOpusPic {
  url?: string;
  width?: number;
  height?: number;
}

/** 动态-图文（MAJOR_TYPE_OPUS）摘要原始结构 */
interface DynRawOpusSummary {
  text?: string;
  rich_text_nodes?: DynRawRichTextNode[];
}

/** 动态-图文（MAJOR_TYPE_OPUS，新版图文动态）原始结构：正文在 summary.text，图片在 pics */
interface DynRawOpus {
  title?: string;
  summary?: DynRawOpusSummary;
  pics?: DynRawOpusPic[];
  jump_url?: string;
}

/** 动态-正文模块原始结构 */
interface DynRawDynamic {
  desc?: DynRawDesc;
  major?: DynRawMajor;
}

/** 动态-统计计数原始结构 */
interface DynRawStatCount {
  count?: number;
  /** ⭐ 当前登录用户是否已赞（B 站 module_stat.like.status）—— 决定点赞胶囊的选中态 */
  status?: boolean;
}

/** 动态-统计模块原始结构 */
interface DynRawStatModule {
  like?: DynRawStatCount;
  forward?: DynRawStatCount;
  comment?: DynRawStatCount;
}

/** 动态-模块集合原始结构 */
interface DynRawModules {
  module_author?: DynRawAuthor;
  module_dynamic?: DynRawDynamic;
  module_stat?: DynRawStatModule;
}

/** 动态-单条原始结构 */
interface DynRawItem {
  id_str?: string;
  type?: string;
  /** ⭐ 评论区定位信息：**动态的评论区不一定挂在自己身上**（视频/专栏类动态的评论挂在稿件/专栏上），
   *  必须用 basic.comment_type + basic.comment_id_str 去请求评论，不能一律用 type=17 + 动态 id */
  basic?: DynRawBasic;
  modules?: DynRawModules;
  orig?: DynRawItem;
}

/** 动态-basic（评论区定位：comment_type=评论区类型码，comment_id_str=评论区对象 id） */
interface DynRawBasic {
  comment_id_str?: string;
  comment_type?: number;
  rid_str?: string;
}

/** 动态-列表原始结构 */
interface DynRawData {
  items?: DynRawItem[];
  offset?: string;
  has_more?: boolean;
  total?: number;
}

/** 动态-响应原始结构 */
interface DynSpaceResponse {
  code: number;
  message: string;
  data?: DynRawData;
}

/** 动态-视频信息（渲染用，扁平化） */
export interface DynVideoInfo {
  aid: number;
  bvid: string;
  title: string;
  cover: string;
  desc: string;
  durationText: string;
  play: number;
  danmaku: number;
}

/** 动态-图片项（渲染用） */
export interface DynImageInfo {
  src: string;
  width: number;
  height: number;
}

/** 动态-通用卡片（渲染用） */
export interface DynCommonInfo {
  title: string;
  desc: string;
  cover: string;
  jumpUrl: string;
  /** ⭐ 番剧季 id（跳转播放页优先用：季接口 /pgc/view/web/season 才能取到 cid） */
  seasonId: number;
  /** ⭐ 分集 id（seasonId 缺失时兜底） */
  epId: number;
}

/** 动态-单条（渲染用，扁平化） */
export interface SpaceDynamicItem {
  idStr: string;
  type: string;        // DYNAMIC_TYPE_AV / DRAW / FORWARD / WORD ...
  majorType: string;   // MAJOR_TYPE_ARCHIVE / DRAW / COMMON ...
  pubTs: number;
  authorMid: number;
  authorName: string;
  authorFace: string;
  text: string;        // 正文
  /** ⭐ 正文分段（含 B 站表情 emoji → 表情图片）：动态正文渲染时按段混排文字/表情图 */
  textSegments: DynTextSegment[];
  video: DynVideoInfo | null;
  images: DynImageInfo[];
  common: DynCommonInfo | null;
  likeCount: number;
  forwardCount: number;
  commentCount: number;
  /** ⭐ 当前登录用户是否已点赞（来自 module_stat.like.status）；点赞按钮的选中态 */
  liked: boolean;
  /**
   * ⭐ 评论区定位（评论区**不在动态本体**上时靠它）：
   *   - `commentType`：评论区类型码（1=视频稿件 / 11=相簿 / 12=专栏 / 17=纯文字·转发动态）
   *   - `commentIdStr`：评论区对象 id（视频=aid、相簿=相簿id、纯文字动态=动态id）
   *   来源 `basic.comment_type` / `basic.comment_id_str`。
   *   ⚠️ 直接用 `type=17 + id_str` 去拉评论，视频类动态会得到 `-404 啥都木有`（2026-09-18 真机踩到）。
   *   两者缺失时由解析层兜底为 (17, id_str)。
   */
  commentType: number;
  commentIdStr: string;
  orig: SpaceDynamicItem | null;   // 转发源
}

/** 动态-列表返回 */
export interface UpSpaceDynamicData {
  items: SpaceDynamicItem[];
  offset: string;
  hasMore: boolean;
  total: number;
}

/**
 * 从动态 desc 提取正文文本：
 * 优先 desc.text；图文动态（MAJOR_TYPE_DRAW）正文在 orig_text（顶层完整文本）或 rich_text_nodes 节点中
 */
function buildDynText(desc: DynRawDesc | undefined): string {
  if (!desc) return '';
  const direct = desc.text ?? '';
  if (direct.length > 0) return direct;
  const orig = desc.orig_text ?? '';
  if (orig.length > 0) return orig;
  const nodes = desc.rich_text_nodes ?? [];
  let text = '';
  for (const node of nodes) {
    const seg = node.text ?? node.orig_text ?? '';
    text += seg;
  }
  return text;
}

/**
 * ⭐ 富文本节点类型 → 分段 kind：只区分需要"特殊样式 + 点击交互"的两类（@某人、#话题#），
 * 其余（TEXT / BV / WEB / 等）仍按普通文字处理（原样返回 'text'）
 */
function dynNodeKind(nodeType: string): string {
  if (nodeType === 'RICH_TEXT_NODE_TYPE_AT') return 'at';
  if (nodeType === 'RICH_TEXT_NODE_TYPE_TOPIC') return 'topic';
  return 'text';
}

/** rid → mid：B 站不同接口给数字或字符串，统一转数字（失败返回 0） */
function toDynMid(rid: number | string | undefined): number {
  if (typeof rid === 'number') return rid;
  if (typeof rid === 'string') {
    const n = parseInt(rid, 10);
    return isNaN(n) ? 0 : n;
  }
  return 0;
}

/**
 * 构建动态正文分段（文字段 / 表情段 / @某人 / #话题#）——B 站 EMOJI 节点含 emoji.icon_url（表情图片），
 * 渲染时文字段用 Text、表情段用 Image（评论区 CommentContentRenderer 同款方案）；
 * AT / TOPIC 节点额外带上 kind（+ mid），由页面渲染成可点的高亮样式
 * @param nodes rich_text_nodes（EMOJI 节点含表情图片 url）
 * @param fallbackText 无富文本节点时的整段回退文本（buildDynText 结果）
 */
function buildDynTextSegments(nodes: DynRawRichTextNode[] | undefined, fallbackText: string): DynTextSegment[] {
  const segs: DynTextSegment[] = [];
  if (nodes && nodes.length > 0) {
    for (const node of nodes) {
      if (node.emoji && node.emoji.icon_url) {
        // ⭐ B 站表情：表情段（渲染为表情图片）
        segs.push({ text: node.text ?? '', emoteUrl: node.emoji.icon_url });
      } else {
        const segText: string = node.text ?? node.orig_text ?? '';
        if (segText.length > 0) {
          const kind: string = dynNodeKind(node.type ?? '');
          if (kind === 'text') {
            segs.push({ text: segText });
          } else {
            segs.push({ text: segText, kind: kind, mid: toDynMid(node.rid) });
          }
        }
      }
    }
  }
  if (segs.length === 0) {
    segs.push({ text: fallbackText });
  }
  return segs;
}

/**
 * 解析 B 站动态 module_author.pub_time 相对时间文本为秒级时间戳
 * 支持格式："刚刚" / "X分钟前" / "X小时前" / "X天前" / "昨天" / "X月X日"（今年）/ "YYYY-MM-DD"（跨年）
 * @param pubTime 相对时间文本（B 站 union 动态 pub_ts=0 时发布时间只在 pub_time 文本里）
 * @returns 秒级时间戳；解析失败返回 0
 */
function parseDynRelativeTime(pubTime: string): number {
  const now = Math.floor(Date.now() / 1000);
  if (!pubTime) return 0;
  if (pubTime.indexOf('刚刚') >= 0) return now;
  const minIdx = pubTime.indexOf('分钟前');
  if (minIdx > 0) {
    const n = parseInt(pubTime.substring(0, minIdx), 10);
    if (!isNaN(n) && n >= 0) return now - n * 60;
  }
  const hourIdx = pubTime.indexOf('小时前');
  if (hourIdx > 0) {
    const n = parseInt(pubTime.substring(0, hourIdx), 10);
    if (!isNaN(n) && n >= 0) return now - n * 3600;
  }
  const dayIdx = pubTime.indexOf('天前');
  if (dayIdx > 0) {
    const n = parseInt(pubTime.substring(0, dayIdx), 10);
    if (!isNaN(n) && n >= 0) return now - n * 86400;
  }
  if (pubTime.indexOf('昨天') >= 0) return now - 86400;
  // X月X日（今年，B 站近期动态格式）
  const monthIdx = pubTime.indexOf('月');
  const dayEndIdx = pubTime.indexOf('日');
  if (monthIdx > 0 && dayEndIdx > monthIdx) {
    const m = parseInt(pubTime.substring(0, monthIdx), 10);
    const d = parseInt(pubTime.substring(monthIdx + 1, dayEndIdx), 10);
    if (!isNaN(m) && !isNaN(d) && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      const ts = Date.UTC(new Date(now * 1000).getFullYear(), m - 1, d);
      if (!isNaN(ts) && ts > 0) return Math.floor(ts / 1000);
    }
  }
  // YYYY-MM-DD（跨年）
  if (pubTime.length >= 10 && pubTime.charAt(4) === '-') {
    const y = parseInt(pubTime.substring(0, 4), 10);
    const m2 = parseInt(pubTime.substring(5, 7), 10);
    const d2 = parseInt(pubTime.substring(8, 10), 10);
    if (!isNaN(y) && !isNaN(m2) && !isNaN(d2) && m2 >= 1 && m2 <= 12 && d2 >= 1 && d2 <= 31) {
      const ts2 = Date.UTC(y, m2 - 1, d2);
      if (!isNaN(ts2) && ts2 > 0) return Math.floor(ts2 / 1000);
    }
  }
  return 0;
}

/** 将单条原始动态转换为扁平渲染结构（不支持的类型返回 null） */
function parseSpaceDynItem(raw: DynRawItem): SpaceDynamicItem | null {
  if (!raw.type) return null;
  const modules = raw.modules;
  const author = modules?.module_author;
  const dynamic = modules?.module_dynamic;
  const stat = modules?.module_stat;
  const major = dynamic?.major;
  const majorType = major?.type ?? '';

  let video: DynVideoInfo | null = null;
  if (majorType === 'MAJOR_TYPE_ARCHIVE' && major?.archive) {
    const a = major.archive;
    const v: DynVideoInfo = {
      aid: a.aid ?? 0,
      bvid: a.bvid ?? '',
      title: a.title ?? '',
      cover: a.cover ?? '',
      desc: a.desc ?? '',
      durationText: a.duration_text ?? '',
      play: a.stat?.play ?? 0,
      danmaku: a.stat?.danmaku ?? 0
    };
    video = v;
  }

  const images: DynImageInfo[] = [];
  if (majorType === 'MAJOR_TYPE_DRAW' && major?.draw?.items) {
    for (const it of major.draw.items) {
      const img: DynImageInfo = {
        src: it.src ?? '',
        width: it.width ?? 0,
        height: it.height ?? 0
      };
      images.push(img);
    }
  } else if (major?.opus?.pics) {
    // ⭐ 图文（OPUS 结构）：图片在 major.opus.pics（字段是 url 而非 src）。
    // 带 features=itemOpusStyle 后，老 DRAW 相簿可能仍标 DYNAMIC_TYPE_DRAW，但 major 下同时有 opus 对象 → 一律按 OPUS 解析
    for (const it of major.opus.pics) {
      const img: DynImageInfo = {
        src: it.url ?? '',
        width: it.width ?? 0,
        height: it.height ?? 0
      };
      images.push(img);
    }
  }

  let common: DynCommonInfo | null = null;
  if (majorType === 'MAJOR_TYPE_COMMON' && major?.common) {
    const c = major.common;
    const ci: DynCommonInfo = {
      title: c.title ?? '',
      desc: c.desc ?? '',
      cover: c.cover ?? '',
      jumpUrl: c.jump_url ?? '',
      seasonId: 0,
      epId: 0
    };
    common = ci;
  } else if (majorType === 'MAJOR_TYPE_ARTICLE' && major?.article) {
    // ⭐ 专栏文章（番剧/专栏分类）：结构与 COMMON 一致，映射为通用卡片
    const a = major.article;
    const ai: DynCommonInfo = {
      title: a.title ?? '',
      desc: a.desc ?? '',
      cover: a.cover ?? '',
      jumpUrl: a.jump_url ?? '',
      seasonId: a.season_id ?? 0,
      epId: a.ep_id ?? 0
    };
    common = ai;
  } else if (majorType === 'MAJOR_TYPE_PGC' && major?.pgc) {
    // ⭐ 番剧（DYNAMIC_TYPE_PGC）：major.pgc 结构与 COMMON 一致；保留 season_id/ep_id 供播放页跳转
    const p = major.pgc;
    const pi: DynCommonInfo = {
      title: p.title ?? '',
      desc: p.desc ?? '',
      cover: p.cover ?? '',
      jumpUrl: p.jump_url ?? '',
      seasonId: p.season_id ?? 0,
      epId: p.ep_id ?? 0
    };
    common = pi;
  } else if (major?.season) {
    // ⭐ 兜底：major 下存在 season 对象（番剧季）→ 映射为通用卡片；保留 season_id/ep_id
    const s = major.season;
    const si: DynCommonInfo = {
      title: s.title ?? '',
      desc: s.desc ?? '',
      cover: s.cover ?? '',
      jumpUrl: s.jump_url ?? '',
      seasonId: s.season_id ?? 0,
      epId: s.ep_id ?? 0
    };
    common = si;
  }

  // ⭐ OPUS 图文正文在 major.opus.summary（text/rich_text_nodes），结构与 desc 一致，复用 buildDynText。
  // 不依赖 majorType：带 features=itemOpusStyle 后老 DRAW 相簿可能仍标 DYNAMIC_TYPE_DRAW，但 major 下带 opus 对象
  const opusSummary: DynRawOpusSummary | undefined = major?.opus ? major.opus.summary : undefined;
  const itemText: string = opusSummary
    ? buildDynText({ text: opusSummary.text, rich_text_nodes: opusSummary.rich_text_nodes })
    : buildDynText(dynamic?.desc);
  // ⭐ 发布时间：优先 module_author.pub_ts，但 B 站 union 动态 pub_ts 可能为 0（PiliPlusX 同款处理 pub_ts==0），
  //   0 时依次用 pub_time（纯数字时间戳字符串）、pub_time 相对文本（"12小时前"/"08月11日"）、desc.timestamp 兜底
  const rawPubTs: number = author?.pub_ts ?? 0;
  let pubTimeTs: number = 0;
  const pubTimeRaw: string = author?.pub_time ?? '';
  if (pubTimeRaw.length > 0) {
    const n = Number(pubTimeRaw);
    if (!isNaN(n) && n > 0) {
      pubTimeTs = n;
    }
  }
  // ⭐ pub_time 相对文本兜底（B 站 union 动态发布时间只在文本里：如 "12小时前"、"08月11日"）
  const pubTimeRelativeTs: number = pubTimeTs > 0 ? 0 : parseDynRelativeTime(pubTimeRaw);
  const item: SpaceDynamicItem = {
    idStr: raw.id_str ?? '',
    type: raw.type,
    majorType: majorType,
    pubTs: rawPubTs > 0 ? rawPubTs
      : (pubTimeTs > 0 ? pubTimeTs
      : (pubTimeRelativeTs > 0 ? pubTimeRelativeTs
      : (dynamic?.desc?.timestamp ?? 0))),
    authorMid: author?.mid ?? 0,
    authorName: author?.name ?? '',
    authorFace: author?.face ?? '',
    text: itemText,
    // ⭐ 正文分段（含 B 站表情 emoji → 表情图片）：解析 rich_text_nodes 的 EMOJI 节点 icon_url，
    //   渲染时文字段 Text / 表情段 Image（评论区同款方案）
    textSegments: buildDynTextSegments(opusSummary?.rich_text_nodes ?? dynamic?.desc?.rich_text_nodes, itemText),
    video: video,
    images: images,
    common: common,
    likeCount: stat?.like?.count ?? 0,
    forwardCount: stat?.forward?.count ?? 0,
    commentCount: stat?.comment?.count ?? 0,
    liked: stat?.like?.status ?? false,
    // ⭐ 评论区定位：优先 basic（视频类动态评论在稿件上）；缺失才兜底 17 + 动态 id
    commentType: raw.basic?.comment_type ?? 17,
    commentIdStr: (raw.basic?.comment_id_str ?? '') || (raw.id_str ?? ''),
    orig: raw.orig ? parseSpaceDynItem(raw.orig) : null
  };
  // ⭐ 诊断日志：确认番剧/专栏等分类动态的真实结构（type/majorType/各字段），排查"暂不支持"
  logInfo(`[DynParse] type=${raw.type} majorType=${majorType} video=${video !== null} img=${images.length} common=${common !== null} textLen=${item.text.length} majorKeys=${major ? JSON.stringify(Object.keys(major)) : 'none'}`);
  // ⭐ 诊断日志：author 结构与 pub_ts/pub_time 实际值（排查"56年前"——pub_ts 为0 时 pub_time 形态）
  logInfo(`[DynParse] authorKeys=${author ? JSON.stringify(Object.keys(author)) : 'none'} pubTs=${rawPubTs} pubTime=${pubTimeRaw} pubTimeTs=${pubTimeTs} descTs=${dynamic?.desc?.timestamp ?? 0}`);
  // ⭐ 诊断日志：desc 真实结构（DRAW 图文正文可能在 rich_text_nodes，排查 textLen=0）
  const descInfo: string = dynamic?.desc
    ? `descKeys=${JSON.stringify(Object.keys(dynamic.desc))} descText=${JSON.stringify(dynamic.desc.text ?? '').substring(0, 60)} nodes=${(dynamic.desc.rich_text_nodes ?? []).length} node0=${dynamic.desc.rich_text_nodes && dynamic.desc.rich_text_nodes.length > 0 ? JSON.stringify(dynamic.desc.rich_text_nodes[0]) : 'none'}`
    : 'desc=none';
  logInfo(`[DynParse] ${descInfo}`);
  return item;
}

/**
 * 获取UP主空间动态列表（offset游标分页）
 * @param mid 用户mid
 * @param offset 游标（首页传空字符串）
 * @returns 动态列表数据
 */
export async function getUpSpaceDynamics(mid: number, offset: string = '', keyword: string = '',
  page: number = 1): Promise<UpSpaceDynamicData | null> {
  await throttleRequest();
  const params: Record<string, string> = {};
  params['host_mid'] = mid.toString();
  if (keyword.trim()) {
    params['keyword'] = keyword.trim();
    params['page'] = page.toString();
    params['features'] = 'itemOpusStyle';
    params['web_location'] = '333.1387';
  }
  if (offset) {
    params['offset'] = offset;
  }
  let queryStr: string;
  try {
    queryStr = await AppSign.generateWebParams(params);
  } catch (_e) {
    logWarn(`[getUpSpaceDynamics] WBI签名失败，使用未签名请求: ${_e}`);
    const parts: string[] = ['host_mid=' + mid.toString()];
    if (offset) {
      parts.push('offset=' + encodeURIComponent(offset));
    }
    if (keyword.trim()) {
      parts.push('keyword=' + encodeURIComponent(keyword.trim()), 'page=' + page.toString(),
        'features=itemOpusStyle', 'web_location=333.1387');
    }
    queryStr = parts.join('&');
  }
  const url = 'https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/space' +
    (keyword.trim() ? '/search?' : '?') + queryStr;
  logInfo('[getUpSpaceDynamics] WBI请求: ' + url.substring(0, 160));
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: getBiliRequestHeaders(),
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode === 200) {
      const rawResult = response.result as string;
      const data = JSON.parse(rawResult) as DynSpaceResponse;
      if (data.code === 0 && data.data) {
        const rawItems = data.data.items ?? [];
        const items: SpaceDynamicItem[] = [];
        for (const rawItem of rawItems) {
          const parsed = parseSpaceDynItem(rawItem);
          if (parsed) {
            items.push(parsed);
          }
        }
        logInfo(`[getUpSpaceDynamics] 成功: items=${items.length}, has_more=${data.data.has_more ?? false}`);
        return {
          items: items,
          offset: data.data.offset ?? '',
          hasMore: data.data.has_more ?? false,
          total: data.data.total ?? 0
        };
      }
      logWarn(`[getUpSpaceDynamics] API错误: code=${data.code}, msg=${data.message}`);
    } else {
      logError(`[getUpSpaceDynamics] HTTP错误: ${response.responseCode}`);
    }
    return null;
  } catch (err) {
    logError(`[getUpSpaceDynamics] 异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

// ══════════════════════════════════════════════════════════════
// 首页关注动态流（x/polymer/web-dynamic/v1/feed/all）
// ══════════════════════════════════════════════════════════════

/** 动态-关注流响应原始结构（与 feed/space 结构一致） */
interface DynAllResponse {
  code: number;
  message: string;
  data?: DynRawData;
}

/**
 * ⭐ 动态接口的"服务端瞬时错误"码（HTTP 200、几十毫秒就返回，但业务码非 0）。
 *    - -799 请求频繁 / -509 超出限制 / -352 风控：退避后重试有效。
 *    ⚠️ 不要把 -101（未登录）、-403（权限）之类放进来：重试只会白等。
 *    ⚠️ 4101132 **不在**这里 —— 它不是故障，见 DYN_EMPTY_CODES。
 */
const DYN_RETRYABLE_CODES: Array<number> = [-799, -509, -352];

/**
 * ⭐⭐ 动态接口「该分类确实没有内容」的专用码：**B站在这种情况下不返回空列表，而是返回一个业务错误**。
 *    - 4101132「请求数据发生错误，请刷新或稍后重试」——2026-09-19 实测定论：
 *      账号一部番都没追时切到「番剧」分类 ⇒ **必现** 4101132（HTTP 200、69ms 返回，不是超时也不是网络问题）；
 *      追番后立刻正常。**它的真实含义就是"没有可展示的内容"**，提示语里的"刷新重试"是误导性的。
 *    ⇒ 必须当作空列表渲染；若按失败处理，用户会看到「加载失败」的错误态，以为客户端坏了。
 *    ⇒ 不放进 DYN_RETRYABLE_CODES：既然是确定性的空，重试只是让用户每次切分类白等 1.2s。
 */
const DYN_EMPTY_CODES: Array<number> = [4101132];
/** 动态接口单次请求结果：`retryable` 供外层决定是否再试一次 */
interface HomeDynOnceResult {
  data: UpSpaceDynamicData | null;
  retryable: boolean;
}

/**
 * ⭐ 最近一次动态流失败的**服务端原文**（成功或"仅仅是没内容"时为空）。
 * 页面把它显示出来，用户才能分清"我没登录/网络坏了"与"B站自己说请求数据发生错误"，
 * 而不是一律看到"加载失败，请检查网络或登录状态"后去怀疑客户端。
 */
let lastHomeDynErrorMsg: string = '';
export function getLastHomeDynErrorMsg(): string {
  return lastHomeDynErrorMsg;
}

/**
 * ⭐ 最近一次动态流是"因无内容而返回空列表"时，服务端给的原文（成功时为空）。
 * 与 lastHomeDynErrorMsg 分开是为了不让「没追番」被当成故障上报/展示。
 */
let lastHomeDynEmptyMsg: string = '';
export function getLastHomeDynEmptyMsg(): string {
  return lastHomeDynEmptyMsg;
}

/**
 * 获取首页关注动态流（offset游标分页，需登录）
 * @param offset 游标（首页传空字符串）
 * @param type 动态类型：all全部 / video投稿 / pgc番剧 / article专栏（默认 all）
 * @param hostMid 仅查看某个UP的动态时传其 mid（对应 PiliPlus 的 UP Tab），不传则按 type 拉全量关注流
 * @returns 动态列表数据
 */
export async function getHomeDynamics(offset: string = '', type: string = 'all', hostMid: number = 0): Promise<UpSpaceDynamicData | null> {
  const MAX_RETRY = 1;
  for (let retry = 0; retry <= MAX_RETRY; retry++) {
    if (retry > 0) {
      logWarn(`[getHomeDynamics] 第${retry}次重试: type=${type}, hostMid=${hostMid}, offset=${offset ? '有' : '空'}`);
      await new Promise<void>((resolve: Function) => setTimeout(resolve, 1200));
    }
    const once: HomeDynOnceResult = await requestHomeDynamicsOnce(offset, type, hostMid);
    if (once.data) {
      return once.data;
    }
    if (!once.retryable) {
      return null;
    }
    if (retry === MAX_RETRY) {
      logWarn(`[getHomeDynamics] 重试后仍失败: type=${type}, hostMid=${hostMid}`);
    }
  }
  return null;
}

async function requestHomeDynamicsOnce(offset: string, type: string, hostMid: number): Promise<HomeDynOnceResult> {
  // ⭐ 走动态专属节流桶（600ms）：点 UP / 切分类是手动高频操作，不能用全局 1.5s 桶
  await dynamicThrottleRequest();
  const params: Record<string, string> = {};
  params['type'] = type;
  // ⭐ features=itemOpusStyle：让 B 站将图文动态以 OPUS 结构返回（正文 major.opus.summary.text、图片 major.opus.pics），
  // 否则老相簿 DRAW 只返回 major.draw 图片且 desc=none（正文取不到，与 PiliPlusX 一致）
  params['features'] = 'itemOpusStyle,listOnlyfans,onlyfansQaCard';
  if (hostMid > 0) {
    params['host_mid'] = hostMid.toString();
  }
  if (offset) {
    params['offset'] = offset;
  }
  let queryStr: string;
  try {
    queryStr = await AppSign.generateWebParams(params);
  } catch (_e) {
    logWarn(`[getHomeDynamics] WBI签名失败，使用未签名请求: ${_e}`);
    const parts: string[] = ['type=' + type];
    parts.push('features=itemOpusStyle,listOnlyfans,onlyfansQaCard');
    if (hostMid > 0) {
      parts.push('host_mid=' + hostMid.toString());
    }
    if (offset) {
      parts.push('offset=' + offset);
    }
    queryStr = parts.join('&');
  }
  const url = 'https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all?' + queryStr;
  // ⭐ 完整打印（截到 400）：原先截 160 会把 offset/host_mid 切掉，排查"这个账号为什么报错"时最需要的正是它们
  logInfo(`[getHomeDynamics] WBI请求: mid=${extractMidFromCookie(getCookieHeader())} type=${type} hostMid=${hostMid} | ${url.substring(0, 400)}`);
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: getBiliRequestHeaders(),
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode === 200) {
      const rawResult = response.result as string;
      const data = JSON.parse(rawResult) as DynAllResponse;
      if (data.code === 0 && data.data) {
        const rawItems = data.data.items ?? [];
        const items: SpaceDynamicItem[] = [];
        for (const rawItem of rawItems) {
          const parsed = parseSpaceDynItem(rawItem);
          if (parsed) {
            items.push(parsed);
          }
        }
        logInfo(`[getHomeDynamics] 成功: items=${items.length}, has_more=${data.data.has_more ?? false}`);
        lastHomeDynErrorMsg = '';
        lastHomeDynEmptyMsg = '';
        return {
          data: {
            items: items,
            offset: data.data.offset ?? '',
            hasMore: data.data.has_more ?? false,
            total: data.data.total ?? 0
          },
          retryable: false
        };
      }
      if (DYN_EMPTY_CODES.includes(data.code)) {
        // ⭐⭐ 这是「没有内容」，不是失败（典型：没追番 ⇒ 番剧分类必现 4101132）。
        //    必须转成空列表 ⇒ 页面走空态；return null 会让用户看到「加载失败」的错误态。
  logInfo('[TV-QR] 请求登录接口');
        lastHomeDynErrorMsg = '';
        lastHomeDynEmptyMsg = `${data.message}(${data.code})`;
        return {
          data: { items: [], offset: '', hasMore: false, total: 0 },
          retryable: false
        };
      }
      // ⭐ 业务错误：把响应体前 300 字符一起打出来，B站常在 data 里塞风控/校验提示，只看 code 看不出来
      logWarn(`[getHomeDynamics] API错误: code=${data.code}, msg=${data.message} | body=${rawResult.substring(0, 300)}`);
      lastHomeDynEmptyMsg = '';
      lastHomeDynErrorMsg = `${data.message}(${data.code})`;
      return { data: null, retryable: DYN_RETRYABLE_CODES.includes(data.code) };
    }
    logError(`[getHomeDynamics] HTTP错误: ${response.responseCode}`);
    lastHomeDynErrorMsg = '';
    lastHomeDynEmptyMsg = '';
    // 网络/网关层错误（非 200）都当作瞬时抖动，允许重试
    return { data: null, retryable: true };
  } catch (err) {
    logError(`[getHomeDynamics] 异常: ${err}`);
    lastHomeDynErrorMsg = '';
    lastHomeDynEmptyMsg = '';
    return { data: null, retryable: true };
  } finally {
    httpRequest.destroy();
  }
}

// ══════════════════════════════════════════════════════════════
// 关注UP列表（x/polymer/web-dynamic/v1/uplist）
// ══════════════════════════════════════════════════════════════

/** UP列表-单个UP原始结构 */
interface DynUpRaw {
  mid?: number;
  uname?: string;
  face?: string;
  has_update?: boolean;
}

/** UP列表-data原始结构 */
interface DynUpListRawData {
  items?: DynUpRaw[];
  has_more?: boolean;
  offset?: string;
  up_list?: DynUpRaw[] | DynUpListRawData;
}

/** UP列表-响应原始结构 */
interface DynUpListResponse {
  code: number;
  message: string;
  data?: DynUpListRawData;
}

/** UP列表-单条（渲染用） */
export interface DynUpItem {
  mid: number;
  uname: string;
  face: string;
  hasUpdate: boolean;
}

/** UP列表-返回 */
export interface DynUpListData {
  items: DynUpItem[];
  hasMore: boolean;
  offset: string;
}

/**
 * 首屏使用门户展开列表，后续按门户返回的 offset 请求 uplist。
 * @param offset 游标（首页传空字符串）
 * @returns UP列表数据
 */
export async function getDynUpList(offset: string = ''): Promise<DynUpListData | null> {
  // ⭐ 与 feed 同一个动态专属桶：进页面时 UP 列表不再被 feed 请求挡住 1.5s
  await dynamicThrottleRequest();
  const params: Record<string, string> = {};
  params['platform'] = 'web';
  params['web_location'] = '333.1365';
  if (!offset) params['up_list_more'] = '1';
  if (offset) {
    params['offset'] = offset;
  }
  let queryStr: string;
  try {
    queryStr = await AppSign.generateWebParams(params);
  } catch (_e) {
    logWarn(`[getDynUpList] WBI签名失败，使用未签名请求: ${_e}`);
    const parts: string[] = ['platform=web', 'web_location=333.1365'];
    if (!offset) parts.push('up_list_more=1');
    if (offset) {
      parts.push('offset=' + offset);
    }
    queryStr = parts.join('&');
  }
  const url = 'https://api.bilibili.com/x/polymer/web-dynamic/v1/' + (offset ? 'uplist?' : 'portal?') + queryStr;
  logInfo('[getDynUpList] WBI请求: ' + url.substring(0, 160));
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: getBiliRequestHeaders(),
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode === 200) {
      const rawResult = response.result as string;
      const data = JSON.parse(rawResult) as DynUpListResponse;
      if (data.code === 0 && data.data) {
        const portalList = data.data.up_list;
        const listData: DynUpListRawData = !offset && portalList
          ? (Array.isArray(portalList) ? { items: portalList as DynUpRaw[] } : portalList as DynUpListRawData)
          : data.data;
        const rawItems = listData.items ?? [];
        const items: DynUpItem[] = [];
        for (const rawItem of rawItems) {
          items.push({
            mid: rawItem.mid ?? 0,
            uname: rawItem.uname ?? '',
            face: rawItem.face ?? '',
            hasUpdate: rawItem.has_update ?? false
          });
        }
        logInfo(`[getDynUpList] 成功: items=${items.length}, has_more=${listData.has_more ?? false}`);
        return {
          items: items,
          hasMore: listData.has_more ?? false,
          offset: listData.offset ?? ''
        };
      }
      logWarn(`[getDynUpList] API错误: code=${data.code}, msg=${data.message}`);
    } else {
      logError(`[getDynUpList] HTTP错误: ${response.responseCode}`);
    }
    return null;
  } catch (err) {
    logError(`[getDynUpList] 异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

// ==================== 动态转发 / 点赞 ====================
interface DynamicRepostText { raw_text: string; type: number; biz_id: string; }
interface DynamicRepostContent { contents: DynamicRepostText[]; }
interface DynamicRepostAppMeta { from: string; mobi_app: string; }
interface DynamicRepostMeta { app_meta: DynamicRepostAppMeta; }
interface DynamicRepostSource { dyn_id_str: string; }
interface DynamicRepostRequest {
  content: DynamicRepostContent;
  scene: number;
  meta: DynamicRepostMeta;
  web_repost_src: DynamicRepostSource;
}
interface DynamicRepostBody { dyn_req: DynamicRepostRequest; }

/** 仅在用户确认转发时调用；动态 id 保持字符串，避免精度损失。 */
export async function repostDynamic(dynIdStr: string, content: string): Promise<CommentLikeResult> {
  if (!dynIdStr) return { ok: false, code: -400, message: '动态 id 缺失' };
  const cookie = getCookieHeader();
  const csrf = extractCsrfFromCookie(cookie);
  if (!csrf) return { ok: false, code: -101, message: '账号未登录或 Cookie 已失效' };
  const request = http.createHttp();
  const body: DynamicRepostBody = { dyn_req: {
    content: { contents: [{ raw_text: content.trim() || '转发动态', type: 1, biz_id: '' }] },
    scene: 4,
    meta: { app_meta: { from: 'create.dynamic.web', mobi_app: 'web' } },
    web_repost_src: { dyn_id_str: dynIdStr }
  } };
  try {
    const response = await request.request(`https://api.bilibili.com/x/dynamic/feed/create/dyn?csrf=${csrf}`, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': `https://t.bilibili.com/${dynIdStr}`,
        'Origin': 'https://www.bilibili.com',
        'Cookie': cookie
      },
      extraData: JSON.stringify(body),
      connectTimeout: 10000, readTimeout: 10000
    });
    if (response.responseCode !== 200) {
      return { ok: false, code: response.responseCode, message: `网络错误(${response.responseCode})` };
    }
    const result = JSON.parse(response.result as string) as ApiResponse<Object>;
    return { ok: result.code === 0, code: result.code,
      message: result.code === 0 ? '' : (result.message || '转发失败，请稍后重试') };
  } catch (_e) {
    return { ok: false, code: -1, message: '网络异常，请稍后重试' };
  } finally {
    request.destroy();
  }
}

/**
 * 点赞 / 取消点赞一条动态（web 端 /x/dynamic/feed/dyn/thumb，无需 WBI，需登录 CSRF）
 *
 * ⚠️ 三个关键点（写错就是 `4100001 参数错误`，别照抄评论点赞的写法）：
 *  1. `csrf` 放 **URL query**（不是 body）；body 必须是 **JSON**（不是 x-www-form-urlencoded）；
 *  2. 点赞状态字段叫 **`up`**：0=切换 / 1=点赞 / 2=取消（`type` 是本接口**不存在**的字段）；
 *  3. `dyn_id_str` 是 19 位数字串，**超出 number 安全精度**（2^53），全程当字符串传，绝不能 parseInt。
 *  实测踩坑（2026-09-18）：用 form 编码 + `type=` + csrf 在 body → 服务端回 4100001 参数错误。
 *
 * @param dynIdStr 动态 id 字符串（SpaceDynamicItem.idStr）
 * @param like true=点赞，false=取消点赞
 * @returns ok=false 时 message 可直接提示用户（未登录 / 风控 / 网络错误）
 */
export async function setDynamicLike(dynIdStr: string, like: boolean): Promise<CommentLikeResult> {
  if (!dynIdStr) {
    return { ok: false, code: -400, message: '动态 id 缺失' };
  }
  const cookie = getCookieHeader();
  const csrf = extractCsrfFromCookie(cookie);
  if (!csrf) {
    logWarn('[setDynamicLike] 缺少 CSRF token（未登录）');
    return { ok: false, code: -101, message: '账号未登录或 Cookie 已失效' };
  }

  const url = `https://api.bilibili.com/x/dynamic/feed/dyn/thumb?csrf=${csrf}`;
  const bodyJson = JSON.stringify({ dyn_id_str: dynIdStr, up: like ? 1 : 2 });
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': `https://t.bilibili.com/${dynIdStr}`,
        'Origin': 'https://www.bilibili.com',
        'Cookie': cookie,
        'X-Bili-Mid': getBiliMid()
      },
      extraData: bodyJson,
      connectTimeout: 10000,
      readTimeout: 10000
    });

    if (response.responseCode !== 200) {
      logError(`[setDynamicLike] HTTP 错误: ${response.responseCode}`);
      return { ok: false, code: response.responseCode as number, message: `网络错误(${response.responseCode})` };
    }

    const jsonData = JSON.parse(response.result as string) as ApiResponse<Object>;
    if (jsonData.code !== 0) {
      const msg = jsonData.message || '';
      // 常见：-101 未登录 / -111 csrf 校验失败 / 10003 该动态不存在或被删
      logWarn(`[setDynamicLike] 失败: code=${jsonData.code}, message=${msg}, like=${like}, dyn=${dynIdStr}`);
      let friendly = msg || '操作失败';
      if (jsonData.code === -101) friendly = '账号未登录或 Cookie 已失效';
      if (jsonData.code === -111) friendly = 'CSRF 校验失败，请重新登录';
      if (jsonData.code === 10003) friendly = '该动态已不存在';
      return { ok: false, code: jsonData.code, message: friendly };
    }

    logInfo(`[setDynamicLike] 成功: ${like ? '点赞' : '取消赞'} dyn=${dynIdStr}`);
    return { ok: true, code: 0, message: '' };
  } catch (err) {
    logError(`[setDynamicLike] 异常: ${err}`);
    return { ok: false, code: -1, message: '网络异常，请稍后重试' };
  } finally {
    httpRequest.destroy();
  }
}

// ==================== 动态详情（x/polymer/web-dynamic/v1/detail） ====================

/** 动态详情响应（data.item 与 feed 接口同构，可直接复用 parseSpaceDynItem） */
interface DynDetailResponse {
  code: number;
  message: string;
  data?: DynDetailData;
}

interface DynDetailData {
  item?: DynRawItem;
}

/**
 * 获取单条动态详情
 *
 * ⚠️ `id` 必须是**动态 id 字符串**（19 位，超 number 精度），别 parseInt；
 *    返回结构与 feed/list 完全相同（modules.module_author / module_dynamic / module_stat），
 *    所以直接复用 `parseSpaceDynItem`，不另写一套解析。
 *    带 features=itemOpusStyle（与本工程 feed 一致）：图文动态才会以 OPUS 结构返回正文与图片。
 *
 * @param dynIdStr 动态 id 字符串
 * @returns 解析后的动态；失败/已删除返回 null
 */
export async function getDynamicDetail(dynIdStr: string): Promise<SpaceDynamicItem | null> {
  if (!dynIdStr) {
    logWarn('[getDynamicDetail] dynIdStr 为空');
    return null;
  }
  const features = 'itemOpusStyle,listOnlyfans,onlyfansQaCard';
  const params: Record<string, string> = {};
  params['id'] = dynIdStr;
  params['features'] = features;
  let url: string;
  try {
    url = `https://api.bilibili.com/x/polymer/web-dynamic/v1/detail?${await AppSign.generateWebParams(params)}`;
  } catch (err) {
    // WBI 签名失败退回未签名（与 getHomeDynamics 同策略）
    logWarn(`[getDynamicDetail] WBI签名失败，改用未签名请求: ${err}`);
    url = `https://api.bilibili.com/x/polymer/web-dynamic/v1/detail?id=${dynIdStr}&features=${features}`;
  }

  const httpRequest = http.createHttp();
  try {
    await dynamicThrottleRequest();
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: getBiliRequestHeaders(),
      connectTimeout: 10000,
      readTimeout: 10000
    });
    if (response.responseCode !== 200) {
      logError(`[getDynamicDetail] HTTP错误: ${response.responseCode}`);
      return null;
    }
    const data = JSON.parse(response.result as string) as DynDetailResponse;
    if (data.code !== 0) {
      logWarn(`[getDynamicDetail] API错误: code=${data.code}, msg=${data.message}, dyn=${dynIdStr}`);
      return null;
    }
    const raw: DynRawItem | undefined = data.data?.item;
    if (!raw) {
      logWarn(`[getDynamicDetail] data.item 缺失: dyn=${dynIdStr}`);
      return null;
    }
    const item: SpaceDynamicItem | null = parseSpaceDynItem(raw);
    if (item) {
      logInfo(`[getDynamicDetail] 成功: dyn=${dynIdStr} type=${item.type} 图=${item.images.length} 赞=${item.likeCount} 评论=${item.commentCount} liked=${item.liked}`);
    }
    return item;
  } catch (err) {
    logError(`[getDynamicDetail] 异常: ${err}`);
    return null;
  } finally {
    httpRequest.destroy();
  }
}
