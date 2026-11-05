import Foundation

// ════════════════════════════════════════════════════════════════════
//  备考级别
// ════════════════════════════════════════════════════════════════════
//
//  级别同时出现在三个地方：进度存档（`Progress.level`）、内容标签（`lv`）、
//  界面上的选项。用散字符串写，最容易出的错是同一级别在两处拼得不一样
//  （存档写 "cet4"、标签写 "4"），表现是「选了四级却什么都看不到」。
//  收进枚举之后，拼错的下场是 `fromKey` 返回 nil（等于没选过），
//  而不是悄悄匹配不上、界面一片空白。

enum CetLevel: String, CaseIterable, Identifiable {

    case cet4 = "cet4"
    case cet6 = "cet6"
    case ky = "ky"
    case ck = "ck"
    case all = "all"

    var id: String { rawValue }

    /// 选级卡片上的标题
    var label: String {
        switch self {
        case .cet4: return "四级"
        case .cet6: return "六级"
        case .ky: return "考研"
        case .ck: return "成考"
        case .all: return "全都要"
        }
    }

    /// 拼进「距离四级还有 N 天」这类句子。`.all` 没有具体考试，用泛称。
    var examLabel: String {
        switch self {
        case .cet4: return "四级"
        case .cet6: return "六级"
        case .ky: return "考研"
        case .ck: return "成考"
        case .all: return "考试"
        }
    }

    /// 设置页那一行说明。写清「素材从哪来」，因为考研和成考都在借用四级素材。
    var note: String {
        switch self {
        case .cet4: return "四级词汇与真题，默认目标"
        case .cet6: return "六级词汇，素材沿用四级"
        case .ky: return "四级素材 + 考研词"
        case .ck: return "四级素材 + 成考专升本词"
        case .all: return "不做筛选，全部素材一起排"
        }
    }

    /// 从存档里的字符串解析。返回 nil 表示没选过或存的是非法值，
    /// 调用方要当成「必须让用户重新选一次」，不能默默兜底成四级。
    static func fromKey(_ raw: String?) -> CetLevel? {
        guard let raw else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return CetLevel(rawValue: key)
    }

    /// 这个级别要不要收下这条内容。
    ///
    /// `lv` 可以是逗号分隔的多个标签（`both,ky` = 两级共有、又在考研词表里）。
    /// 必须拆开逐段比：加了第二个标签之后，`lv == "both"` 对 `both,ky` 恒假，
    /// 四级池会静悄悄少掉 1865 个词，而界面上看不出任何异常。
    /// 空标签视为未打标签，所有具体级别都收，这样老素材在分级上线后不会变成空列表。
    func accepts(_ lv: String?) -> Bool {
        let tags = (lv ?? "")
            .lowercased()
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let untagged = tags.contains("")
        let has: (String) -> Bool = { tags.contains($0) }

        switch self {
        case .all:
            return true
        case .cet4:
            return untagged || has("cet4") || has("both")
        case .cet6:
            // 刻意不收 ky：考研词里有一批超纲的六级词，混进六级池会打乱切片节奏。
            return untagged || has("cet6") || has("both")
        case .ky:
            // 考研 = 四级素材 + 考研词。只收 ky 的话听力 / 真题页会全空，今日任务直接卡死。
            return untagged || has("cet4") || has("both") || has("ky")
        case .ck:
            // 成考同理：素材先用四级的撑住流水线，词表另走 ck_words.json。
            return untagged || has("cet4") || has("both") || has("ck")
        }
    }
}
