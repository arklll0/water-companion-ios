import Foundation

// ════════════════════════════════════════════════════════════════════
//  成考精讲讲义（lectures.json）
// ════════════════════════════════════════════════════════════════════
//
//  结构是「章 > 课 > 块」。块只有四种：h 标题 / p 段落 / l 列表 / t 表格。
//  没有单独的「难度」「时长」字段，所以时长按字数估：
//  一分钟 300 字，向上取整，最少 1 分钟。这个数字只用来在列表上给个心理预期，
//  不参与任何调度计算，所以估算得粗一点没关系。
//
//  所有字段都走 decodeIfPresent：讲义是外部生成的，某一课少一个 note
//  不该让整个讲义页变成空白。

struct LectureFile: Decodable {

    var schema: Int
    var chapters: [LectureChapter]

    var isEmpty: Bool { chapters.isEmpty }

    var lessonCount: Int {
        chapters.reduce(0) { $0 + $1.lessons.count }
    }

    init(schema: Int = 1, chapters: [LectureChapter] = []) {
        self.schema = schema
        self.chapters = chapters
    }

    enum CodingKeys: String, CodingKey {
        case schema, chapters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        chapters = try c.decodeIfPresent([LectureChapter].self, forKey: .chapters) ?? []
    }
}

struct LectureChapter: Decodable, Identifiable {

    var id: String
    var title: String
    var note: String
    var lessons: [LectureLesson]

    init(id: String = "", title: String = "", note: String = "", lessons: [LectureLesson] = []) {
        self.id = id
        self.title = title
        self.note = note
        self.lessons = lessons
    }

    enum CodingKeys: String, CodingKey {
        case id, title, note, lessons
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        lessons = try c.decodeIfPresent([LectureLesson].self, forKey: .lessons) ?? []
    }
}

struct LectureLesson: Decodable, Identifiable {

    var id: String
    var title: String
    /// 原始文档名（如「成人高考（专升本）-英语-教材精讲班-第一章.doc」），只用于溯源展示
    var src: String
    var blocks: [LectureBlock]

    /// 正文总字数：段落、列表项、表格单元格都算。
    /// 用 String.count 数的是人眼看到的字符，而不是 UTF-8 字节。
    var charCount: Int {
        blocks.reduce(0) { total, block in
            var n = total + block.s.count
            for item in block.items {
                n += item.count
            }
            for row in block.rows {
                for cell in row {
                    n += cell.count
                }
            }
            return n
        }
    }

    /// 预估阅读时长（分钟）。向上取整，至少 1 分钟。
    var minutes: Int {
        max(1, (charCount + 299) / 300)
    }

    init(id: String = "", title: String = "", src: String = "", blocks: [LectureBlock] = []) {
        self.id = id
        self.title = title
        self.src = src
        self.blocks = blocks
    }

    enum CodingKeys: String, CodingKey {
        case id, title, src, blocks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        src = try c.decodeIfPresent(String.self, forKey: .src) ?? ""
        blocks = try c.decodeIfPresent([LectureBlock].self, forKey: .blocks) ?? []
    }
}

struct LectureBlock: Decodable {

    /// "h" 标题 / "p" 段落 / "l" 列表 / "t" 表格。缺省当段落处理，
    /// 因为未知识别码画不出来，当普通文字至少还能读。
    var k: String
    var s: String
    var items: [String]
    var rows: [[String]]

    init(k: String = "p", s: String = "", items: [String] = [], rows: [[String]] = []) {
        self.k = k
        self.s = s
        self.items = items
        self.rows = rows
    }

    enum CodingKeys: String, CodingKey {
        case k, s, items, rows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        k = try c.decodeIfPresent(String.self, forKey: .k) ?? "p"
        s = try c.decodeIfPresent(String.self, forKey: .s) ?? ""
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
        rows = try c.decodeIfPresent([[String]].self, forKey: .rows) ?? []
    }
}
