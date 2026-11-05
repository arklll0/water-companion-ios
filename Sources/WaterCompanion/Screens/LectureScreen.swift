import SwiftUI

// MARK: - 语法讲义目录
//
// 5 章 52 篇一次列完，不折叠：讲义是「随手翻」的资料，不是任务清单，
// 折叠起来只会让人多点一次。用系统的 `List` + `.insetGrouped`，
// 分组圆角、分隔线、行高都由系统处理，和单词页的列表保持同一套观感。

struct LectureScreen: View {

    let lectures: LectureFile
    /// (chapterId, lessonId)。页面不自己管路由，交给上层决定。
    let onOpen: (String, String) -> Void

    var body: some View {
        ZStack {
            AppBackground()

            if lectures.isEmpty {
                // 讲义是打包资源，缺了基本只有「文件没进 bundle」这一种可能，
                // 所以空态直接把原因和动作写清楚，省掉一次客服对话。
                ContentUnavailableView(
                    "讲义还没加载出来",
                    systemImage: "book.closed",
                    description: Text("讲义文件可能没打进包，重装一次试试。")
                )
            } else {
                catalog
            }
        }
    }

    private var catalog: some View {
        List {
            ForEach(lectures.chapters) { chapter in
                Section {
                    ForEach(chapter.lessons) { lesson in
                        row(chapter: chapter, lesson: lesson)
                    }
                } header: {
                    // 章名 + 一句说明。篇数直接算出来，不写死在文案里，
                    // 以后增删篇目不用回来改文案。
                    SectionHeader(
                        chapter.title,
                        subtitle: "\(chapter.note) 共 \(chapter.lessons.count) 篇"
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        // 不隐藏的话，List 会盖一层系统底色，AppBackground 就被埋掉了。
        .scrollContentBackground(.hidden)
    }

    private func row(chapter: LectureChapter, lesson: LectureLesson) -> some View {
        Button {
            onOpen(chapter.id, lesson.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(lesson.title)
                    .font(Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Space.sm)

                Text("\(lesson.minutes) 分钟")
                    .font(Typography.micro)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            // 整行可点：只让文字响应的话，右侧留白会变成死区。
            .frame(minHeight: Touch.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.Colors.surface)
    }
}
