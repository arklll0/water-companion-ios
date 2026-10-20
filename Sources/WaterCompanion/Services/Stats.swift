import Foundation

// ════════════════════════════════════════════════════════════════════
//  能力分析
// ════════════════════════════════════════════════════════════════════
//
//  和 DailyPlan 一样是**纯函数**：输入作答记录 / 学习状态，输出算好的结果。
//
//  为什么必须是纯的：同一份数据算出来的数每次都一样，否则「刷新一下正确率就变了」
//  这种事一旦发生，用户就再也不敢信这个页面。
//
//  为什么样本量要有下限：「做了 1 题、错了 1 题」= 正确率 0%。直接参与排名的话，
//  它会把「做了 30 题、正确率 55%」挤到后面，于是最弱项变成噪声。
//  所以样本不够的题型**不参与排名**，页面明说还差几题，而不是显示 0%。

enum Stats {

    /// 参与「薄弱项排名」所需的最少样本数。
    /// 定 6 而不是 20：每天只做 1 道题时，20 要等大半个月才看得到结论。
    static let minSamples = 6

    /// 判断「在进步还是在退步」所需的最少作答数：比排名要求更高
    static let minTrend = 20

    // MARK: - 数据结构

    /// 一个题型的统计
    struct KindStat: Identifiable, Hashable {

        let kind: String
        let total: Int
        let correct: Int

        var id: String { kind }

        /// 正确率 0…1。`total == 0` 时为 0，调用方应先判 `enough`
        var acc: Double {
            total == 0 ? 0 : Double(correct) / Double(total)
        }

        /// 百分比整数，直接显示用
        var pct: Int {
            Int((acc * 100).rounded())
        }

        /// 样本够不够参与排名
        var enough: Bool {
            total >= Stats.minSamples
        }
    }

    /// 某一天的作答情况。`total == 0` 表示那天**没做题**，不是「正确率 0%」——
    /// 这个区别很关键：画成 0% 会让人以为自己那天全错。
    struct DayAcc: Identifiable, Hashable {

        let date: String
        let total: Int
        let correct: Int

        var id: String { date }

        var hasData: Bool { total > 0 }

        var acc: Double {
            total == 0 ? 0 : Double(correct) / Double(total)
        }

        var pct: Int {
            Int((acc * 100).rounded())
        }
    }

    // MARK: - 每日正确率

    /// 最近 `days` 天，按日期升序（最老在前、今天在最后）。
    ///
    /// 返回「每天一条」而不是「只返回有数据的那些天」：调用方要按位置画一排柱子，
    /// 没做题的天必须**占位**，否则「中间断了三天」在图上会被压成「只过了一天」。
    static func dailyAcc(
        _ attempts: [Attempt],
        days: Int = 14,
        today: String = Srs.today()
    ) -> [DayAcc] {
        guard days > 0 else { return [] }

        var byDate: [String: (total: Int, correct: Int)] = [:]
        for a in attempts {
            if a.date.isEmpty { continue }
            var slot = byDate[a.date] ?? (total: 0, correct: 0)
            slot.total += 1
            if a.ok { slot.correct += 1 }
            byDate[a.date] = slot
        }

        var out: [DayAcc] = []
        out.reserveCapacity(days)
        for i in 0..<days {
            let d = Srs.addDays(today, -(days - 1 - i))
            let slot = byDate[d]
            out.append(DayAcc(date: d, total: slot?.total ?? 0, correct: slot?.correct ?? 0))
        }
        return out
    }

    // MARK: - 按题型汇总

    /// 按题型汇总，**正确率升序**（最弱在前）。
    ///
    /// 排序第一关键字是「样本够不够」：够的排前面、不够的排后面，
    /// 于是 `weakest` 取第一个就行，也保证页面上不会因为样本不足而错位。
    static func byKind(_ attempts: [Attempt]) -> [KindStat] {
        var order: [String] = []
        var totals: [String: (total: Int, correct: Int)] = [:]

        for a in attempts {
            let trimmed = a.kind.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.isEmpty ? "other" : trimmed
            if totals[key] == nil {
                order.append(key)
                totals[key] = (total: 0, correct: 0)
            }
            var slot = totals[key] ?? (total: 0, correct: 0)
            slot.total += 1
            if a.ok { slot.correct += 1 }
            totals[key] = slot
        }

        let stats: [KindStat] = order.map { key in
            let slot = totals[key] ?? (total: 0, correct: 0)
            return KindStat(kind: key, total: slot.total, correct: slot.correct)
        }

        return stats.sorted { lhs, rhs in
            if lhs.enough != rhs.enough { return lhs.enough }
            if lhs.acc != rhs.acc { return lhs.acc < rhs.acc }
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            return lhs.kind < rhs.kind
        }
    }

    /// 最弱的一项。样本不足以判断时返回 nil —— 调用方必须据此显示「还差 N 题」，
    /// 不要退化成显示 0%。
    static func weakest(_ attempts: [Attempt], minN: Int = minSamples) -> KindStat? {
        byKind(attempts).first { $0.total >= minN }
    }

    /// 还差多少题才够判断薄弱项（按样本最多的那个题型算）
    static func needMore(_ attempts: [Attempt], minN: Int = minSamples) -> Int {
        let maxN = byKind(attempts).map { $0.total }.max() ?? 0
        return max(minN - maxN, 0)
    }

    /// 趋势：按**日期**把全部作答切成前后两半，比较正确率，
    /// 返回「后半 − 前半」的百分点差（正数 = 在进步）。
    ///
    /// 按日期切而不是按条数对半切：用户可能某一天一口气刷了 40 题，
    /// 按条数切比出来的是「那天状态好不好」，不是「这段时间有没有进步」。
    static func trend(_ attempts: [Attempt], minN: Int = minTrend) -> Int? {
        let sorted = attempts
            .filter { !$0.date.isEmpty }
            .sorted { $0.date < $1.date }

        guard sorted.count >= minN,
              let first = sorted.first,
              let last = sorted.last else { return nil }

        let span = Srs.daysBetween(first.date, last.date)
        if span <= 0 { return nil }

        let mid = Srs.addDays(first.date, span / 2)
        let before = sorted.filter { $0.date < mid }
        let after = sorted.filter { $0.date >= mid }
        if before.isEmpty || after.isEmpty { return nil }

        return pctOf(after) - pctOf(before)
    }

    // MARK: - 单词记忆维度

    /// 从 `wordProgress` 的 right / wrong 汇总：返回 (答对数, 总评分次数)。
    static func wordAcc(_ wp: [String: WordProgress]) -> (right: Int, total: Int) {
        var right = 0
        var total = 0
        for e in wp.values {
            right += e.right
            total += e.right + e.wrong
        }
        return (right: right, total: total)
    }

    /// 题型 key → 中文名。key 来自 papers.json 的 item.type 与练习题的 kind。
    static func kindLabel(_ kind: String) -> String {
        let trimmed = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "q": return "语法"
        case "vocab": return "词汇辨析"
        case "cloze": return "选词填空"
        case "match": return "段落匹配"
        case "read": return "阅读理解"
        case "listen": return "听力理解"
        default: return trimmed.isEmpty ? "其他" : trimmed
        }
    }

    // MARK: - 内部

    private static func pctOf(_ list: [Attempt]) -> Int {
        guard !list.isEmpty else { return 0 }
        let ok = list.filter { $0.ok }.count
        return Int((Double(ok) * 100.0 / Double(list.count)).rounded())
    }
}
