import Charts
import Foundation
import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  进度统计
// ════════════════════════════════════════════════════════════════════
//
//  这一页的职责是回答三个问题，顺序就是从上到下的顺序：
//    ① 我总共做了多少？（七个数字）
//    ② 最近有没有在动？（近 14 天热力格 + 正确率柱状图）
//    ③ 我该补哪一块？（各题型正确率 + 单词记忆 + 趋势句）
//
//  ## 页面里不做任何统计计算
//
//  所有数字都来自 `Stats`（纯函数）与 `Srs`（纯函数）。理由很实际：
//  同一份数据算出来的结果必须每次都一样，否则「刷新一下正确率就变了」
//  这种事一旦发生，用户就再也不敢信这一页。计算集中在一处，也才可能被复核。
//
//  ## 柱状图为什么用 Swift Charts
//
//  它是苹果自己的框架（随系统提供，不是第三方依赖），坐标轴、无障碍朗读、
//  深色模式配色都由系统负责。手画 14 根矩形要自己处理「没做题的天」和标注，
//  而这些正是 Chart 已经解决掉的问题。

struct StatsScreen: View {

    @Environment(ProgressStore.self) private var store

    /// 与网站 data/words.js 里的 VOCAB_TOTAL 一致
    private static let vocabTotal = 3000

    // MARK: - 派生状态

    private var progress: Progress { store.progress }
    private var today: String { Srs.today() }

    /// 第几天（没设置开始日期时算第 1 天）
    private var dayCount: Int {
        let start = progress.startDate ?? today
        return max(Srs.daysBetween(start, today) + 1, 1)
    }

    private var learned: Int { progress.wordProgress.count }
    private var mastered: Int { Srs.mastered(progress.wordProgress) }

    private var coverage: Double {
        min(Double(mastered) / Double(StatsScreen.vocabTotal), 1.0)
    }

    /// 最近 14 天，最老的一天在前
    private var daily: [Stats.DayAcc] { Stats.dailyAcc(progress.attempts) }

    private var kinds: [Stats.KindStat] { Stats.byKind(progress.attempts) }

    private var weakest: Stats.KindStat? { Stats.weakest(progress.attempts) }

    private var trend: Int? { Stats.trend(progress.attempts) }

    private var daysWithData: Int { daily.filter { $0.hasData }.count }

    private var hasAttempts: Bool { !progress.attempts.isEmpty }

    // MARK: - 视图

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: Space.section) {
                    overviewSection
                    heatSection
                    coverageSection
                    abilitySection
                    wrongPreviewSection
                }
                .padding(.horizontal, Space.pageEdge)
                .padding(.top, Space.md)
                .padding(.bottom, Space.xxl)
            }
        }
        .navigationTitle("进度统计")
        .navigationBarTitleDisplayMode(.inline)
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 七个数字
    // ════════════════════════════════════════════════════════════════

    private struct Metric: Identifiable {
        let id: String
        let icon: String
        let value: String
        let label: String
    }

    private var metrics: [Metric] {
        [
            Metric(id: "streak", icon: "flame.fill", value: "\(progress.streak)", label: "连续打卡"),
            Metric(id: "days", icon: "calendar", value: "\(dayCount)", label: "坚持天数"),
            Metric(id: "learned", icon: "book.fill", value: "\(learned)", label: "累计学过词"),
            Metric(id: "read", icon: "doc.text.fill", value: "\(progress.readDone.count)", label: "精读篇数"),
            Metric(id: "listen", icon: "headphones", value: "\(progress.listenDone.count)", label: "精听段数"),
            Metric(id: "exam", icon: "timer", value: "\(progress.examHistory.count)", label: "模考次数"),
            Metric(
                id: "family",
                icon: "square.grid.2x2.fill",
                value: "\(Srs.mastered(progress.familyProgress))",
                label: "词族掌握"
            )
        ]
    }

    private var overviewSection: some View {
        VStack(spacing: Space.itemGap) {
            SectionHeader("总进度", subtitle: "从第一天算到现在", trailing: "第 \(dayCount) 天")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.md),
                    GridItem(.flexible(), spacing: Space.md)
                ],
                spacing: Space.md
            ) {
                ForEach(metrics) { metric in
                    metricCard(metric)
                }
            }
        }
    }

    private func metricCard(_ metric: Metric) -> some View {
        AppCard(padding: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Image(systemName: metric.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(height: 18)

                Text(metric.value)
                    .font(Typography.dataSmall)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(metric.label)
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 近 14 天热力格
    // ════════════════════════════════════════════════════════════════

    private struct DayCell: Identifiable {
        let id: String
        let acts: Int
    }

    private var heatCells: [DayCell] {
        var out: [DayCell] = []
        out.reserveCapacity(14)
        for offset in stride(from: 13, through: 0, by: -1) {
            let date = Srs.addDays(today, -offset)
            let log = progress.dayLog(date)
            // 权重与 Android 版一致：读/听各顶 5 个词，模考顶 8 个词。
            // 「做一次模考」的实际耗时远大于背一个词，等权会让热力格永远只反映背单词。
            let acts = log.words + log.read * 5 + log.listen * 5 + log.exam * 8
            out.append(DayCell(id: date, acts: acts))
        }
        return out
    }

    private var heatSection: some View {
        VStack(spacing: Space.itemGap) {
            SectionHeader("近 14 天", subtitle: "颜色越深，那天做得越多")

            AppCard {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: Space.xs) {
                        ForEach(heatCells) { cell in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(heatColor(cell.acts))
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                        }
                    }

                    HStack(spacing: Space.xs) {
                        Text("14 天前")
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer(minLength: 0)
                        Text("今天")
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    HStack(spacing: Space.xs) {
                        Text("少")
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        // 图例直接复用同一套取色函数，避免「图例和格子对不上」
                        ForEach(StatsScreen.heatSamples, id: \.self) { sample in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(heatColor(sample))
                                .frame(width: 12, height: 12)
                        }
                        Text("多")
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer(minLength: 0)
                        Text("词×1 · 读×5 · 听×5 · 考×8")
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.top, Space.xs)
                }
            }
        }
    }

    /// 四档：没做 / 轻 / 中 / 重。最重的一档用语义主色，
    /// 这样深色模式下它会自动提亮 —— 用固定的深墨绿压在深色底上会看不见。
    private func heatColor(_ acts: Int) -> Color {
        if acts <= 0 { return Theme.Colors.surfaceMuted }
        if acts < 10 { return Theme.Brand.t200 }
        if acts < 25 { return Theme.Brand.t400 }
        return Theme.Colors.primary
    }

    /// 图例用的四个代表值：分别落进四档
    private static let heatSamples: [Int] = [1, 10, 25, 40]

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 词汇覆盖率
    // ════════════════════════════════════════════════════════════════

    private var coverageSection: some View {
        VStack(spacing: Space.itemGap) {
            SectionHeader(
                "词汇覆盖率",
                subtitle: "四级核心词 \(StatsScreen.vocabTotal)",
                trailing: String(format: "%.1f%%", coverage * 100)
            )

            AppCard {
                VStack(alignment: .leading, spacing: Space.sm) {
                    ProgressView(value: coverage)
                        .tint(Theme.Colors.primary)

                    HStack(spacing: Space.sm) {
                        StatBox("\(mastered)", "已掌握")
                        StatBox("\(learned)", "已接触")
                        StatBox("\(max(StatsScreen.vocabTotal - learned, 0))", "还没碰")
                    }
                    .padding(.top, Space.xs)

                    Text("「掌握」= 复习到第 3 阶以上。按每天 20 词，90 天大约能覆盖六成核心词。")
                        .appCaption()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 能力分析
    // ════════════════════════════════════════════════════════════════

    private var abilitySection: some View {
        VStack(spacing: Space.itemGap) {
            SectionHeader(
                "能力分析",
                subtitle: "共 \(progress.attempts.count) 次作答",
                trailing: hasAttempts ? "\(daysWithData) 天有记录" : nil
            )

            if hasAttempts {
                accuracyChartCard
                kindCard
                wordCard
            } else {
                ContentUnavailableView(
                    "还没有作答记录",
                    systemImage: "chart.bar",
                    description: Text("去练习页做几道题，从下一题开始就会记账。")
                )
            }
        }
    }

    // MARK: 近 14 天正确率

    private var accuracyChartCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("近 14 天正确率")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)

                // 三处泛型都显式固定，避免 Charts 在推断阶段出岔子：
                // ① 用 `id:` 显式给出元素标识（不依赖 Identifiable 的隐式拾取）；
                // ② y 值统一成 Double（与 ③ 的 domain 同类型）；
                // ③ domain 用 ClosedRange<Double>（ScaleDomain 最常见的具体类型）。
                Chart(daily, id: \.date) { day in
                    // 没做题的那天不画柱子 —— 画成 0% 会让人以为自己那天全错。
                    if day.hasData {
                        BarMark(
                            x: .value("日期", shortDate(day.date)),
                            y: .value("正确率", Double(day.pct))
                        )
                        .foregroundStyle(
                            day.acc >= 0.6 ? Theme.Colors.primary : Theme.Colors.error.opacity(0.75)
                        )
                    }
                }
                .chartYScale(domain: 0.0...100.0)
                // 14 个日期标签在手机宽度上必然叠在一起，
                // 所以关掉横轴文字，用下面那行「首尾日期」交代范围。
                .chartXAxis(.hidden)
                .frame(height: 130)

                HStack {
                    Text(shortDate(daily.first?.date ?? today))
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer(minLength: 0)
                    Text("今天")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Text(trendText)
                    .appCaption()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.xs)
            }
        }
    }

    private var trendText: String {
        guard let trend else {
            return "再多做几道题就能看出趋势（需要 \(Stats.minTrend) 次以上作答）。"
        }
        if trend > 0 { return "后半段比前半段高 \(trend) 个百分点，在进步。" }
        if trend < 0 { return "后半段比前半段低 \(-trend) 个百分点，最近有点松。" }
        return "前后两段持平，稳住了。"
    }

    private func shortDate(_ text: String) -> String {
        let parts = text.split(separator: "-")
        guard parts.count == 3 else { return text }
        return "\(parts[1])/\(parts[2])"
    }

    // MARK: 各题型正确率

    private var kindCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("各题型正确率")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)

                VStack(spacing: Space.md) {
                    ForEach(kinds) { stat in
                        kindRow(stat)
                    }
                }

                Text(weakestText)
                    .appBody()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func kindRow(_ stat: Stats.KindStat) -> some View {
        VStack(spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                Text(Stats.kindLabel(stat.kind))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let weakest, weakest.id == stat.id {
                    Text("最弱")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.onPrimary)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.error, in: Capsule())
                }

                Spacer(minLength: 0)

                Text(
                    stat.enough
                        ? "\(stat.pct)%　\(stat.correct)/\(stat.total)"
                        : "样本 \(stat.total) / \(Stats.minSamples)"
                )
                .font(Typography.micro)
                .monospacedDigit()
                .foregroundStyle(stat.enough ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            }

            // 样本不够时，这条画的是「还差多少」，不是正确率 ——
            // 否则「做了 1 题错 1 题」会被画成一根 0% 的空槽，看着像灾难。
            ProgressView(value: barValue(stat))
                .tint(stat.enough ? Theme.Colors.primary : Theme.Colors.idle)
        }
    }

    private func barValue(_ stat: Stats.KindStat) -> Double {
        if stat.enough { return min(max(stat.acc, 0), 1) }
        return min(Double(stat.total) / Double(Stats.minSamples), 1)
    }

    private var weakestText: String {
        if let weakest {
            return "最弱的是「\(Stats.kindLabel(weakest.kind))」：正确率 \(weakest.pct)%"
                + "（\(weakest.correct)/\(weakest.total)），建议优先补这一块。"
        }
        return "每个题型做到 \(Stats.minSamples) 题才参与排名，现在还差 \(Stats.needMore(progress.attempts)) 题。"
    }

    // MARK: 单词记忆

    private var wordCard: some View {
        let acc = Stats.wordAcc(progress.wordProgress)

        return AppCard {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("单词记忆")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if acc.total == 0 {
                    Text("还没有评过分。背单词时点「认识 / 很熟」就会记进来。")
                        .appCaption()
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text("\(acc.right * 100 / acc.total)%")
                            .font(Typography.dataSmall)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.primary)
                        Text("评了 \(acc.total) 次，认对 \(acc.right) 次")
                            .appCaption()
                        Spacer(minLength: 0)
                    }

                    ProgressView(value: Double(acc.right) / Double(acc.total))
                        .tint(Theme.Colors.primary)
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 错题本预览
    // ════════════════════════════════════════════════════════════════

    private var wrongPreview: [WrongItem] {
        Array(progress.wrongBook.prefix(10))
    }

    private var wrongPreviewSection: some View {
        VStack(spacing: Space.itemGap) {
            SectionHeader("错题本", subtitle: "最近记下的十道", trailing: "\(progress.wrongBook.count) 题")

            if progress.wrongBook.isEmpty {
                ContentUnavailableView(
                    "还没有错题",
                    systemImage: "checkmark.circle",
                    description: Text("做题时错的会自动记在这里。")
                )
            } else {
                VStack(spacing: Space.sm) {
                    ForEach(wrongPreview.indices, id: \.self) { index in
                        wrongPreviewRow(wrongPreview[index])
                    }
                }

                NavigationLink(value: AppRoute.wrong) {
                    HStack(spacing: Space.xs) {
                        Text("查看全部 \(progress.wrongBook.count) 题")
                            .font(Typography.captionEmph)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Touch.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func wrongPreviewRow(_ item: WrongItem) -> some View {
        AppCard(padding: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(prefix(item.q, 70))
                    .font(Typography.captionEmph)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.xs) {
                    Text(item.from.isEmpty ? "练习" : item.from)
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)

                    if item.type == "read" || item.type == "paper" || item.type == "exam" {
                        Text("你选了 \(Self.letter(item.chosen))，正确 \(Self.letter(item.right))")
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 截断到 `limit` 个字符，超出的用省略号带过 ——
    /// 不做「按词截断」：中英混排时按词截反而会截出半个句子。
    private func prefix(_ text: String, _ limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "…"
    }

    /// 0 → "A"。选 -1 表示没作答。
    static func letter(_ index: Int) -> String {
        if index < 0 { return "未作答" }
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        guard index < letters.count else { return "\(index + 1)" }
        return letters[index]
    }
}
