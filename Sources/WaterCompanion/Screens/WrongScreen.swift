import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  错题集
// ════════════════════════════════════════════════════════════════════
//
//  阅读、真题、模考、翻译四处答错的内容都会落到这里（`Progress.wrongBook`）。
//  这一页只做三件事：看、删、去重做。
//
//  ## 为什么用 `List` + `.swipeActions`
//
//  「一列可删除的条目」在 iOS 上就是这个形状。自己摆一个「删除」按钮在每行里，
//  既占地方又容易误触；左滑删除是用户本来就有的肌肉记忆，
//  而且系统会自动处理「滑到底直接删」的手势与无障碍操作。
//  删除是不可撤销的，所以不做全滑删除之外的花样。
//
//  ## 「重做」为什么不定位原题
//
//  错题里存的 `ref` 指向阅读下标或「卷-题」，而每日切片是按天变化的 ——
//  今天推给你的那篇可能根本不是这条错题的原文。强行「跳过去」的结果是
//  用户看到的是另一道题，会以为 App 记错了。所以这里只把人送到练习页，
//  让他按当天的节奏做，错题本身留在列表里当索引。

struct WrongScreen: View {

    @Environment(ProgressStore.self) private var store

    /// 点「重做」后由 RootView 负责切到练习页（这一页不该知道外面有几个页签）
    let onRedo: () -> Void

    @State private var showClearConfirm = false

    private var wrongs: [WrongItem] { store.progress.wrongBook }

    // MARK: - 视图

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .navigationTitle("错题集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !wrongs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") {
                        showClearConfirm = true
                    }
                    .foregroundStyle(Theme.Colors.error)
                }
            }
        }
        .confirmationDialog(
            "清空错题集？",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("清空全部 \(wrongs.count) 题", role: .destructive) {
                store.clearWrong()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空之后这些题就找不回来了。")
        }
    }

    @ViewBuilder
    private var content: some View {
        if wrongs.isEmpty {
            ContentUnavailableView(
                "错题集是空的",
                systemImage: "checkmark.circle",
                description: Text("做题时错的会自动记在这里，答对的不记。")
            )
        } else {
            List {
                Section {
                    ForEach(wrongs.indices, id: \.self) { index in
                        row(wrongs[index])
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    store.removeWrong(at: index)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                } footer: {
                    Text("左滑可以删掉一条。重做只把你送到练习页，不定位原题 —— 错题和当天的切片不一定对得上。")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - 一行

    private func row(_ item: WrongItem) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title(item))
                .font(Typography.bodyEmph)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !item.from.isEmpty {
                Text(item.from)
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            // 只有选择题才谈得上「选了哪个」。翻译、词组这两类没有选项，
            // 硬写「你选了 未作答」只会让人困惑。
            if item.type == "read" || item.type == "paper" || item.type == "exam" {
                Text("你选了 \(Self.letter(item.chosen))，正确 \(Self.letter(item.right))")
                    .font(Typography.micro)
                    .foregroundStyle(
                        item.chosen == item.right ? Theme.Colors.primary : Theme.Colors.error
                    )
            }

            if !item.cn.isEmpty {
                Text(item.cn)
                    .appCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }

            if item.type == "read" || item.type == "paper" {
                Button {
                    onRedo()
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("重做")
                            .font(Typography.micro)
                    }
                    .foregroundStyle(Theme.Colors.primary)
                    .padding(.horizontal, Space.md)
                    .frame(height: 32)
                    .background(Theme.Colors.primarySoft, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, Space.xs)
            }
        }
        .padding(.vertical, Space.xs)
    }

    /// 题干可能为空（词组类只存了原文），兜底用 `en`。
    private func title(_ item: WrongItem) -> String {
        let base = item.q.isEmpty ? item.en : item.q
        if base.isEmpty { return "（这条没有题干）" }
        if base.count <= 70 { return base }
        return String(base.prefix(70)) + "…"
    }

    /// 0 → "A"；-1 表示当时没作答。
    private static func letter(_ index: Int) -> String {
        if index < 0 { return "未作答" }
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        guard index < letters.count else { return "\(index + 1)" }
        return letters[index]
    }
}
