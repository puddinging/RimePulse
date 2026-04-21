import SwiftUI

struct SparklineRow: View {
    let metric: TrendMetric
    let records: [AggregatedRecord]

    private var totalValue: String { metric.totalFormatted(from: records) }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(metric.color)
                .frame(width: 6, height: 6)

            Text(metric.title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)

            Sparkline(values: records.map { metric.value(from: $0) }, color: metric.color)
                .frame(height: 18)

            Text(totalValue)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 62, alignment: .trailing)
                .contentTransition(.numericText(countsDown: false))
                .animation(.snappy(duration: 0.25), value: totalValue)
        }
        .frame(height: 18)
    }
}

/// Canvas-based sparkline — 完全不依赖 Swift Charts 框架，
/// 消除菜单栏首次打开时 Charts + Metal shader 的冷启动成本。
private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            draw(in: ctx, size: size)
        }
    }

    private func draw(in ctx: GraphicsContext, size: CGSize) {
        guard !values.isEmpty else { return }

        let topPad: CGFloat = 1.5
        let bottomPad: CGFloat = 1.5
        let drawableH = max(size.height - topPad - bottomPad, 1)
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 0.0001)

        func point(at i: Int) -> CGPoint {
            let x: CGFloat = values.count == 1
                ? size.width / 2
                : CGFloat(i) * (size.width / CGFloat(values.count - 1))
            let normalized = (values[i] - minV) / span
            let y = topPad + drawableH * (1 - CGFloat(normalized))
            return CGPoint(x: x, y: y)
        }

        let pts = (0..<values.count).map(point(at:))

        if pts.count >= 2 {
            let linePath = smoothedPath(points: pts)

            var areaPath = linePath
            areaPath.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
            areaPath.addLine(to: CGPoint(x: pts.first!.x, y: size.height))
            areaPath.closeSubpath()

            ctx.fill(
                areaPath,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.30), color.opacity(0)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            ctx.stroke(
                linePath,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            )
        }

        if let last = pts.last {
            let r: CGFloat = 2.35
            let dot = CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: dot), with: .color(color))
        }
    }

    /// Catmull-Rom → cubic Bezier 平滑，和旧 Chart `.interpolationMethod(.catmullRom)` 视觉一致。
    private func smoothedPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count >= 2 else { return path }

        for i in 0..<(points.count - 1) {
            let p0 = i == 0 ? points[i] : points[i - 1]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}
