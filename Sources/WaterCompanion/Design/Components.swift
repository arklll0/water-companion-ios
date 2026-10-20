import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  通用组件
// ════════════════════════════════════════════════════════════════════
//
//  只放「任何页面都可能用到、且不带业务语义」的东西。
//  带业务的组件（任务卡、单词卡）留在各自页面里 —— 它们只出现一次，
//  抽出来反而要把参数摊开一大串。

// MARK: - 页面背景

/// 冷灰底 + 一层极淡的品牌绿渐变。
/// 纯白/纯灰底会「没有东西可衬」，卡片压上去失去层次；留一点色，层级才立得起来。
struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.Colors.background
            LinearGradient(
                colors: [
                    Theme.Colors.primary.opacity(0.07),
                    Theme.Colors.primary.opacity(0.0)
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - 卡片

/// 一块内容面。所有卡片走同一个圆角与同一套内边距。
struct AppCard<Content: View>: View {

    private let padding: CGFloat
    private let background: Color
    private let showsBorder: Bool
    private let cornerRadius: CGFloat
    private let content: Content

    init(
        padding: CGFloat = Space.cardPadding,
        background: Color = Theme.Colors.surface,
        showsBorder: Bool = true,
        cornerRadius: CGFloat = Radius.card,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.background = background
        self.showsBorder = showsBorder
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.Colors.separator, lineWidth: 1)
                }
            }
    }
}

// MARK: - 区块标题

/// 「今天的任务」+ 一行说明。
/// 说明永远是「点一下就能开始」这种**动作提示**，不是重复标题。
struct SectionHeader: View {

    let title: String
    var subtitle: String?
    var trailing: String?

    init(_ title: String, subtitle: String? = nil, trailing: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).appTitle()
                if let subtitle {
                    Text(subtitle).appCaption()
                }
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).appCaption()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 按钮

/// 主按钮：实心品牌色胶囊，高度 44（触控目标下限）。
struct PrimaryButton: View {

    let title: String
    var icon: String?
    var enabled: Bool
    let action: () -> Void

    init(_ title: String, icon: String? = nil, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(Typography.captionEmph)
            }
            .foregroundStyle(Theme.Colors.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: Touch.min)
            .background(
                Theme.Colors.primary.opacity(enabled ? 1.0 : 0.35),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// 次按钮：描边胶囊。
struct SecondaryButton: View {

    let title: String
    var icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(Typography.captionEmph)
            }
            .foregroundStyle(Theme.Colors.primary)
            .frame(maxWidth: .infinity)
            .frame(height: Touch.min)
            .background(Theme.Colors.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Theme.Colors.primary.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 文字按钮：只用于「撤销 / 去设置 / 退出」这类轻量动作。
struct QuietButton: View {

    let title: String
    var icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(Typography.captionEmph)
            }
            .foregroundStyle(Theme.Colors.primary)
            .padding(.horizontal, Space.sm)
            .frame(minHeight: Touch.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 芯片
//
//  三选一这类「互斥选项」一律用系统的 `Picker` + `.pickerStyle(.segmented)`，
//  不自己做胶囊芯片 —— 系统控件自带选中态、动态字号与无障碍语义。
//  这里原先的 `PillChip` 因为没有真实使用场景，已移除。

// MARK: - 数据小格

/// 一个数字 + 一行标签。用于「今日已学 / 待复习 / 已掌握」。
struct StatBox: View {

    let value: String
    let label: String
    var tint: Color = Theme.Colors.primary

    init(_ value: String, _ label: String, tint: Color = Theme.Colors.primary) {
        self.value = value
        self.label = label
        self.tint = tint
    }

    var body: some View {
        VStack(spacing: Space.xs) {
            Text(value)
                .font(Typography.dataSmall)
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(Typography.micro)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 滚动页容器

/// 非列表型页面（Hero / 翻卡 / 结算卡）的统一容器。
///
/// 列表型页面用系统的 `List` + `.listStyle(.insetGrouped)`，不走这里 ——
/// 只有「一张张设计过的内容面」才需要自己控边距。
struct FormPage<Content: View>: View {

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.section) {
                content
            }
            .padding(.horizontal, Space.pageEdge)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
        }
    }
}

// MARK: - 空态
//
//  刻意**不**提供自定义空态组件：空态一律用系统的 `ContentUnavailableView`
//  （iOS 17）。它的图标尺寸、标题字重、说明间距都是系统调好的，
//  自己再画一个只会比系统更像「另一个 App」。

// MARK: - 分隔线
//
//  不自己画：系统 `Divider()` 已经处理了深浅色、粗细与横向内边距，
//  而且在 `List` 里会替换成原生行分隔线。

// MARK: - 进度环
//
//  环是「一个数字的画法」，不是列表部件，所以自己用 `Circle().trim` 画。
//  其余可点、可滚、可弹的东西一律用系统控件。

/// 环形进度。页面上唯一的大数字，所以只给它品牌色。
struct RingProgress: View {

    let value: Double
    var size: CGFloat
    var lineWidth: CGFloat

    init(value: Double, size: CGFloat = 96, lineWidth: CGFloat = 9) {
        self.value = value
        self.size = size
        self.lineWidth = lineWidth
    }

    private var clamped: Double {
        min(max(value, 0.0), 1.0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.ringTrack, lineWidth: lineWidth)
            Circle()
                // clamped 是 Double，`Shape.trim` 要 CGFloat：显式转一次，
                // 不依赖 Double→CGFloat 的隐式转换（SE-0307）在泛型上下文里是否生效。
                .trim(from: 0, to: CGFloat(clamped <= 0 ? 0.0001 : clamped))
                .stroke(
                    Theme.Colors.primary,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((clamped * 100).rounded()))%")
                    .font(Typography.dataSmall)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.primary)
                Text("今天")
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日进度 \(Int((clamped * 100).rounded()))%")
    }
}

// MARK: - 评分按钮

/// 四级评分的单个按键：主标题 + 一行「下一次什么时候再见」。
struct RateButton: View {

    let title: String
    let subtitle: String
    var highlighted: Bool = false
    let action: () -> Void

    init(_ title: String, subtitle: String, highlighted: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.highlighted = highlighted
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(Typography.captionEmph)
                    .foregroundStyle(highlighted ? Theme.Colors.onPrimary : Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Typography.micro)
                    .foregroundStyle(highlighted ? Theme.Colors.onPrimary.opacity(0.8) : Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                highlighted ? Theme.Colors.primary : Theme.Colors.surface,
                in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
            )
            .overlay {
                if !highlighted {
                    RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                        .strokeBorder(Theme.Colors.separator, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 图标 + 文字的胶囊（发音按钮）

struct SoundChip: View {

    let title: String
    var enabled: Bool
    let action: () -> Void

    init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(title).font(Typography.micro)
            }
            .foregroundStyle(enabled ? Theme.Colors.primary : Theme.Colors.idle)
            .padding(.horizontal, Space.md)
            .frame(height: 34)
            .background(Theme.Colors.primarySoft.opacity(enabled ? 1.0 : 0.35), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
