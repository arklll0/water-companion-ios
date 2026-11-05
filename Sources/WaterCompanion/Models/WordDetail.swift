import Foundation

// ════════════════════════════════════════════════════════════════════
//  单词详情（words_detail.json，3819 个词）
// ════════════════════════════════════════════════════════════════════
//
//  结构是「释义 / 例句 / 词组 / 近义词 / 同根词 / 词源」六块，块与块之间没有关联，
//  一个词可能只有释义。所以除 `t` 之外的字段全部可以缺：
//  `rel` 只有 3536 个词有、`ph` 只有 2567 个有，缺了就是空数组或 nil，不是错误。
//
//  `Term` 这个名字是刻意的：项目里已经有顶层 `Phrase`（常考翻译词组），
//  这里的词组是词典条目，两者语义不同，不能合并，也不该借名。
//
//  查表口径：键统一按小写词形建索引（词典里 China / china 并存，
//  wordProgress 也是按小写记的），查不到返回 nil，由界面决定怎么兜底。

struct WordDetail: Decodable {

    /// 词性释义（v. / n. / adj. 各一条）
    struct Sense: Decodable {

        var pos: String
        var cn: String

        enum CodingKeys: String, CodingKey {
            case pos, cn
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pos = try c.decodeIfPresent(String.self, forKey: .pos) ?? ""
            cn = try c.decodeIfPresent(String.self, forKey: .cn) ?? ""
        }
    }

    /// 例句（c = 英文，cn = 中文）。词组与同根词复用同一个形状。
    struct Term: Decodable {

        var c: String
        var cn: String

        enum CodingKeys: String, CodingKey {
            case c, cn
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.c = try c.decodeIfPresent(String.self, forKey: .c) ?? ""
            cn = try c.decodeIfPresent(String.self, forKey: .cn) ?? ""
        }
    }

    /// 近义词组：一个中文释义 + 若干英文词
    struct Syn: Decodable {

        var pos: String
        var cn: String
        var ws: [String]

        enum CodingKeys: String, CodingKey {
            case pos, cn, ws
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pos = try c.decodeIfPresent(String.self, forKey: .pos) ?? ""
            cn = try c.decodeIfPresent(String.self, forKey: .cn) ?? ""
            ws = try c.decodeIfPresent([String].self, forKey: .ws) ?? []
        }
    }

    /// 同根词的一支：词性 + 该词性下的派生词
    struct RelWord: Decodable {

        var pos: String
        var words: [Term]

        enum CodingKeys: String, CodingKey {
            case pos, words
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pos = try c.decodeIfPresent(String.self, forKey: .pos) ?? ""
            words = try c.decodeIfPresent([Term].self, forKey: .words) ?? []
        }
    }

    struct Root: Decodable {

        var root: String
        var rels: [RelWord]

        enum CodingKeys: String, CodingKey {
            case root, rels
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            root = try c.decodeIfPresent(String.self, forKey: .root) ?? ""
            rels = try c.decodeIfPresent([RelWord].self, forKey: .rels) ?? []
        }
    }

    /// 词源：t = 简短标题，d = 长解释
    struct Ety: Decodable {

        var t: String
        var d: String

        enum CodingKeys: String, CodingKey {
            case t, d
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
            d = try c.decodeIfPresent(String.self, forKey: .d) ?? ""
        }
    }

    var t: [Sense]
    var s: [Term]
    var ph: [Term]
    var sy: [Syn]
    var rel: Root?
    var et: [Ety]

    enum CodingKeys: String, CodingKey {
        case t, s, ph, sy, rel, et
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decodeIfPresent([Sense].self, forKey: .t) ?? []
        s = try c.decodeIfPresent([Term].self, forKey: .s) ?? []
        ph = try c.decodeIfPresent([Term].self, forKey: .ph) ?? []
        sy = try c.decodeIfPresent([Syn].self, forKey: .sy) ?? []
        rel = try c.decodeIfPresent(Root.self, forKey: .rel)
        et = try c.decodeIfPresent([Ety].self, forKey: .et) ?? []
    }
}

/// words_detail.json 的外层：words 是「小写词形 > 详情」的字典。
/// schema / source / generatedFrom 这几个元数据键不用，解码时自然忽略。
struct WordDetailFile: Decodable {

    var words: [String: WordDetail]

    init(words: [String: WordDetail] = [:]) {
        self.words = words
    }

    enum CodingKeys: String, CodingKey {
        case words
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        words = try c.decodeIfPresent([String: WordDetail].self, forKey: .words) ?? [:]
    }
}

/// ck_words.json：成考大纲词表。
///
/// 只存**顺序**和词库里没有的 53 条补充词（`extra` 是完整 Word，自带 lv:"ck"），
/// 其余 2837 个词按 `order` 里的拼写回主词库取。这样不用把整份词库复制一遍，
/// 也不会出现「两份词库改了一处忘另一处」。
struct CkWordList: Decodable {

    var order: [String]
    var extra: [Word]

    /// 白名单为空时必须退回按标签过滤，不能返回空表，所以这个判断要单独暴露出来
    var isEmpty: Bool { order.isEmpty && extra.isEmpty }

    init(order: [String] = [], extra: [Word] = []) {
        self.order = order
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey {
        case order, extra
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
        extra = try c.decodeIfPresent([Word].self, forKey: .extra) ?? []
    }
}
