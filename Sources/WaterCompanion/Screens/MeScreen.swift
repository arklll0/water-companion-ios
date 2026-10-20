import SwiftUI
import UIKit

// ════════════════════════════════════════════════════════════════════
//  我的
// ════════════════════════════════════════════════════════════════════
//
//  这一页只做两件事：**去别处**（统计 / 错题 / 翻译）和**改设置**。
//
//  ## 为什么用 `List` + `Section`
//
//  它本质上就是一张「分组设置表」，而这正是系统 `Form` / 分组 `List` 的形状：
//  行高、分组间距、圆角、选中高亮、动态字号、VoiceOver 的「按钮 / 开关」语义，
//  系统全都替你处理好了。自己拿卡片拼一版只会得到「一个长得像设置页但不好用」的页面。
//
//  ## 为什么全部即时保存
//
//  没有「保存」按钮：iOS 的设置页从来不这么干。改了就落盘（每个 setter 内部
//  都会立刻写 `progress.json`），退出重进还是这个值 —— 用户不需要记得「我改过没保存」。
//  唯一需要二次确认的是**重置**，因为那是不可撤销的。
//
//  ## 进度迁移为什么放在设置里
//
//  它是一次性的、低频的、需要用户做决定的动作。放在首页会变成噪音，
//  藏在「我的 → 学习进度迁移」里，换设备时找得到，平时不打扰。

struct MeScreen: View {

    @Environment(ProgressStore.self) private var store

    /// 迁移输入框的内容。默认空 —— 不预填导出结果，
    /// 因为「打开这一页就看到一屏 JSON」会让人以为出了什么事。
    @State private var transferText = ""

    @State private var showResetConfirm = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    // MARK: - 派生状态

    private var progress: Progress { store.progress }

    /// 主题存的是 "auto" / "light" / "dark"（与网站同一个字段），
    /// 认不出的值按「跟随系统」处理，不让 Picker 落到「一个都没选中」的状态。
    private var themeBinding: Binding<Theme.Mode> {
        Binding(
            get: { Theme.Mode.fromKey(progress.theme) },
            set: { store.setTheme($0.rawValue) }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { MeScreen.minutes.contains(progress.dailyMinutes) ? progress.dailyMinutes : 30 },
            set: { store.setDailyMinutes($0) }
        )
    }

    private var wordsBinding: Binding<Int> {
        Binding(
            get: { MeScreen.wordOptions.contains(progress.dailyWords) ? progress.dailyWords : 20 },
            set: { store.setDailyWords($0) }
        )
    }

    /// 考试日期是「可为空」的，而 `DatePicker` 必须有值。
    /// 没设置时先显示「三个月后」，用户一动就落盘 —— 比强行要求先点「设置」再选日期少一步。
    private var examDateBinding: Binding<Date> {
        Binding(
            get: {
                if let raw = progress.examDate, let date = Srs.date(raw) { return date }
                return MeScreen.defaultExamDate
            },
            set: { store.setExamDate(MeScreen.dateFormatter.string(from: $0)) }
        )
    }

    // MARK: - 视图

    var body: some View {
        ZStack {
            AppBackground()
            list
        }
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.large)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog(
            "确定要重置吗？",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("重置全部进度", role: .destructive) {
                store.reset()
                transferText = ""
                notify("已重置", "全部学习记录已清空，回到第一天。")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会清空单词进度、已读已听记录、模考成绩与错题本，且不可撤销。")
        }
    }

    private var list: some View {
        List {
            featureSection
            appearanceSection
            studySection
            transferSection
            dangerSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - 功能入口

    private var featureSection: some View {
        Section {
            NavigationLink(value: AppRoute.stats) {
                Label {
                    Text("进度统计")
                } icon: {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(Theme.Colors.primary)
                }
            }

            NavigationLink(value: AppRoute.wrong) {
                Label {
                    Text("错题集")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.error)
                }
            }

            NavigationLink(value: AppRoute.translate) {
                Label {
                    Text("翻译工具")
                } icon: {
                    Image(systemName: "character.bubble.fill")
                        .foregroundStyle(Theme.Colors.primary)
                }
            }
        } header: {
            Text("全部功能")
        } footer: {
            Text("统计看的是「这一段有没有进步」，不是分数排行。")
        }
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("主题")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Picker("主题", selection: themeBinding) {
                    ForEach(Theme.Mode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, Space.xs)
        } header: {
            Text("外观")
        } footer: {
            Text(themeFooter)
        }
    }

    private var themeFooter: String {
        switch Theme.Mode.fromKey(progress.theme) {
        case .light:
            return "始终浅色：不管系统怎么切，App 都用浅色。"
        case .dark:
            return "始终深色：不管系统怎么切，App 都用深色。"
        case .auto:
            return "跟随系统：系统切到深色时，App 会当场跟着变。"
        }
    }

    // MARK: - 学习设置

    private var studySection: some View {
        Section {
            DatePicker(
                "考试日期",
                selection: examDateBinding,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .environment(\.locale, Locale(identifier: "zh_CN"))

            if progress.examDate != nil {
                Button("清除考试日期") {
                    store.setExamDate(nil)
                }
                .font(Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                Text("每天学多久")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Picker("每天学多久", selection: minutesBinding) {
                    Text("15 分钟").tag(15)
                    Text("30 分钟").tag(30)
                    Text("60 分钟").tag(60)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, Space.xs)

            VStack(alignment: .leading, spacing: Space.sm) {
                Text("每天背多少词")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Picker("每天背多少词", selection: wordsBinding) {
                    Text("10 词").tag(10)
                    Text("20 词").tag(20)
                    Text("30 词").tag(30)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, Space.xs)
        } header: {
            Text("学习设置")
        } footer: {
            // 一行同时说清两件事：离考试还有多久、词量会连带改什么。
            Text("\(examFooter)\n每天的单词量也会决定听力和阅读的份量，改一处即可。")
        }
    }

    private var examFooter: String {
        guard let raw = progress.examDate, Srs.date(raw) != nil else {
            return "还没设置考试日期。选一个，首页就会开始倒计时。"
        }
        let left = Srs.daysBetween(Srs.today(), raw)
        if left < 0 { return "考试日期已经过了，改一个未来的日期吧。" }
        if left == 0 { return "就是今天。把会的写出来就够了。" }
        return "距离考试还有 \(left) 天。"
    }

    // MARK: - 进度迁移

    private var transferSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $transferText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(Space.sm)
                    .background(
                        Theme.Colors.surfaceMuted,
                        in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    )

                if transferText.isEmpty {
                    Text("在此粘贴进度 JSON，或点下面的「导出」后在此查看…")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.md)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: Space.sm) {
                Button {
                    exportProgress()
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    importProgress()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.vertical, Space.xs)
        } header: {
            Text("学习进度迁移")
        } footer: {
            Text("换设备时用：在旧设备点「导出」并复制，再到新设备粘贴后点「导入」。数据与网站结构一致（cet4_90d_v1），网站导出的进度可以直接导入。")
        }
    }

    // MARK: - 危险区

    private var dangerSection: some View {
        Section {
            Button("重置学习进度", role: .destructive) {
                showResetConfirm = true
            }
        } header: {
            Text("危险区")
        } footer: {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("会清空单词进度、已读已听记录、模考成绩与错题本，不可撤销。")
                Text("水伴英语 1.0.0 (1) · iOS 版")
                    .padding(.top, Space.sm)
            }
        }
    }

    // MARK: - 动作

    private func exportProgress() {
        let json = store.exportJSON()
        transferText = json
        UIPasteboard.general.string = json
        notify("已导出", "进度已填进输入框，并复制到剪贴板。")
    }

    private func importProgress() {
        let raw = transferText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            notify("还没有内容", "先把导出的 JSON 粘进上面的输入框。")
            return
        }
        guard store.importJSON(raw) else {
            notify("格式不对", "这不是一份有效的进度 JSON。检查一下是否复制完整（要包含开头和结尾的大括号）。")
            return
        }

        // 导入成功后给一个「看得见的确认」：只说「成功」用户还是会怀疑到底恢复了什么。
        let day = DailyPlan.dayNumber(startDate: store.progress.startDate)
        let words = store.progress.wordProgress.count
        let read = store.progress.readDone.count
        transferText = ""
        notify("导入成功", "已恢复：第 \(day) 天 · 已学 \(words) 词 · 已读 \(read) 篇")
    }

    private func notify(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    // MARK: - 常量

    private static let minutes: [Int] = [15, 30, 60]
    private static let wordOptions: [Int] = [10, 20, 30]

    /// 没设过考试日期时 `DatePicker` 显示的那一天（三个月后）。
    private static var defaultExamDate: Date {
        Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
    }

    /// 与 `Srs` 内部完全相同的格式规则。`Srs` 的 formatter 是 private，
    /// 这里必须自己建一个 —— 但规则（POSIX 区域、公历、本地时区、yyyy-MM-dd）一模一样，
    /// 否则写进去的日期 `Srs.date(_:)` 就解析不出来了。
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
