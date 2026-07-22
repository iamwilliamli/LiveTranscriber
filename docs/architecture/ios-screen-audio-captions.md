# iOS 屏幕音频与悬浮双语字幕路线

状态：**已实现，等待完整实机验收**
目标分支基线：`audio-sdk-enhancements`
最低系统版本：iOS 26
记录日期：2026-07-22

## 目标

为 iPhone 和 iPad 增加一个由用户明确启动的“屏幕音频转录”模式：用户切换到 Zoom、Teams、Meet、浏览器或其他应用后，Live Transcriber 继续接收允许捕获的应用音频，生成实时原文和翻译，并通过系统画中画窗口显示双语字幕。录音结束后，音频和转录仍进入现有保存页与录音资料库。

同一套转录、翻译、字幕和存储逻辑应同时支持：

- iOS 26：ReplayKit Broadcast Upload Extension 兼容后端。
- iOS 27 及以后：ScreenCaptureKit 原生后端。

不要为 iOS 26、iOS 27 或 macOS 维护永久平台分支。平台采集层独立，业务管线继续在同一个仓库和主干中演进。

## 明确不做

- 不尝试创建可跨应用显示的任意 SwiftUI `UIWindow`。iOS 没有公开 API 允许这样做。
- 不静默启动屏幕录制。用户必须通过系统界面确认。
- 第一阶段不混合系统音频与麦克风音频。
- 不在 Broadcast Upload Extension 内加载 MOSS、Whisper 或其他大模型。
- 不把 Live Activity 当作逐字字幕载体；它只适合显示会话状态或低频摘要。
- 不保证 DRM、受保护媒体、电话音频、FaceTime 或每一个第三方会议应用都能提供可捕获音频。

## 当前代码基线

在开始实现前应重新确认目标 iOS 分支，但 2026-07-22 的代码分析结论如下：

1. iOS deployment target 已经是 26.0，工程也已经使用 `HAS_IOS27_SDK` 隔离 iOS 27 API。
2. `audio-sdk-enhancements` 的 `LiveTranscriptionManager` 仍只从 `AVCaptureSession` 麦克风接收音频。
3. macOS 分支的未提交改动已经证明现有录音、波形、Apple Speech 和本地 Whisper 管线可以接受外部 `CMSampleBuffer`，但这部分不能随整个 macOS 分支直接合并到 iOS 分支。
4. 实时转录后端是 Apple Speech 和本地 Whisper。MOSS 当前是录音结束后的整文件转录与说话人分离服务。
5. 实时翻译及其译文缓存目前属于 `TranscriptionView` 的私有状态；PiP 还没有可订阅的共享字幕状态。
6. 主 App 已声明后台音频模式，但主 App 和现有扩展都没有 App Group entitlement。
7. 工程没有 ReplayKit Broadcast Upload Extension、PiP 控制器或 iOS 单元测试 target。

## 总体架构

```text
iOS 26                                  iOS 27+
RPSystemBroadcastPickerView             SCContentSharingPicker
        |                                       |
Broadcast Upload Extension                 SCStream
        |                                       |
        +----------- SystemAudioSource --------+
                            |
                  48 kHz / stereo PCM
                            |
                 LiveTranscriptionManager
                   /                  \
        Apple Speech / Whisper      AudioFileWriter
                   |                  |
          Live transcript lines    RecordingDraft
                   |
             TranslationSession
                   |
           CaptionPresentationStore
             /                 \
       SwiftUI transcript     CaptionPiPController
                                   |
                         AVSampleBufferDisplayLayer
```

采集后端只负责产生标准化音频和会话事件。它不应该知道录音资料库、翻译 UI、MOSS 或保存页。

## 统一系统音频接口

新增一个主 App 内部协调层，例如：

```swift
enum SystemAudioBackend {
    case replayKitCompatibility
    case screenCaptureKit
}

enum SystemAudioSessionState {
    case idle
    case awaitingUserApproval
    case waitingForAudio
    case capturing
    case paused
    case stopping
    case failed(String)
}
```

后端向主 App 提供：

- 48 kHz 立体声 PCM 音频帧；录音文件保留该格式，转录分析分支再下混并重采样为 16 kHz 单声道。
- 单调递增的帧序号或时间戳。
- started、paused、resumed、finished、failed 和 heartbeat 事件。
- 丢帧、消费者落后及共享存储错误诊断。

`LiveTranscriptionManager` 应增加真正与平台无关的外部 PCM 入口，而不是把所有外部输入都命名为 ScreenCaptureKit。建议把现有采样处理拆成：

```text
CMSampleBuffer / shared PCM chunk
             -> AVAudioPCMBuffer
             -> processPCMBuffer
                 -> recording converter and writer
                 -> Apple analyzer converter
                 -> live Whisper pipeline
                 -> input-level observer
```

外部音频模式不请求麦克风权限，也不打开默认麦克风设备。没有收到有效音频时，错误文案必须是“未捕获到音频”，不能继续显示“无法读取麦克风”。

## iOS 26：ReplayKit 兼容后端

### 工程 target

新增 `LiveTranscriberBroadcastExtension` target：

- Bundle identifier：`com.iamwilliamli.LiveTranscriber.BroadcastUpload`
- Deployment target：iOS 26.0
- `APPLICATION_EXTENSION_API_ONLY = YES`
- `SKIP_INSTALL = YES`
- 嵌入主 App 的 PlugIns 目录
- 只链接扩展需要的 ReplayKit、AVFoundation、CoreMedia 和共享传输代码

扩展 `Info.plist` 应使用：

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.broadcast-services-upload</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).SampleHandler</string>
    <key>RPBroadcastProcessMode</key>
    <string>RPBroadcastProcessModeSampleBuffer</string>
</dict>
```

### App Group

主 App 和 Broadcast Extension 都加入：

```text
group.com.iamwilliamli.LiveTranscriber
```

对应 capability 还需要在 Apple Developer App ID 与 provisioning profile 中启用。只修改本地 entitlement 不足以完成签名设备测试。

### 广播开始流程

1. 用户在转录页选择“屏幕音频”。
2. App 准备字幕 PiP，并显示“等待屏幕音频”。
3. 使用官方 `RPSystemBroadcastPickerView`，将 `preferredExtension` 指向自己的扩展。
4. 第一阶段设置 `showsMicrophoneButton = false`。
5. 用户通过系统界面开始广播并切换到目标应用。
6. `SampleHandler` 收到第一个 `.audioApp` buffer 后发布 started 状态。
7. 主 App 开始外部音频录制、转录和翻译。

不要使用遍历 `RPSystemBroadcastPickerView` 私有子视图的方式模拟点击系统按钮。

### 扩展处理规则

`SampleHandler` 的职责保持最小化：

- `.audioApp`：转换并写入共享音频队列。
- `.audioMic`：第一阶段忽略。
- `.video`：第一阶段忽略；如果以后决定在 PiP 中显示屏幕缩略图，再单独设计低帧率视频桥接。
- `broadcastPaused` / `broadcastResumed`：写入共享会话状态。
- `broadcastFinished`：关闭写入端并发布完成状态。
- 不运行 Speech、Translation、Whisper、MOSS、CloudKit 或录音资料库代码。

ReplayKit API 在 iOS 27 SDK 中已标记 deprecated，因此所有 ReplayKit 主 App UI 和扩展代码都应隔离在兼容层中；iOS 27 运行时不主动走这条路径。

### 跨进程音频传输

第一版建议使用有序、可恢复的 App Group PCM chunk 队列，而不是立即实现无锁 mmap ring buffer：

- 扩展把输入转换成 48 kHz、stereo、interleaved Int16；主 App 还原为 Float32 后写入录音文件。
- 每个 chunk 使用 session UUID 和递增 sequence number 命名。
- 先写临时文件，再原子 rename 为 ready 文件。
- 主 App 按 sequence 顺序读取，转换成 `AVAudioPCMBuffer`，成功消费后删除。
- 共享 session metadata 保存格式、最新 sequence、状态和 heartbeat。
- 设置总积压上限；达到上限时记录 overrun，而不是无限占用磁盘。
- 广播异常结束后，下次启动清理过期 session 目录。

后续若实机性能证明文件队列开销过高，可以在不改变上层 `SystemAudioSource` 接口的情况下替换成带跨进程原子索引的 mmap ring buffer。

## iOS 27：ScreenCaptureKit 后端

iOS 27 后端直接运行在主 App 进程，不需要 Broadcast Upload Extension：

1. 代码文件使用 `#if HAS_IOS27_SDK`。
2. 类型和调用同时使用 `@available(iOS 27.0, *)` / `if #available(iOS 27.0, *)`。
3. 激活 `SCContentSharingPicker.shared` 并注册 observer。
4. 使用系统 picker 返回的 `SCContentFilter` 创建 `SCStream`。
5. `SCStreamConfiguration.capturesAudio = true`。
6. 使用系统提供的原生捕获格式，随后通过统一 PCM 转换层标准化为 48 kHz 立体声；转录分析分支单独转换为 16 kHz 单声道。
7. `excludesCurrentProcessAudio = true`，避免把 Live Transcriber 自身的声音重新采入。
8. 只添加 `.audio` output。

iOS 上不能设置 `SCStreamConfiguration.captureMicrophone`；如果以后允许麦克风，应通过 `SCContentSharingPickerConfiguration.showsMicrophoneControl` 让用户在系统 picker 中选择，并正确处理独立的 `.microphone` output。

## 实时字幕与翻译状态

新增 `CaptionPresentationStore`，由 `ContentView` 或更高层会话对象持有。它至少发布：

```swift
struct CaptionSnapshot: Equatable, Sendable {
    let originalText: String
    let translatedText: String?
    let sourceLanguageID: String
    let targetLanguageID: String?
    let isInterim: Bool
    let sessionState: SystemAudioSessionState
}
```

现有 SwiftUI 转录列表与 PiP 同时订阅这个 store。第一阶段延续当前翻译策略：

- 原文显示最新 interim，加最近一条 final。
- 译文只显示最近完成翻译的 final line。
- 不在每个 interim token 上启动翻译任务。
- 后续可增加约 800 ms 的 interim 翻译节流，但必须取消过期请求并限制模型压力。

## 画中画字幕

新增 `CaptionPiPController` 和 `CaptionFrameRenderer`：

- 使用 `AVSampleBufferDisplayLayer` 作为 PiP content source。
- 以低帧率生成真实字幕视频帧，不构造任意悬浮 SwiftUI 控件。
- 画面至少包含原文、译文、录制状态和清晰的 Live Transcriber 标识。
- 文字变化时立即刷新；无变化时保持足够的帧节奏，避免 display layer 停滞。
- 启动前检查 `isPictureInPictureSupported` 和 `isPictureInPicturePossible`。
- 只有当字幕会话是用户当前主要内容时，才允许自动进入 PiP。

PiP 音频会话必须允许与 Zoom 等目标应用混音，不能复用当前会打断其他音频的普通录音回放配置。需要为字幕会话增加独立的 `.playback` + `.mixWithOthers` 策略，并在停止 PiP 后正确释放。

PiP 停止不等于 ReplayKit 广播停止。UI 必须清楚地区分“关闭字幕窗口”和“停止屏幕广播”。iOS 26 的广播停止仍由系统广播界面或控制中心完成。

## 录音保存与 MOSS

共享 PCM 被主 App 消费后继续进入现有 `AudioFileWriter`，因此停止时仍生成普通 `RecordingDraft`，使用现有保存页、命名、分类、标签、位置和 `RecordingStore.save` 流程。

MOSS 保持后处理职责：

- 实时字幕使用 Apple Speech 或本地 Whisper。
- 保存后允许用户选择 MOSS 多说话人重转录。
- 将来可以增加“停止后自动使用 MOSS 优化转录”选项，但必须显示预计耗时、内存和电量影响。
- MOSS 模型绝不复制到 Broadcast Extension 容器或在扩展进程加载。

## UI 行为

转录页增加输入源选择：

- 麦克风
- 屏幕音频

屏幕音频模式至少显示：

- 当前系统后端：iOS 26 兼容模式或 iOS 27 原生模式。
- 广播状态和最近 heartbeat。
- 开始系统广播按钮。
- 打开/关闭 PiP 字幕按钮。
- 停止和保存指导。
- 没有收到 `.audioApp` 时的明确诊断。

iOS 26 第一阶段隐藏 App 内“暂停录音”按钮。主 App 暂停消费者并不能可靠暂停系统广播；系统触发的 `broadcastPaused` 与 `broadcastResumed` 事件仍应正确反映到 UI。

## 计划文件布局

目标 iOS 分支当前仍把主要共享实现放在 `LiveTranscriber/`。完成 macOS 架构整合后，最终位置可以迁移到 `SharedApp/`，但首次实现不要同时进行大规模目录重构。

```text
LiveTranscriber/SystemAudio/
  SystemAudioSessionCoordinator.swift
  SystemAudioSource.swift
  ReplayKitBroadcastPicker.swift
  IOS27ScreenCaptureSource.swift
  SharedAudioChunkConsumer.swift

LiveTranscriber/PictureInPicture/
  CaptionPresentationStore.swift
  CaptionPiPController.swift
  CaptionFrameRenderer.swift

LiveTranscriberBroadcastExtension/
  Info.plist
  LiveTranscriberBroadcastExtension.entitlements
  SampleHandler.swift
  SharedAudioChunkProducer.swift

LiveTranscriberTests/
  SharedAudioChunkQueueTests.swift
  SystemAudioSessionStateTests.swift
  CaptionSnapshotTests.swift
```

## 分支与提交策略

当前 macOS 分支和 `audio-sdk-enhancements` 已从共同基线分别发展，不要直接合并整个 macOS 分支来获得外部音频代码。

开始实现前：

1. 完成、提交并推送当前 macOS 工作，确保工作区干净。
2. 切换到最新 `audio-sdk-enhancements`。
3. 创建短期分支 `codex/ios-screen-captions`。
4. 参考 macOS 分支的外部音频改动，在 iOS 文件路径下重新实现通用版本。

建议拆成可独立构建的提交：

1. `refactor: accept external PCM in live transcription`
2. `feat: add iOS 26 ReplayKit broadcast extension`
3. `feat: bridge broadcast audio through app group`
4. `feat: add shared live caption presentation state`
5. `feat: show bilingual captions in picture in picture`
6. `feat: add iOS 27 ScreenCaptureKit audio backend`
7. `docs: document screen audio privacy and limitations`

## 验证计划

所有 App 构建使用 Xcode 标准 DerivedData；不要将 build 输出指定到 `/tmp`。

### 自动验证

- iOS 26 Simulator 编译主 App 和所有扩展。
- iOS 27 Simulator 编译 ScreenCaptureKit availability 分支。
- App Group chunk 排序、原子提交、损坏文件、缺失 sequence 和积压上限单元测试。
- 外部 PCM 时间线连续性、暂停/恢复和停止 flush 测试。
- Caption snapshot 去重、翻译更新和 PiP frame generation 测试。
- `git diff --check` 和现有 CI lanes。

### iOS 26 实机

- Safari 普通网页音频。
- 非 DRM 本地或网络视频。
- Zoom、Teams 和 Meet 各至少一次真实通话。
- 扬声器、有线耳机、AirPods 和蓝牙切换。
- 横竖屏切换、锁屏、来电/通知打断。
- 30 分钟以上会话的延迟、磁盘、内存和温度。
- App 前台、PiP 后台以及 App 被系统终止后的残留文件恢复。
- 系统广播暂停、恢复、从控制中心停止。

### iOS 27 实机

- `SCContentSharingPicker` 取消、批准和失败路径。
- `.audio` 输出格式与时间戳连续性。
- `excludesCurrentProcessAudio` 防回声验证。
- iOS 27 运行时不加载 ReplayKit 兼容后端。

## 发布与隐私检查

- 开始屏幕录制前说明会采集其他应用允许提供的音频。
- 始终显示系统录制状态与 App 内状态。
- 明确区分系统声音和麦克风，并默认关闭麦克风。
- 在隐私政策和 App Store privacy labels 中披露音频处理与保存行为。
- 录制会议前提醒用户遵守当地法律和参会者同意要求。
- App Review 说明 PiP 用于用户主动开始的实时媒体转录会话，而不是任意后台悬浮 UI。
- 对无法捕获的受保护内容给出解释，不静默回退到麦克风。

## 完成条件

只有满足以下条件才算完成：

- iOS 26 能通过用户启动的 ReplayKit 广播接收 `.audioApp`，而不是麦克风。
- iOS 27 能通过 ScreenCaptureKit 接收系统音频，且不依赖 Broadcast Extension。
- 两个后端进入同一套实时转录、翻译、保存和错误处理逻辑。
- PiP 能在切换到另一个应用后持续显示原文和翻译。
- 停止后生成的录音可以正常播放、保存、导出并选择 MOSS 重转录。
- 没有系统音频时不会自动或静默保存麦克风录音。
- 通过默认 DerivedData 的增量构建、自动测试和 iOS 26/iOS 27 实机验收。

## Apple API 参考

- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [RPSystemBroadcastPickerView](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview)
- [RPBroadcastSampleHandler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler)
- [RPSampleBufferType](https://developer.apple.com/documentation/replaykit/rpsamplebuffertype)
- [AVPictureInPictureController](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller)
- [AVPictureInPictureController.ContentSource](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource-swift.class)
