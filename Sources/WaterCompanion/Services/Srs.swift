import Foundation

// ════════════════════════════════════════════════════════════════════
//  间隔重复（简化 SM-2）
// ════════════════════════════════════════════════════════════════════
//
//  评分档位与网站一致：1=忘了 2=模糊 3=认识 4=很熟
//  间隔表与网站 js/srs.js 的 SRS_INTERVALS 完全一致 —— 两端共用同一套表，
//  用户在网站上的复习节奏和 App 里的才不会漂移。
//
//  「忘了」不是「降一阶」，而是**回到第 0 阶、今天还要再见一次**：
//  一个词记不住时，隔 3 天再看多半还是记不住；当天再见一次才有意义。

enum Srs {

    /// 评分 → 各阶段间隔（天）。索引就是 stage。
    static let intervals: [Int: [Int]] = [
        1: [0, 1, 1, 2, 3, 5],
        2: [1, 2, 3, 7, 14, 30],
        3: [3, 7, 15, 30, 60, 120],
        4: [7, 20, 45, 90, 180, 365]
    ]

    /// stage 上限（等于间隔表长度 - 1）
    static let maxStage = 5

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - 日期

    /// 今天（yyyy-MM-dd，本地时区）
    static func today() -> String {
        formatter.string(from: Date())
    }

    /// 把 yyyy-MM-dd 解析成 Date（当天 00:00）。解析失败返回 nil。
    static func date(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return formatter.date(from: trimmed)
    }

    /// 日期字符串加减天数。输入非法时原样返回 —— 调用方不需要处理异常。
    static func addDays(_ text: String, _ days: Int) -> String {
        guard let d = date(text) else { return text }
        let next = Calendar.current.date(byAdding: .day, value: days, to: d) ?? d
        return formatter.string(from: next)
    }

    /// b - a 的天数。任一日期非法时返回 0（与 Android 的 runCatching 默认值一致）。
    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = date(a), let db = date(b) else { return 0 }
        let comps = Calendar.current.dateComponents([.day], from: da, to: db)
        return comps.day ?? 0
    }

    // MARK: - 单词

    /// 到期需要复习的词。
    ///
    /// 排序：`due` 升序（越早到期越靠前），同一天按字母序。
    /// Android 侧靠 Map 的插入序，Swift 的 Dictionary 没有稳定顺序，
    /// 所以这里显式排序 —— 否则同一份存档每次打开看到的复习顺序都不一样。
    static func dueWords(_ p: [String: WordProgress], today: String = Srs.today()) -> [String] {
        let dueKeys = p.filter { $0.value.due.isEmpty || $0.value.due <= today }.keys
        return dueKeys.sorted { lhs, rhs in
            let ld = p[lhs]?.due ?? ""
            let rd = p[rhs]?.due ?? ""
            if ld == rd { return lhs < rhs }
            return ld < rd
        }
    }

    /// 已掌握（stage >= 3）数量
    static func mastered(_ p: [String: WordProgress]) -> Int {
        p.values.filter { $0.stage >= 3 }.count
    }

    /// 评一次分，返回新的学习状态。
    static func rate(_ entry: WordProgress, _ rating: Int) -> WordProgress {
        let table = intervals[rating] ?? intervals[2] ?? [1, 2, 3, 7, 14, 30]
        let todayText = today()

        if rating == 1 {
            // 忘了：回到第 0 阶，今天还要再见一次
            var next = entry
            next.stage = 0
            next.due = todayText
            next.seen += 1
            next.wrong += 1
            return next
        }

        let stage = min(entry.stage + 1, table.count - 1)
        let gap = max(table[stage], 1)
        var next = entry
        next.stage = stage
        next.due = addDays(todayText, gap)
        next.seen += 1
        next.right += 1
        return next
    }

    // MARK: - 词族（锚词辐射）
    //
    //  key = "族序号:单词"，复用同一套间隔表。

    /// 词族成员的 SRS key
    static func familyKey(_ familyIndex: Int, _ word: String) -> String {
        "\(familyIndex):\(word)"
    }

    /// 到期的词族成员
    static func dueFamilies(
        _ p: [String: WordProgress],
        today: String = Srs.today()
    ) -> [String] {
        let dueKeys = p.filter { $0.value.due.isEmpty || $0.value.due <= today }.keys
        return dueKeys.sorted()
    }

    /// 词族成员的评分与单词同一套规则
    static func rateFamily(_ entry: WordProgress, _ rating: Int) -> WordProgress {
        rate(entry, rating)
    }
}
