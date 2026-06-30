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
3. 使用 `AVCaptureSession` 立体声采集路径。
4. 准备 SpeechAnalyzer 模块和语言模型。
5. 启动采集，把音频 buffer 写入本地音频文件并送入 SpeechAnalyzer。
6. Speech SDK 返回实时结果后更新转录行和 Live Activity。

暂停时会停止当前采集源并冻结计时。继续录音时重新启动采集，沿用原来的 analyzer pipeline 和音频 writer。

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

录音文件保存在 app 私有目录：

```text
ubiquity-container/Recordings/
```

如果 app 私有 iCloud container 不可用，会 fallback 到 app 本地 `Documents/Recordings/`。当 iCloud 后续可用时，`RecordingStore` 会把本地录音文件复制到私有 iCloud container。

录音索引用 SwiftData 保存，并通过 CloudKit private database 同步到用户自己的 iCloud。`recordings.json` 只作为旧版本迁移来源读取，不再作为当前索引写入。

音频和文本成对保存：

```text
Recording_yyyyMMdd_HHmmss.wav
Recording_yyyyMMdd_HHmmss.txt
```

iCloud 同步设计：

- App entitlement 使用 `iCloud.com.iamwilliamli.LiveTranscriber`，服务为 CloudDocuments 和 CloudKit。
- Info.plist 声明 `NSUbiquitousContainers`，并把 document scope 设为非 public，避免录音文件暴露到 iCloud Drive 文件夹。
- `RecordingStore.recordingsDirectory` 优先使用 ubiquity container 的私有 `Recordings` 目录。
- `reload()` 读取 SwiftData 索引，也会扫描录音目录，把跨设备同步来的音频文件合并进列表。
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

当前只保留 `AVCaptureSession` 立体声采集路径：

1. `LiveTranscriptionManager` 固定走 `CaptureSessionRecordingPipeline`。
2. `AVAudioSession` 使用 `.playAndRecord` + `.default`，options 为 `.defaultToSpeaker`、`.duckOthers`，并请求 `preferredInputNumberOfChannels = 2` 用于 route 诊断。
3. 创建 `AVCaptureDeviceInput(device: AVCaptureDevice.default(for: .audio))`。
4. 检查 `isMultichannelAudioModeSupported(.stereo)`，成功后设置 `multichannelAudioMode = .stereo`。
5. 通过 `AVCaptureAudioDataOutput` 接收 `CMSampleBuffer`。iOS 上不能设置 `AVCaptureAudioDataOutput.audioSettings`，所以格式转换在 app 内完成。
6. 每个 `CMSampleBuffer` 转成源 `AVAudioPCMBuffer` 后分两路：
   - 转成 `Float32 / stereo / non-interleaved`，写入 `AudioFileWriter`，保存 stereo 文件。
   - 转成 `Float32 / mono / non-interleaved`，送入 `AnalyzerInputPipeline`，再由当前 Speech Pipeline 转成 SpeechAnalyzer 需要的格式。
7. 这个路径已经在真机确认可以 work：保存文件是 stereo，转录继续正常工作。

立体声采集限制：

- `AVCaptureDeviceInput.multichannelAudioMode` 默认是 `.none`，必须显式设置 `.stereo`。
- Apple 的这个属性只对内置麦克风生效；外接麦克风可能被系统忽略。
- 如果当前输入不支持 `.stereo`，app 会直接报“不支持 AVCapture stereo 采集”，不要静默降级成 mono，否则用户很难判断录音文件到底是什么。
- 录音详情页会显示保存文件的采样率、声道和编码；capture setup、首个 buffer 格式和转换失败只输出到 Xcode 日志。

实时转录 Pipeline 参数：

- Compatible：`SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)`；iOS 27 上额外设置 `ignoresResourceLimits: true`；输入格式固定为 `16 kHz / mono / Int16 PCM`；转换器为 `AVAudioConverter`。
- iOS 27 Native：`SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse, ignoresResourceLimits: true)`；`AnalyzerInputConverter.converter(compatibleWith: modules)`；`SpeechAnalyzer.prepareToAnalyze(in: nil)`；给 converter 传入合成的连续 `AVAudioTime`。

停止录音后：

1. 停止 `AVCaptureSession`。
2. finish analyzer pipeline，等待 SpeechAnalyzer flush。
3. 如果开发者选项里的“响度处理”开启，用 `RecordingFileNormalizer.normalize(...)` 对刚生成的音频文件做一次离线归一化。
4. 只有归一化成功后才写入 `audioNormalizedAt` 和 `audioNormalizationVersion`。
5. `TranscriptionView` 弹出保存 sheet，让用户修改录音名、添加手动标签、查看时长，并可选择附加地理位置。
6. 用户点保存后，`RecordingStore.save(...)` 才把临时音频、转录文本和 metadata 一起写入私有录音目录与 SwiftData 索引；用户点丢弃时删除临时音频并清空当前 transcript。

“响度处理”默认关闭。开启后，新录音、导入录音和打开详情页时的补处理会执行文件级归一化；关闭时保留 Stereo Capture 原始音量。已经归一化过的旧文件不会自动恢复成原始文件。

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

- 打开录音详情页时调用 `RecordingStore.normalizeAudioIfNeeded(for:loudnessProcessingEnabled:)`。
- 如果“响度处理”开启且 `audioNormalizationVersion` 不是当前版本，会重新归一化。
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

当前使用 `AVAudioEngine + AVAudioPlayerNode`，中间接 `AVAudioUnitEQ`，`globalGain = 3`。播放器负责播放、暂停、seek 和轻量播放端增益；长期、可持久的音量增强放在可选的文件级归一化阶段完成。

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

### 3. 收藏和备注

录音文件可以加：

- 星标。
- 备注。

标签已经在停止录音后的保存 sheet 和录音详情编辑 sheet 中实现，并保存在 SwiftData metadata。Apple Intelligence 生成的 topic tags 会合并进同一组 tags：手动 tags 优先，AI tags 补充，按大小写/宽度/重音无关去重。用户编辑时看到的是合并后的最终 tags；保存后这组 tags 会写回 `manualTags`，避免用户删掉的 AI tag 又在 UI 里重复出现。

### 4. iCloud 同步设置与冲突处理

当前已经优先使用 app 私有 iCloud container，并在 iCloud 不可用时 fallback 到本机 Documents。后续更需要补的是用户可控策略和冲突处理：

- 是否同步完整音频。
- 是否只同步索引和转录文本。
- 是否允许用户固定为本机存储。
- 多设备同时生成或修改同一录音 metadata 时的 CloudKit 合并策略。

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
- 测试系统录音/语音备忘录分享菜单里的音频文件能打开到 app，并弹出语言选择后导入转录。
- 测试录音暂停、继续、停止。
- 测试锁屏和灵动岛计时是否持续。
- 测试无网络或模型未下载时的提示。
- 测试删除录音后文件是否真的移除。
- 测试长录音至少 10 到 30 分钟。
- 检查 PrivacyInfo.xcprivacy 和 Info.plist 权限文案。
- Info.plist 必须包含 `NSCameraUsageDescription`：app 不使用相机，但 `AVCaptureSession` / `AVCaptureDeviceInput` 的静态审核会要求相机 purpose string。
- App Store Connect 隐私信息按 no developer data collection / no tracking 填写；说明 iCloud 和 CloudKit private database 是用户 Apple iCloud 同步，不是开发者服务器。
- Beta Review Notes 写清：无账号、无广告、无分析、无追踪、无开发者后端；麦克风只用于录音，语音识别只用于转录，后台音频只用于录音/播放继续。

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
