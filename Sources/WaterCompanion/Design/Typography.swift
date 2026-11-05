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
//  不用自定义字体：系统字体在中文下的字重与字形最稳。
//  ⚠️ `Font.system(size:)` 是**固定字号**，并不跟随「设置 → 显示与亮度 → 文字大小」；
//     要跟随 Dynamic Type 得改用 `.body` 这类文本样式或 `@ScaledMetric`。
//     这里全站固定字号是有意选择：字阶表里的数值就是设计稿数值，
//     不让各页各自缩放，免得同一套间距在不同字号下错位。
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

    /// 文章正文（近似对齐 Android `Reading.bodyStyle()`：16/400 + 行距 6 ≈ 26 行高）。
    /// 数值今天与 `appBody()` 一致，但它是**文章长文专用**的独立旋钮：
    /// `appBody()` 还被首页说明 / 表格 / 选项 / 词典短句等约 25 处复用，改它会一处误伤全部；
    /// 文章排版要调就调这里（长文优先走 `ReadingPassage` / `ReadingParagraphs` 组件）。
    func appArticleBody(_ color: Color = Theme.Colors.textPrimary) -> some View {
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
