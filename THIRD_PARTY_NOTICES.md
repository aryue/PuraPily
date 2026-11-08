# 第三方组件与许可声明

本项目以 GNU General Public License v3.0（SPDX：`GPL-3.0-only`）发布。下列第三方作品的部分内容已纳入本项目，其版权声明与许可文本随本文件一并保留。

分发本项目的源码或二进制时，本文件须一并提供。

## yunshang-bili

- 来源：<https://github.com/chunwcc/yunshang-bili>
- 使用范围：`entry/src/main/ets/api/` 下的哔哩哔哩接口实现，以其为基础上修改和扩展
- 许可证：MIT License

```text
MIT License

Copyright (c) 2026 chunwcc

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 原生播放相关依赖

IJK、FFmpeg、SDL 及其修订部分的许可证保留在 `entry/libs/ijkplayer-2.0.13-purapily.har` 内的 LICENSE、NOTICE、README.OpenSource，构建与重建说明见 `scripts/ijk-dual-lab/README.md`。FFmpeg 以 LGPL-2.1-or-later 构建（未启用 `--enable-gpl`），修订的 SDL 源码为 LGPL-2.1-or-later。

## 其它依赖

其余第三方依赖遵循各自仓库或包内附带的许可条款。

## 维护约定

后续若纳入其它第三方实现，应在此补充来源、使用范围、版权行与完整许可文本；仅在 README 致谢中列名不足以满足署名类许可（如 MIT、BSD、Apache-2.0）的条件。
