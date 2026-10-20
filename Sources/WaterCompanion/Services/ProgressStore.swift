import Foundation
import Observation

// ════════════════════════════════════════════════════════════════════
//  进度持久化
// ════════════════════════════════════════════════════════════════════
//
//  单文件：`Application Support/progress.json`。
//  为什么是单文件而不是 UserDefaults：进度里有上千条 attempts / wrongBook，
//  塞进 plist 会让每次启动都整份读出、整份写回；单文件可以原子写（`.atomic`），
//  写一半断电也不会留下半个 JSON。
//
//  `@MainActor`：所有可变状态都只在主线程改。App 的写操作全部来自用户点击，
//  本来就在主线程；显式标注是为了让编译器替我们守住这条线，
//  而不是靠「反正不会有人从后台线程调」这种口头约定。
//
//  每次修改都**立刻落盘**。不做节流/延迟写：单份 JSON 只有几十 KB，
//  而丢一次评分比多写两次磁盘难受得多。

@MainActor
@Observable
final class ProgressStore {

    /// 当前进度。
    ///
    /// 约定：**只通过下面的方法修改**，这样「改完要存盘」不可能被漏掉。
    /// 直接赋值不会落盘，重启后那次修改就丢了。
    var progress: Progress = Progress()

    /// 上次读写失败的原因（正常情况下为 nil）。界面可以据此提示，但不要因此阻断使用。
    var lastError: String?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - 生命周期

    init(fileURL: URL? = nil) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
        self.fileURL = fileURL ?? ProgressStore.defaultFileURL()
        load()
    }

    /// `Application Support/progress.json`
    private static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent("progress.json")
    }

    // MARK: - 磁盘

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            progress = Progress()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            if data.isEmpty {
                progress = Progress()
                return
            }
            progress = try decoder.decode(Progress.self, from: data)
            lastError = nil
        } catch {
            // 存档损坏时**不清空**：留着原文件，用空进度继续跑。
            // 用户下次导出还能看到旧数据，而不是「一打开进度全没了」。
            lastError = "读取进度失败：\(error.localizedDescription)"
            progress = Progress()
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(progress)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "保存进度失败：\(error.localizedDescription)"
        }
    }

    /// 读 - 改 - 写 一次完成。所有 setter 都从这里走。
    private func update(_ block: (inout Progress) -> Void) {
        var next = progress
        block(&next)
        progress = next
        save()
    }

    // MARK: - 今日活动

    /// 记录今天的学习量。field 取 words / read / listen / exam，其余计入 tasks。
    func bump(_ field: String, _ n: Int = 1) {
        let today = Srs.today()
        update { p in
            var entry = p.log[today] ?? DayLog()
            switch field {
            case "words": entry.words += n
            case "read": entry.read += n
            case "listen": entry.listen += n
            case "exam": entry.exam += n
            default: entry.tasks += n
            }
            p.log[today] = entry
        }
    }

    /// 今天的学习量
    var todayLog: DayLog {
        progress.dayLog(Srs.today())
    }

    // MARK: - 单词 / 词族评分

    /// 评一个单词，并把今天的学习量 +1。
    ///
    /// 两件事合成一次写：分开写就是两个「读 - 改 - 写」回合，
    /// 一旦中间有别的写入，后一次会覆盖前一次 —— 表现为「词记了、今日进度没动」。
    func recordWordRating(word: String, rating: Int) {
        let today = Srs.today()
        update { p in
            let entry = p.wordProgress[word] ?? WordProgress()
            p.wordProgress[word] = Srs.rate(entry, rating)

            var log = p.log[today] ?? DayLog()
            log.words += 1
            p.log[today] = log
        }
    }

    /// 评一个词族成员（key = "族序号:单词"），同样计入今天的学习量。
    func recordFamilyRating(familyIndex: Int, word: String, rating: Int) {
        let key = Srs.familyKey(familyIndex, word)
        let today = Srs.today()
        update { p in
            let entry = p.familyProgress[key] ?? WordProgress()
            p.familyProgress[key] = Srs.rateFamily(entry, rating)

            var log = p.log[today] ?? DayLog()
            log.words += 1
            p.log[today] = log
        }
    }

    // MARK: - 各模块完成记录

    func markReadDone(index: Int) {
        update { p in
            if !p.readDone.contains(index) {
                p.readDone.append(index)
            }
        }
    }

    func markListenDone(key: String) {
        update { p in
            if !p.listenDone.contains(key) {
                p.listenDone.append(key)
            }
        }
    }

    /// 标记「每日练习」的某道小题做过了（key = PaperItemRef.id，如 "3-4"）
    func markPaperDone(id: String) {
        update { p in
            if !p.paperDone.contains(id) {
                p.paperDone.append(id)
            }
        }
    }

    func addExam(_ record: ExamRecord) {
        update { p in
            p.examHistory.append(record)
        }
    }

    // MARK: - 作答记录（能力分析的数据源）

    /// 记一次作答：**答对也要记**，否则正确率没有分母。
    ///
    /// - Parameters:
    ///   - kind: 细分题型（vocab / q / cloze / match / read / listen）
    ///   - ok: 是否答对
    ///   - wrong: 答错时传错题条目；答对传 nil。日期、kind、ok 由这里统一补上。
    func recordAnswer(kind: String, ok: Bool, wrong: WrongItem? = nil) {
        let today = Srs.today()
        update { p in
            p.attempts.append(Attempt(date: today, kind: kind, ok: ok))
            if var item = wrong {
                item.date = today
                item.kind = kind
                item.ok = ok
                p.wrongBook.append(item)
            }
        }
    }

    // MARK: - 错题集

    func addWrong(_ item: WrongItem) {
        update { p in
            p.wrongBook.append(item)
        }
    }

    func removeWrong(at index: Int) {
        update { p in
            guard index >= 0, index < p.wrongBook.count else { return }
            p.wrongBook.remove(at: index)
        }
    }

    func clearWrong() {
        update { p in
            p.wrongBook.removeAll()
        }
    }

    // MARK: - 今日任务推迟

    /// 把某个今日任务推到 `toDate` 那天再出现。
    ///
    /// 顺手剪掉已经过期的条目（`value < today`）—— 否则 `postponed` 会随使用时间
    /// 无限增长。剪枝用字符串比较：yyyy-MM-dd 定长且高位在前，字典序 == 时间序。
    func postponeTask(id: String, to toDate: String) {
        let today = Srs.today()
        update { p in
            p.postponed = p.postponed.filter { $0.value >= today }
            p.postponed[id] = toDate
        }
    }

    /// 撤销「今天」的所有推迟（把今天被推走的任务放回列表）。
    ///
    /// 做成「一次恢复今天全部」而不是「按 id 逐个恢复」：逐个调用会让多次
    /// 读 - 改 - 写 互相覆盖，最后只生效一个。
    func resumePostponedToday() {
        let today = Srs.today()
        update { p in
            p.postponed = p.postponed.filter { $0.value != today }
        }
    }

    /// 今天被推迟的任务 id 集合
    var postponedTodayIds: Set<String> {
        let today = Srs.today()
        return Set(progress.postponed.filter { $0.value == today }.keys)
    }

    // MARK: - 设置

    func setExamDate(_ date: String?) {
        let normalized: String? = {
            guard let date else { return nil }
            let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        update { p in
            p.examDate = normalized
        }
    }

    func setDailyMinutes(_ minutes: Int) {
        let value = max(minutes, 5)
        update { p in
            p.dailyMinutes = value
        }
    }

    func setDailyWords(_ words: Int) {
        let value = min(max(words, 5), 100)
        update { p in
            p.dailyWords = value
        }
    }

    func setTheme(_ theme: String) {
        let value = Theme.Mode.fromKey(theme).rawValue
        update { p in
            p.theme = value
        }
    }

    // MARK: - 首次启动 / 连续打卡

    /// 首次启动写入开始日期，并按「昨天有没有来过」维护连续打卡。
    /// 幂等：同一天调多次结果不变。
    func touchStreak() {
        let today = Srs.today()
        var changed = false

        var next = progress
        if next.startDate == nil || next.startDate?.isEmpty == true {
            next.startDate = today
            changed = true
        }
        if next.lastActive != today {
            let yesterday = Srs.addDays(today, -1)
            next.streak = (next.lastActive == yesterday) ? next.streak + 1 : 1
            next.lastActive = today
            changed = true
        }

        if changed {
            progress = next
            save()
        }
    }

    // MARK: - 导入 / 导出 / 重置

    /// 导入网站「导出进度」得到的 JSON。成功返回 true。
    func importJSON(_ raw: String) -> Bool {
        guard let data = raw.data(using: .utf8) else { return false }
        do {
            let decoded = try decoder.decode(Progress.self, from: data)
            progress = decoded
            save()
            return true
        } catch {
            lastError = "导入失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 导出当前进度（可以直接粘回网站导入）
    func exportJSON() -> String {
        do {
            let data = try encoder.encode(progress)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            lastError = "导出失败：\(error.localizedDescription)"
            return "{}"
        }
    }

    /// 清空全部进度（考试日期 / 每日词量这些设置也一起回到默认值）
    func reset() {
        progress = Progress()
        save()
    }
}
