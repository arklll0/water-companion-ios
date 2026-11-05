import Foundation

// ════════════════════════════════════════════════════════════════════
//  整套真题（papers_full.json，30 套）
// ════════════════════════════════════════════════════════════════════
//
//  结构与 `papers.json`（每日练习用的单题流）完全不同：这里是**一套完整卷**，
//  听力、选词填空、匹配、仔细阅读、翻译、作文齐全，还带答案和答案空档。
//
//  两个必须留意的点：
//  1. `meta.set` 是 Swift 的上下文关键字（`set` 访问器），属性名改成 `setNo`，
//     CodingKeys 里映射回 "set"。不改名会在某些位置解析出歧义。
//  2. `answers` 的键是**字符串题号**（"1" / "26" / "46"），不是 Int。
//     用 Int 当键会在解码时直接失败，整份素材静默变空。
//
//  `answerGaps` 列的是「没有答案、不计入分母」的题号。判分时必须先把它剔掉，
//  否则满分永远达不到，正确率会莫名其妙地低于 100%。
//
//  素材里同一个字段有两种写法，解码要同时兼容（见下面的 `FlexEntry`）：
//  - 选词备选词是 `{"letter":"A","word":"accessible"}`，段落匹配的段落是
//    `{"letter":"A","text":"..."}`，陈述是 `{"no":36,"text":"..."}`；
//  - 讲义式的段落则是整段字符串。
//  写成固定 `[String]` 会在真实素材上直接抛 typeMismatch，整个 `fullPapers` 变空表。
//  这才是「界面只显示没有素材」的典型成因，所以这里按形态兼容，而不是按文档想当然。
//
//  全部字段手写 `init(from:)`：素材是脚本生成的，缺一个 sample 或 note
//  不该让 30 套题一起消失。

/// 一个既能是纯字符串、又能是 `{letter, text}` / `{no, text}` / `{letter, word}` 的条目。
///
/// 只在本文件内使用：对外仍然暴露 `[String]`，UI 不必为两种写法分叉。
/// 字母单独留在 `letter` 里，因为段落匹配的字母并不总是从 A 连续排下来
/// （有 4 套卷跳过了 D 或 I 这类容易和数字混淆的字母），
/// 按数组下标推字母会跟答案对不上。
private struct FlexEntry: Decodable {

    var text: String = ""
    var letter: String = ""

    enum CodingKeys: String, CodingKey {
        case text, word, letter, no
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let plain = try? single.decode(String.self) {
            text = plain
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        letter = (try? c.decode(String.self, forKey: .letter)) ?? ""
        if let value = try? c.decode(String.self, forKey: .text) {
            text = value
        } else if let value = try? c.decode(String.self, forKey: .word) {
            text = value
        }
    }
}

/// 段落字段可能是 `"整段文字"`，也可能是 `["第一段", "第二段"]`。
private enum FlexParagraph {

    static func list<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> [String] {
        if let single = try? container.decode(String.self, forKey: key) {
            return split(single)
        }
        if let array = try? container.decode([String].self, forKey: key) {
            return array
        }
        return []
    }

    /// 单串正文交给统一的文章组件排版：英文按 `(?<=[.!?])\s+` 切句 + 320 字预算合并，
    /// 中文原样返回（不切 320、不插 U+2002）。素材里目前整段没有换行，
    /// 所以之前按 `\n` 切开只会得到一个元素；现在这一步统一走 `ReadingPassage`。
    /// 已经是 `[String]` 的分支（`list`）保持 1:1 直返，不猜分段。
    static func split(_ text: String) -> [String] {
        ReadingBody.splitReadingParagraphs(text)
    }
}

struct FullPaper: Decodable, Identifiable {

    // MARK: - 元信息

    struct Meta: Decodable {

        var level: String
        var year: Int
        var month: Int
        /// JSON 里的键是 "set"
        var setNo: Int
        var paperPages: Int

        var levelLabel: String {
            switch level {
            case "cet4": return "四级"
            case "cet6": return "六级"
            default: return level
            }
        }

        enum CodingKeys: String, CodingKey {
            case level, year, month
            case setNo = "set"
            case paperPages
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            level = try c.decodeIfPresent(String.self, forKey: .level) ?? ""
            year = try c.decodeIfPresent(Int.self, forKey: .year) ?? 0
            month = try c.decodeIfPresent(Int.self, forKey: .month) ?? 0
            setNo = try c.decodeIfPresent(Int.self, forKey: .setNo) ?? 0
            paperPages = try c.decodeIfPresent(Int.self, forKey: .paperPages) ?? 0
        }
    }

    // MARK: - 作文

    struct Writing: Decodable {

        var directions: String
        var minutes: Int
        var minWords: Int
        var maxWords: Int
        var sample: String

        enum CodingKeys: String, CodingKey {
            case directions, minutes, minWords, maxWords, sample
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            directions = try c.decodeIfPresent(String.self, forKey: .directions) ?? ""
            minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
            minWords = try c.decodeIfPresent(Int.self, forKey: .minWords) ?? 0
            maxWords = try c.decodeIfPresent(Int.self, forKey: .maxWords) ?? 0
            sample = try c.decodeIfPresent(String.self, forKey: .sample) ?? ""
        }
    }

    // MARK: - 听力

    struct ListenQ: Decodable, Identifiable {

        var no: Int
        var options: [String]
        var transcript: String

        var id: Int { no }

        enum CodingKeys: String, CodingKey {
            case no, options, transcript
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            no = try c.decodeIfPresent(Int.self, forKey: .no) ?? 0
            options = try c.decodeIfPresent([String].self, forKey: .options) ?? []
            transcript = try c.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        }
    }

    struct Listening: Decodable {

        var questions: [ListenQ]

        enum CodingKeys: String, CodingKey {
            case questions
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            questions = try c.decodeIfPresent([ListenQ].self, forKey: .questions) ?? []
        }
    }

    // MARK: - 阅读

    struct Blank: Decodable, Identifiable {

        var no: Int
        var context: String

        var id: Int { no }

        enum CodingKeys: String, CodingKey {
            case no, context
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            no = try c.decodeIfPresent(Int.self, forKey: .no) ?? 0
            context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
        }
    }

    struct Cloze: Decodable {

        /// 15 个备选词，按 A-O 的顺序
        var bank: [String]
        var blanks: [Blank]
        var passage: [String]

        enum CodingKeys: String, CodingKey {
            case bank, blanks, passage
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let entries = (try? c.decode([FlexEntry].self, forKey: .bank)) ?? []
            bank = entries.map(\.text)
            blanks = try c.decodeIfPresent([Blank].self, forKey: .blanks) ?? []
            passage = FlexParagraph.list(c, .passage)
        }
    }

    struct Matching: Decodable {

        var title: String
        /// 16 个段落，答案是一个段落字母
        var paragraphs: [String]
        /// 10 个陈述句，与题目 36-45 一一对应
        var statements: [String]
        /// 每个段落**原本**的字母。素材里有 4 套卷跳过了 D、I 这类字母，
        /// 按下标重新数会跟 `answers.matching` 里的字母错开一位，所以这里单独留着。
        var paragraphLetters: [String]

        enum CodingKeys: String, CodingKey {
            case title, paragraphs, statements
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            let paraEntries = (try? c.decode([FlexEntry].self, forKey: .paragraphs)) ?? []
            paragraphs = paraEntries.map(\.text)
            paragraphLetters = paraEntries.map(\.letter)
            let statementEntries = (try? c.decode([FlexEntry].self, forKey: .statements)) ?? []
            statements = statementEntries.map(\.text)
        }
    }

    struct CareQ: Decodable, Identifiable {

        var no: Int
        var options: [String]
        var stem: String

        var id: Int { no }

        enum CodingKeys: String, CodingKey {
            case no, options, stem
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            no = try c.decodeIfPresent(Int.self, forKey: .no) ?? 0
            options = try c.decodeIfPresent([String].self, forKey: .options) ?? []
            stem = try c.decodeIfPresent(String.self, forKey: .stem) ?? ""
        }
    }

    /// 一篇仔细阅读（两篇各带 5 道题，题号 46-50 / 51-55）。
    ///
    /// id 取第一篇的第一题号：同一套卷里两篇的题号段不同，所以能区分开，
    /// 不需要额外字段，也不会因为数组重排而变化。
    struct Careful: Decodable, Identifiable {

        var passage: [String]
        var questions: [CareQ]

        var id: Int { questions.first?.no ?? 0 }

        enum CodingKeys: String, CodingKey {
            case passage, questions
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            passage = FlexParagraph.list(c, .passage)
            questions = try c.decodeIfPresent([CareQ].self, forKey: .questions) ?? []
        }
    }

    struct Reading: Decodable {

        var cloze: Cloze
        var matching: Matching
        var careful: [Careful]

        enum CodingKeys: String, CodingKey {
            case cloze, matching, careful
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            cloze = try c.decodeIfPresent(Cloze.self, forKey: .cloze) ?? Cloze.empty
            matching = try c.decodeIfPresent(Matching.self, forKey: .matching) ?? Matching.empty
            careful = try c.decodeIfPresent([Careful].self, forKey: .careful) ?? []
        }
    }

    // MARK: - 翻译

    struct Translation: Decodable {

        var chinese: String
        var reference: String

        enum CodingKeys: String, CodingKey {
            case chinese, reference
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            chinese = try c.decodeIfPresent(String.self, forKey: .chinese) ?? ""
            reference = try c.decodeIfPresent(String.self, forKey: .reference) ?? ""
        }
    }

    // MARK: - 答案

    /// 键是字符串题号（"1" / "26" / "46"），值是选项字母（"A"）。
    /// 用 Int 当键会在解码阶段就失败，整份素材会静默变空。
    struct Answers: Decodable {

        var listening: [String: String]
        var cloze: [String: String]
        var matching: [String: String]
        var careful: [String: String]

        enum CodingKeys: String, CodingKey {
            case listening, cloze, matching, careful
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            listening = FullPaper.gradeable((try? c.decodeIfPresent([String: String].self, forKey: .listening)) ?? [:])
            cloze = FullPaper.gradeable((try? c.decodeIfPresent([String: String].self, forKey: .cloze)) ?? [:])
            matching = FullPaper.gradeable((try? c.decodeIfPresent([String: String].self, forKey: .matching)) ?? [:])
            careful = FullPaper.gradeable((try? c.decodeIfPresent([String: String].self, forKey: .careful)) ?? [:])
        }
    }

    /// 没有答案、不计入分母的题号
    struct Gaps: Decodable {

        var listening: [Int]
        var cloze: [Int]
        var matching: [Int]
        var careful: [Int]

        enum CodingKeys: String, CodingKey {
            case listening, cloze, matching, careful
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            listening = try c.decodeIfPresent([Int].self, forKey: .listening) ?? []
            cloze = try c.decodeIfPresent([Int].self, forKey: .cloze) ?? []
            matching = try c.decodeIfPresent([Int].self, forKey: .matching) ?? []
            careful = try c.decodeIfPresent([Int].self, forKey: .careful) ?? []
        }
    }

    // MARK: - 顶层字段

    var id: String
    var meta: Meta
    var writing: Writing
    var listening: Listening
    var reading: Reading
    var translation: Translation
    var answers: Answers
    var answerGaps: Gaps
    /// 音频相对路径，如 "set_audio/cet4-2020-07-s1.m4a"
    var audio: String

    /// 「2020 年 7 月 · 第 1 套」
    var title: String {
        "\(meta.year) 年 \(meta.month) 月 · 第 \(meta.setNo) 套"
    }

    enum CodingKeys: String, CodingKey {
        case id, meta, writing, listening, reading, translation
        case answers, answerGaps, audio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        meta = try c.decodeIfPresent(Meta.self, forKey: .meta) ?? Meta.empty
        writing = try c.decodeIfPresent(Writing.self, forKey: .writing) ?? Writing.empty
        listening = try c.decodeIfPresent(Listening.self, forKey: .listening) ?? Listening.empty
        reading = try c.decodeIfPresent(Reading.self, forKey: .reading) ?? Reading.empty
        translation = try c.decodeIfPresent(Translation.self, forKey: .translation) ?? Translation.empty
        answers = try c.decodeIfPresent(Answers.self, forKey: .answers) ?? Answers.empty
        answerGaps = try c.decodeIfPresent(Gaps.self, forKey: .answerGaps) ?? Gaps.empty
        audio = try c.decodeIfPresent(String.self, forKey: .audio) ?? ""
    }

    /// 素材里有 155 处答案是空串（等于没有答案），其中一部分并没有登记在 `answerGaps` 里。
    /// 空串留着会被当成一道有正确答案的题：用户永远选不中，总分永远差几分。
    /// 所以解码时直接剔掉，让「没有答案」这件事只有一个表示。
    fileprivate static func gradeable(_ raw: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in raw {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                out[key] = trimmed
            }
        }
        return out
    }
}

// MARK: - 空壳
//
// 某一段缺失时用它顶上，界面拿到的是「空卷」而不是 nil：少一层可选判断，
// 也避免某套卷因为缺 translation 就在列表里整条消失。

extension FullPaper.Meta {
    static var empty: FullPaper.Meta {
        FullPaper.Meta(level: "", year: 0, month: 0, setNo: 0, paperPages: 0)
    }

    init(level: String, year: Int, month: Int, setNo: Int, paperPages: Int) {
        self.level = level
        self.year = year
        self.month = month
        self.setNo = setNo
        self.paperPages = paperPages
    }
}

extension FullPaper.Writing {
    static var empty: FullPaper.Writing {
        FullPaper.Writing(directions: "", minutes: 0, minWords: 0, maxWords: 0, sample: "")
    }

    init(directions: String, minutes: Int, minWords: Int, maxWords: Int, sample: String) {
        self.directions = directions
        self.minutes = minutes
        self.minWords = minWords
        self.maxWords = maxWords
        self.sample = sample
    }
}

extension FullPaper.Listening {
    static var empty: FullPaper.Listening {
        FullPaper.Listening(questions: [])
    }

    init(questions: [FullPaper.ListenQ]) {
        self.questions = questions
    }
}

extension FullPaper.Cloze {
    static var empty: FullPaper.Cloze {
        FullPaper.Cloze(bank: [], blanks: [], passage: [])
    }

    init(bank: [String], blanks: [FullPaper.Blank], passage: [String]) {
        self.bank = bank
        self.blanks = blanks
        self.passage = passage
    }
}

extension FullPaper.Matching {
    static var empty: FullPaper.Matching {
        FullPaper.Matching(title: "", paragraphs: [], statements: [], paragraphLetters: [])
    }

    init(title: String, paragraphs: [String], statements: [String], paragraphLetters: [String] = []) {
        self.title = title
        self.paragraphs = paragraphs
        self.statements = statements
        self.paragraphLetters = paragraphLetters
    }
}

extension FullPaper.Reading {
    static var empty: FullPaper.Reading {
        FullPaper.Reading(cloze: .empty, matching: .empty, careful: [])
    }

    init(cloze: FullPaper.Cloze, matching: FullPaper.Matching, careful: [FullPaper.Careful]) {
        self.cloze = cloze
        self.matching = matching
        self.careful = careful
    }
}

extension FullPaper.Translation {
    static var empty: FullPaper.Translation {
        FullPaper.Translation(chinese: "", reference: "")
    }

    init(chinese: String, reference: String) {
        self.chinese = chinese
        self.reference = reference
    }
}

extension FullPaper.Answers {
    static var empty: FullPaper.Answers {
        FullPaper.Answers(listening: [:], cloze: [:], matching: [:], careful: [:])
    }

    init(listening: [String: String], cloze: [String: String], matching: [String: String], careful: [String: String]) {
        self.listening = listening
        self.cloze = cloze
        self.matching = matching
        self.careful = careful
    }
}

extension FullPaper.Gaps {
    static var empty: FullPaper.Gaps {
        FullPaper.Gaps(listening: [], cloze: [], matching: [], careful: [])
    }

    init(listening: [Int], cloze: [Int], matching: [Int], careful: [Int]) {
        self.listening = listening
        self.cloze = cloze
        self.matching = matching
        self.careful = careful
    }
}
