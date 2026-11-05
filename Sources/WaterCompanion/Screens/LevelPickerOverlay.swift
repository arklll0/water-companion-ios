import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  首次启动选级
// ════════════════════════════════════════════════════════════════════
//
//  为什么做成覆盖层而不是一个路由页：
//  这个面板没有「跳过」这条路，选完才能进 App。放进 NavigationStack 会
//  自动带上返回按钮与侧滑返回，等于给了用户一个「先不选」的出口；
//  而级别没定下来时，单词 / 阅读 / 真题都不知道该取哪一池。
//
//  它挂在 RootView 的 NavigationStack 外层 overlay 上，所以底栏也会被盖住：
//  只盖内容区的话，用户能一边看到「先选一个目标」一边切页签。
//
//  这里只负责把选项摆出来，选中后把 key 交回上层。落盘由 `ProgressStore` 做，
//  视图不持有自己的工作副本，避免出现「界面选了、存档没变」。

struct LevelPickerOverlay: View {

    /// 传 `CetLevel.rawValue`。上层直接落盘，本视图不持状态。
    let onPick: (String) -> Void

    var body: some View {
        ZStack {
            // 背景自己铺满整屏（AppBackground 内部已处理安全区），
            // 下面的正文仍然留在安全区内，标题不会被状态栏或灵动岛压住。
            AppBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    header
                    options
                }
                .padding(.horizontal, Space.pageEdge)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xxl)
            }
        }
    }

    // MARK: - 标题

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("先选一个备考目标")
                .font(Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("之后随时能在「我的」里改，进度不会丢。")
                .font(Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 选项

    private var options: some View {
        VStack(spacing: Space.itemGap) {
            // 顺序走 allCases：四级 / 六级 / 考研 / 成考 / 全都要。
            // 手写一遍数组的话，以后枚举加一档这里就会漏掉，而漏掉的选项
            // 不会报错，只会在界面上「少一个」。
            ForEach(CetLevel.allCases) { level in
                Button {
                    onPick(level.rawValue)
                } label: {
                    AppCard {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(level.label)
                                .font(Typography.captionEmph)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Text(level.note)
                                .font(Typography.micro)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // 整卡可点：只让文字响应的话，卡片右侧的留白会变成死区，
                    // 用户点在空白处会以为按钮坏了。
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
