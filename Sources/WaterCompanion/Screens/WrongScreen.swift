import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  错题集
// ════════════════════════════════════════════════════════════════════
//
//  阅读、真题、模考、翻译四处答错的内容都会落到这里（`Progress.wrongBook`），
//  听力句子的三档自评落在上面一段（`Progress.listenRating`）。
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
//
//  ## 听力为什么不走 `wrongBook`
//
//  句子没有「选项」也没有「正确答案」，塞进 `wrongBook` 会让那一堆字段
//  （chosen / right / q / ref）全部落空，`row(_:)` 里一半的分支都用不上。
//  自评本来就是一张独立的表，直接按它筛更干净；顺手还能显示「下次什么时候再来」。

struct WrongScreen: View {

    @Environment(ProgressStore.self) private var store
    @Environment(ContentStore.self) private var content
    @Environment(AudioPlayer.self) private var audio

    /// 点「重做」后由 RootView 负责切到练习页（这一页不该知道外面有几个页签）
    let onRedo: () -> Void

    @State private var showClearConfirm = false

    private var wrongs: [WrongItem] { store.progress.wrongBook }

    /// 听力错句：只留 1（没听懂）和 2（模糊）。
    /// 评 3 的不删记录、只是不在这里出现 —— 想回看「哪句当初没听懂」还能查到。
    private struct ListenRow: Identifiable {
        let id: String
        let item: ListenItem
        let score: Int
        let nextDue: String
    }

    private var listenRows: [ListenRow] {
        let ratings = store.progress.listenRating
        let due = store.progress.listenDue

        var byId: [String: ListenItem] = [:]
        for item in content.allListening { byId[item.id] = item }

        return ratings
            .filter { $0.value <= 2 }
            .sorted { lhs, rhs in
                // 没听懂的排前面，同档按 id 稳定排序（Dictionary 本身没有顺序）
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value < rhs.value
            }
            .compactMap { entry in
                guard let item = byId[entry.key] else { return nil }
                return ListenRow(
                    id: entry.key,
                    item: item,
                    score: entry.value,
                    nextDue: due[entry.key] ?? ""
                )
            }
    }

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
            Text("清空之后这些题就找不回来了。听力句子不在这份清单里。")
        }
    }

    @ViewBuilder
    private var content: some View {
        if wrongs.isEmpty && listenRows.isEmpty {
            ContentUnavailableView(
                "错题集是空的",
                systemImage: "checkmark.circle",
                description: Text("做题时错的、听力里没听懂的，都会自动记在这里。")
            )
        } else {
            List {
                if !listenRows.isEmpty {
                    listenSection
                }
                if !wrongs.isEmpty {
                    wrongSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - 听力句子

    private var listenSection: some View {
        Section {
            ForEach(listenRows) { row in
                listenRow(row)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            // 标成「听懂」＝ 从这一档挪走，同时把下次复训推到十天后。
                            store.rateListen(id: row.id, rating: 3)
                        } label: {
                            Label("已听懂", systemImage: "checkmark")
                        }
                        .tint(Theme.Colors.primary)
                    }
            }
        } header: {
            Text("听力句子 · \(listenRows.count) 句")
        } footer: {
            Text("没听懂和模糊的都会收在这里。左滑标成「已听懂」，它就挪走了，十天后再兜一次。")
        }
    }

    private func listenRow(_ row: ListenRow) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(row.item.en)
                .font(Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)

            if !row.item.cn.isEmpty {
                Text(row.item.cn)
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: Space.sm) {
                Text(row.score == 1 ? "没听懂" : "模糊")
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.error)

                if !row.nextDue.isEmpty {
                    Text("下次 \(row.nextDue)")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                // 单句播放，不接管听力页的队列：错题集是翻查用的，
                // 不是第二个播放器，把队列概念带进来只会让两边的游标打架。
                Button {
                    _ = audio.play(text: row.item.en)
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("重听")
                            .font(Typography.micro)
                    }
                    .foregroundStyle(Theme.Colors.primary)
                    .padding(.horizontal, Space.sm)
                    .frame(height: 28)
                    .background(Theme.Colors.primarySoft, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Space.xs)
    }

    // MARK: - 题目错题

    private var wrongSection: some View {
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
