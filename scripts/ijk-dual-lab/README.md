# IJK 双轨播放原生构建

正式播放页使用 `libpurapily_ijk.so`，不依赖临时 `ijkprobe` 工程。原始 HAR 保留，应用依赖修补后的 `ijkplayer-2.0.13-purapily.har`。两种 ABI 为 arm64-v8a / x86_64。

## 依赖与命令

- DevEco Studio 默认 SDK（脚本默认位置 `D:/Program Files/Huawei/DevEco Studio`，可用 `--studio` 指定）。
- Python 3.10+、Git。
- [ohos_ijkplayer](https://gitcode.com/CPF-ApplicationTPC/ohos_ijkplayer) 源码，提交 `4cfc0031d0403a4663942022ce411eedc28eec98`，放在 `.local/ijk-dual/ohos-ijk`，或用 `--ijk` 指定。
- [ohos_ffmpeg](https://gitcode.com/CPF-ApplicationTPC/ohos_ffmpeg) 源码，提交 `69c05840d1d5412007e50beb94c8508015e51d4f`，放在 `.local/ijk-dual/ohos-ffmpeg`，或用 `--ffmpeg` 指定。
- 仓库中的原版 `entry/libs/ijkplayer-2.0.13.har`。

在项目根目录执行：

```powershell
python scripts/ijk-dual-lab/build_native.py
Push-Location entry
ohpm install
Pop-Location
hvigorw --mode module -p module=entry@default assembleHap --no-daemon
```

脚本严格检查源码提交，构建目录为 `.local/ijk-native-rebuild`，输出 SHA-256 清单在该目录的 `sha256.json`。重新生成主包前必须执行 `ohpm install`，使本地 HAR 的变化进入依赖缓存。主包签名沿用项目本地配置。

## 源码对应关系

- `bridge.c`：生成应用私有、0600 权限的媒体描述文件，包含两条 HTTPS URL、必要请求头、磁盘缓存开关及备用源。禁止请求头换行；不把账户 Cookie 或签名 URL 写入日志。播放器释放时删除描述文件。
- `../ijk_dual_demux_lab.c`：FFmpeg 私有输入格式 `puradual`；独立连接两条音视频轨，按时间戳交织，统一时钟解码与同步定位。继承取消回调，失败不混用定位前后数据。私有 ABI 有编译期偏移检查，不能替换成上游 FFmpeg 8 头文件。
- `player_backend.cpp`：NAPI 播放控制、消息转发、异步 shutdown 和独立于 XComponent 生命周期的播放器持有。解码采用 buffer 输出，Surface 切换不重建播放器。
- `prewarm.c`：有上限的异步连接预热池；失败回退冷连接。
- `cache.c` / `prefetch.c`：当前正式内核的分块磁盘缓存、备用 CDN 与可选首帧区间预读；原先临时工程中的这部分实现已归入本构建入口，重建不再丢失这些能力。
- 普通 H.264/HEVC 视频和 AAC 音频在 MP4 头已有完整解码参数、时间基和尺寸/音频格式时直接发布流；参数不足仍执行 `avformat_find_stream_info`。不再为完整 DASH 轨重复读包/解码探测，且不更改原播放缓冲水位。
- `sdl/`：保留上游许可证的 SDL 修订源码。窗口变更只更新目标，由渲染线程切换 EGL；切换后重新创建 renderer 状态；不调用会影响同进程其它播放器的共享 display `eglTerminate`。旧目标的末帧保留一秒供系统转场使用，随后在渲染线程回收；停止播放时统一释放剩余目标。
- `surface_forward.c`：把 AndroidSurface 入口转发到修订后的 native-window 实现。

SDL 的其它实现保留原始二进制，等长修改其 SONAME 为 `libijksdx.so`，修订后的 `libijksdl.so` 链接它。原 HAR 的许可证及 NOTICE 保留在修补 HAR 中。两个修订 SDL 文件为 LGPL-2.1-or-later，保留原作者声明；其余依赖许可证见 HAR 的 LICENSE、NOTICE、README.OpenSource。源码及重建方式应随发布一并保留。

## 应用行为

入口为「我的 → 设置 → 播放内核」，默认系统 AVPlayer，可选 IJK 双轨直连（实验）。下一次打开视频时生效，选择会持久化。普通支持的 AVC/HEVC DASH 使用 IJK；HDR、杜比及非双轨来源保留系统路径。直播和本地离线播放沿用系统实现。

「播放实验」也在同一个主 HAP 内，不需要配套 feature HAP。它使用包装层验证基础双轨能力；正式播放页使用上述独立 C API 后端。

系统 PiP 沿用已有系统窗口和控制，主播放器只切 Surface。画质候选和连刷候选通过同一播放器工厂选择内核。实例预热池仍默认关闭，属于另一个独立实验开关；不得把它的 prepared 日志当作真实出画证明。

IJK 模式取流不再优先改用合并流，并按内核隔离 UGC 取流缓存。备用实例通过 `setPlaybackRange` 在 prepare 前传入起播点：本移植版在首次 play 之前暂停 read_thread，此时等待 seekDone 会互相等待。系统 AVPlayer 保持原有准备、定位顺序。
