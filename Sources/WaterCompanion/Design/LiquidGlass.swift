import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  液态玻璃（Liquid Glass）
// ════════════════════════════════════════════════════════════════════
//
//  ## 为什么是双路实现
//
//  苹果的原生玻璃是 `glassEffect(_:in:)`，要 iOS 26 SDK 才有。本机构建走
//  GitHub Actions，用的是 Xcode 16.4（iOS 18.5 SDK），**那个符号根本不存在**，
//  写在 `#available` 里也照样编译失败 —— `#available` 只管运行期，不管符号在不在。
//
//  所以两路：
//   · `#if compiler(>=6.2)` 且 `#available(iOS 26.0, *)` → 系统 `glassEffect`
//     （Xcode 26 起 Swift 版本是 6.2，用编译器版本当 SDK 版本的替身）
//   · 否则 → `GlassFallback`：`ultraThinMaterial` + 顶光渐变 + 湿边高光 + 单层投影
//
//  两路的**几何和排版完全一致**，只有"玻璃"的实现不同，所以切换时不会跳版。
//
//  ## HIG 怎么说的（照做，不是照抄视觉）
//
//  1. **玻璃属于导航层，不属于内容层。** 苹果的原话是 standard components
//     （tab bar / toolbar / 浮动控件）用玻璃，自定义组件可以跟着用；
//     但内容卡片不用 —— 玻璃会跟后面的内容抢注意力，还会把正文对比度拉低。
//     所以这里只给「底栏」「听力页底部操作板」用，句子卡、题目卡、设置列表一律不动。
//  2. **不要玻璃叠玻璃。** 玻璃面板里面再放玻璃块，边缘会互相咬出脏边。
//     面板内部的胶囊/小按钮继续用 `surfaceMuted` 实色。
//  3. **文字对比度优先。** 玻璃上的文字一律走 `textPrimary` / `textSecondary`，
//     不用半透明白字 —— 后面滚过一张白卡片时，白字会直接消失。
//  4. **尊重「降低透明度」。** 开了这个辅助功能就必须换成不透明底，
//     否则"能看见背后内容"从装饰变成了障碍。`GlassFallback` 里处理了。
//
//  ## 手写近似为什么这么叠
//
//  真实玻璃的四件事，按重要性排：
//   ① 背景被模糊（`ultraThinMaterial` 负责，同时带来轻微的饱和度提升）
//   ② 上沿亮、下沿暗：光从上面来（顶部白色渐变）
//   ③ 边缘有一圈"湿"的高光（1pt 的白色渐变描边，左上最亮）
//   ④ 落在下面的一层柔和投影（说明它浮在内容之上）
//  少任何一条都会从"玻璃"退化成"半透明色块"；四条都在，小尺寸下就很难分辨真假。

// MARK: - 对外入口

extension View {

    /// 把视图做成一块液态玻璃。
    /// - Parameters:
    ///   - shape: 玻璃的形状（胶囊 / 圆角矩形），必须和内容的实际轮廓一致，
    ///     否则描边会露在内容外面一圈。
    ///   - tint: 染色。用来表达"当前选中的那个"或"主操作"，不要用来装饰。
    ///   - interactive: 是否需要随按压产生形变（只有按钮给 true）。
    @ViewBuilder
    func liquidGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else if interactive {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.glassEffect(in: shape)
            }
        } else {
            self.modifier(GlassFallback(shape: shape, tint: tint))
        }
        #else
        self.modifier(GlassFallback(shape: shape, tint: tint))
        #endif
    }
}

// MARK: - 手写近似

private struct GlassFallback<S: Shape>: ViewModifier {

    let shape: S
    let tint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { scheme == .dark }

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    // 关了透明度就别玩虚的：实底 + 一条描边，信息层级一个字都不少。
                    shape.fill(Theme.Colors.surface)
                } else {
                    glass
                }
            }
            .overlay { rim }
            // 先合成再投影：不合成的话，投影会按里面每一层分别投，边缘出现重影。
            .compositingGroup()
            .shadow(
                color: Color.black.opacity(isDark ? 0.45 : 0.13),
                radius: 18,
                x: 0,
                y: 7
            )
    }

    /// ① 模糊底 + ② 顶光 + 染色
    private var glass: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)

            // 顶光：浅色下白得更明显（纸/玻璃），深色下收敛，否则整块发灰。
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isDark ? 0.16 : 0.34),
                        Color.white.opacity(isDark ? 0.02 : 0.06)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            if let tint {
                shape.fill(tint.opacity(isDark ? 0.26 : 0.16))
            }
        }
    }

    /// ③ 湿边高光：左上最亮，右下回一点亮，中间几乎是透明的
    private var rim: some View {
        shape.strokeBorder(
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(isDark ? 0.55 : 0.90), location: 0.0),
                    .init(color: Color.white.opacity(isDark ? 0.06 : 0.16), location: 0.45),
                    .init(color: Color.white.opacity(isDark ? 0.28 : 0.52), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1
        )
    }
}

// MARK: - 玻璃面板

/// 一块带内边距的玻璃面板。底栏、听力页底部操作板都用它，
/// 保证两处的圆角、内距、投影是同一套数字。
struct GlassPanel<Content: View>: View {

    private let radius: CGFloat
    private let tint: Color?
    private let horizontal: CGFloat
    private let vertical: CGFloat
    private let content: Content

    init(
        radius: CGFloat = Radius.card,
        tint: Color? = nil,
        horizontal: CGFloat = Space.lg,
        vertical: CGFloat = Space.md,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.tint = tint
        self.horizontal = horizontal
        self.vertical = vertical
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: radius, style: .continuous),
                tint: tint
            )
    }
}

// MARK: - 按压反馈

/// 玻璃控件的按压：轻微内缩 + 提亮。
/// 幅度必须小 —— 玻璃本身已经很"软"，再叠大幅缩放会像果冻。
struct LiquidPressStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
