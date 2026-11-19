import SwiftUI

/// 全局设计语言：统一主题色 + 可复用小组件。
/// 只做视觉层，不涉及任何交互逻辑。
enum AppTheme {
    /// 主色：与「板栗仁」源的图 detail tint 呼应（#5B5BD6）
    static let accent = Color(red: 0.357, green: 0.357, blue: 0.839)
    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.42, green: 0.40, blue: 0.90),
            Color(red: 0.31, green: 0.30, blue: 0.74)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 圆形/圆角图标徽章底色
    static func soft(_ color: Color) -> Color { color.opacity(0.13) }
}

/// 小胶囊标签：版本、架构、分类等
struct Badge: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.13), in: Capsule())
            .lineLimit(1)
    }
}

/// 圆角方块图标徽章（列表行首）
struct IconBadge: View {
    let symbol: String
    var color: Color = AppTheme.accent
    var side: CGFloat = 40
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.13))
            Image(systemName: symbol)
                .font(.system(size: side * 0.45, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(width: side, height: side)
    }
}

/// 空状态占位图（渐变圆 + 图标）
struct EmptyStateIcon: View {
    let symbol: String
    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentGradient)
                .frame(width: 84, height: 84)
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(.white)
        }
        .shadow(color: AppTheme.accent.opacity(0.28), radius: 14, y: 6)
    }
}
