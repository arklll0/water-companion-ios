import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  练习页：阅读 / 真题 / 模考
// ════════════════════════════════════════════════════════════════════
//
//  三块共用同一个答题区（`QuizView`），差别只在「今天做哪一份」怎么来：
//    · 阅读：`DailyPlan` 按「第几天 + 当天单词量」切出一篇
//    · 真题：同样按天切，但切的是「拍平后的题目流」里的一道
//    · 模考：整套随机抽，见 `ExamScreen`
//
//  ## 为什么「今天这一份」是主视图，全部素材是折叠区
//
//  一屏摊开 90 篇阅读 / 若干套卷子，用户得先做一次「选哪个」的决策 ——
//  而这一步最容易让人关掉 App。把「今天该做的那一份」直接摆出来，
//  决策成本就降到零；想自己挑的时候再展开，给的是同一个入口，不冲突。
//
//  ## 答题即完成
//
//  答错也算完成：错题已经单独进了错题集，再让今天的卡片停在「未完成」
//  只会让人不想再打开它。但**答对也要记** —— 正确率的分母全靠 attempts，
//  只记错题的话「做了 20 道错 3 道」和「做了 5 道错 3 道」长得一模一样。
//
//  ## 编号必须与存档一致
//
//  `readDone` 存的是**全局下标**（`readings` 数组里的位置），
//  `paperDone` 存的是 `PaperItemRef.id`（"卷序号-题序号"）。
//  这两套编号是网站导出的老存档也在用的，不能改成「今天这几篇里的第几篇」。

struct PracticeScreen: View {

    @Environment(ProgressStore.self) private var store
    @Environment(ContentStore.self) private var content
    @Environment(AudioPlayer.self) private var audio

    /// 三个板块
    private enum Board: String, CaseIterable, Identifiable {
        case reading
        case paper
        case exam

        var id: String { rawValue }

        var title: String {
            switch self {
            case .reading: return "阅读"
            case .paper: return "真题"
            case .exam: return "模考"
            }
        }
    }

    /// 真题有两条进入路径，去向不同：
    /// 从「今天这一题」进来时「下一个」在今天的题目流里走；
    /// 从「某一套卷子」进来时在卷内往下走。用一个枚举把两者分开，
    /// 比拿两个可能互相矛盾的 Int 状态去猜要稳。
    private enum PaperRoute: Equatable {
        case daily(Int)
        case paper(paper: Int, item: Int)
    }

    @State private var board: Board = .reading

    @State private var readingIndex: Int?
    @State private var readingFlow: [Int] = []
    @State private var showAllReadings = false

    @State private var paperRoute: PaperRoute?
    @State private var showAllPapers = false

    /// 模考是否正在进行（交给 `ExamScreen` 同步）。进行中要把板块切换器藏起来 ——
    /// 计时考试最怕手滑点到别处。
    @State private var examRunning = false

    /// 当前这道题作答了没有。`QuizView` 的锁定状态在它自己内部，
    /// 这里只记「能不能放行到下一题」。
    @State private var answered = false

    // MARK: - 派生状态

    private var progress: Progress { store.progress }
    private var dayNumber: Int { DailyPlan.dayNumber(startDate: progress.startDate) }

    /// 正在做题 / 考试时收起板块切换器
    private var showsBoardPicker: Bool {
        readingIndex == nil && paperRoute == nil && !examRunning
    }

    // MARK: - 视图

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                if showsBoardPicker {
                    Picker("板块", selection: $board) {
                        ForEach(Board.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, Space.pageEdge)
                    .padding(.bottom, Space.md)
                }

                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("练习")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private var page: some View {
        switch board {
        case .reading:
            if let index = readingIndex, content.readings.indices.contains(index) {
                readingDetail(index)
            } else {
                readingList
            }
        case .paper:
            paperDetailOrList
        case .exam:
            ExamScreen(isSessionActive: $examRunning)
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 阅读
    // ════════════════════════════════════════════════════════════════

    /// 今天该读哪几篇（全局下标）
    private var todayReadings: [Int] {
        DailyPlan.slice(
            content.readingOrder,
            DailyPlan.dayIndex(startDate: progress.startDate),
            DailyPlan.readCount(progress.dailyWords)
        )
    }

    private var readingDoneToday: Int {
        todayReadings.filter { progress.readDone.contains($0) }.count
    }

    private var readingList: some View {
        ScrollView {
            VStack(spacing: Space.section) {
                todayPanel(
                    title: readingPanelTitle,
                    done: readingDoneToday,
                    total: todayReadings.count,
                    hint: "篇数跟当天单词量联动：每 20 个词 1 篇。明天会自动换成新的。"
                )

                VStack(spacing: Space.itemGap) {
                    SectionHeader("今天这一份", subtitle: "点一下开始")

                    if content.readings.isEmpty {
                        ContentUnavailableView(
                            "暂无阅读素材",
                            systemImage: "doc.text",
                            description: Text("检查一下 Resources/Content/reading.json。")
                        )
                    } else {
                        ForEach(todayReadings, id: \.self) { index in
                            readingCard(
                                index,
                                leading: "今天第 \(positionInToday(index)) 篇"
                            )
                        }
                    }
                }

                allReadingsSection
            }
            .padding(.horizontal, Space.pageEdge)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
        }
    }

    private var readingPanelTitle: String {
        if todayReadings.isEmpty { return "第 \(dayNumber) 天 · 暂无阅读素材" }
        if readingDoneToday == 0 { return "第 \(dayNumber) 天 · 今天要读 \(todayReadings.count) 篇" }
        if readingDoneToday < todayReadings.count {
            return "第 \(dayNumber) 天 · 还剩 \(todayReadings.count - readingDoneToday) 篇"
        }
        return "第 \(dayNumber) 天 · 今天的阅读读完了"
    }

    private func positionInToday(_ index: Int) -> Int {
        (todayReadings.firstIndex(of: index) ?? 0) + 1
    }

    private func readingCard(_ index: Int, leading: String) -> some View {
        let reading = content.readings[index]
        let done = progress.readDone.contains(index)

        return AppCard(
            padding: Space.lg,
            background: done ? Theme.Colors.doneCard : Theme.Colors.surface,
            showsBorder: !done
        ) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text(leading)
                        .font(Typography.micro)
                        .foregroundStyle(done ? Theme.Colors.doneText.opacity(0.8) : Theme.Colors.textSecondary)
                    Spacer(minLength: 0)
                    if done {
                        Text("已读")
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.doneText)
                    }
                }

                Text(reading.tag.isEmpty ? "未命名短文" : reading.tag)
                    .font(Typography.titleSmall)
                    .foregroundStyle(done ? Theme.Colors.doneText : Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(reading.levelLabel) · 约 \(reading.minutes) 分钟 · \(reading.o.count) 个选项")
                    .appCaption(done ? Theme.Colors.doneText.opacity(0.75) : Theme.Colors.textSecondary)

                HStack(spacing: Space.sm) {
                    Button {
                        openReading(index, flow: todayReadings)
                    } label: {
                        Text(done ? "再做一遍" : "开始阅读")
                            .font(Typography.captionEmph)
                            .foregroundStyle(done ? Theme.Colors.doneText : Theme.Colors.primary)
                            .padding(.horizontal, Space.md)
                            .frame(height: 34)
                            .background(
                                done ? Theme.Colors.doneEdge.opacity(0.5) : Theme.Colors.primarySoft,
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(.top, Space.xs)
            }
        }
    }

    private var allReadingsSection: some View {
        VStack(spacing: Space.itemGap) {
            SecondaryButton(
                showAllReadings
                    ? "收起全部素材"
                    : "展开全部素材（\(content.readings.count) 篇）",
                icon: showAllReadings ? "chevron.up" : "chevron.down"
            ) {
                withAnimation(.snappy) { showAllReadings.toggle() }
            }

            if !showAllReadings {
                Text("想自己挑一篇再展开。每天推荐的那几篇在上面。")
                    .appCaption()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xs)
            }

            if showAllReadings {
                VStack(spacing: Space.itemGap) {
                    SectionHeader("全部素材", subtitle: "按难度排序", trailing: "共 \(content.readings.count) 篇")

                    ForEach(content.readings.indices, id: \.self) { index in
                        readingCard(index, leading: "第 \(index + 1) 篇")
                    }
                }
                .padding(.top, Space.xs)
            }
        }
    }

    private func readingDetail(_ index: Int) -> some View {
        let reading = content.readings[index]

        return ScrollView {
            VStack(spacing: Space.itemGap) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(reading.tag.isEmpty ? "第 \(index + 1) 篇" : reading.tag)
                        .font(Typography.titleSmall)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("约 \(reading.minutes) 分钟")
                        .font(Typography.micro)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer(minLength: 0)
                    QuietButton("退出", icon: "xmark") {
                        closeReading()
                    }
                }

                QuizView(
                    question: reading.q,
                    options: reading.o,
                    correctIndex: reading.a,
                    explanation: reading.ex,
                    passage: reading.p,
                    readAloud: { text in _ = audio.togglePlay(text: text) }
                ) { chosen in
                    answered = true
                    recordReadingAnswer(index, chosen)
                }
                .id(index)

                if answered, nextReading != nil {
                    SecondaryButton("下一篇", icon: "arrow.right") {
                        advanceReading()
                    }
                }
            }
            .padding(.horizontal, Space.pageEdge)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
        }
    }

    private var nextReading: Int? {
        guard let index = readingIndex,
              let pos = readingFlow.firstIndex(of: index),
              pos + 1 < readingFlow.count else { return nil }
        return readingFlow[pos + 1]
    }

    private func openReading(_ index: Int, flow: [Int]) {
        answered = false
        readingFlow = flow
        readingIndex = index
    }

    private func closeReading() {
        answered = false
        readingIndex = nil
        readingFlow = []
    }

    private func advanceReading() {
        guard let next = nextReading else { return }
        answered = false
        readingIndex = next
    }

    private func recordReadingAnswer(_ index: Int, _ chosen: Int) {
        guard content.readings.indices.contains(index) else { return }
        let reading = content.readings[index]
        let ok = chosen == reading.a

        store.recordAnswer(
            kind: "read",
            ok: ok,
            wrong: ok ? nil : WrongItem(
                q: reading.q,
                chosen: chosen,
                right: reading.a,
                from: "阅读",
                type: "read",
                ref: "\(index)"
            )
        )
        store.markReadDone(index: index)
        store.bump("read")
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 真题
    // ════════════════════════════════════════════════════════════════

    private var todayPapers: [PaperItemRef] {
        DailyPlan.slice(
            content.paperItemRefs,
            DailyPlan.dayIndex(startDate: progress.startDate),
            DailyPlan.paperCount(progress.dailyWords)
        )
    }

    private var paperDoneToday: Int {
        todayPapers.filter { progress.paperDone.contains($0.id) }.count
    }

    @ViewBuilder
    private var paperDetailOrList: some View {
        if let route = paperRoute {
            switch route {
            case .daily(let position):
                if todayPapers.indices.contains(position) {
                    dailyPaperDetail(todayPapers[position])
                } else {
                    paperList
                }
            case .paper(let paperIndex, let itemIndex):
                if content.papers.indices.contains(paperIndex),
                   content.papers[paperIndex].items.indices.contains(itemIndex) {
                    paperItemDetail(paperIndex: paperIndex, itemIndex: itemIndex)
                } else {
                    paperList
                }
            }
        } else {
            paperList
        }
    }

    private var paperList: some View {
        ScrollView {
            VStack(spacing: Space.section) {
                todayPanel(
                    title: paperPanelTitle,
                    done: paperDoneToday,
                    total: todayPapers.count,
                    hint: "题数跟当天单词量联动：每 20 个词 1 题。明天会自动换成新的。"
                )

                VStack(spacing: Space.itemGap) {
                    SectionHeader("今天这一题", subtitle: "点一下开始")

                    if todayPapers.isEmpty {
                        ContentUnavailableView(
                            "暂无练习素材",
                            systemImage: "doc.questionmark",
                            description: Text("检查一下 Resources/Content/papers.json。")
                        )
                    } else {
                        ForEach(todayPapers) { ref in
                            dailyPaperCard(ref)
                        }
                    }
                }

                allPapersSection
            }
            .padding(.horizontal, Space.pageEdge)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
        }
    }

    private var paperPanelTitle: String {
        if todayPapers.isEmpty { return "第 \(dayNumber) 天 · 暂无练习素材" }
        if paperDoneToday == 0 { return "第 \(dayNumber) 天 · 今天要做 \(todayPapers.count) 题" }
        if paperDoneToday < todayPapers.count {
            return "第 \(dayNumber) 天 · 还剩 \(todayPapers.count - paperDoneToday) 题"
        }
        return "第 \(dayNumber) 天 · 今天的练习做完了"
    }

    private func dailyPaperCard(_ ref: PaperItemRef) -> some View {
        let done = progress.paperDone.contains(ref.id)

        return AppCard(
            padding: Space.lg,
            background: done ? Theme.Colors.doneCard : Theme.Colors.surface,
            showsBorder: !done
        ) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text(ref.label)
                        .font(Typography.micro)
                        .foregroundStyle(done ? Theme.Colors.doneText.opacity(0.8) : Theme.Colors.textSecondary)
                    Spacer(minLength: 0)
                    if done {
                        Text("已做")
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.doneText)
                    }
                }

                Text(ref.item.q.isEmpty ? "（这道题没有题干）" : ref.item.q)
                    .font(Typography.titleSmall)
                    .foregroundStyle(done ? Theme.Colors.doneText : Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(content.kindLabel(ref.item.type)) · \(ref.item.o.count) 个选项")
                    .appCaption(done ? Theme.Colors.doneText.opacity(0.75) : Theme.Colors.textSecondary)

                HStack(spacing: Space.sm) {
                    Button {
                        openDailyPaper(todayPapers.firstIndex { $0.id == ref.id } ?? 0)
                    } label: {
                        Text(done ? "再做一遍" : "开始做题")
                            .font(Typography.captionEmph)
                            .foregroundStyle(done ? Theme.Colors.doneText : Theme.Colors.primary)
                            .padding(.horizontal, Space.md)
                            .frame(height: 34)
                            .background(
                                done ? Theme.Colors.doneEdge.opacity(0.5) : Theme.Colors.primarySoft,
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(.top, Space.xs)
            }
        }
    }

    private var allPapersSection: some View {
        VStack(spacing: Space.itemGap) {
            SecondaryButton(
                showAllPapers
                    ? "收起全部套卷"
                    : "展开全部套卷（\(content.papers.count) 套）",
                icon: showAllPapers ? "chevron.up" : "chevron.down"
            ) {
                withAnimation(.snappy) { showAllPapers.toggle() }
            }

            if !showAllPapers {
                Text("想整套做、或挑某一年的卷子时再展开。")
                    .appCaption()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xs)
            }

            if showAllPapers {
                VStack(spacing: Space.itemGap) {
                    SectionHeader("全部套卷", subtitle: "从头做一整套", trailing: "共 \(content.papers.count) 套")

                    ForEach(content.papers.indices, id: \.self) { paperIndex in
                        paperCard(paperIndex)
                    }
                }
                .padding(.top, Space.xs)
            }
        }
    }

    private func paperCard(_ paperIndex: Int) -> some View {
        let paper = content.papers[paperIndex]
        let doneCount = paper.items.indices.filter {
            progress.paperDone.contains("\(paperIndex)-\($0)")
        }.count

        return AppCard {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(paper.title.isEmpty ? "第 \(paperIndex + 1) 套" : paper.title)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(paper.year) · \(paper.items.count) 题 · 已做 \(doneCount) 题")
                    .appCaption()

                HStack(spacing: Space.sm) {
                    Button {
                        openPaperItem(paperIndex: paperIndex, itemIndex: 0)
                    } label: {
                        Text("开始")
                            .font(Typography.captionEmph)
                            .foregroundStyle(Theme.Colors.primary)
                            .padding(.horizontal, Space.md)
                            .frame(height: 34)
                            .background(Theme.Colors.primarySoft, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(.top, Space.xs)
            }
        }
    }

    private func dailyPaperDetail(_ ref: PaperItemRef) -> some View {
        let position = todayPapers.firstIndex { $0.id == ref.id } ?? 0

        return ScrollView {
            VStack(spacing: Space.itemGap) {
                detailHeader(title: ref.label, trailing: "\(position + 1) / \(todayPapers.count)") {
                    closePaper()
                }

                QuizView(
                    question: ref.item.q,
                    options: ref.item.o,
                    correctIndex: ref.item.a,
                    explanation: ref.item.ex,
                    passage: ref.item.passage,
                    readAloud: { text in _ = audio.togglePlay(text: text) }
                ) { chosen in
                    answered = true
                    recordPaperAnswer(ref, chosen)
                }
                .id(ref.id)

                if answered, position + 1 < todayPapers.count {
                    SecondaryButton("下一题", icon: "arrow.right") {
                        openDailyPaper(position + 1)
                    }
                }
            }
            .padding(.horizontal, Space.pageEdge)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
        }
    }

    private func paperItemDetail(paperIndex: Int, itemIndex: Int) -> some View {
        let paper = content.papers[paperIndex]
        let item = paper.items[itemIndex]

        return ScrollView {
            VStack(spacing: Space.itemGap) {
                detailHeader(
                    title: paper.title.isEmpty ? "第 \(paperIndex + 1) 套" : paper.title,
                    trailing: "\(itemIndex + 1) / \(paper.items.count)"
                ) {
                    closePaper()
                }

                QuizView(
                    question: item.q,
                    options: item.o,
                    correctIndex: item.a,
                    explanation: item.ex,
                    passage: item.passage,
                    readAloud: { text in _ = audio.togglePlay(text: text) }
                ) { chosen in
                    answered = true
                    recordPaperAnswer(
                        paperIndex: paperIndex,
                        itemIndex: itemIndex,
                        paperTitle: paper.title,
                        item: item,
                        chosen: chosen
                    )
                }
                .id("\(paperIndex)-\(itemIndex)")

                if answered, itemIndex + 1 < paper.items.count {
                    SecondaryButton("下一题", icon: "arrow.right") {
                        openPaperItem(paperIndex: paperIndex, itemIndex: itemIndex + 1)
                    }
                }
            }
            .padding(.horizontal, Space.pageEdge)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
        }
    }

    private func detailHeader(title: String, trailing: String, onExit: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text(title)
                .font(Typography.titleSmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(trailing)
                .font(Typography.micro)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
            QuietButton("退出", icon: "xmark", action: onExit)
        }
    }

    private func openDailyPaper(_ position: Int) {
        answered = false
        paperRoute = .daily(position)
    }

    private func openPaperItem(paperIndex: Int, itemIndex: Int) {
        answered = false
        paperRoute = .paper(paper: paperIndex, item: itemIndex)
    }

    private func closePaper() {
        answered = false
        paperRoute = nil
    }

    private func recordPaperAnswer(_ ref: PaperItemRef, _ chosen: Int) {
        recordPaperAnswer(
            paperIndex: ref.paperIndex,
            itemIndex: ref.itemIndex,
            paperTitle: ref.paperTitle,
            item: ref.item,
            chosen: chosen
        )
    }

    private func recordPaperAnswer(
        paperIndex: Int,
        itemIndex: Int,
        paperTitle: String,
        item: PaperItem,
        chosen: Int
    ) {
        let ok = chosen == item.a
        let refId = "\(paperIndex)-\(itemIndex)"

        // kind 用题目自己的题型（vocab / q / cloze / match / read），不要写死成 "paper"：
        // 写死的话所有题型会被并成一类，统计页就永远只能说「你整体正确率多少」。
        store.recordAnswer(
            kind: item.type,
            ok: ok,
            wrong: ok ? nil : WrongItem(
                q: item.q,
                chosen: chosen,
                right: item.a,
                from: "真题·\(paperTitle)",
                type: "paper",
                ref: refId
            )
        )
        store.markPaperDone(id: refId)
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 公用
    // ════════════════════════════════════════════════════════════════

    /// 「今天要 N 份、已完成 M 份」+ 进度条。
    /// 用浅底无边框（banner）：这是一块**状态**，不是要操作的卡片，视觉上退后一档。
    private func todayPanel(title: String, done: Int, total: Int, hint: String) -> some View {
        let ratio = total == 0 ? 0.0 : Double(done) / Double(total)

        return AppCard(background: Theme.Colors.banner, showsBorder: false) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(title)
                        .font(Typography.titleSmall)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if total > 0 {
                        Text("\(done) / \(total)")
                            .font(Typography.captionEmph)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.primary)
                    }
                }

                ProgressView(value: ratio)
                    .tint(Theme.Colors.primary)

                Text(hint)
                    .appCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 阅读难度

private extension Reading {

    /// `level` 是英文键（easy / medium / hard），界面上要中文
    var levelLabel: String {
        switch level {
        case "easy": return "入门"
        case "medium": return "进阶"
        case "hard": return "冲刺"
        default: return "常规"
        }
    }
}

// MARK: - 题型名

extension ContentStore {

    /// 题型键 → 中文名。
    ///
    /// 直接转给 `Stats.kindLabel`：统计页和练习页必须用同一套叫法，
    /// 否则同一个 `q` 在练习页叫「单选题」、在统计页叫「语法」，
    /// 用户会以为是两个不同的东西。这里只保留一个入口，映射表只有一份。
    func kindLabel(_ kind: String) -> String {
        Stats.kindLabel(kind)
    }
}
