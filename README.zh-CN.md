# RetroGo-iOS

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

**基于 RetroArch (Libretro) 的高性能原生 iOS 模拟器前端**

简体中文 | [English](README.md)

## 📖 项目简介

**RetroGo** 是一款专为 iOS 设计的开源模拟器前端项目。与传统的 RetroArch 移植版不同，RetroGo 对其源代码进行了“手术级”的架构重构：

* **深度解耦**：我们完全剔除了 RetroArch 原生的菜单系统（Menu）与 UI 组件（Widgets）。
* **原生重构**：底层保留了 RetroArch 强大的核心调度逻辑（Core Environment）与跨平台桥接层，而交互界面则使用原生 **UIKit** (Swift/Objective-C) 从零开始重新实现。
* **极致体验**：这使得 RetroGo 既拥有 Libretro 顶级的模拟兼容性，又具备 iOS 系统原生应用丝滑、直观的操作感。

## ⚠️ 重要声明 (Disclaimer)

* **关联说明**：本项目与 ESP32 设备上的 [retro-go 固件](https://github.com/ducalex/retro-go) **没有任何** 关联、支持或所属关系。这是一个独立的 iOS 移动端应用程序。
* **内容说明**：本项目是一个纯粹的技术工具，**不内置、不提供、亦不分发** 任何受版权保护的游戏镜像（ROM）或系统固件（BIOS）。

## ✨ 功能特性

* **原生 iOS UI**：采用 UIKit 构建，提供响应迅速、符合系统直觉的导航与设置体验。
* **Libretro 深度集成**：通过行业标准的 Libretro API 运行模拟核心，确保高性能与高精度。
* **精简核心库**：首发版集成了 14 个主流核心（涵盖 NES, SNES, GBA, GBC, N64, PS1, PSP, NDS, DOS 等）。
* **内置已签名 Framework**：为了简化构建，核心二进制文件已预先签名并封装为标准 Framework，开箱即用。
* **经典的屏幕按键**：继承并优化了虚拟手柄逻辑，移除了不相关的品牌标识，界面更纯净且合规。
* **文件系统集成**：深度支持 iOS “文件” App 及 iTunes 文件共享，管理游戏库简单快捷。

## 🛠️ 技术架构

* **开发语言**：Swift, Objective-C, C/C++
* **UI 框架**：UIKit (Frontend), Libretro (Render Backend)
* **依赖管理**：Swift Package Manager (SPM)
* **底层核心**：基于 RetroArch/Libretro 调度层

### 关于模拟核心 (Cores)
为了确保 1.0 版本的构建便捷性，本项目采取了以下方案：
1.  **来源**：核心二进制文件均源自 [RetroArch 官方 Buildbot](https://buildbot.libretro.com/)。
2.  **封装**：我们通过工具将官方 dylibs 签名并封装为 iOS Framework 格式。这些制作好的 Framework 已内置于仓库中，无需额外运行脚本即可直接编译。
3.  **合规**：各核心独立遵循其原始许可证（GPLv2, GPLv3, MIT 等）。

## 🚀 构建指南

### 前提条件
* 安装了最新版本 **Xcode** 的 macOS 设备。
* 安装了 **Git**。

### 构建步骤

1.  **克隆仓库**
    ```bash
    git clone https://github.com/askrsw/RetroGo-iOS.git
    cd RetroGo-iOS
    ```

2.  **打开项目**
    直接双击打开 `RetroGo.xcodeproj`。Xcode 会自动解析 Swift Package Manager 依赖。

3.  **签名配置**
    * 在项目导航栏选择 Target。
    * 进入 **Signing & Capabilities** 选项卡。
    * 配置您的 Apple 开发者 Team（支持个人免费账号）。

4.  **构建并运行**
    连接您的 iPhone/iPad，按下 `Cmd + R` 即可开始构建。

## 🎮 使用说明

### 导入游戏 (ROMs)
1.  将 iOS 设备连接至电脑。
2.  在 **访达 (Finder)** 或 **iTunes** 中找到您的设备并进入 **文件 (Files)** 选项卡。
3.  将合法的 ROM 文件及 BIOS 文件拖入 **RetroGo** 文件夹。
4.  **提示**：为了获得最佳的兼容性和加载速度，**强烈建议在导入前解压 ZIP 压缩包**，直接使用原始 ROM 格式。

## ⚖️ 许可与合规

* **开源协议**：本项目基于 **GNU General Public License v3.0 (GPLv3)** 开源。
* **中国大陆备案**：鲁ICP备2023034487号-9A
* **主要开发者**：haharsw (GitHub: [askrsw](https://github.com/askrsw))

## 🤝 致谢

* **[Libretro / RetroArch](https://www.libretro.com/)**：感谢其卓越的 API 与底层调度架构。
* **开源社区**：感谢全球成千上万名模拟核心贡献者。
