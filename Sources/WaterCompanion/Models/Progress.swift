import Foundation

// ════════════════════════════════════════════════════════════════════
//  学习进度存档
// ════════════════════════════════════════════════════════════════════
//
//  字段名与 Android 版 `data/model/Progress.kt`（也就是网站 localStorage 里的
//  `cet4_90d_v1`）**完全一致**。原因是硬性的：用户在网站上导出的进度 JSON
//  要能直接导进来，改一个键名就等于让所有人的老进度失效。
//
//  关于「加字段会不会弄坏老存档」：不会。
//  - 老存档里**没有**某个键 → 我们的 `init(from:)` 用默认值补上，解码正常；
//  - 新存档里**多**某个键 → JSONDecoder 忽略未知键；
//  - 真正会弄坏存档的是「改已有字段的类型或语义」，那种改动一律不做。
//
//  所以下面每个类型都手写了 `init(from:)`。Swift 的合成解码器**不会**用属性
//  默认值去补缺失的键 —— 缺一个键就抛错，整份进度会退化成空档。这一点必须
//  自己实现，不能依赖 `decodeIfPresent` 之外的任何魔法。

// MARK: - 单个词 / 词族成员的学习状态

struct WordProgress: Codable, Hashable {

    var stage: Int = 0
    var due: String = ""
    var seen: Int = 0
    var right: Int = 0
    var wrong: Int = 0

    init(stage: Int = 0, due: String = "", seen: Int = 0, right: Int = 0, wrong: Int = 0) {
        self.stage = stage
        self.due = due
        self.seen = seen
        self.right = right
        self.wrong = wrong
    }

    enum CodingKeys: String, CodingKey {
        case stage, due, seen, right, wrong
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stage = try c.decodeIfPresent(Int.self, forKey: .stage) ?? 0
        due = try c.decodeIfPresent(String.self, forKey: .due) ?? ""
        seen = try c.decodeIfPresent(Int.self, forKey: .seen) ?? 0
        right = try c.decodeIfPresent(Int.self, forKey: .right) ?? 0
        wrong = try c.decodeIfPresent(Int.self, forKey: .wrong) ?? 0
    }
}

// MARK: - 一次作答

/// 一次作答记录。`wrongBook` 只收答错的题，没有分母就算不出正确率，
/// 所以「答对的也要记」—— 这张表是能力分析的数据源。
struct Attempt: Codable, Hashable {

    /// yyyy-MM-dd
    var date: String = ""
    /// 细分题型：vocab / q / cloze / match / read / listen
    var kind: String = ""
    var ok: Bool = false

    init(date: String = "", kind: String = "", ok: Bool = false) {
        self.date = date
        self.kind = kind
        self.ok = ok
    }

    enum CodingKeys: String, CodingKey {
        case date, kind, ok
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
    }
}

// MARK: - 错题

/// 错题条目。`kind` 是细分题型（vocab / q / cloze / match / read / listen），
/// 与 `type` 分开是刻意的：`type` 在老数据里一律是 "paper"，改它的语义会让
/// 新老数据不可比，所以另开一个字段，老字段一个不动。
struct WrongItem: Codable, Hashable, Identifiable {

    var q: String = ""
    var chosen: Int = -1
    var right: Int = 0
    var from: String = ""
    var type: String = ""
    var ref: String = ""
    var en: String = ""
    var cn: String = ""
    /// 哪天错的。老存档没有这个键 → 默认空串，解码不受影响。
    var date: String = ""
    var kind: String = ""
    var ok: Bool = false

    /// 列表里需要一个稳定 id；同一道题可能被错两次，所以拼上日期。
    var id: String { "\(ref)|\(q)|\(date)" }

    init(
        q: String = "",
        chosen: Int = -1,
        right: Int = 0,
        from: String = "",
        type: String = "",
        ref: String = "",
        en: String = "",
        cn: String = "",
        date: String = "",
        kind: String = "",
        ok: Bool = false
    ) {
        self.q = q
        self.chosen = chosen
        self.right = right
        self.from = from
        self.type = type
        self.ref = ref
        self.en = en
        self.cn = cn
        self.date = date
        self.kind = kind
        self.ok = ok
    }

    enum CodingKeys: String, CodingKey {
        case q, chosen, right, from, type, ref, en, cn, date, kind, ok
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        q = try c.decodeIfPresent(String.self, forKey: .q) ?? ""
        chosen = try c.decodeIfPresent(Int.self, forKey: .chosen) ?? -1
        right = try c.decodeIfPresent(Int.self, forKey: .right) ?? 0
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        ref = try c.decodeIfPresent(String.self, forKey: .ref) ?? ""
        en = try c.decodeIfPresent(String.self, forKey: .en) ?? ""
        cn = try c.decodeIfPresent(String.self, forKey: .cn) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
    }
}

// MARK: - 模考

struct ExamRecord: Codable, Hashable, Identifiable {

    var date: String = ""
    var correct: Int = 0
    var total: Int = 0
    var acc: Int = 0
    var score: Int = 0

    var id: String { "\(date)|\(score)|\(correct)" }

    init(date: String = "", correct: Int = 0, total: Int = 0, acc: Int = 0, score: Int = 0) {
        self.date = date
        self.correct = correct
        self.total = total
        self.acc = acc
        self.score = score
    }

    enum CodingKeys: String, CodingKey {
        case date, correct, total, acc, score
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        correct = try c.decodeIfPresent(Int.self, forKey: .correct) ?? 0
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        acc = try c.decodeIfPresent(Int.self, forKey: .acc) ?? 0
        score = try c.decodeIfPresent(Int.self, forKey: .score) ?? 0
    }
}

// MARK: - 某一天的学习量

struct DayLog: Codable, Hashable {

    var words: Int = 0
    var read: Int = 0
    var listen: Int = 0
    var exam: Int = 0
    var tasks: Int = 0

    init(words: Int = 0, read: Int = 0, listen: Int = 0, exam: Int = 0, tasks: Int = 0) {
        self.words = words
        self.read = read
        self.listen = listen
        self.exam = exam
        self.tasks = tasks
    }

    enum CodingKeys: String, CodingKey {
        case words, read, listen, exam, tasks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        words = try c.decodeIfPresent(Int.self, forKey: .words) ?? 0
        read = try c.decodeIfPresent(Int.self, forKey: .read) ?? 0
        listen = try c.decodeIfPresent(Int.self, forKey: .listen) ?? 0
        exam = try c.decodeIfPresent(Int.self, forKey: .exam) ?? 0
        tasks = try c.decodeIfPresent(Int.self, forKey: .tasks) ?? 0
    }
}

// MARK: - 完整进度

/// 完整学习进度。键名与网站 `cet4_90d_v1` 对齐，网站「导出进度」的 JSON
/// 可以直接导入（未知键会被忽略）。
struct Progress: Codable, Hashable {

    /// 开始日期（yyyy-MM-dd）。null 表示还没开始 —— 首次启动时写入今天。
    var startDate: String? = nil
    /// 考试日期（yyyy-MM-dd）。null 表示还没设置。
    var examDate: String? = nil
    var dailyMinutes: Int = 30
    var dailyWords: Int = 20
    /// key = 单词原文
    var wordProgress: [String: WordProgress] = [:]
    /// key = "族序号:单词"
    var familyProgress: [String: WordProgress] = [:]
    /// 已读过的阅读下标
    var readDone: [Int] = []
    /// 已听过的听力条目 id
    var listenDone: [String] = []
    var examHistory: [ExamRecord] = []
    var wrongBook: [WrongItem] = []
    /// key = yyyy-MM-dd
    var log: [String: DayLog] = [:]
    var streak: Int = 0
    var lastActive: String? = nil
    var todayTaskDone: [String] = []
    /// auto / light / dark
    var theme: String = "auto"
    /// 「推迟到明天」的任务：key = 任务 id（words/listen/read/exam），
    /// value = 它应该**重新出现**的日期（yyyy-MM-dd）。
    ///
    /// 存目标日期而不是布尔值：布尔值需要第二天由某个定时逻辑去清掉，而 App 是
    /// 被动启动的；存日期则完全靠「日期比较」推导 —— 到了那天 `value != today`，
    /// 任务自动回到列表，**过期条目天然失效**，不需要任何清理任务。
    var postponed: [String: String] = [:]
    /// 已做过的「每日练习」小题 id（形如 "3-4"）
    var paperDone: [String] = []
    /// 每一次作答（对的和错的都记）
    var attempts: [Attempt] = []

    init(
        startDate: String? = nil,
        examDate: String? = nil,
        dailyMinutes: Int = 30,
        dailyWords: Int = 20,
        wordProgress: [String: WordProgress] = [:],
        familyProgress: [String: WordProgress] = [:],
        readDone: [Int] = [],
        listenDone: [String] = [],
        examHistory: [ExamRecord] = [],
        wrongBook: [WrongItem] = [],
        log: [String: DayLog] = [:],
        streak: Int = 0,
        lastActive: String? = nil,
        todayTaskDone: [String] = [],
        theme: String = "auto",
        postponed: [String: String] = [:],
        paperDone: [String] = [],
        attempts: [Attempt] = []
    ) {
        self.startDate = startDate
        self.examDate = examDate
        self.dailyMinutes = dailyMinutes
        self.dailyWords = dailyWords
        self.wordProgress = wordProgress
        self.familyProgress = familyProgress
        self.readDone = readDone
        self.listenDone = listenDone
        self.examHistory = examHistory
        self.wrongBook = wrongBook
        self.log = log
        self.streak = streak
        self.lastActive = lastActive
        self.todayTaskDone = todayTaskDone
        self.theme = theme
        self.postponed = postponed
        self.paperDone = paperDone
        self.attempts = attempts
    }

    enum CodingKeys: String, CodingKey {
        case startDate, examDate, dailyMinutes, dailyWords
        case wordProgress, familyProgress
        case readDone, listenDone
        case examHistory, wrongBook, log
        case streak, lastActive, todayTaskDone, theme
        case postponed, paperDone, attempts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
        examDate = try c.decodeIfPresent(String.self, forKey: .examDate)
        dailyMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyMinutes) ?? 30
        dailyWords = try c.decodeIfPresent(Int.self, forKey: .dailyWords) ?? 20
        wordProgress = try c.decodeIfPresent([String: WordProgress].self, forKey: .wordProgress) ?? [:]
        familyProgress = try c.decodeIfPresent([String: WordProgress].self, forKey: .familyProgress) ?? [:]
        readDone = try c.decodeIfPresent([Int].self, forKey: .readDone) ?? []
        listenDone = try c.decodeIfPresent([String].self, forKey: .listenDone) ?? []
        examHistory = try c.decodeIfPresent([ExamRecord].self, forKey: .examHistory) ?? []
        wrongBook = try c.decodeIfPresent([WrongItem].self, forKey: .wrongBook) ?? []
        log = try c.decodeIfPresent([String: DayLog].self, forKey: .log) ?? [:]
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        lastActive = try c.decodeIfPresent(String.self, forKey: .lastActive)
        todayTaskDone = try c.decodeIfPresent([String].self, forKey: .todayTaskDone) ?? []
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "auto"
        postponed = try c.decodeIfPresent([String: String].self, forKey: .postponed) ?? [:]
        paperDone = try c.decodeIfPresent([String].self, forKey: .paperDone) ?? []
        attempts = try c.decodeIfPresent([Attempt].self, forKey: .attempts) ?? []
    }

    /// 某一天的学习量（没有记录就是全 0，不是 nil —— 调用方不必到处判空）
    func dayLog(_ date: String) -> DayLog {
        log[date] ?? DayLog()
    }
}
