import SwiftUI
import UIKit

// ════════════════════════════════════════════════════════════════════
//  共用答题区
// ════════════════════════════════════════════════════════════════════
//
//  阅读、真题、模考三处用的是同一种小题：原文段落 + 题干 + 四个选项 + 一句解析。
//  三处都自己写一遍的话，最麻烦的不是重复，而是**不一致** ——
//  「点一下锁定」「选错标红」「解析什么时候出现」这三条只要有一样在不同页面里
//  表现不同，用户就会觉得这 App 有点飘。
//
//  所以这里的规则写死，调用方只负责给数据：
//    ① 点一个选项就锁定，不能改答案（选项本身不再响应点击，但**不置灰** ——
//       置灰会把刚标好的绿色一起压暗，反而看不清对了没有）；
//    ② 锁定后：正确选项标品牌绿，选了错的再把它标红，解析卡在下方展开；
//    ③ 每次点选给一次轻触反馈。答题是高频动作，重震动会烦人。
//
//  `chosen` 是**这个视图内部**的状态，不是外部传进来的：
//  一张卷子从头做到尾时，切到下一题要能自动回到「未作答」的样子。
//  外部通过 `.onChange(of: question)` 这条兜底重置（见 body），
//  这样即使 SwiftUI 复用了同一个视图身份，也不会把上一题的答案带过来。

struct QuizView: View {

    /// 题干
    let question: String
    /// 选项（A / B / C / D 的顺序就是数组顺序）
    let options: [String]
    /// 正确选项的下标
    let correctIndex: Int
    /// 解析。空串表示这道题没有解析 —— 那就只标对错，不弹空卡片。
    let explanation: String
    /// 原文段落。阅读题、部分真题有；没有就传空数组。
    var passage: [String] = []
    /// 逐段朗读回调。传 nil 表示这个场景不需要朗读（比如模考中）。
    var readAloud: ((String) -> Void)?
    /// 作答回调，参数是用户选中的下标。答错时的错题登记交给调用方 ——
    /// 只有调用方知道这道题的来源（哪篇阅读 / 哪套卷子 / 第几题）。
    let onAnswer: (Int) -> Void

    @State private var chosen: Int = -1

    init(
        question: String,
        options: [String],
        correctIndex: Int,
        explanation: String,
        passage: [String] = [],
        readAloud: ((String) -> Void)? = nil,
        onAnswer: @escaping (Int) -> Void
    ) {
        self.question = question
        self.options = options
        self.correctIndex = correctIndex
        self.explanation = explanation
        self.passage = passage
        self.readAloud = readAloud
        self.onAnswer = onAnswer
    }

    private var answered: Bool { chosen >= 0 }

    var body: some View {
        VStack(spacing: Space.md) {
            if !passage.isEmpty {
                passageCard
            }
            questionCard
            if answered && !explanation.isEmpty {
                explanationCard
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: chosen)
        .onChange(of: question) { _, _ in
            // 换了一道题（同一套卷子的下一题 / 下一篇阅读）就把作答状态清掉。
            // 视图身份被复用时不会重新走 init，只有这条能保证「新题是空白的」。
            chosen = -1
        }
    }

    // MARK: - 原文

    private var passageCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(passage.indices, id: \.self) { i in
                    let paragraph = passage[i]
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(paragraph)
                            .appBody()
                            .fixedSize(horizontal: false, vertical: true)

                        // 离线包是按「段」合成的，所以朗读也给到段的粒度：
                        // 想复读哪段点哪段，不必为了重听一句而从头放整篇。
                        if let readAloud {
                            SoundChip("朗读本段") {
                                readAloud(paragraph)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 题干 + 选项

    private var questionCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Space.md) {
                Text(question)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Space.sm) {
                    ForEach(options.indices, id: \.self) { index in
                        optionRow(index, options[index])
                    }
                }
            }
        }
    }

    private func optionRow(_ index: Int, _ text: String) -> some View {
        let isCorrect = answered && index == correctIndex
        let isWrong = answered && index == chosen && index != correctIndex

        return Button {
            choose(index)
        } label: {
            HStack(alignment: .top, spacing: Space.sm) {
                Text("\(Self.letter(index)).")
                    .font(Typography.bodyEmph)
                    .foregroundStyle(tint(isCorrect: isCorrect, isWrong: isWrong))
                    .frame(minWidth: 20, alignment: .leading)

                Text(text)
                    .font(Typography.body)
                    .foregroundStyle(tint(isCorrect: isCorrect, isWrong: isWrong))
                    .lineSpacing(Typography.captionLineSpacing)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Colors.primary)
                        .transition(.scale.combined(with: .opacity))
                } else if isWrong {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Colors.error)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.md)
            .frame(minHeight: Touch.min)
            .background(background(isCorrect: isCorrect, isWrong: isWrong), in: rowShape)
            .overlay {
                rowShape.strokeBorder(border(isCorrect: isCorrect, isWrong: isWrong), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 不给 `.disabled`：系统会在禁用态整体压暗，
        // 刚标好的绿/红会一起变灰，等于把唯一的信息抹掉。
        // 锁定逻辑放在 `choose` 里判断，视觉保持原样。
        .accessibilityLabel("\(Self.letter(index))，\(text)")
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
    }

    private func background(isCorrect: Bool, isWrong: Bool) -> Color {
        if isCorrect { return Theme.Colors.primarySoft }
        if isWrong { return Theme.Colors.error.opacity(0.12) }
        return Theme.Colors.surface
    }

    private func border(isCorrect: Bool, isWrong: Bool) -> Color {
        if isCorrect { return Theme.Colors.primary }
        if isWrong { return Theme.Colors.error }
        return Theme.Colors.separator
    }

    private func tint(isCorrect: Bool, isWrong: Bool) -> Color {
        if isCorrect { return Theme.Colors.primary }
        if isWrong { return Theme.Colors.error }
        return Theme.Colors.textPrimary
    }

    // MARK: - 解析

    private var explanationCard: some View {
        AppCard(background: Theme.Colors.banner, showsBorder: false) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.primary)
                    Text("解析")
                        .font(Typography.captionEmph)
                        .foregroundStyle(Theme.Colors.primary)
                    Spacer(minLength: 0)
                    Text(chosen == correctIndex ? "答对了" : "正确答案 \(Self.letter(correctIndex))")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text(explanation)
                    .appBody()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 交互

    private func choose(_ index: Int) {
        guard !answered else { return }
        guard index >= 0, index < options.count else { return }

        chosen = index
        Self.haptic()
        onAnswer(index)
    }

    /// 轻触反馈。每次点选一次 —— 答题是高频动作，重震会让人不想再点。
    private static func haptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    /// 0 → "A"，1 → "B" …（超过 8 个选项退回数字，正常题库不会有）
    private static let letters: [String] = ["A", "B", "C", "D", "E", "F", "G", "H"]

    private static func letter(_ index: Int) -> String {
        guard index >= 0, index < letters.count else { return "\(index + 1)" }
        return letters[index]
    }
}
