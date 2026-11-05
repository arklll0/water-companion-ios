import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  词族页（锚词辐射法）
// ════════════════════════════════════════════════════════════════════
//
//  记一个锚词 + 一个动作画面，前缀就是方向，整族词一次串起来：
//  press = 压 → ex-（向外）= express 表达；im-（向内）= impress 留下印象。
//
//  交互上刻意做成「先看 clue、再翻面」：直接给「compress = 压缩」只是又背一遍
//  词表；先让用户从 `com- 一起` 猜一次，才调动了主动回忆 —— 这是词族法生效的关键。
//
//  SRS key = "族序号:单词"（Srs.familyKey），与单词表分开存，
//  因为同一个词在不同族里出现时提示线索不同，混在一起会互相覆盖。
//
//  版式：族列表用系统 `List` + `.insetGrouped`；族内学习是设计过的内容面，自己排。

struct FamilyScreen: View {

    @Environment(ProgressStore.self) private var store
    @Environment(ContentStore.self) private var content
    @Environment(AudioPlayer.self) private var audio

    @State private var familyIndex: Int = -1
    @State private var memberIndex: Int = 0
    @State private var flipped: Bool = false
    @State private var finished: Bool = false

    // MARK: 派生状态

    private var families: [Family] { content.families }
    private var progress: Progress { store.progress }
    private var dueCount: Int { Srs.dueFamilies(progress.familyProgress).count }
    private var learnedCount: Int { progress.familyProgress.count }
    private var masteredCount: Int { Srs.mastered(progress.familyProgress) }

    private var currentFamily: Family? {
        guard familyIndex >= 0, familyIndex < families.count else { return nil }
        return families[familyIndex]
    }

    var body: some View {
        ZStack {
            AppBackground()
            page
        }
        .navigationTitle("词族")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 三态

    @ViewBuilder
    private var page: some View {
        if finished, let family = currentFamily {
            FormPage { finishPanel(family) }
        } else if let family = currentFamily {
            FormPage { familyPanel(family) }
        } else {
            listPage
        }
    }

    @ViewBuilder
    private var listPage: some View {
        if families.isEmpty {
            ContentUnavailableView(
                "词族库还没加载出来",
                systemImage: "tray",
                description: Text("请重新打开 App 再试一次")
            )
        } else {
            familyList
        }
    }

    // MARK: - 族列表（系统分组列表）

    private var familyList: some View {
        List {
            Section {
                VStack(spacing: Space.md) {
                    HStack(spacing: Space.sm) {
                        StatBox("\(dueCount)", "待复习")
                        StatBox("\(learnedCount)", "已学词")
                        StatBox("\(masteredCount)", "已掌握")
                    }
                    PrimaryButton("随机复习一组", icon: "shuffle") {
                        openRandomFamily()
                    }
                }
                .padding(.vertical, Space.xs)
            }

            Section {
                ForEach(families.indices, id: \.self) { i in
                    familyRow(i)
                }
            } header: {
                HStack {
                    Text("\(families.count) 个锚词族")
                    Spacer()
                    Text("点一个开始")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } footer: {
                Text("例：press = 压 → ex- 向外 = express 表达；im- 向内 = impress 留下印象")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func familyRow(_ i: Int) -> some View {
        let family = families[i]
        return Button {
            open(i)
        } label: {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(family.anchor)
                        .font(Typography.bodyEmph)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(family.cn)
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Space.sm)
                Text("\(family.members.count) 个词")
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.idle)
            }
            .frame(minHeight: Touch.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 族内学习

    private func familyPanel(_ family: Family) -> some View {
        VStack(spacing: Space.itemGap) {
            HStack(spacing: Space.sm) {
                Text("\(memberIndex + 1) / \(family.members.count)")
                    .font(Typography.captionEmph)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(family.anchor) · \(family.cn)")
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
                QuietButton("退出") {
                    closeFamily()
                }
            }

            anchorCard(family)

            if let member = currentMember(family) {
                memberCard(family: family, member: member)

                if flipped {
                    ratingGrid(family: family, member: member)
                } else {
                    Text("先按 clue 猜一次，再翻面。")
                        .appCaption()
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func anchorCard(_ family: Family) -> some View {
        AppCard(padding: Space.md, background: Theme.Colors.banner, showsBorder: false) {
            VStack(spacing: Space.xs) {
                Text(family.anchor)
                    .font(Typography.dataSmall)
                    .foregroundStyle(Theme.Colors.primary)
                Text(family.cn)
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
                if !family.action.isEmpty {
                    Text("🤚 \(family.action)")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Space.xs)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func memberCard(family: Family, member: FamilyMember) -> some View {
        let hasAudio = audio.hasAudio(for: member.word)

        return AppCard(padding: Space.lg) {
            VStack(spacing: Space.sm) {
                if flipped {
                    Text(member.word)
                        .font(Typography.display)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(member.meaning)
                        .font(Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                    SoundChip("跟读", enabled: hasAudio) {
                        audio.play(text: member.word)
                    }
                    if !family.sentence.isEmpty {
                        Text(family.sentence)
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Space.xs)
                    }
                } else {
                    Text(member.clue)
                        .font(Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("这个词是？")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    SoundChip("听一遍", enabled: hasAudio) {
                        audio.play(text: member.word)
                    }
                    Button {
                        withAnimation(.snappy) { flipped = true }
                    } label: {
                        Text("点一下看答案")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.Colors.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: Touch.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func ratingGrid(family: Family, member: FamilyMember) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.sm),
                GridItem(.flexible(), spacing: Space.sm)
            ],
            spacing: Space.sm
        ) {
            RateButton("忘了", subtitle: "待会再来") { rate(1, family: family, member: member) }
            RateButton("模糊", subtitle: "明天复习") { rate(2, family: family, member: member) }
            RateButton("认识", subtitle: "3 天后再见") { rate(3, family: family, member: member) }
            RateButton("很熟", subtitle: "7 天后再见") { rate(4, family: family, member: member) }
        }
    }

    // MARK: - 完成

    private func finishPanel(_ family: Family) -> some View {
        AppCard {
            VStack(spacing: Space.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Theme.Colors.primary)
                    .symbolEffect(.bounce, value: finished)
                Text("这一族记完了")
                    .font(Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("你刚刚过了 \(family.members.count) 个词。")
                    .appCaption()
                    .multilineTextAlignment(.center)

                HStack(spacing: Space.sm) {
                    PrimaryButton("再记一族", icon: "arrow.clockwise") {
                        if familyIndex >= 0 { open(familyIndex) }
                    }
                    SecondaryButton("回列表") {
                        closeFamily()
                    }
                }
                .padding(.top, Space.sm)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 状态迁移

    private func currentMember(_ family: Family) -> FamilyMember? {
        guard memberIndex >= 0, memberIndex < family.members.count else { return nil }
        return family.members[memberIndex]
    }

    private func open(_ i: Int) {
        guard i >= 0, i < families.count else { return }
        familyIndex = i
        memberIndex = 0
        flipped = false
        finished = false
    }

    private func openRandomFamily() {
        guard !families.isEmpty else { return }
        open(Int.random(in: 0..<families.count))
    }

    private func closeFamily() {
        familyIndex = -1
        memberIndex = 0
        flipped = false
        finished = false
    }

    private func rate(_ rating: Int, family: Family, member: FamilyMember) {
        store.recordFamilyRating(
            familyIndex: familyIndex,
            word: member.word,
            rating: rating
        )

        // 忘了不重排队列：族内只有 6 个词，重排会让「进度 N/6」来回跳。
        // 当天再见一次由 SRS 的 due = 今天 保证（词会在复习里再出现）。
        flipped = false
        memberIndex += 1

        if memberIndex >= family.members.count {
            finished = true
        }
    }
}
