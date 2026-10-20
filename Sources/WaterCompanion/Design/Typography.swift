import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  字阶：只有四级 + 单词卡专用的一档
// ════════════════════════════════════════════════════════════════════
//
//  | 级别 | 字号 / 字重 | 用在哪 |
//  |---|---|---|
//  | 数据强调 | 24~28 / 700 | 「25%」「还有 57 天」这类一眼要看到的数字 |
//  | 标题     | 17~20 / 600 | 卡片主标题、区块标题 |
//  | 正文     | 16 / 400    | 说明文字、段落、句子（行距 +6） |
//  | 辅助     | 12~14 / 400 | 次要信息、标签、单位 |
//
//  不用自定义字体：系统字体在中文下的字重与字形最稳，也自动跟随
//  「设置 → 显示与亮度 → 文字大小」，用户调大字号时整页会跟着放大 —— 这是应该的。
//
//  数字为什么开 `.monospacedDigit()`：默认字宽下 1 比 8 窄，倒计时从 84 跳到 83
//  时旁边的文字会左右抖一下。等宽数字只让变化的那一位在动。
//  只加在「数据强调」级 —— 正文开等宽会让中文排版变松。

enum Typography {

    /// 单词卡正面那个大词（超高一级，不与上面四级抢层级）
    static let display = Font.system(size: 34, weight: .bold)

    /// 数据强调（大）：28 / 700
    static let dataLarge = Font.system(size: 28, weight: .bold)

    /// 数据强调（小）：24 / 700
    static let dataSmall = Font.system(size: 24, weight: .bold)

    /// 标题：20 / 600
    static let title = Font.system(size: 20, weight: .semibold)

    /// 小标题：17 / 600
    static let titleSmall = Font.system(size: 17, weight: .semibold)

    /// 正文：16 / 400
    static let body = Font.system(size: 16, weight: .regular)

    /// 正文强调：16 / 500
    static let bodyEmph = Font.system(size: 16, weight: .medium)

    /// 辅助：14 / 400
    static let caption = Font.system(size: 14, weight: .regular)

    /// 辅助强调：14 / 600
    static let captionEmph = Font.system(size: 14, weight: .semibold)

    /// 微：12 / 500
    static let micro = Font.system(size: 12, weight: .medium)

    /// 正文行距。中文长段落按 1.4 倍排会「挤成一饼」，统一 +6。
    static let lineSpacing: CGFloat = 6

    /// 辅助文字行距
    static let captionLineSpacing: CGFloat = 3
}

// MARK: - 常用文字样式

extension View {

    /// 正文
    func appBody(_ color: Color = Theme.Colors.textPrimary) -> some View {
        self.font(Typography.body)
            .foregroundStyle(color)
            .lineSpacing(Typography.lineSpacing)
    }

    /// 辅助文字
    func appCaption(_ color: Color = Theme.Colors.textSecondary) -> some View {
        self.font(Typography.caption)
            .foregroundStyle(color)
            .lineSpacing(Typography.captionLineSpacing)
    }

    /// 区块标题
    func appTitle() -> some View {
        self.font(Typography.title).foregroundStyle(Theme.Colors.textPrimary)
    }
}
