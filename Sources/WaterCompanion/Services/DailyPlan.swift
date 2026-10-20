import Foundation

// ════════════════════════════════════════════════════════════════════
//  每日调度
// ════════════════════════════════════════════════════════════════════
//
//  纯函数：只依赖「第几天」和「每天多少条」两个输入，输出「今天的这一份」。
//  - 不读也不写任何状态 ⇒ 同一天里多次打开结果必然一致（不会刷几次就换了内容）；
//  - 不依赖历史 ⇒ 中间断了三天再回来，看到的仍然是「第 N 天」该看的那一份。
//
//  素材只追加、不重排：切片按下标取，而 readDone / listenDone 里存的就是下标
//  或下标派生的 key。新素材只能往数组末尾追加，否则老进度会错位，
//  变成「明明没读过却显示已读」。

enum DailyPlan {

    /// 计划总天数。素材量按这个数字准备（听力 90×6、阅读 90、练习 90）。
    static let totalDays = 90

    /// 今天是第几天（0 起）。没设置开始日期时返回 0 —— 新装 App 第一屏就该是第 1 天。
    static func dayIndex(startDate: String?, today: String = Srs.today()) -> Int {
        guard let raw = startDate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return 0 }
        let diff = Srs.daysBetween(raw, today)
        let safe = max(diff, 0)
        return safe % totalDays
    }

    /// 人类可读的「第 N 天」（1 起，超过 90 天按回绕后的天数算）
    static func dayNumber(startDate: String?, today: String = Srs.today()) -> Int {
        dayIndex(startDate: startDate, today: today) + 1
    }

    // MARK: - 每日条数：与单词量绑定
    //
    //  比例来自「20 个词 / 天」这套默认设置下的期望值：
    //  20 词 → 6 句听力 + 1 篇阅读 + 1 道练习。
    //  单词量调大只是等比放大，不会出现「背了 60 个词却只听 4 句」的失衡。

    /// 听力句数：单词量的 0.3 倍，下限 4 句。20 → 6；10 → 4；40 → 12。
    static func listenCount(_ dailyWords: Int) -> Int {
        let words = max(dailyWords, 1)
        return max(4, Int(ceil(Double(words) * 0.3)))
    }

    /// 阅读篇数：每 20 个词 1 篇，下限 1 篇。20 → 1；40 → 2。
    static func readCount(_ dailyWords: Int) -> Int {
        let words = max(dailyWords, 1)
        return max(1, Int(ceil(Double(words) / 20.0)))
    }

    /// 练习题数：与阅读同比例，下限 1 题。
    static func paperCount(_ dailyWords: Int) -> Int {
        let words = max(dailyWords, 1)
        return max(1, Int(ceil(Double(words) / 20.0)))
    }

    /// 从静态素材池里取出第 `dayIndex` 天的那 `count` 条。
    ///
    /// 用**连续切片**而不是按步长跳着取：素材池本身按难度递增排好，
    /// 连续取才能保证「天数往前走、难度往上涨」。跳着取会把三种难度混在一天里。
    static func slice<T>(_ pool: [T], _ dayIndex: Int, _ count: Int) -> [T] {
        if pool.isEmpty || count <= 0 { return [] }
        let size = pool.count
        let n = min(count, size)
        var out: [T] = []
        out.reserveCapacity(n)
        for j in 0..<n {
            let raw = (dayIndex * count + j) % size
            let i = raw < 0 ? raw + size : raw
            out.append(pool[i])
        }
        return out
    }

    /// 今天这几条里已经完成了几条。判据由调用方给（不同模块的「完成」含义不同）。
    static func doneCount<T>(_ items: [T], isDone: (T) -> Bool) -> Int {
        items.filter(isDone).count
    }

    /// 「3 / 6 已完成」那种进度文案
    static func progressText<T>(_ items: [T], isDone: (T) -> Bool) -> String {
        "\(doneCount(items, isDone: isDone)) / \(items.count) 已完成"
    }
}
