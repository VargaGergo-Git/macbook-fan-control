import SwiftUI
import MacFanControlCore

struct ThermalChartView: View {
    let samples: [HistorySample]
    let maxRPM: Double
    var showGPU: Bool = false

    @State private var hoverIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last 8 minutes")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let hoverIndex, samples.indices.contains(hoverIndex) {
                    Text(hoverCaption(samples[hoverIndex]))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            SurfaceCard(padding: 10) {
                if samples.count < 2 {
                    Text("Collecting samples…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                } else {
                    chart
                        .frame(height: 110)
                        .drawingGroup()
                    legend
                        .padding(.top, 6)
                }
            }
        }
    }

    private var chart: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let count = samples.count

            Canvas { context, size in
                drawPressureBands(context: &context, size: size, count: count)
                if let cpuPath = linePath(values: samples.map(\.cpuCelsius), in: size, range: 40...100) {
                    context.stroke(cpuPath, with: .color(AppTheme.heat), lineWidth: 1.8)
                }
                if showGPU, let gpuPath = linePath(values: samples.map(\.gpuCelsius), in: size, range: 40...100) {
                    context.stroke(gpuPath, with: .color(AppTheme.warm), lineWidth: 1.4)
                }
                if let rpmPath = linePath(values: samples.map(\.fanRPM), in: size, range: 0...max(maxRPM, 1)) {
                    context.stroke(
                        rpmPath,
                        with: .color(AppTheme.tealDeep.opacity(0.9)),
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                    )
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let index = Int((location.x / max(width, 1)) * CGFloat(count - 1) + 0.5)
                    hoverIndex = min(max(index, 0), count - 1)
                case .ended:
                    hoverIndex = nil
                }
            }

            if let hoverIndex, samples.indices.contains(hoverIndex), count > 1 {
                let x = CGFloat(hoverIndex) / CGFloat(count - 1) * width
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                .stroke(AppTheme.ink.opacity(0.2), lineWidth: 1)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: AppTheme.heat, title: "CPU")
            if showGPU {
                legendItem(color: AppTheme.warm, title: "GPU")
            }
            legendItem(color: AppTheme.tealDeep, title: "Fan", dashed: true)
            legendItem(color: AppTheme.calm.opacity(0.7), title: "Pressure")
            Spacer()
            Text("40–100 °C")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func legendItem(color: Color, title: String, dashed: Bool = false) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: dashed ? 10 : 8, height: 3)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func drawPressureBands(context: inout GraphicsContext, size: CGSize, count: Int) {
        guard count > 1 else { return }
        let bandWidth = size.width / CGFloat(count - 1)
        for index in 0..<(count - 1) {
            let rect = CGRect(x: CGFloat(index) * bandWidth, y: 0, width: bandWidth + 0.5, height: size.height)
            context.fill(Path(rect), with: .color(AppTheme.pressureColor(samples[index].pressure).opacity(0.14)))
        }
    }

    private func linePath(values: [Double?], in size: CGSize, range: ClosedRange<Double>) -> Path? {
        let points: [CGPoint] = values.enumerated().compactMap { index, value in
            guard let value else { return nil }
            let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
            let unit = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let clamped = min(max(unit, 0), 1)
            let y = size.height * (1 - CGFloat(clamped))
            return CGPoint(x: x, y: y)
        }
        guard points.count >= 2 else { return nil }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func hoverCaption(_ sample: HistorySample) -> String {
        var parts: [String] = [sample.pressure.label]
        if let cpu = sample.cpuCelsius {
            parts.append(String(format: "CPU %.0f°", cpu))
        }
        if showGPU, let gpu = sample.gpuCelsius {
            parts.append(String(format: "GPU %.0f°", gpu))
        }
        if let rpm = sample.fanRPM {
            parts.append("\(Int(rpm.rounded())) RPM")
        }
        return parts.joined(separator: " · ")
    }
}
