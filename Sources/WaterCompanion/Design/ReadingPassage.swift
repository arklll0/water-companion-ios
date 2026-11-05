import SwiftUI
import Foundation

// ════════════════════════════════════════════════════════════════════
//  文章正文统一排版（对齐 Android 2026-10-30 的 Reading.bodyStyle()）
// ════════════════════════════════════════════════════════════════════
//
//  之前 iOS 没有统一文章组件：每页各自 `Text(长串).appBody()`，段距全靠页面级
//  `VStack(spacing:)` 顺带产生的 4/8/12/16/24，全部小于行高，长文在手机上就是一整块字墙。
//  这里把「文章正文」的排版收口到一个组件。
//
//  ★ 命名说明：规格里写的是 `enum Reading`，但 `Models/Content.swift:150` 已经有
//    顶层 `struct Reading`（阅读 DTO）。Swift 同模块不允许两个同名顶层类型
//    （invalid redeclaration，CI 必挂），所以命名空间取 `ReadingBody`，DTO 一个字不动。
//
//  ## 近似对齐（有意这么选，别换成 UIKit 桥接）
//  Android 是 16sp / 行高 26sp / 段距 28dp；iOS 这边保留 SwiftUI 的
//  `.lineSpacing(6)`：16pt 系统字体默认行高约 20pt，20 + 6 ≈ 26pt。
//  这是**近似**，与 Android 的 sp/dp 不会像素级一致。
//  不引入 NSParagraphStyle / UIViewRepresentable：本机没有 Mac/Xcode 无法验证
//  UIKit 桥接，而且写死行高会丢掉 Dynamic Type 的整体缩放能力。
//
//  ## 中文不二次切段
//  讲义 `LectureBlock.s`（最长 16 651 字 / 197 块）、汉译英原文、中文解析是中文，
//  `(?<=[.!?])\s+` 的匹配数为 0；硬按 320 字切会把 `LazyVStack` 的子 View 数量翻几倍。
//  中文分支只统一字号 / 行高 / 块距，不切 320、不插 U+2002。
//
//  ## 填空横线
//  `_{2,}` 只上色加粗，绝不 `replacingOccurrences` —— 横线长度本身就是「这个空有多长」的信息。
//  `NSRegularExpression` 给出的 NSRange 经 `Range(nsRange, in: text)` 转成 `String.Index`，
//  避免中文 / emoji 下用整数下标切片错位。
//  ⚠️ `Text(AttributedString)` 上再叠 `.font()` 对已设 font 的 run 不生效，
//     所以字号（以及由字号决定的行高）必须写进 `AttributeContainer`。
//     段距由组件内部 `VStack(spacing:)` 管理，不改页面级 VStack 的全局值。

/// 文章正文的排版参数 + 纯函数。
enum ReadingBody {

    /// 正文 16pt
    static let bodySize: CGFloat = 16

    /// 行距 +6（16pt 默认行高 ≈20，20+6≈26，近似对齐 Android 26sp 行高）
    static let lineSpacing: CGFloat = 6

    /// 段距 28。★ 硬规则：段距 ≥ 行高，用 assert 把这条约束写进代码里。
    static let paragraphGap: CGFloat = {
        let gap = Space.paragraphSpacing
        assert(gap >= bodySize + lineSpacing, "文章段距必须不小于行高")
        return gap
    }()

    /// 每个排版段的目标字符数（与 Android `PARAGRAPH_BUDGET` 一致）。
    static let paragraphBudget = 320

    /// 句末标点后的空白（只认 `. ! ?` 后面确实跟着空白的地方）。
    private static let sentenceEnd = "(?<=[.!?])\\s+"

    /// 两个以上下划线 = 填空横线。
    private static let blankRun = "_{2,}"

    // MARK: - 判定

    /// 中文判定：出现中文句末标点，或 CJK 占比 > 20%。
    /// 中文分支不切 320、不插 U+2002。
    static func isChinese(_ text: String) -> Bool {
        if text.contains(where: { "。！？".contains($0) }) {
            return true
        }
        let meaningful = text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        guard !meaningful.isEmpty else { return false }
        let cjk = meaningful.filter {
            $0.value >= 0x4E00 && $0.value <= 0x9FFF
        }.count
        return Double(cjk) / Double(meaningful.count) > 0.2
    }

    // MARK: - 分段

    /// 单串正文的分段（纯函数）。
    ///
    /// 英文：① 尊重原空行分段（单个换行只当一个空格）；② 没有空行时按
    /// `(?<=[.!?])\s+` 切句、按 320 字预算合并成段、句间插 U+2002（en space）。
    /// 中文：整串一个元素返回，不切 320、不插 U+2002。
    static func splitReadingParagraphs(_ raw: String) -> [String] {
        let norm = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !norm.isEmpty else { return [] }

        // 中文：讲义 / 汉译英原文 / 中文解析，绝不按 320 字二次切段。
        if isChinese(norm) { return [norm] }

        // ① 有原始空行就尊重原分段
        let hardBreaks = splitByPattern("\\n\\s*\\n", in: norm)
            .map {
                $0.replacingOccurrences(of: "\\s*\\n\\s*", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        if hardBreaks.count > 1 {
            return hardBreaks.map { sentenceGap($0) }
        }

        // ② 没有空行：按句切 + 320 字预算合并
        let flat = norm
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sentences = splitByPattern(sentenceEnd, in: flat)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard sentences.count > 1 else { return [flat] }

        var out: [String] = []
        var current = ""
        for sentence in sentences {
            if !current.isEmpty { current += "\u{2002}" }
            current += sentence
            if current.utf16.count >= paragraphBudget {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// 句末空白换成 en space（U+2002），让句子边界比词间空格略宽。
    static func sentenceGap(_ text: String) -> String {
        text.replacingOccurrences(of: sentenceEnd, with: "\u{2002}", options: .regularExpression)
    }

    /// 正则切分辅助：把 NSRange 经 `Range(_, in:)` 转成 `String.Index`，返回被切开各段。
    private static func splitByPattern(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: full)
        var parts: [String] = []
        var cursor = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            parts.append(String(text[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }
        parts.append(String(text[cursor..<text.endIndex]))
        return parts
    }

    // MARK: - 样式

    /// `_{2,}` 上色加粗（只设 `foregroundColor` + 加粗字体，不替换任何字符）。
    /// 基础字号 / 颜色一并写进 `AttributeContainer`：`Text(AttributedString)` 上叠
    /// `.font()` 对已设 font 的 run 不生效，行高也由这个 font 决定。
    static func styled(_ text: String) -> AttributedString {
        var base = AttributeContainer()
        base.font = Typography.body
        base.foregroundColor = Theme.Colors.textPrimary

        var blank = AttributeContainer()
        blank.font = Typography.bodyEmph
        blank.foregroundColor = Theme.Colors.primary

        var result = AttributedString()
        guard let regex = try? NSRegularExpression(pattern: blankRun) else {
            return AttributedString(text, attributes: base)
        }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: full) {
            guard let range = Range(match.range, in: text) else { continue }
            if cursor < range.lowerBound {
                result += AttributedString(String(text[cursor..<range.lowerBound]), attributes: base)
            }
            result += AttributedString(String(text[range]), attributes: blank)
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            result += AttributedString(String(text[cursor..<text.endIndex]), attributes: base)
        }
        return result
    }

    /// 已分段数组的展示文本：英文补句间 U+2002，中文原样（不插）。
    static func displayText(_ paragraph: String) -> String {
        isChinese(paragraph) ? paragraph : sentenceGap(paragraph)
    }
}

// MARK: - Views

/// 单串正文：走 `splitReadingParagraphs` 切分后逐段排版。
struct ReadingPassage: View {

    let text: String

    private var paragraphs: [String] {
        ReadingBody.splitReadingParagraphs(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ReadingBody.paragraphGap) {
            ForEach(paragraphs.indices, id: \.self) { index in
                Text(ReadingBody.styled(paragraphs[index]))
                    .lineSpacing(ReadingBody.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 已分段数组正文：**不猜分段**，只套样式，段距由组件内部 `VStack(spacing: 28)` 管理。
/// 可选的 `readAloud` 让 QuizView 保留原来逐段的「朗读本段」按钮。
/// `insertSentenceGaps` 默认开启（英文段内补 U+2002，与 Android 一致）；讲义这类
/// 中英混排的块传 false，只统一字号 / 行高 / 块距，一个字符都不改。
struct ReadingParagraphs: View {

    let paragraphs: [String]
    var readAloud: ((String) -> Void)?
    var insertSentenceGaps: Bool

    init(
        _ paragraphs: [String],
        readAloud: ((String) -> Void)? = nil,
        insertSentenceGaps: Bool = true
    ) {
        self.paragraphs = paragraphs
        self.readAloud = readAloud
        self.insertSentenceGaps = insertSentenceGaps
    }

    private func display(_ paragraph: String) -> String {
        insertSentenceGaps ? ReadingBody.displayText(paragraph) : paragraph
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ReadingBody.paragraphGap) {
            ForEach(paragraphs.indices, id: \.self) { index in
                let paragraph = paragraphs[index]
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(ReadingBody.styled(display(paragraph)))
                        .lineSpacing(ReadingBody.lineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                    if let readAloud {
                        SoundChip("朗读本段") { readAloud(paragraph) }
                    }
                }
            }
        }
    }
}
