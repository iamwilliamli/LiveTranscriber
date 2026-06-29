# LiveTranscriber 开发笔记

本文档记录当前 app 的开发思路、关键取舍、架构说明、已知限制和后续可扩展方向。它不是用户说明书，而是给后续继续开发、上 TestFlight 前复盘、或者重构时使用的工程笔记。

## 产品定位

LiveTranscriber 是一个 iOS 26+ 的本地录音和实时转录工具。iOS 27 上保留 Native Speech Pipeline 作为可选开发者模式。

核心目标：

- 开始录音后实时显示转录文字。
- 录音结束后保存音频文件和对应文本。
- 录音文件可播放，点击转录文本行可以跳到对应音频时间。
- 灵动岛和锁屏 Live Activity 显示录音状态、最新转录内容和持续计时。
- 尽量使用 Apple 原生 SDK，降低维护成本，保持 iOS 系统风格。

当前 app 不是云转录工具，默认不把音频或文本上传到第三方服务。主要依赖 Apple Speech 本机模型和系统权限。

## 平台和 SDK 取舍

项目当前兼容 iOS 26+，但使用 iOS 27 SDK 构建，以便在 iOS 27 设备上保留新的 Speech Pipeline：

- `SpeechAnalyzer` 负责音频分析管线。
- `SpeechTranscriber` 负责实时转录。
- `AnalyzerInputConverter` 只在 iOS 27 Native Pipeline 中使用。
- `ActivityKit` 和 Widget extension 用于灵动岛与锁屏状态展示。

当前保留两条实时转录 Pipeline：

- Compatible Pipeline：iOS 26/27 默认稳定路径，`AVAudioConverter -> 16 kHz / mono / Int16 PCM`，再送入 `SpeechAnalyzer.prepareToAnalyze(in: analyzerInputFormat)`。
- iOS 27 Native Pipeline：使用 `AnalyzerInputConverter.converter(compatibleWith: modules)` 和 `SpeechAnalyzer.prepareToAnalyze(in: nil)`，让系统选择输入格式。

两条 Pipeline 都使用 `SpeechTranscriber(preset: .timeIndexedProgressiveTranscription)`，并对 `AnalyzerInput.bufferStartTime` 使用严格单调的 frame-based `CMTime` 累加，避免时间戳重叠。

## 当前能力

当前主界面是三栏 Tab：

- `TranscriptionView`：实时录音、暂停/继续、停止、当前转录文本。
- `RecordingsView`：录音文件、搜索、导入、重转录、播放、分享、复制、删除、智能摘要和标签。
- `SettingsView`：转录语言、录音格式、文件数量和存储位置。

### 实时录音和转录

入口在 `LiveTranscriptionManager`。

流程：

1. 请求语音识别和麦克风权限。
2. 配置 `AVAudioSession`。
3. 获取麦克风输入格式。
4. 准备 SpeechAnalyzer 模块和语言模型。
5. 安装 `AVAudioEngine` input tap。
6. 每个音频 buffer 同时写入本地音频文件并送入 SpeechAnalyzer。
7. Speech SDK 返回实时结果后更新转录行和 Live Activity。

暂停时会停止 input tap 和 audio engine，并冻结计时。继续录音时重新安装 tap，沿用原来的 analyzer pipeline 和音频 writer。

### 转录行

`TranscriptionLine` 保存：

- `startSeconds`：从录音开始算起的秒数。
- `text`：识别文本。
- `isFinal`：是否最终结果。

文本保存为按行格式：

```text
[00:12:00] 这是一行转录内容
[00:18:00] 这是下一行
```

这个格式方便人读，也方便 `RecordingsView` 解析后实现“点文字跳转音频”。

### 录音文件

当前支持两种原生稳定格式：

- WAV：Linear PCM，无损，文件更大。
- M4A：AAC 压缩，文件更小。

MP3 没有做成可选项。原因是 iOS 原生 AVFoundation 录音写入链路不提供可靠的 MP3 编码路径。强行显示 MP3 选项会导致用户录完后才遇到失败，体验更差。后续如果确实需要 MP3，可以考虑引入独立编码库或服务端转码，但那会带来体积、授权、性能和隐私成本。

录音保存在：

```text
iCloud Drive/Live Transcriber/Documents/Recordings/
```

如果 iCloud Documents 容器不可用，会 fallback 到 app 本地 `Documents/Recordings/`。当 iCloud 后续可用时，`RecordingStore` 会把本地录音文件复制到 iCloud 目录。

索引文件：

```text
Documents/Recordings/recordings.json
```

音频和文本成对保存：

```text
Recording_yyyyMMdd_HHmmss.wav
Recording_yyyyMMdd_HHmmss.txt
```

iCloud 同步设计：

- App entitlement 使用 `iCloud.com.iamwilliamli.LiveTranscriber`，服务为 CloudDocuments。
- Info.plist 声明 `NSUbiquitousContainers`，并把 document scope 设为 public，让文件出现在 iCloud Drive。
- `RecordingStore.recordingsDirectory` 优先使用 ubiquity container 的 `Documents/Recordings`。
- `reload()` 不只读 `recordings.json`，还会扫描录音目录，把跨设备同步来的音频文件合并进列表。
- App 回到前台时会重新 `reload()`，用于接收其他设备同步来的变更。

导入录音设计：

- 录音列表 toolbar 提供“导入录音”按钮，使用系统 Files picker。
- 支持 `UTType.audio`，实际能否读取由 `AVAudioFile` 决定。
- 用户选中文件后会先弹出语言选择，而不是直接使用当前设置语言。
- `RecordingStore` 先创建带 `RecordingImportStatus` 的占位 `RecordingItem`，列表和详情页可以展示进度。
- 导入 worker 复制源文件到录音目录，并创建空 `.txt`。
- `ImportedRecordingTranscriptionService` 用 `SpeechAnalyzer` / `SpeechTranscriber` 离线转录，按音频读取进度更新 UI。
- 转录完成后写入 timed transcript，更新 preview、行数、时长、语言和归一化版本。
- 导入失败时不直接丢掉条目，而是把 `importStatus.isFailed` 设为 true，方便用户看到失败原因。

重转录设计：

- 列表行、context menu 和详情页 toolbar 都可以触发重转录。
- 重转录时用户选择目标语言。
- 重转录复用原音频文件，替换 `.txt`，更新语言、preview 和行数。
- 重转录完成后会清空旧的智能摘要/标签，避免摘要对应旧文本。
- 转录进行中禁用删除和再次重转录，避免同一文件被并发改写。

### 录音处理 Pipeline

当前这套链路在真机体验上可以稳定工作：录音文件音量足够，播放不再破音。后续不要回到录制阶段实时放大的方案；播放端如果保留增益，也应只是小幅辅助，不能替代文件级归一化。

录音阶段：

1. `AVAudioSession` 使用 `.playAndRecord` + `.voiceChat`，options 为 `.allowBluetoothHFP`、`.defaultToSpeaker`、`.duckOthers`。
2. `AVAudioEngine` input tap 收到每个 `AVAudioPCMBuffer` 后复制两份。
3. 第一份原始 buffer 直接写入 `AudioFileWriter`，不做实时增益。
4. 第二份原始 buffer 送入 `AnalyzerInputPipeline` / `SpeechAnalyzer`，避免音量处理影响转录识别。

实时转录 Pipeline 参数：

- Compatible：`SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)`；iOS 27 上额外设置 `ignoresResourceLimits: true`；输入格式固定为 `16 kHz / mono / Int16 PCM`；转换器为 `AVAudioConverter`。
- iOS 27 Native：`SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse, ignoresResourceLimits: true)`；`AnalyzerInputConverter.converter(compatibleWith: modules)`；`SpeechAnalyzer.prepareToAnalyze(in: nil)`；给 converter 传入合成的连续 `AVAudioTime`。

停止录音后：

1. 停止 input tap 和 audio engine。
2. finish analyzer pipeline，等待 SpeechAnalyzer flush。
3. 用 `RecordingFileNormalizer.normalize(...)` 对刚生成的音频文件做一次离线归一化。
4. 归一化成功后写入 `audioNormalizedAt` 和 `audioNormalizationVersion`。

当前归一化版本是 `RecordingFileNormalizer.version = 2`。核心参数：

- `targetActiveRMS = 0.20`
- `maximumGain = 16`
- `limiterCeiling = 0.94`
- `activeSampleThreshold = 0.012`
- `minimumActiveRMS = 0.006`
- `frameCapacity = 8192`

归一化按“有效语音样本”的 RMS 计算增益，而不是按整段 RMS 或单个最高峰值计算。这样短促爆点不会把整段人声音量压低。写出时使用软限幅，避免硬裁剪造成破音。

归一化写入策略：

- 先读原文件统计 active RMS。
- 写到同目录临时文件 `.normalized-UUID.ext`。
- 写完后用 backup 文件做替换，失败时尽量恢复原文件。

已有录音：

- 打开录音详情页时调用 `RecordingStore.normalizeAudioIfNeeded(for:)`。
- 如果 `audioNormalizationVersion` 不是当前版本，会重新归一化。
- 如果版本已匹配，则不重复处理，避免反复增益导致破音。

明确不要做：

- 不要在 input tap 写文件前实时放大。
- 不要继续提高播放端增益来替代文件级归一化。
- 不要用单个 peak 决定整段 gain。
- 不要每次打开详情页都重复归一化同一个版本的文件。

### 文件管理

`RecordingsView` 使用系统 `List`，而不是 `ScrollView + LazyVStack`，原因是：

- 原生滑动删除更稳定。
- VoiceOver 和列表交互更符合系统预期。
- 行为更接近 iOS 文件/录音列表。

删除入口保留：

- 左滑删除。
- 长按菜单删除。
- 详情页 toolbar 删除。

列表中不再常显删除按钮，避免视觉噪音和误触。

当前搜索已经实现，不再是后续功能。搜索入口使用 `.searchable`，匹配范围包括：

- 文件名。
- 语言名。
- transcript preview。
- 完整 `.txt` 转录文本。
- 智能摘要。
- 智能标签。

搜索实现是直接读取文本文件并做大小写、变音符、全半角不敏感匹配。录音数量很大时再考虑建立索引。

### 音频播放

播放逻辑在 `RecordingPlaybackController`。

当前使用 `AVAudioEngine + AVAudioPlayerNode`，中间接 `AVAudioUnitEQ`，`globalGain = 3`。播放器负责播放、暂停、seek 和轻量播放端增益；长期、可持久的音量增强仍然放在文件级归一化阶段完成。

详情页会把转录文本解析成带时间的行。点击某一行会 `seek(to:)` 到该行的 `startSeconds`。

播放计时约每 120ms 更新一次。当前行高亮由播放位置和下一行开始时间共同决定。

### 灵动岛和锁屏

Live Activity 状态由 `TranscriptionLiveActivityCoordinator` 管理。

关键点：计时不能只显示 `elapsedText` 静态字符串。Widget 不会自己每秒重新计算普通字符串。现在状态里带了 `timerReferenceDate`，Widget 用：

```swift
Text(state.timerReferenceDate, style: .timer)
```

录音中系统会自动刷新计时。暂停或结束时显示固定的 `elapsedText`，避免计时继续跳。

最新转录文本会在锁屏和灵动岛 expanded 区域显示。锁屏最多显示 3 行；灵动岛保留 2 行以适配系统区域。超长时从尾部截断，优先保留最新内容。

Live Activity 文本更新策略：

- 录音开始时 start 一次 Activity。
- 每段转录变成 final 时 update 一次，把最新 final transcript 同步到锁屏/灵动岛。
- interim 转录不更新 Activity。
- 不做短时间定时节流刷新，也不按 timer tick 更新 Activity。
- 暂停、继续、结束仍然更新一次状态。

这样可以避免短时间内 Activity update 过多。计时由 Widget 里的 system timer 自己刷新，不需要 app 持续推送。

## UI/UX 思路

### 总体视觉

设计方向是“像系统工具，不像营销页面”。

关键词：

- 安静。
- 清晰。
- 低干扰。
- 常用操作优先。
- 接近 Voice Memos 的录音心智。

字体统一使用 Reddit Sans，包括主 app 和 Widget。这样视觉上和原来的 Red Downloader 系列保持一点品牌一致性，但控件行为仍然是 iOS 原生风格。

视觉 token 在 `AppTheme`：

- 圆角：普通卡片 8pt，紧凑控件 7pt。
- 主品牌红用于录音格式、时间戳和强调态。
- danger 红用于录音/停止/删除等高风险动作。
- info 蓝、success 绿、warning 黄分别用于信息、成功和警告状态。
- 背景使用系统 grouped / secondary grouped / tertiary grouped 色。
- 卡片边框用 separator opacity，阴影保持轻。

字体在 `AppTypography`：

- SwiftUI 统一使用 `.redditSans(...)`。
- UIKit appearance 会覆盖导航标题、Tab、BarButton、TextField、SegmentedControl、SearchTextField。
- 计时和时间戳统一使用 monospaced digit。

### 录音页

录音页重点是四件事：

- 当前语言和格式。
- 大号计时。
- 开始、暂停、停止。
- 当前转录文本和行数。

录音页不显示波形和语音检测状态。前期做过实时波形，但信息价值不高，还会增加视觉噪音；当前保留更接近系统录音机的简洁布局。

当前布局：

- 顶部 recorder card 显示标题、状态、录音状态 badge、大号计时、格式 badge、语言 menu、行数、保存成功和错误提示。
- transcript card 显示最新转录文本，列表按新内容优先展示。
- 未录音时底部是全宽红色“开始录音” capsule。
- 录音中底部是 material floating dock，包含暂停/继续和停止。
- 录音中或准备中禁用语言切换。

### 设置页

设置页分为：

- 转录：语言 menu，录音中锁定。
- 录音：WAV/M4A segmented picker 和格式说明。
- 文件：录音数量和当前存储位置。

### 文件页

列表行展示：

- 日期时间。
- 文件名。
- 时长。
- 语言。
- 文本行数。
- 转录预览，或智能摘要/标签，或导入/重转录状态。

删除不常显，保持列表干净。真正需要删除时使用滑动或长按。

详情页由四个卡片组成：

- header：文件名、日期、时长、语言。
- player：播放、暂停、slider、当前时间和总时长。
- intelligence：摘要、标签、生成时间、分析/重新分析。
- transcript：导入状态或可点击的时间戳转录行。

详情 toolbar 支持分享音频/转录文字、重转录、复制、分析和删除。

### 触感反馈

`HapticFeedback` 集中管理 UIKit haptics，并对高频事件做节流。当前覆盖：

- 页面导航、菜单选择、主操作。
- 录音开始、暂停、继续、停止、保存。
- 播放、时间线 seek、复制。
- 导入、重转录、智能分析。
- 删除、阻塞操作、警告和失败。

## 已知限制

### 暂不做多人声区分

当前使用的 Apple SpeechAnalyzer/SpeechTranscriber 管线没有提供稳定的多人声区分 API。因此 app 不应假装能区分不同讲话者。

可行的后续方向：

- 如果 Apple 后续增加系统级多人声区分能力，直接接入 SDK。
- 使用第三方本地模型，但会增加包体和性能压力。
- 使用服务端模型，但会改变隐私边界。

### MP3 不作为原生录音格式

MP3 是用户熟悉的格式，但 iOS 原生录音链路不适合直接编码 MP3。当前只在设置里说明原因，不暴露不可用选项。

### Live Activity 文本刷新频率受系统控制

计时可以用系统 timer 实时刷新，但最新转录文本仍然依赖 app 更新 Activity。系统可能会根据电量、锁屏状态和后台策略限制刷新频率。

### 长录音压力

长时间录音会带来：

- 音频文件变大。
- 转录行增多。
- 列表和详情解析压力增加。
- Live Activity 更新频率需要控制。

后续如果支持很长会议录音，需要考虑分段保存、后台任务和更强的索引结构。

## 后续功能想法

### 1. 转录文本编辑

详情页支持修改某一行文本：

- 点击行进入编辑。
- 保存后同步更新 `.txt` 和 index preview。

这会让转录结果更适合导出和分享。

### 2. 导出格式

除 txt 外，可以增加：

- Markdown。
- SRT 字幕。
- JSON。

SRT 很适合视频字幕场景，当前已有每行时间，可以扩展成字幕格式。

### 3. 标签和收藏

录音文件可以加：

- 星标。
- 标签。
- 备注。

这需要扩展 `RecordingItem` 的 index schema，并考虑旧数据迁移。

### 4. iCloud 同步设置与冲突处理

当前已经优先使用 iCloud Drive，并在 iCloud 不可用时 fallback 到本机 Documents。后续更需要补的是用户可控策略和冲突处理：

- 是否同步完整音频。
- 是否只同步索引和转录文本。
- 是否允许用户固定为本机存储。
- 多设备同时生成或修改 `recordings.json` 时的合并策略。

音频文件较大，默认策略继续保持简单；如果要加开关，需要先设计清楚旧文件迁移和跨设备删除语义。

### 5. 更强的录音波形

当前主页不显示波形。后续如果要恢复波形，更适合放在录音详情页：保存音频峰值数据，显示完整录音波形，并支持拖动波形 seek。

可以新增一个 `.waveform.json`：

```json
{
  "duration": 128,
  "samples": [0.1, 0.3, 0.2]
}
```

录音完成后后台生成，详情页直接读取，避免每次打开都重新分析音频。

### 6. 背景录音

如果要支持锁屏后持续录音，需要认真处理：

- Background Modes。
- 音频 session。
- Live Activity 状态。
- 中断恢复。
- 来电、耳机、蓝牙设备切换。

这是 TestFlight 前需要重点真机测试的部分。

## TestFlight 前检查清单

- 真机测试麦克风权限首次弹窗。
- 真机测试语音识别权限首次弹窗。
- 测试中文、英文语言切换。
- 测试 WAV 和 M4A 保存、播放、分享。
- 测试录音暂停、继续、停止。
- 测试锁屏和灵动岛计时是否持续。
- 测试无网络或模型未下载时的提示。
- 测试删除录音后文件是否真的移除。
- 测试长录音至少 10 到 30 分钟。
- 检查 PrivacyInfo.xcprivacy 和 Info.plist 权限文案。

## 构建验证命令

暂存项目构建：

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -quiet \
  -project LiveTranscriber.xcodeproj \
  -scheme LiveTranscriber \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/LiveTranscriberDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

最终项目路径：

```text
~/workspace/LiveTranscriber
```

最终项目构建时把 workdir 切到该目录，并使用单独的 DerivedData 路径即可。
