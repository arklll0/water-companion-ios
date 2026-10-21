import SwiftUI
import UIKit

// ════════════════════════════════════════════════════════════════════
//  我的
// ════════════════════════════════════════════════════════════════════
//
//  这一页只做两件事：**去别处**（统计 / 错题 / 翻译）和**改设置**。
//
//  ## 为什么不用系统的 `List`
//
//  之前用的是 `List` + `.insetGrouped`。它在真机上出了两个问题：
//    ① 行内容（日期控件、分段控件）比行宽还宽，右边缘被裁在屏幕外
//       —— 分组列表的行内边距由系统算，行里再塞自定义宽度就很容易顶出去；
//    ② 整页观感与其它页（今日 / 单词 / 听力 / 练习）不一致：
//       那几页都是 `AppCard` 卡片 + 16pt 页面边距。
//
//  所以这一页改成和全 App 同一套：`ScrollView` + `AppCard` +
//  `SectionHeader`，左右边距一律 `Space.pageEdge`，宽度完全由我们自己管，
//  不会再出现「贴到屏幕右边」这种问题。
//
//  ## 为什么全部即时保存
//
//  没有「保存」按钮：iOS 的设置页从来不这么干。改了就落盘（每个 setter 内部
//  都会立刻写 `progress.json`），退出重进还是这个值 —— 用户不需要记得「我改过没保存」。
//  唯一需要二次确认的是**重置**，因为那是不可撤销的。

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

            ScrollView {
                VStack(spacing: Space.section) {
                    featureSection
                    appearanceSection
                    studySection
                    transferSection
                    dangerSection
                }
                .padding(.horizontal, Space.pageEdge)
                .padding(.top, Space.md)
                .padding(.bottom, Space.xxl)
            }
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

    // MARK: - 功能入口

    private var featureSection: some View {
        VStack(alignment: .leading, spacing: Space.itemGap) {
            SectionHeader("全部功能", subtitle: "统计 / 错题 / 翻译")

            AppCard(padding: Space.sm) {
                VStack(spacing: 0) {
                    routeRow("进度统计", icon: "chart.bar.xaxis", tint: Theme.Colors.primary, route: .stats)
                    rowDivider
                    routeRow("错题集", icon: "exclamationmark.triangle.fill", tint: Theme.Colors.error, route: .wrong)
                    rowDivider
                    routeRow("翻译工具", icon: "character.bubble.fill", tint: Theme.Colors.primary, route: .translate)
                }
            }

            Text("统计看的是「这一段有没有进步」，不是分数排行。")
                .appCaption()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.xs)
        }
    }

    /// 一行入口：图标 + 标题 + 右侧箭头。整行可点，热区撑满。
    private func routeRow(_ title: String, icon: String, tint: Color, route: AppRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, alignment: .leading)

                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.idle)
            }
            .padding(.horizontal, Space.md)
            .frame(minHeight: Touch.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, Space.xxl)
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Space.itemGap) {
            SectionHeader("外观", subtitle: "跟系统还是自己定")

            AppCard {
                VStack(alignment: .leading, spacing: Space.sm) {
                    fieldLabel("主题")

                    Picker("主题", selection: themeBinding) {
                        ForEach(Theme.Mode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(themeFooter)
                        .appCaption()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.xs)
                }
            }
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
        VStack(alignment: .leading, spacing: Space.itemGap) {
            SectionHeader("学习设置", subtitle: "改一处，全 App 生效")

            AppCard {
                VStack(alignment: .leading, spacing: Space.lg) {
                    // 日期单独一行：标签在上一行、控件占满整行，
                    // 不再让「考试日期」四个字和日期胶囊挤在同一行里抢宽度。
                    VStack(alignment: .leading, spacing: Space.sm) {
                        fieldLabel("考试日期")

                        HStack(spacing: Space.sm) {
                            DatePicker(
                                "考试日期",
                                selection: examDateBinding,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "zh_CN"))

                            Spacer(minLength: 0)

                            if progress.examDate != nil {
                                Button {
                                    store.setExamDate(nil)
                                } label: {
                                    Text("清除")
                                        .font(Typography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .padding(.horizontal, Space.sm)
                                        .frame(height: Touch.min)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.sm) {
                        fieldLabel("每天学多久")

                        Picker("每天学多久", selection: minutesBinding) {
                            Text("15 分钟").tag(15)
                            Text("30 分钟").tag(30)
                            Text("60 分钟").tag(60)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: Space.sm) {
                        fieldLabel("每天背多少词")

                        Picker("每天背多少词", selection: wordsBinding) {
                            Text("10 词").tag(10)
                            Text("20 词").tag(20)
                            Text("30 词").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // 一行同时说清两件事：离考试还有多久、词量会连带改什么。
                    Text("\(examFooter)\n每天的单词量也会决定听力和阅读的份量，改一处即可。")
                        .appCaption()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var examFooter: String {
        guard let raw = progress.examDate, Srs.date(raw) != nil else {
            return "还没设置考试日期 —— 上面显示的是默认的 90 天后，点开选一个日期就会保存。"
        }
        let left = Srs.daysBetween(Srs.today(), raw)
        if left < 0 { return "考试日期已经过了，改一个未来的日期吧。" }
        if left == 0 { return "就是今天。把会的写出来就够了。" }
        return "距离考试还有 \(left) 天。"
    }

    // MARK: - 进度迁移

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: Space.itemGap) {
            SectionHeader("学习进度迁移", subtitle: "换设备时用")

            AppCard {
                VStack(alignment: .leading, spacing: Space.md) {
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
                        SecondaryButton("导出", icon: "square.and.arrow.up") {
                            exportProgress()
                        }
                        PrimaryButton("导入", icon: "square.and.arrow.down") {
                            importProgress()
                        }
                    }

                    Text("在旧设备点「导出」并复制，再到新设备粘贴后点「导入」。数据与网站结构一致（cet4_90d_v1），网站导出的进度可以直接导入。")
                        .appCaption()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 危险区

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: Space.itemGap) {
            SectionHeader("危险区", subtitle: "不可撤销")

            Button {
                showResetConfirm = true
            } label: {
                Text("重置学习进度")
                    .font(Typography.captionEmph)
                    .foregroundStyle(Theme.Colors.error)
                    .frame(maxWidth: .infinity)
                    .frame(height: Touch.min)
                    .background(Theme.Colors.error.opacity(0.12), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Text("会清空单词进度、已读已听记录、模考成绩与错题本。")
                .appCaption()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.xs)

            Text(appVersionText)
                .font(Typography.micro)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Space.sm)
        }
    }

    // MARK: - 小工具

    /// 版本号直接从 bundle 读 —— 手写在这里迟早会和 project.yml 走岔。
    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "水伴英语 \(version) (\(build)) · iOS 版"
    }

    /// 字段名。比正文小一档、比说明深一点，用来给下面那排控件当标题。
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
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