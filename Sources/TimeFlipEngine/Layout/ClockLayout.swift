import CoreGraphics

public enum ClockLayout {
    /// 由容器宽度反算单个数字卡片宽度。
    /// 每个冒号占 0.4 个字宽，每个缝隙占 0.12 个字宽。
    public static func digitWidth(containerWidth: CGFloat, slots: Int, colons: Int) -> CGFloat {
        guard containerWidth > 0, slots > 0 else { return 0 }
        let gaps = max(0, slots + colons - 1)
        let units = CGFloat(slots) + 0.4 * CGFloat(colons) + 0.12 * CGFloat(gaps)
        return max(1, containerWidth / units)
    }
}
