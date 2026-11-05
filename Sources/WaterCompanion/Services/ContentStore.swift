import Foundation
import Observation

// ════════════════════════════════════════════════════════════════════
//  内容数据加载
// ════════════════════════════════════════════════════════════════════
//
//  12 个 JSON 随 App 打包，启动时一次性读进内存（合计约 8.5 MiB）。
//  为什么不用「用到再读」：每个页面都要按名字查词（`word("abandon")`），
//  懒加载会把「一次 O(1) 的数组查找」变成「读文件 + 解析 + 查找」，
//  在翻卡这种高频路径上是灾难。
//
//  路径查找做了两条兜底：XcodeGen 的 group 型资源会被**拍平**到 bundle 根目录，
//  而 folder reference 会保留子目录。两种打包方式都要能读出来，
//  这类「源码没问题、只是路径不对」的故障在 CI 上最难查，所以干脆都试一遍。
//
//  每份素材独立解码：某一份坏了只往 `loadIssues` 里记一条，其余照常可用。
//  一份素材缺失不该让整个 App 变成「没有素材」。

/// 听力分组。分组顺序就是难度坡度（basic → dialog → passage → exam4 → exam6），
/// 每日调度直接按下标推进，不需要额外的难度字段。
struct ListenGroup: Identifiable {

    /// basic / dialog / passage / exam4 / exam6
    let key: String
    let title: String
    let items: [ListenItem]

    var id: String { key }
}

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

    /// 听力五个分组（只收非空组）。听力页的「全部素材」按这个顺序展开。
    var listeningGroups: [ListenGroup] = []

    /// 成考精讲讲义。加载失败时是空壳，不是 nil：界面少一层判空。
    var lectures: LectureFile = LectureFile()

    /// 整套真题（30 套，含成考 3 套）
    var fullPapers: [FullPaper] = []

    /// 成考大纲词表的顺序 + 补充词。加载失败时为空，`LevelContent.words` 会自动退回按标签过滤。
    var ckWordList: CkWordList = CkWordList()

    /// 加载失败的项（正常为空）。界面不因此崩溃，只是列表为空。
    var loadIssues: [String] = []

    /// 只建一次索引：单词原文 → 数据
    private var wordIndex: [String: Word] = [:]

    /// 单词详情索引，键是**小写词形**（词典里大小写不统一，进度也是按小写记的）
    private var wordDetails: [String: WordDetail] = [:]

    // MARK: - 生命周期

    init() {
        loadAll()
    }

    // MARK: - 派生数据

    /// 听力素材的合并池：按分组顺序拍平。
    /// 每日调度跨档推进难度，所以页面只认这一个池子。
    var allListening: [ListenItem] {
        listeningGroups.flatMap(\.items)
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

    /// 按词形取详情。查不到返回 nil，由界面决定显示「暂无详解」还是隐藏入口。
    func wordDetail(_ text: String) -> WordDetail? {
        wordDetails[text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    /// 真题拍平成「按题排列的流」（顺序 = 卷子顺序 × 卷内题序）
    var paperItemRefs: [PaperItemRef] {
        papers.toItemRefs()
    }

    /// 阅读按难度排序后的**下标序列**。
    /// 只重排下标、不动数组本身：readDone 里存的是下标，两边必须同一套编号。
    /// 过滤规则统一走 `LevelContent`，这里传 `.all` 保持「全部素材」的旧口径。
    var readingOrder: [Int] {
        LevelContent.readingOrder(readings, level: .all)
    }

    // MARK: - 加载

    private func loadAll() {
        var issues: [String] = []

        words = decodeArray(Word.self, file: "words", issues: &issues)
        families = decodeArray(Family.self, file: "families", issues: &issues)
        phrases = decodeArray(Phrase.self, file: "phrases", issues: &issues)
        readings = decodeArray(Reading.self, file: "reading", issues: &issues)
        transPractices = decodeArray(TransPractice.self, file: "trans_practice", issues: &issues)

        // 卷序号就是数组下标，paperDone 存的是 "卷序号-题序号"。
        // 所有新卷**只追加不重排**：只有往后追加才不会让老存档的下标移位。
        // 四级 0..15 / 成考 16..18 / 考研 19..33。
        let cetPapers = decodeArray(Paper.self, file: "papers", issues: &issues)
        let ckPapers = decodeArray(Paper.self, file: "ck_papers", issues: &issues)
        let kyPapers = decodeArray(Paper.self, file: "ky_papers", issues: &issues)
        papers = cetPapers + ckPapers + kyPapers

        loadListening(&issues)

        if let lectureFile: LectureFile = decodeObject(LectureFile.self, file: "lectures", issues: &issues) {
            lectures = lectureFile
        }

        fullPapers = decodeArray(FullPaper.self, file: "papers_full", issues: &issues)

        if let list: CkWordList = decodeObject(CkWordList.self, file: "ck_words", issues: &issues) {
            ckWordList = list
        }

        if let detailFile: WordDetailFile = decodeObject(WordDetailFile.self, file: "words_detail", issues: &issues) {
            var index: [String: WordDetail] = [:]
            index.reserveCapacity(detailFile.words.count)
            for (key, value) in detailFile.words {
                let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !normalized.isEmpty {
                    index[normalized] = value
                }
            }
            wordDetails = index
        }

        var index: [String: Word] = [:]
        index.reserveCapacity(words.count)
        for w in words where !w.w.isEmpty {
            index[w.w] = w
        }
        wordIndex = index

        loadIssues = issues
    }

    /// 解析 listening.json，同时填三个旧属性和新的分组列表。
    private func loadListening(_ issues: inout [String]) {
        guard let pack: ListeningPack = decodeObject(ListeningPack.self, file: "listening", issues: &issues) else {
            return
        }

        // ★ 稳定 id 必须与 Android 端逐字一致：`"$level-$indexInLevel"`
        //   （Android 的 AssetsDataSource.loadAllListening 就是这么生成的）。
        //   存档里 listenDone 存的就是这批 key，用英文原文当 id 会让
        //   「从 Android 导过来的已听记录」一条都对不上，等于把打卡清零。
        let sources: [(key: String, title: String, items: [ListenItem])] = [
            ("basic", "入门短句", pack.basic),
            ("dialog", "短对话", pack.dialog),
            ("passage", "短文独白", pack.passage),
            ("exam4", "四级真题原文", pack.exam4),
            ("exam6", "六级真题原文", pack.exam6)
        ]

        var groups: [ListenGroup] = []
        for source in sources {
            let tagged = source.items.enumerated().map { i, item in
                var it = item
                it.stableId = "\(source.key)-\(i)"
                return it
            }

            switch source.key {
            case "basic": listeningBasic = tagged
            case "dialog": listeningDialog = tagged
            case "passage": listeningPassage = tagged
            default: break
            }

            if !tagged.isEmpty {
                groups.append(ListenGroup(key: source.key, title: source.title, items: tagged))
            }
        }
        listeningGroups = groups
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
