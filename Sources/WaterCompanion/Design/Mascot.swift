import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  看板娘「汐汐」：素材的唯一出口
// ════════════════════════════════════════════════════════════════════
//
//  角色在这里承担的是**情绪**，不是插画装饰。所以只给三个组件、按「需要多大的脸」分：
//
//  | 组件 | 用在哪 | 为什么是它 |
//  |---|---|---|
//  | `MascotAvatar` | 问候、答题反馈、翻卡提示 | 一句话的场景只要一张脸，身体反而占地方 |
//  | `MascotStage` | 一组背完、空态 | 立绘 + 一块淡色底盘：深色下深蓝轮廓直接贴卡片会糊掉 |
//  | `MascotFigure` | 基本不单独用 | 裸立绘，不带底；外面必须自己铺底盘，否则深色模式会失踪 |
//  | `MascotEmptyState` | 整屏空态 | 空态是三件套（形象 + 一句解释 + 一个出口），不是一张图 |
//
//  三条硬纪律：
//
//  ① **不要用字符串拼素材名。** 名字拼错在编译期没有任何提示，运行期只是一张空白图，
//     这种 bug 只有在真机上翻到那一页才会发现。所以情绪 / 姿态都做成枚举，名字由 `rawValue` 派生。
//
//  ② **角色永远是蓝的（#2E5BD8），页面主色是墨绿（#0E5F4B）。** 蓝色不许往外渗，
//     所以她的每一处出现都带着自己的底盘（`Theme.Colors.mascotHalo`）——
//     底盘同时也是深色模式下的救兵：她的轮廓线是深海军蓝，直接落在近黑底上会整片糊掉，
//     只剩一团白头发。
//
//  ③ **素材是单倍图**（`Contents.json` 里只有 `"scale": "1x"`，情绪图 300×359px）。
//     所以这里一律 `resizable()` + 显式尺寸，任何地方都不要读 `Image` 的固有尺寸——
//     读固有尺寸会按 300pt 排版，一屏放不下一个头。

// MARK: - 素材表

/// 10 个表情。`rawValue` 必须与 `Assets.xcassets/mascot_emotion_<rawValue>.imageset` 逐字一致。
enum MascotEmotion: String, CaseIterable, Identifiable {
    /// 笑开了眼：答对、全部完成
    case happy
    /// 眼睛发亮：惊喜（暂未接入，留给连续答对）
    case surprise
    /// 抿嘴专注：在做题/学习中
    case focus
    /// 托腮思考：等她不知道答案时（整套真题交卷前）
    case think
    /// 歪头疑惑：找不到内容 / 数据不对
    case puzzled
    /// 握拳鼓劲：答错、还没开始
    case encourage
    /// 脸红：被夸的时候（暂未接入）
    case shy
    /// 打哈欠：空态、今天已经做完
    case sleepy
    /// 眉眼放软：听力自评「没听懂」—— 要给台阶，不能像在评判
    case kind
    /// 眼睛弯起来：听力自评「听懂了」—— 一起高兴
    case joy

    var id: String { rawValue }

    fileprivate var assetName: String { "mascot_emotion_\(rawValue)" }
}

/// 13 个全身姿态。`rawValue` 规则同上。
enum MascotPose: String, CaseIterable {
    /// 招手 + 抱书：第一次见面
    case wave
    /// 坐着读书
    case read
    /// 趴着打盹
    case sleep
    /// 欢呼加油
    case cheer
    /// 戴耳机：听力页，句子还没挑的时候
    case listen
    /// 拿教鞭讲：讲义目录（「这一章讲什么」的引子）
    case teach
    /// 正面站姿，手背在身后：我的页角色卡
    case stand
    /// 闭眼戴耳机：听力「盲听」那一格，正好是这一格要的状态
    case headphone
    /// 正常比例版招手：比 Q 版高一截，用在需要「人味」的整块空态里
    case normalWave = "normal_wave"
    /// 托腮发呆：没有任务可做的空隙
    case idle
    /// 抱着本子写字：练习页
    case practice
    /// 挺胸得意：连续打卡、破纪录
    case proud
    /// 拿着数据板：统计页
    case stats

    fileprivate var assetName: String { "mascot_pose_\(rawValue)" }
}

// MARK: - 头像

/// 圆形头像：只露头和半截肩。
///
/// 情绪素材本身是 300×359 的「头 + 肩膀」，而且**肩膀是被硬切掉的**
/// （抠图时素材下沿就是一刀平切）。所以这里按 `.fill` 铺满后**顶对齐**、
/// 让圆在下部切一刀：切在头发或衣服上是圆的自然边缘，切在肩膀那条平切线上会露出一条直线。
struct MascotAvatar: View {

    let emotion: MascotEmotion
    var size: CGFloat
    var halo: Bool

    init(_ emotion: MascotEmotion, size: CGFloat = 56, halo: Bool = true) {
        self.emotion = emotion
        self.size = size
        self.halo = halo
    }

    var body: some View {
        ZStack {
            if halo {
                Circle().fill(Theme.Colors.mascotHalo)
            }

            Image(emotion.assetName)
                .resizable()
                // `.fill` + `alignment: .top`：宽度铺满、纵向溢出，溢出的部分被下面的圆裁掉。
                // 换成 `.fit` 会把整条肩膀平切线留在圆里，像贴了张剪歪的贴纸。
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size, alignment: .top)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if halo {
                Circle().strokeBorder(Theme.Colors.separator, lineWidth: 1)
            }
        }
        // 纯装饰：语义由旁边的文字承担，读屏念一遍「图片」只会打断句子。
        .accessibilityHidden(true)
    }
}

// MARK: - 只画一张脸
//
//  和 `MascotAvatar` 的区别：不裁圆、不带底盘。
//  开关行、评分角标这种「挨着一行文字」的位置，圆形头像会显得像另起一个控件；
//  直接放一张脸，视觉上是这句话的表情，不是一张图。

/// 一张脸，高度即尺寸，不裁圆。
struct MascotFace: View {

    let emotion: MascotEmotion
    var height: CGFloat

    init(_ emotion: MascotEmotion, height: CGFloat = 38) {
        self.emotion = emotion
        self.height = height
    }

    var body: some View {
        Image(emotion.assetName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

// MARK: - 一起听
//
//  播放中轻轻点头（±2.5°，1.1 秒一个来回）。幅度必须小：她只有几十点高，
//  转到 5° 以上看着像在摇头否定。关掉「减弱动态效果」时完全不转。

struct MascotListening: View {

    var playing: Bool
    var height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilted = false

    init(playing: Bool, height: CGFloat = 56) {
        self.playing = playing
        self.height = height
    }

    var body: some View {
        MascotFigure(.headphone, height: height)
            .rotationEffect(.degrees(tilted ? 2.5 : 0), anchor: .bottom)
            .onAppear { sync() }
            .onChange(of: playing) { _, _ in sync() }
    }

    private func sync() {
        guard playing, !reduceMotion else {
            // 停下时要显式归零：只取消动画的话，她会歪着停在那儿。
            withAnimation(.easeOut(duration: 0.2)) { tilted = false }
            return
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            tilted = true
        }
    }
}

// MARK: - 全身

/// 全身立绘。`height` 是**整个画面的高度**，宽度由素材比例决定（不裁切）。
struct MascotFigure: View {

    let pose: MascotPose
    var height: CGFloat

    init(_ pose: MascotPose, height: CGFloat = 180) {
        self.pose = pose
        self.height = height
    }

    var body: some View {
        Image(pose.assetName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

// MARK: - 舞台
//
//  立绘不能直接贴在卡片上：她的轮廓线是深海军蓝，落在深色卡片上会整片糊掉。
//  所以凡是「站着」出现的地方，都先给一块淡色圆当底（见 Theme.Colors.mascotHalo）。
//  圆比人小、人往圆下沿外站一点，看起来才是站在这里，而不是印在圆里。

/// 立绘 + 底盘。空态、背完一组这类「有整块留白」的地方都用它。
struct MascotStage: View {

    let pose: MascotPose
    /// 立绘高度（不是整块高度）
    var figureHeight: CGFloat
    /// 底盘圆的直径
    var disc: CGFloat

    init(_ pose: MascotPose, figureHeight: CGFloat = 140, disc: CGFloat = 156) {
        self.pose = pose
        self.figureHeight = figureHeight
        self.disc = disc
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(Theme.Colors.mascotHalo)
                .frame(width: disc, height: disc)

            MascotFigure(pose, height: figureHeight)
        }
        // 按「脚踩同一条地线」对齐，不做偏移：人比圆高时头和肩自然冒出圆外，
        // 像站在一束光前面；人比圆矮时（趴睡那种横图）就坐在圆里。
        // 两种比例都不用改参数，也不会溢出到下面的文字上。
        .frame(height: max(disc, figureHeight))
        .accessibilityHidden(true)
    }
}

// MARK: - 空态

/// 整屏空态：形象 + 一句解释 +（可选）一个出口。
///
/// 系统 `ContentUnavailableView` 的图标位只放得下一个 SF Symbol（尺寸、字重都被系统锁死），
/// 塞不进立绘。这是本项目**唯一**自建空态的地方，其余空态继续用系统组件
/// （见 `Components.swift` 里那段说明）。
struct MascotEmptyState: View {

    /// 给了 `pose` 就站着，没给就只露头（小屏或区块内空态用头像更省地方）。
    var pose: MascotPose?
    var emotion: MascotEmotion
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        pose: MascotPose? = nil,
        emotion: MascotEmotion = .think,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.pose = pose
        self.emotion = emotion
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Space.md) {
            stage

            Text(title)
                .font(Typography.titleSmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .appCaption()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                SecondaryButton(actionTitle, action: action)
                    .frame(maxWidth: 220)
                    .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.xl)
    }

    @ViewBuilder
    private var stage: some View {
        if let pose {
            MascotStage(pose)
                .padding(.bottom, Space.xs)
        } else {
            MascotAvatar(emotion, size: 88)
                .padding(.bottom, Space.xs)
        }
    }
}
