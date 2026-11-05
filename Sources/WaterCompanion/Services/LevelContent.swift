import Foundation

// ════════════════════════════════════════════════════════════════════
//  分级过滤
// ════════════════════════════════════════════════════════════════════
//
//  分级会同时影响四个池子（单词 / 听力 / 阅读 / 真题），每个池子的过滤方式还不一样：
//  单词、听力、词组返回新列表；阅读和真题返回**原始下标**。
//
//  为什么阅读和真题只能返回下标：存档里存的就是下标（`readDone` 存阅读下标、
//  `paperDone` 存 "卷序号-题序号"）。一旦把数组本身裁掉，下标全部错位，
//  老用户的「已读」会漂到别的文章上，而这种错不会报错，只会让人觉得进度乱了。
//
//  规则集中在这一个文件，是为了不让「某一处忘了过滤」这种错误散落到各个页面。
//  那种错误的表现是「选了六级还能看到四级题」，用户不会当故障报，只会以为分级没生效。
//
//  全部是纯函数，不读写任何状态：同一组入参永远得到同一组出参，方便单独验证。

enum LevelContent {

    /// 单词池。
    ///
    /// 成考单独一条路：成考大纲 2890 词里 2837 个本来就在词库中，差别是**池子范围和顺序**
    /// （大纲表不含四六级那批超纲词，且按大纲顺序排）。靠 lv 标签做不到「精确到这两千多个词、
    /// 按这个顺序」，只能按白名单重建：`ck_words.json` 存顺序 + 53 条词库里没有的补充词。
    ///
    /// 白名单为空时**必须**退回按标签过滤。文件缺了或解析失败会让整个单词页变成
    /// 「今天没有要背的词」，那是所有故障里最难查的一种。
    static func words(_ all: [Word], ck: CkWordList, level: CetLevel) -> [Word] {
        guard level == .ck, !ck.isEmpty else {
            return all.filter { level.accepts($0.lv) }
        }

        // 词库里大小写不统一（China / china），wordProgress 也是按小写记的，索引统一小写。
        var byKey: [String: Word] = [:]
        byKey.reserveCapacity(all.count)
        for w in all {
            let key = w.w.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty {
                byKey[key] = w
            }
        }

        var picked: [Word] = []
        picked.reserveCapacity(ck.order.count + ck.extra.count)
        for spelling in ck.order {
            let key = spelling.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let hit = byKey[key] {
                picked.append(hit)
            }
        }
        return picked + ck.extra
    }

    /// 听力素材池。按内容标签过滤，不动 `stableId`：
    /// 那个 id 要和存档里的 `listenDone` 以及 Android 端逐字对齐。
    static func listening(_ all: [ListenItem], level: CetLevel) -> [ListenItem] {
        all.filter { level.accepts($0.lv) }
    }

    /// 阅读的课程顺序，返回**原始下标**。
    ///
    /// 过滤之后还要按 easy < medium < hard 重排：reading.json 是「老素材在前、新素材往后追加」
    /// 长出来的，老的前 6 篇难度是混着排的，直接按数组顺序切片会出现「第 6 天做 hard、
    /// 第 7 天退回 easy」的锯齿。同档内保持原下标升序，保证顺序稳定可复现。
    static func readingOrder(_ all: [Reading], level: CetLevel) -> [Int] {
        let rank: [String: Int] = ["easy": 0, "medium": 1, "hard": 2]
        return all.indices
            .filter { level.accepts(all[$0].lv) }
            .sorted { lhs, rhs in
                let l = rank[all[lhs].level] ?? 1
                let r = rank[all[rhs].level] ?? 1
                if l != r { return l < r }
                return lhs < rhs
            }
    }

    /// 真题可见卷的**原始下标**。
    ///
    /// 成考单独判：`accepts` 对成考收 cet4 是为了「还没有成考卷时不至于空着」，
    /// 但成考卷已经接进来了（下标 16-18），再把 9 套四级卷列出来只会把成考卷埋掉。
    /// 万一 ck_papers.json 丢了，ckOnly 为空，才退回按标签过滤。
    static func paperIndices(_ all: [Paper], level: CetLevel) -> [Int] {
        if level == .ck {
            let ckOnly = all.indices.filter { i in
                all[i].lv
                    .lowercased()
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .contains("ck")
            }
            if !ckOnly.isEmpty {
                return ckOnly
            }
        }
        return all.indices.filter { level.accepts(all[i].lv) }
    }

    /// 常考翻译词组。目前全部标 both，过滤只是让接口与其余几个池子保持一致。
    static func phrases(_ all: [Phrase], level: CetLevel) -> [Phrase] {
        all.filter { level.accepts($0.lv) }
    }
}
