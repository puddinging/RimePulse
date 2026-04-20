import Charts
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

            sparkChart
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

    private var sparkChart: some View {
        let values = records.map { metric.value(from: $0) }
        let lastIndex = records.indices.last

        return Chart {
            ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                let v = metric.value(from: record)

                LineMark(
                    x: .value("i", index),
                    y: .value("v", v)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(metric.color)
                .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                AreaMark(
                    x: .value("i", index),
                    y: .value("v", v)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [metric.color.opacity(0.30), metric.color.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }

            if let lastIndex, !values.isEmpty {
                PointMark(
                    x: .value("i", lastIndex),
                    y: .value("v", values[lastIndex])
                )
                .symbolSize(22)
                .foregroundStyle(metric.color)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.padding(.vertical, 1)
        }
        .animation(.snappy(duration: 0.25), value: records.count)
    }
}
