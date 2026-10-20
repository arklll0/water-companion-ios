import Foundation

// ════════════════════════════════════════════════════════════════════
//  内容 DTO
// ════════════════════════════════════════════════════════════════════
//
//  字段名与 Android 版 `data/model/Content.kt` **一字不差** ——
//  JSON 里的键就是这些短名（w/p/t/m/e/ec），改名会让解码全部失败。
//
//  每个类型都写了 `init(from:)`：JSON 里缺键时用默认值补上，而不是抛错。
//  这不是洁癖 —— 内容文件是外部生成的，少一个 `sentence` 之类的可选字段
//  不应该让整页白屏。

// MARK: - 词汇

/// 词汇：w=单词 p=音标 t=词性 m=释义 e=英文例句 ec=例句中文
struct Word: Codable, Identifiable, Hashable {

    var w: String = ""
    var p: String = ""
    var t: String = ""
    var m: String = ""
    var e: String = ""
    var ec: String = ""

    var id: String { w }

    init(
        w: String = "",
        p: String = "",
        t: String = "",
        m: String = "",
        e: String = "",
        ec: String = ""
    ) {
        self.w = w
        self.p = p
        self.t = t
        self.m = m
        self.e = e
        self.ec = ec
    }

    enum CodingKeys: String, CodingKey {
        case w, p, t, m, e, ec
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        w = try c.decodeIfPresent(String.self, forKey: .w) ?? ""
        p = try c.decodeIfPresent(String.self, forKey: .p) ?? ""
        t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
        m = try c.decodeIfPresent(String.self, forKey: .m) ?? ""
        e = try c.decodeIfPresent(String.self, forKey: .e) ?? ""
        ec = try c.decodeIfPresent(String.self, forKey: .ec) ?? ""
    }
}

// MARK: - 听力

/// 听力素材：一句英文 + 一句中文
struct ListenItem: Codable, Identifiable, Hashable {

    var en: String = ""
    var cn: String = ""

    /// 稳定 id：由 ContentStore 在加载时按「档-序号」写入（basic-0 / dialog-3 / passage-17）。
    ///
    /// 规则与 Android 的 `AssetsDataSource.loadAllListening()` 完全一致 ——
    /// 存档里的 `listenDone` 存的正是这批 key，两边必须逐字相同，
    /// 否则从 Android 导入的进度在听力页会一条都认不出来。
    /// 不参与 JSON 编解码（内容文件里没有这个字段）。
    var stableId: String = ""

    /// 兜底用英文原文（只有素材加载失败、stableId 没写进去时才会走到）
    var id: String { stableId.isEmpty ? en : stableId }

    init(en: String = "", cn: String = "", stableId: String = "") {
        self.en = en
        self.cn = cn
        self.stableId = stableId
    }

    enum CodingKeys: String, CodingKey {
        case en, cn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        en = try c.decodeIfPresent(String.self, forKey: .en) ?? ""
        cn = try c.decodeIfPresent(String.self, forKey: .cn) ?? ""
    }
}

/// listening.json 的外层结构：三档难度
struct ListeningPack: Codable {

    var basic: [ListenItem] = []
    var dialog: [ListenItem] = []
    var passage: [ListenItem] = []

    init(basic: [ListenItem] = [], dialog: [ListenItem] = [], passage: [ListenItem] = []) {
        self.basic = basic
        self.dialog = dialog
        self.passage = passage
    }

    enum CodingKeys: String, CodingKey {
        case basic, dialog, passage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        basic = try c.decodeIfPresent([ListenItem].self, forKey: .basic) ?? []
        dialog = try c.decodeIfPresent([ListenItem].self, forKey: .dialog) ?? []
        passage = try c.decodeIfPresent([ListenItem].self, forKey: .passage) ?? []
    }
}

// MARK: - 阅读

/// 阅读：p=段落 q=题干 o=选项 a=正确下标 ex=解析
struct Reading: Codable, Identifiable, Hashable {

    var tag: String = ""
    var level: String = ""
    var minutes: Int = 0
    var p: [String] = []
    var q: String = ""
    var o: [String] = []
    var a: Int = 0
    var ex: String = ""

    var id: String { "\(tag)|\(q)" }

    init(
        tag: String = "",
        level: String = "",
        minutes: Int = 0,
        p: [String] = [],
        q: String = "",
        o: [String] = [],
        a: Int = 0,
        ex: String = ""
    ) {
        self.tag = tag
        self.level = level
        self.minutes = minutes
        self.p = p
        self.q = q
        self.o = o
        self.a = a
        self.ex = ex
    }

    enum CodingKeys: String, CodingKey {
        case tag, level, minutes, p, q, o, a, ex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tag = try c.decodeIfPresent(String.self, forKey: .tag) ?? ""
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? ""
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        p = try c.decodeIfPresent([String].self, forKey: .p) ?? []
        q = try c.decodeIfPresent(String.self, forKey: .q) ?? ""
        o = try c.decodeIfPresent([String].self, forKey: .o) ?? []
        a = try c.decodeIfPresent(Int.self, forKey: .a) ?? 0
        ex = try c.decodeIfPresent(String.self, forKey: .ex) ?? ""
    }
}

// MARK: - 词族

/// 词族成员：clue 是「前缀 + 方向」的提示，翻面后看 word / meaning
struct FamilyMember: Codable, Identifiable, Hashable {

    var word: String = ""
    var clue: String = ""
    var meaning: String = ""

    var id: String { word }

    init(word: String = "", clue: String = "", meaning: String = "") {
        self.word = word
        self.clue = clue
        self.meaning = meaning
    }

    enum CodingKeys: String, CodingKey {
        case word, clue, meaning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decodeIfPresent(String.self, forKey: .word) ?? ""
        clue = try c.decodeIfPresent(String.self, forKey: .clue) ?? ""
        meaning = try c.decodeIfPresent(String.self, forKey: .meaning) ?? ""
    }
}

/// 词族：锚词 + 动作画面 + 成员词
struct Family: Codable, Identifiable, Hashable {

    var anchor: String = ""
    var action: String = ""
    var cn: String = ""
    var members: [FamilyMember] = []
    var sentence: String = ""

    var id: String { anchor }

    init(
        anchor: String = "",
        action: String = "",
        cn: String = "",
        members: [FamilyMember] = [],
        sentence: String = ""
    ) {
        self.anchor = anchor
        self.action = action
        self.cn = cn
        self.members = members
        self.sentence = sentence
    }

    enum CodingKeys: String, CodingKey {
        case anchor, action, cn, members, sentence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        anchor = try c.decodeIfPresent(String.self, forKey: .anchor) ?? ""
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? ""
        cn = try c.decodeIfPresent(String.self, forKey: .cn) ?? ""
        members = try c.decodeIfPresent([FamilyMember].self, forKey: .members) ?? []
        sentence = try c.decodeIfPresent(String.self, forKey: .sentence) ?? ""
    }
}

// MARK: - 真题 / 练习

/// 真题/练习小题
struct PaperItem: Codable, Identifiable, Hashable {

    var type: String = "q"
    var passage: [String] = []
    var q: String = ""
    var o: [String] = []
    var a: Int = 0
    var ex: String = ""

    var id: String { "\(type)|\(q)" }

    init(
        type: String = "q",
        passage: [String] = [],
        q: String = "",
        o: [String] = [],
        a: Int = 0,
        ex: String = ""
    ) {
        self.type = type
        self.passage = passage
        self.q = q
        self.o = o
        self.a = a
        self.ex = ex
    }

    enum CodingKeys: String, CodingKey {
        case type, passage, q, o, a, ex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "q"
        passage = try c.decodeIfPresent([String].self, forKey: .passage) ?? []
        q = try c.decodeIfPresent(String.self, forKey: .q) ?? ""
        o = try c.decodeIfPresent([String].self, forKey: .o) ?? []
        a = try c.decodeIfPresent(Int.self, forKey: .a) ?? 0
        ex = try c.decodeIfPresent(String.self, forKey: .ex) ?? ""
    }
}

/// 一套题
struct Paper: Codable, Identifiable, Hashable {

    var id: String = ""
    var title: String = ""
    var year: String = ""
    var items: [PaperItem] = []

    init(id: String = "", title: String = "", year: String = "", items: [PaperItem] = []) {
        self.id = id
        self.title = title
        self.year = year
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case id, title, year, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        year = try c.decodeIfPresent(String.self, forKey: .year) ?? ""
        items = try c.decodeIfPresent([PaperItem].self, forKey: .items) ?? []
    }
}

/// 扁平化之后的一道小题 —— 每日练习要从「所有卷子的所有小题」里按天取一道，
/// 所以必须记住它属于哪套卷子的第几题（错题集的 ref 与 paperDone 的 key 都靠它）。
struct PaperItemRef: Identifiable, Hashable {

    let paperIndex: Int
    let itemIndex: Int
    let paperTitle: String
    let item: PaperItem

    /// 稳定 id，形如 "3-4"
    var id: String { "\(paperIndex)-\(itemIndex)" }

    /// 「2023年12月 真题 · 第 4 题」这种列表标题
    var label: String { "\(paperTitle) · 第 \(itemIndex + 1) 题" }

    init(paperIndex: Int, itemIndex: Int, paperTitle: String, item: PaperItem) {
        self.paperIndex = paperIndex
        self.itemIndex = itemIndex
        self.paperTitle = paperTitle
        self.item = item
    }
}

extension Array where Element == Paper {

    /// 把「按套组织的题库」拍平成「按题排列的流」。
    /// 顺序 = 卷子顺序 × 卷内题序，所以往末尾加新卷子只会追加、不会让已有下标移位。
    func toItemRefs() -> [PaperItemRef] {
        var out: [PaperItemRef] = []
        for (pi, paper) in enumerated() {
            for (ii, item) in paper.items.enumerated() {
                out.append(
                    PaperItemRef(
                        paperIndex: pi,
                        itemIndex: ii,
                        paperTitle: paper.title,
                        item: item
                    )
                )
            }
        }
        return out
    }
}

// MARK: - 翻译

/// 汉译英练习
struct TransPractice: Codable, Identifiable, Hashable {

    var cn: String = ""
    var ref: String = ""
    var tips: [String] = []

    var id: String { cn }

    init(cn: String = "", ref: String = "", tips: [String] = []) {
        self.cn = cn
        self.ref = ref
        self.tips = tips
    }

    enum CodingKeys: String, CodingKey {
        case cn, ref, tips
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cn = try c.decodeIfPresent(String.self, forKey: .cn) ?? ""
        ref = try c.decodeIfPresent(String.self, forKey: .ref) ?? ""
        tips = try c.decodeIfPresent([String].self, forKey: .tips) ?? []
    }
}

/// 常考翻译词组
struct Phrase: Codable, Identifiable, Hashable {

    var en: String = ""
    var cn: String = ""

    var id: String { en }

    init(en: String = "", cn: String = "") {
        self.en = en
        self.cn = cn
    }

    enum CodingKeys: String, CodingKey {
        case en, cn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        en = try c.decodeIfPresent(String.self, forKey: .en) ?? ""
        cn = try c.decodeIfPresent(String.self, forKey: .cn) ?? ""
    }
}
