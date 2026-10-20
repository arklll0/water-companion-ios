# 水伴英语 · iOS 版

把 Android 版（2.5.6 / versionCode 35）重写为 SwiftUI 原生 iOS 应用，界面遵循 Apple Human Interface Guidelines。

- **目标设备**：iPhone 13（iOS 17 及以上）
- **数据完全互通**：存档结构与 Android 的 `state_json` 一字不差，Android 导出的进度可以直接粘贴导入
- **构建方式**：本机没有 Mac，用 GitHub Actions 的 macOS 机器编译出未签名 IPA，再在 Windows 上用 Sideloadly 签名装进 iPhone

---

## 一、怎么装到 iPhone（无 Mac 操作路径）

### 1. 准备账号与工具（一次性）

| 需要 | 说明 |
|---|---|
| GitHub 账号 | 免费即可，用来跑 macOS 编译机 |
| Apple ID | 普通免费账号即可（不需要 99 美元开发者账号） |
| Sideloadly | Windows 侧载工具，官网 `sideloadly.io` 下载 |
| iTunes | Sideloadly 依赖它的驱动来连 iPhone，微软商店版或官网版都行 |

### 2. 把工程传上 GitHub

1. 网页打开 GitHub，新建一个 **Private** 仓库，名字随意，例如 `water-companion-ios`
2. 把本目录（`WaterCompanion-iOS/`）里的**全部内容**上传上去（网页拖拽上传也行）
   - 注意：要让 `.github/workflows/ios.yml` 出现在仓库根目录的 `.github/workflows/` 下
3. 上传完成后，仓库顶部 **Actions** 标签会自动开始跑 `Build iOS IPA`

### 3. 下载 IPA

1. Actions 页面点进最新一次运行，等约 5~10 分钟（首次装 XcodeGen 会慢一点）
2. 跑完后在页面底部 **Artifacts** 里下载 `WaterCompanion-unsigned-ipa`
3. 解压得到 `WaterCompanion-unsigned.ipa`

### 4. 装进 iPhone

1. iPhone 用数据线连电脑，手机上点「信任此电脑」
2. 打开 Sideloadly，把 `.ipa` 拖进窗口
3. **Apple ID** 一栏填你的 Apple ID，点 Start，输入密码
4. 安装完成后，手机上进入 **设置 → 通用 → VPN 与设备管理**，点你的 Apple ID → **信任**
5. 回到桌面，图标「水伴英语」即可打开

> **7 天有效期**：免费 Apple ID 签名的应用 7 天后会打不开。到期时把手机连回电脑，Sideloadly 里重新点一次 Start 即可续签，**App 内的学习进度不会丢**（重签是覆盖安装，不是卸载）。

---

## 二、以后有了 Mac 怎么办

```bash
brew install xcodegen
cd WaterCompanion-iOS
xcodegen generate
open WaterCompanion.xcodeproj
```

Xcode 里选自己的 Apple ID 作为 Team，连上 iPhone 直接 Run 即可（免费账号同样是 7 天有效期，付费账号 1 年）。

---

## 三、目录结构

```
WaterCompanion-iOS/
├── project.yml                     XcodeGen 工程描述（Xcode 工程由它生成，不提交 pbxproj）
├── Sources/WaterCompanion/
│   ├── WaterCompanionApp.swift     入口
│   ├── RootView.swift              自定义底部胶囊 TabBar + 页面切换
│   ├── Design/                     颜色 / 字阶 / 间距 / 通用组件
│   ├── Models/                     内容模型 + 进度模型
│   ├── Services/                   存档、内容加载、每日调度、SRS、统计、音频
│   └── Screens/                    各页面
├── Resources/
│   ├── Content/                    词库 / 听力 / 阅读 / 真题 / 词族 / 短语 JSON
│   ├── Audio/                      3362 条音频（m4a）+ index.json
│   └── Assets.xcassets/            App 图标
└── .github/workflows/ios.yml       macOS 构建流水线
```

---

## 四、与 Android 版的对应关系

| Android | iOS | 说明 |
|---|---|---|
| `state_json`（DataStore） | `Application Support/progress.json` | 字段名完全一致，可互相导入导出 |
| `DailyPlan.kt` | `Services/DailyPlan.swift` | 同样 90 天循环、连续切片、按词量联动 |
| `Srs.kt` | `Services/Srs.swift` | 同样四张间隔表 |
| `AssetsDataSource` | `Services/ContentStore.swift` | 同一批 JSON |
| 离线 `audio/*.ogg` | `Resources/Audio/*.m4a` | iOS 不支持 ogg，已转 AAC 32kbps（体积 22.8MB → 31.6MB） |
| Compose 悬浮胶囊底栏 | SwiftUI 自定义 TabBar + `.ultraThinMaterial` | 保留品牌观感，交互按 iOS 习惯 |

### 导入 Android 的进度

「我的」→「学习进度迁移」→ 粘贴 Android 端「导出」得到的 JSON → 导入。
字段名一致，多出的键会被忽略，缺失的键用默认值补齐，不会清空已有数据。

---

## 五、设计原则

1. **优先用系统能力**：图标全部 SF Symbols，字体全部 SF Pro，控件优先 `List` / `Form` / `NavigationStack` / `Picker` / `ContentUnavailableView`，材质用 `.ultraThinMaterial`，动效用 `.snappy` / `.smooth`。
2. **品牌色保留**：墨绿 `#0E5F4B`（浅色）/ `#5FC7A0`（深色），与 Android 版一致。
3. **间距只有 6 档**：4 / 8 / 12 / 16 / 24 / 32，页面边距 16，卡片圆角 12。
4. **深色模式必须可用**，跟随系统，也可在设置里强制浅色/深色。

---

## 六、已知限制

- 免费 Apple ID 侧载的应用 **7 天需要重签一次**（重签不丢数据）。
- 同一 Apple ID 同时最多装 3 个自签应用。
- 翻译功能依赖 MyMemory 公共接口，断网时不可用，其余功能全部离线。
- 无法在 App Store 上架（个人自用）。
