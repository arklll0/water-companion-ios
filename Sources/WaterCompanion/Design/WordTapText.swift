import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  可点词的句子
// ════════════════════════════════════════════════════════════════════
//
//  SwiftUI 的 `Text` 没法给「其中一个词」单独挂手势 —— `AttributedString`
//  也没有可点击区间（那是 UIKit 的 `NSAttributedString.link` 才有的东西）。
//  所以这里把句子拆成词、用自写的 `FlowLayout` 重排一遍，一个词一个 `Button`。
//
//  ## 为什么按词排，不按字符排
//
//  按字符排会在词中间断行（"listen / ing"），英文读者一眼就看得出是拼的。
//  按词排的换行位置和人手排版一致；代价是超长单词会整块换行，可以接受。
//
//  ## 标点跟着词走
//
//  "listening," 拆成词 `listening` + 后缀 `,`，后缀挂在同一个 item 上：
//  既不参与点击（点逗号不该弹释义），也不单独占一格（否则会出现 "word ,"）。
//
//  ## 间距为什么用固定 4
//
//  17pt 的 SF 里一个空格约 4.3pt。App 里只有 16 / 17 两档正文，都用 4 就够准；
//  把空格写进 `Text` 反而有风险 —— 末尾空格在测宽时可能被吞掉，词会粘在一起。

struct WordTapText: View {

    let text: String
    var font: Font = Typography.titleSmall
    var color: Color = Theme.Colors.textPrimary

    @Environment(ContentStore.self) private var content
    @Environment(AudioPlayer.self) private var audio

    @State private var picked: PickedWord?

    /// 一个可点的词。`id` 用序号：同一句里可能出现两个 `the`，
    /// 拿词形当 id 会让 `ForEach` 认成同一个视图。
    private struct PickedWord: Identifiable {
        let id: Int
        let word: String
    }

    private struct Piece: Identifiable {
        let id: Int
        /// 词形（可点的那部分）。全是标点时为空串 → 当普通文字画。
        let word: String
        let prefix: String
        var suffix: String
    }

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: Typography.lineSpacing) {
            ForEach(WordTapText.pieces(of: text)) { piece in
                if piece.word.isEmpty {
                    Self.styled(piece.prefix + piece.suffix, font: font, color: color)
                } else {
                    Button {
                        picked = PickedWord(id: piece.id, word: piece.word)
                    } label: {
                        Self.styled(piece.prefix + piece.word + piece.suffix, font: font, color: color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $picked) { target in
            lookupSheet(target.word)
        }
    }

    private static func styled(_ text: String, font: Font, color: Color) -> Text {
        Text(text).font(font).foregroundStyle(color)
    }

    // MARK: - 释义卡

    private func lookupSheet(_ raw: String) -> some View {
        // 查词统一走词库：词库里只有原形，所以先按原样、再按小写试两次。
        // 这两次都不中就当「词库没收」，不硬猜词形变化（guess 出来的东西更容易错）。
        let word = content.word(raw) ?? content.word(raw.lowercased())

        return VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(raw)
                    .font(Typography.display)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let word, !word.p.isEmpty {
                    Text(word.p)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                Button {
                    speak(raw)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.primary)
                        .frame(width: Touch.min, height: Touch.min)
                        .background(Theme.Colors.primarySoft, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let word, !word.m.isEmpty {
                Text(word.m)
                    .font(Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !word.t.isEmpty {
                    Text(word.t)
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if !word.e.isEmpty {
                    Divider()
                    Text(word.e)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !word.ec.isEmpty {
                        Text(word.ec)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("词库里没有 \(raw)，只放个音，意思是自己查。")
                    .appCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Space.xl)
        .padding(.top, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(260), .medium])
        .presentationDragIndicator(.visible)
    }

    /// 发音先走离线包，没有再退系统 TTS —— 和听力页同一条路。
    private func speak(_ text: String) {
        if audio.play(text: text) { return }
        SpeechFallback.shared.play(text: text) { _ in }
    }

    // MARK: - 切词

    private static func pieces(of text: String) -> [Piece] {
        var out: [Piece] = []
        var index = 0

        for raw in text.split(separator: " ", omittingEmptySubsequences: false) {
            let chars = Array(raw)

            if chars.isEmpty {
                // 连续空格：并进上一块的尾巴，不单独占一格（否则一行里会多出一条缝）
                if !out.isEmpty { out[out.count - 1].suffix += " " }
                continue
            }

            var head = 0
            while head < chars.count, !chars[head].isLetter, !chars[head].isNumber { head += 1 }
            var tail = chars.count
            while tail > head, !chars[tail - 1].isLetter, !chars[tail - 1].isNumber { tail -= 1 }

            out.append(
                Piece(
                    id: index,
                    word: head < tail ? String(chars[head..<tail]) : "",
                    prefix: String(chars[0..<head]),
                    suffix: String(chars[tail...])
                )
            )
            index += 1
        }

        return out
    }
}

// ════════════════════════════════════════════════════════════════════
//  按行流式排布
// ════════════════════════════════════════════════════════════════════
//
//  SwiftUI 的 `HStack` 不换行、`LazyVGrid` 又要求等宽格子，逐词排版只能自己算。
//  iOS 16 起 `Layout` 协议就是为这种场景开的：给一份子视图清单，
//  自己决定每块放哪儿。
//
//  只做最基本的左对齐逐行排布：放不下就换行，行高取该行最高的那一块。
//  不做基线对齐 —— 整句都是同一档字号，各块高度本来就一样。

struct FlowLayout: Layout {

    var spacing: CGFloat
    var lineSpacing: CGFloat

    private struct Line {
        var range: Range<Int>
        var height: CGFloat
        var width: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = arrange(subviews: subviews, maxWidth: maxWidth)

        let height = lines.reduce(0) { $0 + $1.height }
            + lineSpacing * CGFloat(max(lines.count - 1, 0))
        let width = lines.map(\.width).max() ?? 0

        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let lines = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for line in lines {
            var x = bounds.minX
            for i in line.range {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var start = 0
        var x: CGFloat = 0
        var height: CGFloat = 0

        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)

            if x > 0, x + size.width > maxWidth {
                lines.append(
                    Line(range: start..<i, height: height, width: x - spacing)
                )
                start = i
                x = 0
                height = 0
            }

            x += size.width + spacing
            height = max(height, size.height)
        }

        if start < subviews.count {
            lines.append(
                Line(range: start..<subviews.count, height: height, width: max(x - spacing, 0))
            )
        }

        return lines
    }
}
