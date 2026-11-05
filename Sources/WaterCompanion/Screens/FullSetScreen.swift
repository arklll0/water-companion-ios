import AVFoundation
import SwiftUI

// MARK: - 整套真题的成绩
//
// 只统计「有答案、且不在 answerGaps 里」的题：官方答案里标记为残缺的题
// 不参与判分，否则分母里多一道必错题，分数会平白低一截。

struct FullSetResult {
    let paperId: String
    let title: String
    let correct: Int
    let total: Int
    let acc: Int
    let score: Int
}

// MARK: - 整套真题
//
// 交互按 Android 2.10.0 的四段式还原：写作 / 听力 / 阅读 / 翻译。
// 阅读再分选词填空 / 段落匹配 / 仔细阅读三小段。
//
// 判分只在交卷时做：作答期间不显示对错，也不显示正确答案。
// 所有选择放在内存里的 `chosen`（题号 → 选项下标），退出即丢，
// 这是真考卷的行为，不需要落盘。
//
// `answers` 的键是题号字符串，四个部分共用同一套题号空间：
// 听力 1-25、选词填空 26-35、段落匹配 36-45、仔细阅读 46-50。
// 所以 `chosen` 用题号做键不会互相覆盖。

struct FullSetScreen: View {

    let papers: [FullPaper]
    /// 已经交过卷的 FullPaper.id。只用来在列表上打「已交」标签，
    /// 不禁用点击：真题的价值在于反复做。
    let doneIds: [String]
    let onFinish: (FullSetResult) -> Void

    @State private var selected: FullPaper?
    @State private var section: Int = 0
    @State private var readingTab: Int = 0
    @State private var chosen: [Int: Int] = [:]

    @State private var result: FullSetResult?
    @State private var showsSubmitConfirm = false
    @State private var unanswered = 0

    @State private var showsWritingSample = false
    @State private var showsTranslationReference = false

    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioMissing = false

    private static let sectionTitles = ["写作", "听力", "阅读", "翻译"]
    private static let readingTitles = ["选词填空", "段落匹配", "仔细阅读"]

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .confirmationDialog(
            "还有 \(unanswered) 题没选，确定交卷？",
            isPresented: $showsSubmitConfirm,
            titleVisibility: .visible
        ) {
            Button("交卷") { submit() }
            Button("继续做", role: .cancel) {}
        }
        .onDisappear {
            // 页面切走时把录音停掉，不然听力会跟着用户去别的页签。
            audioPlayer?.stop()
            audioPlayer = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if let paper = selected {
            if let finished = result {
                resultPanel(finished)
            } else {
                paperPage(paper)
            }
        } else {
            paperList
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 列表态
    // ════════════════════════════════════════════════════════════════

    @ViewBuilder
    private var paperList: some View {
        if papers.isEmpty {
            ContentUnavailableView("这一档还没有整套真题", systemImage: "doc.text")
        } else {
            ScrollView {
                VStack(spacing: Space.itemGap) {
                    SectionHeader(
                        "整套真题",
                        subtitle: "按考试顺序做：写作、听力、阅读、翻译",
                        trailing: "共 \(papers.count) 套"
                    )

                    ForEach(papers) { paper in
                        Button {
                            open(paper)
                        } label: {
                            paperRow(paper)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Space.pageEdge)
                .padding(.top, Space.md)
                .padding(.bottom, Space.xxl)
            }
        }
    }

    private func paperRow(_ paper: FullPaper) -> some View {
        AppCard {
            HStack(alignment: .top, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(paper.title)
                        .font(Typography.titleSmall)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(paperSubtitle(paper))
                        .appCaption()
                }

                Spacer(minLength: 0)

                if doneIds.contains(paper.id) {
                    Text("已交")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.primary)
                }
            }
            .contentShape(Rectangle())
        }
    }

    /// 卡片副标题：考研 / 成考卷没有听力，写「听力 0 题」像是数据丢了；缺题也如实标出来。
    /// 题数与缺口都从卷子里数出来，别写死 —— 考研是 45 题，成考是 48 题。
    private func paperSubtitle(_ paper: FullPaper) -> String {
        var parts = [paper.meta.levelLabel]
        let listen = paper.listening.questions.count
        if listen > 0 {
            parts.append("听力 \(listen) 题")
        }
        let read = paper.reading.cloze.blanks.count
            + paper.reading.matching.statements.count
            + paper.reading.careful.reduce(0) { $0 + $1.questions.count }
        // 成考的「阅读」区里装着词汇语法 + 完形 + 阅读三段，
        // 笼统写「阅读 48 题」会把词汇题算成阅读题
        parts.append(paper.meta.level == "ck" ? "共 \(read) 题" : "阅读 \(read) 题")
        let gap = paper.answerGaps.listening.count + paper.answerGaps.cloze.count
            + paper.answerGaps.matching.count + paper.answerGaps.careful.count
        if gap > 0 {
            parts.append("收录 \(read - gap)/\(read) 题")
        }
        return parts.joined(separator: " · ")
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 做卷态
    // ════════════════════════════════════════════════════════════════

    /// 这套卷实际有内容的段：0 写作 / 1 听力 / 2 阅读 / 3 翻译。
    /// 考研卷没有听力，分区控件不能给它留一个点进去空白的页签。
    private func visibleSections(_ paper: FullPaper) -> [Int] {
        var out: [Int] = []
        if !paper.writing.directions.isEmpty { out.append(0) }
        if !paper.listening.questions.isEmpty { out.append(1) }
        if !paper.reading.cloze.blanks.isEmpty
            || !paper.reading.matching.paragraphs.isEmpty
            || !paper.reading.careful.isEmpty { out.append(2) }
        if !paper.translation.chinese.isEmpty { out.append(3) }
        return out.isEmpty ? [0] : out
    }

    private func paperPage(_ paper: FullPaper) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                QuietButton("返回列表", icon: "chevron.left") {
                    closePaper()
                }
                Spacer(minLength: 0)
                Text(paper.title)
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.pageEdge)

            // 考研卷没有听力：留一个点进去空白的「听力」页签只会让人以为数据丢了。
            Picker("部分", selection: $section) {
                ForEach(visibleSections(paper), id: \.self) { index in
                    Text(Self.sectionTitles[index]).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Space.pageEdge)
            .padding(.bottom, Space.sm)

            // 录音放在顶部常驻：听力途中切到阅读看题时，按钮还在原地，
            // 不用滚回听力页再点。
            audioButton(paper)
                .padding(.horizontal, Space.pageEdge)
                .padding(.bottom, Space.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if section == 0 {
                        writingSection(paper)
                    } else if section == 1 {
                        listeningSection(paper)
                    } else if section == 2 {
                        readingSection(paper)
                    } else {
                        translationSection(paper)
                    }

                    PrimaryButton("交卷") {
                        attemptSubmit(paper)
                    }
                    .padding(.top, Space.md)
                }
                .padding(.horizontal, Space.pageEdge)
                .padding(.top, Space.md)
                .padding(.bottom, Space.xxl)
            }
        }
    }

    // MARK: - 写作

    private func writingSection(_ paper: FullPaper) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader(
                "写作",
                // 考研英语二是一篇 100 词、一篇 150 词，压成一个区间会误导。
                // minutes = 0 表示原卷没写这段单独给多久（成考模拟卷只给了全卷 90 分钟），
                // 拼成「0 分钟」比不写更糟。
                subtitle: paper.meta.level == "ky"
                    ? "建议 Part A 约 100 词 · Part B 约 150 词"
                    : (paper.writing.minutes > 0
                        ? "\(paper.writing.minutes) 分钟 / \(paper.writing.minWords)-\(paper.writing.maxWords) 词"
                        : "建议 \(paper.writing.minWords)-\(paper.writing.maxWords) 词")
            )

            AppCard {
                VStack(alignment: .leading, spacing: Space.md) {
                    ReadingPassage(text: paper.writing.directions)

                    SecondaryButton(
                        showsWritingSample ? "收起范文" : "看范文",
                        icon: showsWritingSample ? "chevron.up" : "doc.text"
                    ) {
                        withAnimation(.snappy) {
                            showsWritingSample.toggle()
                        }
                    }
                }
            }

            if showsWritingSample {
                AppCard(background: Theme.Colors.banner, showsBorder: false) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("范文")
                            .font(Typography.captionEmph)
                            .foregroundStyle(Theme.Colors.primary)
                        ReadingPassage(text: paper.writing.sample)
                    }
                }
            }
        }
    }

    // MARK: - 听力

    private func listeningSection(_ paper: FullPaper) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader(
                "听力",
                subtitle: "共 \(paper.listening.questions.count) 题，交卷前不显示对错"
            )

            ForEach(paper.listening.questions) { question in
                // correctIndex 传 -1：交卷前不把正确答案交给答题区。
                // 已知限制：QuizView 目前把「已选、但下标不等于 correctIndex」当成错答标红，
                // 所以选中后会看到红叉。等 QuizView 改成只在 correctIndex >= 0 时判错即可消失。
                QuizView(
                    question: "第 \(question.no) 题",
                    options: question.options,
                    correctIndex: -1,
                    explanation: "",
                    passage: [],
                    readAloud: nil
                ) { index in
                    chosen[question.no] = index
                }
                .id(question.no)
            }
        }
    }

    private func audioButton(_ paper: FullPaper) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SecondaryButton(
                audioMissing ? "录音没打进包" : "播放本套录音",
                icon: audioMissing ? "exclamationmark.triangle" : "play.fill"
            ) {
                playAudio(paper)
            }

            if audioMissing {
                Text("bundle 里没找到这一套的录音，可以先看题目。")
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    // MARK: - 阅读

    private func readingSection(_ paper: FullPaper) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            // 考研 / 成考卷的阅读只有 careful 一段（考研是完形 + Part A + Part B，
            // 成考是词汇语法 + 完形 + 阅读，都被映射进 careful），没有选词填空 / 段落匹配，
            // 不给它们三个页签 —— 点进去一片空白的页签比没有更糟。
            if paper.meta.level == "ky" || paper.meta.level == "ck" {
                carefulSection(paper)
            } else {
                Picker("阅读部分", selection: $readingTab) {
                    ForEach(Self.readingTitles.indices, id: \.self) { index in
                        Text(Self.readingTitles[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if readingTab == 0 {
                    clozeSection(paper)
                } else if readingTab == 1 {
                    matchingSection(paper)
                } else {
                    carefulSection(paper)
                }
            }
        }
    }

    // MARK: 选词填空

    private func clozeSection(_ paper: FullPaper) -> some View {
        let cloze = paper.reading.cloze

        return VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader(
                "选词填空",
                subtitle: "备选词可以重复使用，判分只看字母"
            )

            if !cloze.passage.isEmpty {
                AppCard {
                    // 已分段数组不猜分段；段距 28 由组件内部管理。
                    ReadingParagraphs(cloze.passage)
                }
            }

            if !cloze.bank.isEmpty {
                AppCard {
                    // 两列排 A-O：一列十五个词会把这一段拉得比正文还长。
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: Space.sm),
                            GridItem(.flexible(), spacing: Space.sm)
                        ],
                        alignment: .leading,
                        spacing: Space.xs
                    ) {
                        ForEach(cloze.bank.indices, id: \.self) { index in
                            Text("\(Self.letter(index)). \(cloze.bank[index])")
                                .font(Typography.micro)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            ForEach(cloze.blanks) { blank in
                blankCard(blank, bank: cloze.bank)
            }
        }
    }

    private func blankCard(_ blank: FullPaper.Blank, bank: [String]) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text("\(blank.no).")
                        .font(Typography.bodyEmph)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                    ReadingPassage(text: blank.context)
                }

                HStack(spacing: Space.sm) {
                    wordMenu(
                        label: bankLabel(bank, chosen[blank.no]),
                        titles: bank.indices.map { "\(Self.letter($0)). \(bank[$0])" }
                    ) { index in
                        chosen[blank.no] = index
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: 段落匹配

    private func matchingSection(_ paper: FullPaper) -> some View {
        let matching = paper.reading.matching

        return VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader(
                "段落匹配",
                subtitle: "为每条陈述选一个段落，段落可以重复选"
            )

            if !matching.title.isEmpty {
                Text(matching.title)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !matching.paragraphs.isEmpty {
                AppCard {
                    // 段落字母必须保留（4 套卷跳号，与 answers.matching 判分耦合），
                    // 所以这里不用 ReadingParagraphs，只把段距 12 → 28、正文换成统一款式。
                    VStack(alignment: .leading, spacing: ReadingBody.paragraphGap) {
                        ForEach(matching.paragraphs.indices, id: \.self) { index in
                            HStack(alignment: .top, spacing: Space.sm) {
                                Text(paragraphLetter(matching, index))
                                    .font(Typography.captionEmph)
                                    .foregroundStyle(Theme.Colors.primary)
                                    .frame(width: 18, alignment: .leading)
                                Text(ReadingBody.styled(ReadingBody.displayText(matching.paragraphs[index])))
                                    .lineSpacing(ReadingBody.lineSpacing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            ForEach(matching.statements.indices, id: \.self) { index in
                statementCard(
                    number: 36 + index,
                    text: matching.statements[index],
                    letters: matching.paragraphLetters
                )
            }
        }
    }

    /// 段落字母一律用素材里的原始字母。
    /// 30 套卷里有 4 套是跳号的（cet4-2023-06-s1 是 ABCDFGJKLM，cet6-2020-12-s1 是 ABCEFGHIJKMNOPQR），
    /// 而 answers.matching 用的是原始字母。按下标推字母会让这 4 套卷的菜单显示和判分一起错位。
    private func paragraphLetter(_ matching: FullPaper.Matching, _ index: Int) -> String {
        guard matching.paragraphLetters.indices.contains(index) else {
            return Self.letter(index)
        }
        return matching.paragraphLetters[index]
    }

    private func statementCard(number: Int, text: String, letters: [String]) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text("\(number).")
                        .font(Typography.bodyEmph)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                    ReadingPassage(text: text)
                }

                HStack(spacing: Space.sm) {
                    wordMenu(
                        label: letterLabel(chosen[number], letters: letters),
                        titles: letters
                    ) { index in
                        chosen[number] = index
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: 仔细阅读

    /// 组标题：考研与成考的 carefully 里装着不止「阅读」。
    ///
    /// 考研：1-20 完形、21-40 阅读、41-45 Part B；
    /// 成考：1-20 词汇与语法、21-40 完形、41-48 阅读（每篇 4 题）。
    /// 一律标「第 N 篇」会把词汇题和完形叫成阅读篇。
    ///
    /// 考研 2011 那套缺了前 4 题，完形组首题号是 5 —— 所以完形判定写 `<= 20`
    /// 而不是 `1...20`，否则那组会被算成「第 -2 篇」。
    private func carefulGroupTitle(_ level: String, _ firstNo: Int) -> String {
        if level == "ck" {
            if firstNo <= 20 { return "词汇与语法" }
            if firstNo <= 40 { return "完形填空" }
            return "第 \((firstNo - 41) / 4 + 1) 篇"
        }
        if firstNo <= 20 { return "完形填空" }
        if firstNo >= 41 { return "Part B 新题型" }
        return "第 \((firstNo - 21) / 5 + 1) 篇"
    }

    private func carefulSection(_ paper: FullPaper) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ForEach(paper.reading.careful) { group in
                VStack(alignment: .leading, spacing: Space.lg) {
                    // 四六级这块就是「仔细阅读」，按篇数标题不标也不会认错；
                    // 考研 / 成考这块混着三种题型，必须标。
                    if paper.meta.level == "ky" || paper.meta.level == "ck",
                       let firstNo = group.questions.first?.no {
                        Text(carefulGroupTitle(paper.meta.level, firstNo))
                            .font(Typography.captionEmph)
                            .foregroundStyle(Theme.Colors.primary)
                    }
                    if !group.passage.isEmpty {
                        AppCard {
                            ReadingParagraphs(group.passage)
                        }
                    }

                    ForEach(group.questions) { question in
                        QuizView(
                            question: question.stem,
                            options: question.options,
                            correctIndex: -1,
                            explanation: "",
                            passage: [],
                            readAloud: nil
                        ) { index in
                            chosen[question.no] = index
                        }
                        .id(question.no)
                    }
                }
            }
        }
    }

    // MARK: - 翻译

    private func translationSection(_ paper: FullPaper) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader(
                "翻译",
                // 四六级是汉译英，考研英语二是英译汉
                subtitle: paper.meta.level == "ky" ? "把下面这段英文译成中文" : "把下面这段中文译成英文"
            )

            AppCard {
                // 中文原文走组件的中文分支：不切 320、不插 U+2002。
                ReadingPassage(text: paper.translation.chinese)
            }

            SecondaryButton(
                showsTranslationReference ? "收起参考译文" : "看参考译文",
                icon: showsTranslationReference ? "chevron.up" : "doc.text"
            ) {
                withAnimation(.snappy) {
                    showsTranslationReference.toggle()
                }
            }

            if showsTranslationReference {
                AppCard(background: Theme.Colors.banner, showsBorder: false) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("参考译文")
                            .font(Typography.captionEmph)
                            .foregroundStyle(Theme.Colors.primary)
                        ReadingPassage(text: paper.translation.reference)
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 选词控件
    // ════════════════════════════════════════════════════════════════

    /// 一个胶囊形的菜单。选项多时（A-O）用 `Menu` 而不是分段控件：
    /// 十五个分段在手机上每段只有两三个字符宽，根本点不中。
    private func wordMenu(
        label: String,
        titles: [String],
        onPick: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            ForEach(titles.indices, id: \.self) { index in
                Button(titles[index]) {
                    onPick(index)
                }
            }
        } label: {
            HStack(spacing: Space.xs) {
                Text(label)
                    .font(Typography.captionEmph)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.Colors.primary)
            .padding(.horizontal, Space.md)
            .frame(minHeight: Touch.min)
            .background(Theme.Colors.primarySoft, in: Capsule())
        }
    }

    private func bankLabel(_ bank: [String], _ index: Int?) -> String {
        guard let index, bank.indices.contains(index) else { return "选一个词" }
        return "\(Self.letter(index)). \(bank[index])"
    }

    private func letterLabel(_ index: Int?, letters: [String]) -> String {
        guard let index, letters.indices.contains(index) else { return "选一个段落" }
        return letters[index]
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 交卷与结算
    // ════════════════════════════════════════════════════════════════

    private func attemptSubmit(_ paper: FullPaper) {
        let missing = missingCount(paper)
        if missing > 0 {
            unanswered = missing
            showsSubmitConfirm = true
        } else {
            submit()
        }
    }

    private func submit() {
        guard let paper = selected else { return }
        let tally = grade(paper)
        let accuracy = tally.total == 0 ? 0 : tally.correct * 100 / tally.total
        // 710 分制：正确率折算成 70% 的区间，再加 248 的基数。
        // 全对刚好 710，全错是 248（四六级成绩单的下限）。
        let raw = Double(710 * tally.correct) / Double(max(tally.total, 1)) * 0.7
        let score = min(710, Int(raw.rounded()) + 248)

        let finished = FullSetResult(
            paperId: paper.id,
            title: paper.title,
            correct: tally.correct,
            total: tally.total,
            acc: accuracy,
            score: score
        )
        result = finished
        onFinish(finished)
    }

    private func resultPanel(_ finished: FullSetResult) -> some View {
        FormPage {
            AppCard {
                VStack(spacing: Space.sm) {
                    Text("\(finished.score)")
                        .font(Typography.dataLarge)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.primary)
                    Text("710 分制估分")
                        .appCaption()

                    HStack(spacing: Space.sm) {
                        StatBox("\(finished.correct) / \(finished.total)", "答对")
                        StatBox("\(finished.acc)%", "正确率")
                    }
                    .padding(.top, Space.sm)

                    Text(finished.title)
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }

            PrimaryButton("再做一套") {
                redo()
            }

            Text("成绩只在本页显示，不会记录成错题，也不会改动存档。")
                .appCaption()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 判分
    // ════════════════════════════════════════════════════════════════

    private func grade(_ paper: FullPaper) -> (correct: Int, total: Int) {
        var correct = 0
        var total = 0

        func tally(_ answers: [String: String], gaps: [Int], letters: [String]? = nil) {
            for (key, raw) in answers {
                guard let number = Int(key) else { continue }
                // 官方标记的残缺题不计入分母：它们没有可判的答案。
                if gaps.contains(number) { continue }

                total += 1

                guard let picked = chosen[number] else { continue }
                let expected = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                // 段落匹配的段落字母可能跳号，要换算回素材里的原始字母；其余题型按下标推字母即可。
                let pickedLetter: String
                if let letters = letters, letters.indices.contains(picked) {
                    pickedLetter = letters[picked]
                } else {
                    pickedLetter = Self.letter(picked)
                }
                if pickedLetter == expected {
                    correct += 1
                }
            }
        }

        tally(paper.answers.listening, gaps: paper.answerGaps.listening)
        tally(paper.answers.cloze, gaps: paper.answerGaps.cloze)
        tally(
            paper.answers.matching,
            gaps: paper.answerGaps.matching,
            letters: paper.reading.matching.paragraphLetters
        )
        tally(paper.answers.careful, gaps: paper.answerGaps.careful)

        return (correct, total)
    }

    private func missingCount(_ paper: FullPaper) -> Int {
        var missing = 0

        func scan(_ answers: [String: String], gaps: [Int]) {
            for key in answers.keys {
                guard let number = Int(key) else { continue }
                if gaps.contains(number) { continue }
                if chosen[number] == nil {
                    missing += 1
                }
            }
        }

        scan(paper.answers.listening, gaps: paper.answerGaps.listening)
        scan(paper.answers.cloze, gaps: paper.answerGaps.cloze)
        scan(paper.answers.matching, gaps: paper.answerGaps.matching)
        scan(paper.answers.careful, gaps: paper.answerGaps.careful)

        return missing
    }

    /// 0 -> "A"，25 -> "Z"。题号空间最多到 50，不会超过 Z。
    private static func letter(_ index: Int) -> String {
        guard index >= 0, index < 26,
              let scalar = UnicodeScalar(UInt32(65 + index)) else {
            return "?"
        }
        return String(scalar)
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 音频
    // ════════════════════════════════════════════════════════════════

    private func playAudio(_ paper: FullPaper) {
        audioPlayer?.stop()
        audioPlayer = nil

        guard !paper.audio.isEmpty, let url = Self.audioURL(for: paper.audio) else {
            // 不弹 alert：录音缺失不是用户能处理的错误，弹窗只会打断做题。
            // 把按钮标题改掉，用户看一眼就明白。
            audioMissing = true
            return
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)
        try? session.setActive(true)

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            _ = player.play()
            audioPlayer = player
            audioMissing = false
        } catch {
            audioMissing = true
        }
    }

    /// `paper.audio` 形如 "set_audio/cet4-2020-07-s1.m4a"。
    /// folder reference 打包后子目录会保留，但不同 Xcode 版本的落点不完全一致，
    /// 所以按「Audio/set_audio → Audio → 根目录」逐级退让。
    private static func audioURL(for path: String) -> URL? {
        let full = path as NSString
        let nameWithExtension = full.lastPathComponent
        let name = (nameWithExtension as NSString).deletingPathExtension
        let ext = (nameWithExtension as NSString).pathExtension

        if let url = Bundle.main.url(
            forResource: nameWithExtension,
            withExtension: nil,
            subdirectory: "Audio/set_audio"
        ) { return url }

        if let url = Bundle.main.url(
            forResource: nameWithExtension,
            withExtension: nil,
            subdirectory: "Audio"
        ) { return url }

        if let url = Bundle.main.url(forResource: nameWithExtension, withExtension: nil) {
            return url
        }

        if !ext.isEmpty {
            if let url = Bundle.main.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "Audio/set_audio"
            ) { return url }

            if let url = Bundle.main.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "Audio"
            ) { return url }

            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }

        return nil
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 状态切换
    // ════════════════════════════════════════════════════════════════

    private func open(_ paper: FullPaper) {
        chosen = [:]
        result = nil
        section = 0
        readingTab = 0
        showsWritingSample = false
        showsTranslationReference = false
        audioMissing = false
        audioPlayer?.stop()
        audioPlayer = nil
        selected = paper
    }

    private func closePaper() {
        audioPlayer?.stop()
        audioPlayer = nil
        selected = nil
        result = nil
        chosen = [:]
        section = 0
        readingTab = 0
        showsWritingSample = false
        showsTranslationReference = false
        audioMissing = false
    }

    private func redo() {
        // 只清这一套的选择和结算结果，回列表重新挑一套。
        // 分页 / 展开状态留给 `open` 去复位，这里不重复清，避免以后漏掉一处。
        chosen = [:]
        result = nil
        selected = nil
        audioPlayer?.stop()
        audioPlayer = nil
        audioMissing = false
    }
}
