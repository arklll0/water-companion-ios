import Foundation
import Observation

// ════════════════════════════════════════════════════════════════════
//  内容数据加载
// ════════════════════════════════════════════════════════════════════
//
//  6 个 JSON 随 App 打包，启动时一次性读进内存（合计约 500 KB）。
//  为什么不用「用到再读」：每个页面都要按名字查词（`word("abandon")`），
//  懒加载会把「一次 O(1) 的数组查找」变成「读文件 + 解析 + 查找」，
//  在翻卡这种高频路径上是灾难。
//
//  路径查找做了两条兜底：XcodeGen 的 group 型资源会被**拍平**到 bundle 根目录，
//  而 folder reference 会保留子目录。两种打包方式都要能读出来 ——
//  这类「源码没问题、只是路径不对」的故障在 CI 上最难查，所以干脆都试一遍。

@MainActor
@Observable
final class ContentStore {

    var words: [Word] = []
    var families: [Family] = []
    var phrases: [Phrase] = []
    var readings: [Reading] = []
    var papers: [Paper] = []
    var transPractices: [TransPractice] = []

    var listeningBasic: [ListenItem] = []
    var listeningDialog: [ListenItem] = []
    var listeningPassage: [ListenItem] = []

    /// 加载失败的项（正常为空）。界面不因此崩溃，只是列表为空。
    var loadIssues: [String] = []

    /// 只建一次索引：单词原文 → 数据
    private var wordIndex: [String: Word] = [:]

    // MARK: - 生命周期

    init() {
        loadAll()
    }

    // MARK: - 派生数据

    /// 听力素材的合并池（basic → dialog → passage，按难度顺序拍平）。
    /// 每日调度跨档推进难度，所以页面只认这一个池子。
    var allListening: [ListenItem] {
        listeningBasic + listeningDialog + listeningPassage
    }

    /// 按原文取词
    func word(_ text: String) -> Word? {
        wordIndex[text]
    }

    /// 按原文取词，取不到时返回一个只有词形的占位（保证卡片永远有东西可画）
    func wordOrPlaceholder(_ text: String) -> Word {
        wordIndex[text] ?? Word(w: text)
    }

    /// 已学过的词里有多少条（wordProgress 的 key 可能包含词族成员，
    /// 所以这里按「能在词库里找到的」算）
    func isKnownWord(_ text: String) -> Bool {
        wordIndex[text] != nil
    }

    /// 真题拍平成「按题排列的流」（顺序 = 卷子顺序 × 卷内题序）
    var paperItemRefs: [PaperItemRef] {
        papers.toItemRefs()
    }

    /// 阅读按难度排序后的**下标序列**。
    /// 只重排下标、不动数组本身 —— readDone 里存的是下标，两边必须同一套编号。
    var readingOrder: [Int] {
        let levelRank: [String: Int] = ["easy": 0, "medium": 1, "hard": 2]
        return readings.indices.sorted { lhs, rhs in
            let l = levelRank[readings[lhs].level] ?? 1
            let r = levelRank[readings[rhs].level] ?? 1
            if l != r { return l < r }
            return lhs < rhs
        }
    }

    // MARK: - 加载

    private func loadAll() {
        var issues: [String] = []

        words = decodeArray(Word.self, file: "words", issues: &issues)
        families = decodeArray(Family.self, file: "families", issues: &issues)
        phrases = decodeArray(Phrase.self, file: "phrases", issues: &issues)
        readings = decodeArray(Reading.self, file: "reading", issues: &issues)
        papers = decodeArray(Paper.self, file: "papers", issues: &issues)
        transPractices = decodeArray(TransPractice.self, file: "trans_practice", issues: &issues)

        if let pack: ListeningPack = decodeObject(ListeningPack.self, file: "listening", issues: &issues) {
            // ★ 稳定 id 必须与 Android 端逐字一致：`"$level-$indexInLevel"`
            //   （Android 的 AssetsDataSource.loadAllListening 就是这么生成的）。
            //   存档里 listenDone 存的就是这批 key —— 用英文原文当 id 会让
            //   「从 Android 导过来的已听记录」一条都对不上，等于把打卡清零。
            listeningBasic = pack.basic.enumerated().map { i, item in
                var it = item; it.stableId = "basic-\(i)"; return it
            }
            listeningDialog = pack.dialog.enumerated().map { i, item in
                var it = item; it.stableId = "dialog-\(i)"; return it
            }
            listeningPassage = pack.passage.enumerated().map { i, item in
                var it = item; it.stableId = "passage-\(i)"; return it
            }
        }

        var index: [String: Word] = [:]
        index.reserveCapacity(words.count)
        for w in words where !w.w.isEmpty {
            index[w.w] = w
        }
        wordIndex = index

        loadIssues = issues
    }

    private func decodeArray<T: Decodable>(
        _ type: T.Type,
        file: String,
        issues: inout [String]
    ) -> [T] {
        guard let url = ContentStore.resourceURL(name: file, ext: "json") else {
            issues.append("缺少资源 \(file).json")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            issues.append("\(file).json 解析失败：\(error.localizedDescription)")
            return []
        }
    }

    private func decodeObject<T: Decodable>(
        _ type: T.Type,
        file: String,
        issues: inout [String]
    ) -> T? {
        guard let url = ContentStore.resourceURL(name: file, ext: "json") else {
            issues.append("缺少资源 \(file).json")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            issues.append("\(file).json 解析失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 在 bundle 里找资源：先按可能的子目录找，最后按根目录找。
    static func resourceURL(name: String, ext: String) -> URL? {
        let candidates = ["Content", "Resources/Content"]
        for sub in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: sub) {
                return url
            }
        }
        return Bundle.main.url(forResource: name, withExtension: ext)
    }
}
