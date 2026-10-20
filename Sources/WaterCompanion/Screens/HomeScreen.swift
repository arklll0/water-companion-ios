import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  今日页
// ════════════════════════════════════════════════════════════════════
//
//  信息层级是两级的：
//  1. **一个主进度** —— 圆环。它是页面上唯一的大数字。
//  2. 两个次要指标压成一行小字（第 N/90 天 · 2/4 已完成），归到一处。
//
//  上一版把「天数 / 百分比 / 已完成数」平铺在 Hero 里，还配了一条线性进度条 ——
//  四个东西说的其实是同一件事，眼睛不知道先看哪个，读完还是不知道「我现在该干嘛」。
//
//  下面是倒计时横幅（浅色底、无边框，视觉重量低于任务卡），再下面是任务列表。
//  「今天该做什么」必须比「还有多少天」重 —— 后者只是背景信息。

// MARK: - 数据

private struct HomeTask: Identifiable {

    let id: String
    let name: String
    let detail: String
    let icon: String
    /// 点「开始」后要去哪个页签（与 Android 版 TASKS 的 go 字段同构）
    let target: String

    /// 与网站 js/app.js 的 TASKS 一致
    /// （「记 10 个易错点」指向错题本，与它的说明文字相符）。
    /// 图标全部用 SF Symbols，且用 `.fill` 变体 —— 任务卡是实心内容面，
    /// 线性图标压上去会显得飘。
    static let all: [HomeTask] = [
        HomeTask(id: "words", name: "背单词", detail: "2 分钟起，背完就能打卡", icon: "book.fill", target: "words"),
        HomeTask(id: "listen", name: "听力精听", detail: "1 段，约 5 分钟", icon: "headphones", target: "listen"),
        HomeTask(id: "read", name: "做一篇阅读", detail: "约 5 分钟", icon: "doc.text.fill", target: "practice"),
        HomeTask(id: "exam", name: "记 10 个易错点", detail: "看错题本，约 3 分钟", icon: "exclamationmark.triangle.fill", target: "wrong")
    ]
}

// MARK: - 首页

struct HomeScreen: View {

    @Environment(ProgressStore.self) private var store
    let onNavigate: (String) -> Void

    /// 底部激励语。不喊口号、不制造焦虑、承认「不想学」是正常的。
    private static let quotes: [String] = [
        "不要想着「学英语」，只想「完成下一个 2 分钟」。",
        "今天不用学完所有东西，只要比昨天多记住一个词。",
        "状态不好也没关系，先翻开一页，剩下的交给惯性。",
        "你不是在背单词，你是在给三个月后的自己攒底气。",
        "专注力不强不是缺点 —— 把任务拆小才是解法。",
        "连续做小事的人，最后会赢过一直在等状态的人。"
    ]

    @State private var quoteIndex = 0

    // MARK: 派生状态

    private var progress: Progress { store.progress }
    private var today: String { Srs.today() }
    private var log: DayLog { progress.dayLog(today) }
    private var dayNumber: Int { DailyPlan.dayNumber(startDate: progress.startDate) }

    /// 今天被推迟的任务（value == today 才算「今天不出现」；
    /// 到了明天这个条件自然不成立，任务自己就回来了）
    private var postponedIds: Set<String> { store.postponedTodayIds }

    private var tasks: [HomeTask] {
        HomeTask.all.filter { !postponedIds.contains($0.id) }
    }

    private var postponedNames: [String] {
        HomeTask.all.filter { postponedIds.contains($0.id) }.map { $0.name }
    }

    private var doneCount: Int {
        tasks.filter { isDone($0.id) }.count
    }

    private var percent: Double {
        tasks.isEmpty ? 0 : Double(doneCount) / Double(tasks.count)
    }

    private var heroTitle: String {
        if tasks.isEmpty { return "今天没有待办" }
        if doneCount == 0 { return "今天只需要 \(progress.dailyMinutes) 分钟" }
        if doneCount < tasks.count { return "已经开始了，很好" }
        return "今天的任务完成了"
    }

    private var heroSubtitle: String {
        if tasks.isEmpty { return "都被你推到明天了，也行，明天记得先做它们" }
        if doneCount == 0 { return "从最简单的那个开始，别想太多" }
        if doneCount < tasks.count { return "还剩 \(tasks.count - doneCount) 个，很快就能收工" }
        return "剩下的时间是你自己的了"
    }

    var body: some View {
        ZStack {
            AppBackground()

            FormPage {
                hero
                countdown

                VStack(spacing: Space.itemGap) {
                    SectionHeader("今天的任务", subtitle: "点一下就能开始")
                    ForEach(tasks) { task in
                        taskRow(task)
                    }
                    if !postponedNames.isEmpty {
                        postponedRow
                    }
                    if !tasks.isEmpty && doneCount == tasks.count {
                        completionBanner
                    }
                }

                Divider()
                quoteBlock
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: doneCount) { oldValue, newValue in
            // 每多完成一个任务就换一条激励语：同一句话看到第十遍就变成背景噪音，
            // 而「每完成一步换一句」是一个很小的、只属于这一秒的奖励。
            if newValue > oldValue {
                quoteIndex = (quoteIndex + 1) % HomeScreen.quotes.count
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        AppCard(padding: Space.cardPadding) {
            HStack(spacing: Space.md) {
                RingProgress(value: percent, size: 96, lineWidth: 9)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(heroTitle)
                        .font(Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(heroSubtitle)
                        .appCaption()
                        .fixedSize(horizontal: false, vertical: true)

                    Text("第 \(dayNumber)/90 天 · \(doneCount)/\(tasks.count) 已完成")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 倒计时

    private var countdown: some View {
        AppCard(
            padding: Space.cardPadding,
            background: Theme.Colors.banner,
            showsBorder: false
        ) {
            HStack(alignment: .center, spacing: Space.md) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: Space.xs) {
                    countdownText
                }

                Spacer(minLength: Space.xs)

                QuietButton(countdownActionTitle) {
                    onNavigate("me")
                }
            }
        }
    }

    @ViewBuilder
    private var countdownText: some View {
        if let left = daysLeft {
            if left < 0 {
                Text("考试日期已过")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("换成下一次考试的日期，倒计时会重新开始")
                    .appCaption()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text("距离四级还有")
                        .appCaption()
                    Text("\(left)")
                        .font(Typography.dataLarge)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.primary)
                    Text("天")
                        .appCaption()
                }
                Text("每天 \(progress.dailyWords) 个词\n\(left) 天正好过一遍高频词")
                    .appCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("还没设置考试日期")
                .font(Typography.titleSmall)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("设完之后这里会显示还有多少天")
                .appCaption()
        }
    }

    /// 距离考试还有几天。nil = 没设置；负数 = 已经过了。
    private var daysLeft: Int? {
        guard let raw = progress.examDate else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard Srs.date(trimmed) != nil else { return nil }
        return Srs.daysBetween(today, trimmed)
    }

    private var countdownActionTitle: String {
        guard let left = daysLeft else { return "去设置" }
        return left < 0 ? "去设置" : "改"
    }

    // MARK: - 任务卡

    @ViewBuilder
    private func taskRow(_ task: HomeTask) -> some View {
        if isDone(task.id) {
            // 已完成的不给推迟手势：能推的只有「还没做的事」
            cardBody(task, done: true)
        } else {
            Button {
                onNavigate(task.target)
            } label: {
                cardBody(task, done: false)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    store.postponeTask(id: task.id, to: Srs.addDays(today, 1))
                } label: {
                    Label("推迟到明天", systemImage: "calendar")
                }
            }
        }
    }

    private func cardBody(_ task: HomeTask, done: Bool) -> some View {
        AppCard(
            padding: Space.lg,
            background: done ? Theme.Colors.doneCard : Theme.Colors.surface,
            showsBorder: !done
        ) {
            HStack(alignment: .center, spacing: Space.md) {
                stateBadge(done: done)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.name)
                        .font(Typography.titleSmall)
                        .foregroundStyle(done ? Theme.Colors.doneText : Theme.Colors.textPrimary)
                    Text(task.detail)
                        .font(Typography.micro)
                        .foregroundStyle(
                            done
                                ? Theme.Colors.doneText.opacity(0.75)
                                : Theme.Colors.textSecondary
                        )
                }

                Spacer(minLength: Space.xs)

                if done {
                    Text("已完成")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.doneText)
                } else {
                    Text("开始")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.onPrimary)
                        .padding(.horizontal, Space.md)
                        .frame(height: 32)
                        .background(Theme.Colors.primary, in: Capsule())
                }
            }
            .frame(minHeight: Touch.min)
            .contentShape(Rectangle())
        }
    }

    /// 状态徽标：直接用系统符号。
    /// 完成 = `checkmark.circle.fill`，未完成 = `circle` —— 两者字宽相同，
    /// 所以上下几张卡的文字左边缘永远对齐（换成两个尺寸不同的图标就会错位）。
    private func stateBadge(done: Bool) -> some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(done ? Theme.Colors.primary : Theme.Colors.idle)
            .symbolEffect(.bounce, value: done)
            .frame(width: 30, height: 30)
    }

    // MARK: - 推迟提示 / 完成横幅 / 激励语

    private var postponedRow: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            Text("已推迟到明天：\(postponedNames.joined(separator: "、"))")
                .appCaption()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.xs)
            QuietButton("撤销", icon: "arrow.counterclockwise") {
                store.resumePostponedToday()
            }
        }
        .padding(.horizontal, Space.xs)
    }

    private var completionBanner: some View {
        AppCard(background: Theme.Colors.doneCard, showsBorder: false) {
            HStack(alignment: .center, spacing: Space.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Theme.Colors.primary)
                    .symbolEffect(.bounce, value: doneCount)
                VStack(alignment: .leading, spacing: 2) {
                    Text("今天完成了")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Theme.Colors.doneText)
                    Text("你刚刚做到了很多人坚持不到的事。明天见。")
                        .appCaption(Theme.Colors.doneText.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var quoteBlock: some View {
        HStack(alignment: .top, spacing: Space.md) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Theme.Colors.primary)
                .frame(width: 3)
            Text(HomeScreen.quotes[quoteIndex])
                .appCaption()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .animation(.smooth, value: quoteIndex)
    }

    // MARK: - 完成判定

    /// 完成判定与 Android 版逐字一致 —— 两边对「今天算不算做完」的答案必须相同，
    /// 否则用户换了设备会看到进度倒退。
    private func isDone(_ id: String) -> Bool {
        switch id {
        case "words":
            return log.words > 0
        case "listen":
            return log.listen > 0
        case "read":
            return log.read > 0
        case "exam":
            return log.exam > 0 || progress.wrongBook.count >= 10
        default:
            return false
        }
    }
}
