# Startrails · 星迹 for iOS

<p align="left">
  <img src="Startrails/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="Startrails iOS Icon" width="88" style="border-radius: 20px;" />
</p>

**[Startrails · 星迹](https://github.com/vongzh/startrails) 自托管订阅服务的原生 iOS / iPadOS 客户端（SwiftUI + WidgetKit），随时随地管理订阅源、查看全球节点点阵分布、执行本机 TCP 握手测速、编排策略组与分流规则，并一键拉起 19 款代理客户端导入订阅。**

[![Build iOS](https://github.com/vongzh/startrails-ios/actions/workflows/build.yml/badge.svg)](https://github.com/vongzh/startrails-ios/actions/workflows/build.yml)
[![Platform](https://img.shields.io/badge/platform-iOS%2017.0%2B%20%7C%20iPadOS%2017.0%2B-1b2138.svg)](project.yml)
[![Swift](https://img.shields.io/badge/Swift-5.10-f05138.svg)](https://swift.org)
[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/license-CC%20BY--NC--SA%204.0-b05430.svg)](LICENSE)

---

## 核心能力

```text
iOS / iPadOS 客户端 (SwiftUI + WidgetKit)
  ├── Keychain 令牌存储 & Face ID / Touch ID 应用锁
  ├── 本机 NWConnection TCP 测速 / 服务端测速双模式
  └── Admin API ◀──▶ Startrails 服务端 ──▶ 19 款客户端产物预览 / 二维码 / URL Scheme 一键导入
```

- **订阅概览与智能接入**
  - 支持远程订阅、本地文件订阅与组合订阅的增删改查、单源独立刷新及上游额度/到期时间汇总。
  - **剪贴板智能识别与扫码导入**：复制任意 HTTP(S) 订阅地址或节点分享链接（`ss://`、`vmess://`、`vless://`、`trojan://`、`hysteria2://`、`tuic://`、`anytls://`、`wireguard://`、`snell://`）后切回应用，顶部悬浮条一键填入新建。
- **节点探索与双模式延迟探测**
  - **离线世界点阵地图**：内置与 Web 端同源的全球经纬度点阵底图，直观展示当前 Profile 节点的地理分布与国别占比。
  - **本机 + 服务端双测速**：支持直接通过 iOS 设备本地网络（`NWConnection` TCP 握手）并发探测真实直连延迟，或调用服务端节点探测接口；自动识别本地 TUN 透明代理劫持（`≤2ms`）与纯 UDP 协议（Hysteria2 / TUIC / WireGuard）跳过原因。
  - 支持按国家地区、协议类型、关键词组合过滤，支持列表与网格双视图切换及按延迟升序排列。
- **策略编排与分流规则**
  - **策略组与节点加工链**：可视化配置 `select` / `url-test` / `fallback` / `load-balance` 策略组、地区图标映射（Fluent Emoji 3D / Twemoji / Quantumult X SF Symbols）与声明式节点算子（`filter` / `rename` / `prefix` / `sort` / `dedupe` / `limit`）。
  - **规则与运行时段**：管理分流规则、批量逻辑规则，以及 DNS（系统 / 加密上游 / Fake-IP / `nameserver-policy`）与 TUN 运行时参数，支持多套 Profile 独立隔离与切换。
- **产物预览与 19 款客户端一键导入**
  - 内置 19 款目标客户端（Clash Meta / Mihomo、Stash、Surge、Loon、Quantumult X、sing-box、Egern、Shadowrocket、V2Box、Karing、FlClash、Clash Verge Rev 等）原生矢量品牌图标与能力矩阵核查。
  - 支持配置全文语法高亮预览、构建诊断明细查看、已签发订阅地址管理、二维码生成，以及通过各客户端官方 URL Scheme 一键唤起导入。
- **桌面小组件、iOS 18 图标与系统安全**
  - **WidgetKit 桌面小组件**：提供 Small / Medium 两种尺寸，通过 App Group（`group.com.vongzh.startrails`）在主屏实时展示总额度消耗进度、剩余流量与最早到期倒计时。
  - **iOS 18 三态图标**：完整适配默认（Light）、深色（Dark）与色调（Tinted）桌面图标。
  - **多实例与生物识别锁**：管理令牌加密保存在系统 Keychain，支持多实例快速切换与 Face ID / Touch ID 解锁保护。

---

## 安装与构建

### 1. 预构建产物

前往本仓库 [**Releases**](https://github.com/vongzh/startrails-ios/releases) 页面获取最新版本的预构建包，或按下方步骤直接从源码编译安装。

### 2. 从源码构建（macOS + Xcode 16+）

本项目使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理工程配置（`project.yml`）：

```bash
# 1. 安装 XcodeGen 并生成 Xcode 工程
brew install xcodegen
xcodegen generate

# 2. 在 Xcode 中打开工程
open Startrails.xcodeproj
```

- **真机运行**：在 Xcode 的 `Signing & Capabilities` 中为 `Startrails` 与 `StartrailsWidget` 选择你的开发者签名团队（Development Team）。
- **命令行模拟器构建**：

```bash
xcodebuild \
  -project Startrails.xcodeproj \
  -scheme Startrails \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

---

## 工程目录结构

```text
.
├── project.yml                  # XcodeGen 工程定义（Startrails 主应用 + StartrailsWidget 扩展）
├── Shared/
│   └── WidgetSnapshotStore.swift # 主应用与 WidgetKit 小组件共享的 App Group 快照存储
├── Startrails/
│   ├── App/                     # 应用入口、生物识别门禁与全局响应式状态仓库 AppStore
│   ├── Core/                    # API 客户端、数据模型、Keychain、本机 TCP 测速、19 客户端矢量图标与语法高亮
│   ├── Views/                   # 四大主视图（概览、节点、编排、导出）、首次初始化引导与设置页
│   └── Resources/               # Assets.xcassets（含 iOS 18 三态图标）、Info.plist 与离线世界点阵底图
└── StartrailsWidget/
    └── StartrailsWidget.swift   # Small / Medium 桌面流量与到期监控小组件
```

---

## 许可协议

本仓库采用 **[CC BY-NC-SA 4.0](LICENSE)** 协议授权，仅供非商业用途使用。

Startrails 服务端与核心转换引擎仓库（MIT）：[vongzh/startrails](https://github.com/vongzh/startrails)
