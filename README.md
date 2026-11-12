<div align="center">

<img src="AppScope/resources/base/media/app_icon_v5.png" width="112" alt="PuraPily 图标" />

# PuraPily

使用 ArkTS / ArkUI 开发的 HarmonyOS 原生哔哩哔哩第三方客户端

沉浸光感 · 刷新率锁定 · ijkplayer · 悬浮底栏 · 自定义壁纸

[项目主页](https://github.com/aryue/PuraPily) · [下载](https://github.com/aryue/PuraPily/releases) · [反馈与建议](https://github.com/aryue/PuraPily/issues)

</div>

## 简介

PuraPily 面向 HarmonyOS，提供视频、直播、番剧、动态与个人空间等浏览和播放功能，围绕原生材质、手势切换和横竖屏布局持续打磨体验。

项目仍在开发中，以下为当前源码已接入的主要功能。具体可用性取决于设备、系统版本、账号权限及接口返回；实验功能可能随版本调整。

## 适配平台

| 项目 | 当前配置                                  |
| --- |---------------------------------------|
| 系统 | HarmonyOS                             |
| 最低兼容版本 | HarmonyOS 6.1.0（API 23，以工程配置为准）       |
| 编译 / 目标 SDK | 26.0.0                                |
| 原生库架构 | arm64-v8a                      |
| 界面 | 基于Pura X View 和MatePad Mini 适配，其余机型未测试 |

## 功能

### 外观与系统体验

- [x] 悬浮底栏、智感握姿
- [x] 自定义壁纸，横竖屏不同构图
- [x] 沉浸光感卡片，可调材质厚度
- [x] 持续请求指导刷新率，防止未触摸时锁60Hz
- [x] 音量 / 亮度调节条的液面、粒子与弹性形变效果(仿控制中心)
- [x] 按实际音频输出路由切换扬声器 / 耳机图标
- [x] 横屏播放可调节布局

### 实验功能

- **IJK 双轨直连播放内核**：可在设置中选择；适用内容及回退路径见 [IJK 构建与行为说明](scripts/ijk-dual-lab/README.md)。

### 首页与内容发现

- [x] 直播、推荐、热门、分区、番剧、影视频道
- [x] App / Web 推荐源
- [x] 分区导航、排行榜及分页加载
- [x] 搜索历史、搜索发现与搜索筛选

### 视频播放

- [x] 普通播放、横屏全屏与竖屏连刷
- [x] 清晰度、倍速、播放比例与字幕选择
- [x] 弹幕显示、发送及样式设置
- [x] 手势调节进度、音量与亮度，长按倍速播放
- [x] 播放进度记忆、分 P 与合集选集
- [x] 点赞、投币、收藏与稍后再看
- [x] 相关推荐、评论、楼中楼回复及对话查看
- [x] 后台播放、定时关闭与系统投屏入口
- [x] 系统级 PiP 小窗，支持跨页面及返回桌面后继续播放
- [x] 离线缓存、任务暂停 / 继续、缓存管理与本地播放

画质、字幕、音视频规格及投屏能力以当前内容、账号权限和设备支持为准。

### 直播

- [x] 直播推荐与直播间播放
- [x] 上下滑动切换直播间
- [x] 直播弹幕信息区，切房时隔离消息
- [x] 单击显隐主播、标题、弹幕及操作信息
- [x] 按实际直播流提供画质选项
- [x] 竖屏直播完整显示 / 裁切铺满及生效范围设置
- [x] 后台播放与系统分享

### 动态与个人空间

- [x] 动态信息流、图文动态及转发内容查看
- [x] 视频投稿直接进入播放页
- [x] 动态详情、点赞、转发、评论与子评论回复
- [x] 动态详情竖屏单栏、横屏正文 / 评论双栏
- [x] UP 主资料、投稿与动态浏览，关注 / 取消关注
- [x] UP 空间内同时搜索该用户的视频与动态

### 账号与消息

- [x] Web 扫码、TV 扫码与网页登录
- [x] 观看历史、收藏夹与稍后再看
- [x] 站内私信、消息与通知查看
- [x] 评论点赞、回复、复制、举报与黑名单入口


## 下载与安装

拉取源码自行编译。


## 本地构建

### 环境准备

- DevEco Studio
- 签名配置。

### 构建步骤

1. 克隆仓库，并使用 DevEco Studio 打开项目根目录。

   ```bash
   git clone https://github.com/aryue/PuraPily.git
   cd PuraPily
   ```

2. 在 DevEco Studio 中同步依赖，或在已配置 OHPM 的终端执行：

   ```bash
   ohpm install
   ```

3. 在 DevEco Studio 的项目签名配置中生成并使用自己的证书、Profile 和密钥库。仓库中的 `build-profile.json5` 不包含签名配置；本地生成的签名路径和凭据请勿提交。
4. 确认 `entry/libs` 中存在 `ijkplayer-2.0.13-purapily.har`，以及对应架构的 `libpurapily_ijk.so`。
5. 通过 DevEco Studio 的运行或构建入口生成 HAP，并安装到目标设备。

如果需要重建 IJK 原生库，请按 [IJK 双轨播放原生构建文档](scripts/ijk-dual-lab/README.md) 准备指定版本的源码及工具链。更新本地 HAR 后，需要重新同步依赖。

## 发版

在工作区干净、已同步 `origin/main` 的 `main` 分支准备发版。说明文件可以放在仓库外，正文会写入 annotated tag 并用于 GitHub Release。

```powershell
scripts\release.cmd --dry-run 2.1.2 ..\release-notes.md
scripts\release.cmd 2.1.2 ..\release-notes.md
```

Windows 入口需要 Git for Windows。Git Bash 或 Linux 可用 `bash scripts/release.sh` 加同样的参数。预检会核对版本、远端分支和 tag，并显示说明预览。正式执行会更新 `AppScope/app.json5`，创建发版提交和 tag，再一次推送两者。

推送版本 tag 后，`Build Unsigned HAP` 会构建并发布未签名 HAP、SHA-256 校验文件和构建信息。手动运行 workflow 默认只构建，勾选发布后的分支构建会创建预发布。

## 反馈与贡献

欢迎通过 [Issues](https://github.com/aryue/PuraPily/issues) 提交问题或功能建议，也欢迎提交 Pull Request。

反馈问题时请尽量附上应用版本、设备型号、系统版本、复现步骤，以及必要的截图或录屏。播放问题可补充内容链接、所选清晰度和播放内核。诊断日志可从应用设置的关于页面导出或分享；提交前请检查并移除账号凭据等个人信息。

## 声明

PuraPily 是非官方第三方客户端，与哔哩哔哩官方无隶属关系。项目用于学习、研究与交流，不提供付费内容或账号权限的绕过能力。视频、图片、文字及相关商标的权利归各自权利人所有。

本项目未授权任何第三方以 PuraPily 名义分发安装包。官方发布渠道仅为本仓库与 Releases 页面；从其它渠道获取的安装包、修改版或所谓「内部版」均与本项目无关。

## 开源许可

Copyright (C) 2026 本项目作者

本仓库代码采用 [GNU General Public License v3.0](LICENSE)（SPDX 标识：`GPL-3.0-only`）。

依据 GPL-3.0，分发本项目的二进制文件（例如编译好的 HAP）时，须同时向接收者提供对应版本的完整源码。源码托管在 [GitHub 仓库](https://github.com/aryue/PuraPily)，每个发布版本都有对应的提交记录与 tag，[Releases](https://github.com/aryue/PuraPily/releases) 页面提供源码归档；构建所需的工程配置、原生库重建脚本与打包步骤均包含在本仓库内，见上文「本地构建」。

第三方组件及其许可的完整声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)；其中 IJK / FFmpeg / SDL 相关说明、许可证保留与重建方式见 [原生构建文档](scripts/ijk-dual-lab/README.md) 及 HAR 内的 LICENSE、NOTICE、README.OpenSource。

## 致谢

- [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)、[yunshang-bili](https://github.com/chunwcc/yunshang-bili)：项目参考。
- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)：哔哩哔哩 API 社区文档。
- [ohos_ijkplayer](https://gitcode.com/CPF-ApplicationTPC/ohos_ijkplayer)、[ohos_ffmpeg](https://gitcode.com/CPF-ApplicationTPC/ohos_ffmpeg)：HarmonyOS 播放相关依赖。
- [@ohos/lottie](https://ohpm.openharmony.cn/#/cn/detail/@ohos%2Flottie)：动画支持。
- 所有提供开源代码、问题反馈与测试帮助的贡献者。
