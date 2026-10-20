import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  根容器：五个页签 + 二级页导航
// ════════════════════════════════════════════════════════════════════
//
//  底栏是**自己画的悬浮胶囊**，不是 `TabView`：
//  系统 TabView 在 iOS 17 上没法做成「浮在内容之上、圆角胶囊、毛玻璃」的样子，
//  而这一条是品牌观感的重点。代价是要自己管页签状态 —— 就一个 enum，不值一提。
//
//  导航：一个 `NavigationStack` 包住整屏。切页签时清空 `path`，
//  因为「单词 → 词族 → 切到今日 → 再切回单词」不该停在词族页里 ——
//  用户点的是页签，期待的是回到那一页的顶层。

// MARK: - 页签

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case words
    case listen
    case practice
    case me

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "今日"
        case .words: return "单词"
        case .listen: return "听力"
        case .practice: return "练习"
        case .me: return "我的"
        }
    }

    /// 图标一律用 SF Symbols —— 不引图片、不手绘 Path。
    /// 系统里有现成的就用系统语义最贴近的那一个：
    /// 房子 = 今日、字在书里 = 单词、耳朵 = 听力、笔 + 清单 = 练习、人像 = 我的。
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .words: return "character.book.closed.fill"
        case .listen: return "ear.fill"
        case .practice: return "pencil.and.list.clipboard"
        case .me: return "person.crop.circle.fill"
        }
    }
}

// MARK: - 二级页

/// 二级页路由。用 `NavigationLink(value:)` 推入，不在页面里自己管状态 ——
/// 这样「我的 → 统计 → 错题」能一路返回，也自动带上系统的返回手势与返回按钮。
enum AppRoute: Hashable {
    case family
    case stats
    case wrong
    case translate
}

// MARK: - 根视图

struct RootView: View {

    @Environment(ProgressStore.self) private var store

    @State private var tab: AppTab = .home
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                TabBar(selection: $tab)
                    .padding(.horizontal, Space.pageEdge)
                    .padding(.top, Space.sm)
                    .padding(.bottom, Space.xs)
            }
            .background(AppBackground())
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .family:
                    FamilyScreen()
                case .stats:
                    StatsScreen()
                case .wrong:
                    // 「重做」只切到练习页的阅读分段，不定位原题 ——
                    // 错题里的 ref 指向的那道题可能已经不在今天的切片里了，
                    // 强行定位会做出一堆「跳过去却是另一道题」的错觉。
                    WrongScreen(onRedo: {
                        tab = .practice
                        if !path.isEmpty {
                            path.removeLast(path.count)
                        }
                    })
                case .translate:
                    TranslateScreen()
                }
            }
        }
        .task {
            // 首次启动写入开始日期、维护连续打卡。幂等，重复调用没有副作用。
            store.touchStreak()
        }
        .onChange(of: tab) { _, _ in
            if !path.isEmpty {
                path.removeLast(path.count)
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch tab {
        case .home:
            HomeScreen(onNavigate: handleNavigate)
        case .words:
            WordsScreen(onGoFamily: { path.append(AppRoute.family) })
        case .listen:
            ListenScreen()
        case .practice:
            PracticeScreen()
        case .me:
            MeScreen()
        }
    }

    /// 首页的四个任务卡按字符串路由跳页签，与 Android 版 `TASKS` 的 `go` 字段同构。
    private func handleNavigate(_ target: String) {
        switch target {
        case "words":
            tab = .words
        case "listen":
            tab = .listen
        case "practice", "read":
            tab = .practice
        default:
            tab = .me
        }
    }
}

// MARK: - 悬浮胶囊底栏

private struct TabBar: View {

    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { item in
                Button {
                    // 系统动效（iOS 17 `.snappy`），不手调 spring 参数
                    withAnimation(.snappy) {
                        selection = item
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 22)
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(
                        selection == item ? Theme.Colors.primary : Theme.Colors.idle
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: Touch.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(.horizontal, Space.xs)
        .padding(.vertical, Space.xs)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Theme.Colors.separator.opacity(0.7), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 5)
    }
}
