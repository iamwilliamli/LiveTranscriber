# LiveTranscriber

<p align="center">
  <img src="docs/assets/readme-poster.png" alt="LiveTranscriber README poster" />
</p>

<p align="center">
  <strong>简体中文</strong> · <a href="README.md">English</a> ·
  <a href="https://apps.apple.com/app/id6785515364">App Store</a> ·
  <a href="https://testflight.apple.com/join/gsu9xa9k">TestFlight 测试版</a>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS%2026%2B%20%7C%20watchOS%2026%2B-black">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-blue">
  <img alt="Local first" src="https://img.shields.io/badge/privacy-local--first-green">
  <img alt="License" src="https://img.shields.io/badge/license-source--available-orange">
</p>

> [!NOTE]
> 这是 LiveTranscriber App Store 版本的公开展示仓库和稳定基础版本。后续产品开发与发布自动化将在私有仓库中进行；Issue 和用户支持仍保留在这里。

LiveTranscriber 是一款面向 iPhone 和 Apple Watch 的本地优先录音转写工具。它可以录音、实时生成字幕、翻译文本、区分说话人，并把保存的录音整理成可搜索的笔记和会议分析。大部分流程都能完全在设备上完成；云端处理需要用户主动开启，并使用自己的 API Key。

## App 截图

<p align="center">
  <img src="docs/assets/screenshots/overview-dashboard.jpg" width="31%" alt="包含本周统计和录音活跃度热力图的总览页" />
  <img src="docs/assets/screenshots/multispeaker-transcript.jpg" width="31%" alt="带翻译和波形回放的多说话人转录页" />
  <img src="docs/assets/screenshots/recording-intelligence.jpg" width="31%" alt="包含摘要、关键点和位置信息的录音编辑页" />
</p>

<p align="center">
  录音总览与回顾 · 多说话人转录 · 录音智能整理
</p>

## 现在能做什么

| 场景 | LiveTranscriber 的能力 |
| --- | --- |
| 录音过程中 | 保存 WAV 或 M4A，并实时显示带时间戳的字幕。 |
| 多人对话 | 可选本机 Sortformer，实时稳定标记最多 4 位说话人。 |
| 外语内容 | 用 Apple Translation 翻译实时或已保存的转录，同时保留原文。 |
| 录完以后 | 用 Apple Speech、Nemotron、Qwen3-ASR、Whisper 或 MOSS 多说话人模型在本机重转录。 |
| 内容整理 | 生成摘要、标签、会议笔记、行动项、决策、待确认问题，并可以针对单条录音问答。 |
| 回顾查找 | 搜索转录和 metadata，统计主题与地点，继续播放未听完的录音。 |

## 录音和实时字幕

- 原生 SwiftUI 录音界面，支持立体声麦克风采集、WAV/M4A、暂停/继续、实时音量、后台录音，以及语言和音频质量设置。
- 支持锁屏 Live Activity、灵动岛、桌面组件、Shortcuts/App Intents；切换到 App 其他页面时仍有持续录音控制。
- 支持从文件和系统“打开方式/分享”入口导入音频；长时间本地处理带进度、取消、checkpoint 恢复和系统 continued processing。
- 在系统和设备支持时，可转写系统声音或其他 App 的声音，并通过画中画字幕窗口查看内容。

实时引擎可以使用 **Automatic**，也可以手动指定：

| 实时引擎 | 用途 |
| --- | --- |
| Apple Speech | 通过 `SpeechAnalyzer` 和 `SpeechTranscriber` 做系统级本机转写。 |
| Nemotron 3.5 Streaming | 推荐的快速离线引擎，只增量处理新到达的 320 ms 音频。 |
| Qwen3-ASR Live | 实验性的本机多语言实时转写。 |
| Local Whisper Live | 在可用地区提供的实验性 whisper.cpp 实时路径。 |

Automatic 会优先为支持的语言选择 Apple Speech，并在适合时回退到 Nemotron。实时说话人分离与 ASR 引擎相互独立：可选的 NVIDIA Sortformer Core ML 模型能够配合任何实时引擎，为最多 4 位说话人添加稳定标签。

## 保存后的录音

- 点击转录行即可跳到波形播放器的对应时间；支持前后 5 秒、单曲循环、倍速和跟随转录等控制。
- 可以重新处理原始音频，同时保留可恢复的旧转录。
- 本地 **MOSS Transcribe Diarize** 可生成带时间戳和稳定颜色的多说话人转录；也可以按速度、准确率和语言选择 Qwen3-ASR、Nemotron、Apple Speech 或已下载的 Whisper 模型。
- 翻译已保存的转录并保留原文；支持复制或导出 TXT、Markdown、SRT、VTT、JSON。
- 可编辑标题、摘要、关键点、分类、标签、说话人、转录行、语言和位置 metadata。
- 搜索覆盖文件名、转录预览和全文、语言、摘要、关键点、会议分析、分类、地点和标签。

## 智能整理和个人回顾

- **Recording Intelligence：**通过 Apple Intelligence、本地 Qwen3，或用户明确选择的 Gemini Cloud 生成摘要和主题标签。
- **Meeting Analysis：**生成结构化摘要、带负责人和日期的行动项、决策、待确认问题和补充笔记；行动项可以检查、编辑后加入 Apple Reminders。
- **Ask AI：**围绕一条已保存录音的内容继续问答。
- **Overview：**展示本周时长与录音/地点/主题统计、过去 12 个月活跃度热力图、周报、继续收听、地点收藏、主题排行和历史录音回顾。
- **位置感知录音库：**可选保存录音地点，在地图和地点合集里浏览，并显示本地化地点名。

Automatic 智能分析始终保持本地：优先尝试 Apple Intelligence，不可用时使用已下载的本地 Qwen3；它不会静默选择 Gemini。

## Apple Watch

watchOS 配套 App 可以独立录音，支持暂停/继续和录音质量设置，并在获得授权后记录位置信息。完成后的音频会传到配对的 iPhone，进入同一个可搜索录音库，再使用手机上的转写、翻译、说话人分离和智能整理功能。

## 使用的模型和系统框架

当前 App 使用以下处理路径。可下载的本地模型通过 Apple 托管的 Background Assets 资源包分发，并排除在 iCloud 备份之外。

| 模型或框架 | 当前模型文件 | 用途 | 运行位置 |
| --- | --- | --- | --- |
| Apple Speech | `SpeechAnalyzer` + `SpeechTranscriber` | 实时字幕、导入音频、重转录 | Apple 系统框架，本机 |
| NVIDIA Nemotron | `aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-MLX-8bit` 和 `aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8` | 推荐的流式 ASR 和本地重转录 | 本机 |
| Qwen3-ASR | `aufklarer/Qwen3-ASR-0.6B-MLX-4bit` + `aufklarer/Silero-VAD-v6.2.1-MLX` | 多语言实时/录后转写和音频时间戳 | 本机 |
| Whisper | Tiny、Base、Small、Medium、Large v3 Turbo Q5、Large v3 Q5、Large v3 系列 | 可选实时转写和录后重转录 | 本机 whisper.cpp |
| NVIDIA Sortformer | `aufklarer/Sortformer-Diarization-CoreML`（4-speaker streaming 版本） | 配合任意实时 ASR 引擎生成说话人标签 | 本机 |
| MOSS | `vanch007/mlx-MOSS-Transcribe-Diarize-4bit` | 录后转写、时间戳和多说话人分离 | 本机 MLX |
| Apple Intelligence | Foundation Models framework | 摘要、标签、会议分析和录音问答 | Apple 系统模型，本机 |
| Qwen3 | `Qwen_Qwen3-1.7B-Q4_K_M.gguf` | Apple Intelligence 不可用时的本地摘要、标签、会议分析和问答 | 本机 llama.cpp |
| Gemini | `gemini-3.5-flash` | 可选逐字多说话人处理和智能分析 | 云端，用户 API Key，明确选择后运行 |

具体可用性会受 App Store storefront、设备性能、系统版本和语言影响；Gemini Cloud 和部分第三方路径会按照地区分发要求隐藏。

## 隐私和存储

- 录音、转录、索引和分析结果默认保存在 App 本机私有目录。
- 可选 iCloud 同步使用用户的 App 私有容器和 CloudKit private database。
- 默认流程没有开发者运营的转录服务器，不包含广告、第三方 analytics 或 tracking。
- Apple Speech、Translation 和 Foundation Models 使用 Apple 系统框架。
- Nemotron、Qwen3-ASR、Whisper、Sortformer、MOSS 和 Qwen3 摘要模型在资源包可用后都在本机运行。
- Gemini 只在用户主动开启、填写自己的 API Key，并明确选择 Gemini 操作后使用；请求设置 `store: false`，处理结束后会尽力删除临时上传的音频。

## 系统要求

- iOS 26 或更高版本；部分原生语音和系统声音功能需要 iOS 27。
- Apple Watch 配套 App 需要 watchOS 26 或更高版本。
- 构建公开基础版本需要匹配 iOS SDK 的 Xcode。
- 单个引擎还会受到设备、语言、storefront 和模型是否已下载的限制。

## 构建

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -quiet \
  -project LiveTranscriber.xcodeproj \
  -scheme LiveTranscriber \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/LiveTranscriberDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

真机测试需要在 Xcode 里配置 signing team，并启用 iCloud 和 Live Activity 相关 capabilities。

## 项目结构

- `LiveTranscriber/`：主 iOS app target。
- `LiveTranscriberWidget/`：锁屏、灵动岛和桌面组件扩展。
- `Vendor/`：内置 whisper.cpp 和 llama.cpp XCFramework。
- `docs/`：工程文档。
- `DEVELOPMENT_NOTES.md`：开发记录和实现细节。

## 文档

- [Documentation Index](docs/README.md)
- [Current Product and UI Design](docs/CURRENT_DESIGN.md)
- [Recording Processing Pipeline](docs/RECORDING_PIPELINE.md)
- [Live Activity Design](docs/LIVE_ACTIVITY.md)
- [Localization](docs/LOCALIZATION.md)
- [Development Notes](DEVELOPMENT_NOTES.md)

## 试用和反馈

- [在 App Store 下载](https://apps.apple.com/app/id6785515364)
- [TestFlight Beta](https://testflight.apple.com/join/gsu9xa9k)
- [Contributing Guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)
- [Bug Reports](https://github.com/iamwilliamli/LiveTranscriber/issues/new?template=bug_report.md)
- [Feature Requests](https://github.com/iamwilliamli/LiveTranscriber/issues/new?template=feature_request.md)

## 授权和商业署名

LiveTranscriber 的公开基础版本使用 [LiveTranscriber Source Available License 1.0](LICENSE)。代码可供学习、fork，并可在已发布的基础版本上继续构建。

这不是 OSI 认证的开源许可证，因为商业 fork 有署名要求。任何基于本项目的商业 app、服务、fork 或衍生产品，都必须在 app 内合理可见的位置展示：

```text
Based on LiveTranscriber by William Li
Original project: https://github.com/iamwilliamli/LiveTranscriber
```

如果需要无署名、白标或私有品牌商业使用，需要获得 William Li 的单独书面许可。完整条款见 [LICENSE](LICENSE)、[NOTICE](NOTICE) 和 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 第三方许可

Reddit Sans 使用 SIL Open Font License 1.1，whisper.cpp 和 llama.cpp 使用 MIT License。可下载的 Whisper、Nemotron、Qwen3-ASR/VAD、Sortformer、MOSS 和 Qwen3 GGUF 模型来自上表对应的发布者，并在 App 内第三方模型许可目录中署名；面向用户的模型包通过 Apple 托管的 Background Assets 分发。公开基础版本内置内容的许可见 [LiveTranscriber/Fonts/OFL.txt](LiveTranscriber/Fonts/OFL.txt) 和 [NOTICE](NOTICE)。
