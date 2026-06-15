//
//  ReactorCoreGame.swift
//  A 5x5 honeycomb control rod balancing prototype, built with pure SwiftUI.
//

import SwiftUI
import Combine

// MARK: - Hexagon Shape

struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let r = min(rect.width, rect.height) / 2
        var path = Path()
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 - .pi / 6  // pointy-top
            let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Model

struct ControlRod: Identifiable {
    let id: Int
    var insertion: Double = 0.0

    var color: Color {
        insertion < 0.5
            ? Color(red: insertion / 0.5, green: 1.0, blue: 0.0)
            : Color(red: 1.0, green: 1.0 - (insertion - 0.5) / 0.5, blue: 0.0)
    }
}

// MARK: - ViewModel

final class ReactorViewModel: ObservableObject {
    @Published var rods: [ControlRod]
    @Published var reactivity: Double = 0.0
    @Published var isMeltdown: Bool = false
    @Published var elapsedTicks: Int = 0

    private var timer: Timer?
    private var alarmTimer: Timer?
    private var alarmInterval: TimeInterval = 0
    private var flashTimer: Timer?
    private var flashInterval: TimeInterval = 0
    @Published var flashOn: Bool = false

    private let driftPerTick: Double = 0.012
    private let tickInterval: TimeInterval = 0.2

    let tapReduction: Double = 0.30
    let holdReductionPerTick: Double = 0.04

    init() {
        rods = (0..<25).map { ControlRod(id: $0, insertion: Double.random(in: 0.1...0.3)) }
        startSimulation()
    }

    var survivalTime: String {
        let s = Int(Double(elapsedTicks) * tickInterval)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var coreTemp: Int { Int(285 + reactivity * 415) }
    var powerMW: Int { Int(3200.0 * (0.2 + reactivity * 0.8)) }
    var neutronFlux: String { String(format: "%.2e", 1.2e13 * (0.3 + reactivity * 1.5)) }

    func startSimulation() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopSimulation() {
        timer?.invalidate()
        timer = nil
        stopAlarmHaptics()
        stopFlashEffect()
    }

    func pauseGame() {
        timer?.invalidate()
        timer = nil
        stopAlarmHaptics()
        stopFlashEffect()
    }

    func resumeGame() {
        guard !isMeltdown else { return }
        startSimulation()
    }

    private func tick() {
        guard !isMeltdown else { return }
        elapsedTicks += 1
        for i in rods.indices {
            rods[i].insertion = min(1.0, rods[i].insertion + driftPerTick * Double.random(in: 0.6...1.4))
        }
        recomputeReactivity()
    }

    private func recomputeReactivity() {
        let total = rods.reduce(0.0) { $0 + $1.insertion }
        reactivity = total / Double(rods.count)
        updateAlarmHaptics()
        updateFlashEffect()
        if reactivity >= 1.0 { triggerMeltdown() }
    }

    // MARK: Alarm haptics — continuous vibration scaling with reactivity

    private func updateAlarmHaptics() {
        #if os(iOS)
        guard reactivity > 0.5 && !isMeltdown else {
            stopAlarmHaptics()
            return
        }

        // t: 0 at 50% reactivity, 1 at 100%
        let t = (reactivity - 0.5) / 0.5
        // Interval collapses exponentially: 0.45s → 0.05s
        let target = max(0.05, 0.45 * pow(0.11, t))

        guard alarmTimer == nil || abs(target - alarmInterval) > 0.02 else { return }
        alarmInterval = target

        alarmTimer?.invalidate()

        // Two generators alternated on each tick — bypasses iOS coalescing
        // so the engine fires twice as many distinct impacts per second.
        let genA = UIImpactFeedbackGenerator(style: .heavy)
        let genB = UIImpactFeedbackGenerator(style: .heavy)
        genA.prepare()
        genB.prepare()

        var flip = false
        alarmTimer = Timer(timeInterval: target, repeats: true) { [weak self] _ in
            guard let self, !self.isMeltdown else { return }
            let live = max(0.0, (self.reactivity - 0.5) / 0.5)
            // High baseline intensity — 0.75 at threshold, 1.0 at 100%
            let intensity = CGFloat(min(1.0, 0.75 + live * 0.25))

            (flip ? genA : genB).impactOccurred(intensity: intensity)
            flip.toggle()

            // Above 65% reactivity fire a second impact 25 ms later for a hard double-hit
            if live > 0.3 {
                let secondary = flip ? genA : genB
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                    guard let self, !self.isMeltdown else { return }
                    secondary.impactOccurred(intensity: intensity)
                }
            }
        }
        RunLoop.main.add(alarmTimer!, forMode: .common)
        #endif
    }

    private func stopAlarmHaptics() {
        alarmTimer?.invalidate()
        alarmTimer = nil
        alarmInterval = 0
    }

    // MARK: Flash overlay — red screen pulse scaling with reactivity

    private func updateFlashEffect() {
        guard reactivity > 0.75 && !isMeltdown else {
            flashTimer?.invalidate()
            flashTimer = nil
            flashInterval = 0
            flashOn = false
            return
        }

        // t: 0 at 75%, 1 at 100%
        let t = (reactivity - 0.75) / 0.25
        // Interval: 0.5s at t=0 → 0.07s at t=1
        let target = max(0.07, 0.5 * pow(0.14, t))

        guard flashTimer == nil || abs(target - flashInterval) > 0.02 else { return }
        flashInterval = target
        flashTimer?.invalidate()

        flashTimer = Timer(timeInterval: target, repeats: true) { [weak self] _ in
            self?.flashOn.toggle()
        }
        RunLoop.main.add(flashTimer!, forMode: .common)
    }

    private func stopFlashEffect() {
        flashTimer?.invalidate()
        flashTimer = nil
        flashInterval = 0
        flashOn = false
    }

    // MARK: Meltdown haptics — escalating burst

    private func meltdownHaptics() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.prepare()
        for i in 1...8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                gen.impactOccurred(intensity: min(1.0, CGFloat(i) * 0.13))
            }
        }
        #endif
    }

    private func triggerMeltdown() {
        reactivity = 1.0
        isMeltdown = true
        stopSimulation()
        meltdownHaptics()
    }

    func tapRod(_ id: Int) {
        guard !isMeltdown, let i = rods.firstIndex(where: { $0.id == id }) else { return }
        rods[i].insertion = max(0.0, rods[i].insertion - tapReduction)
        recomputeReactivity()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    func holdRod(_ id: Int) {
        guard !isMeltdown, let i = rods.firstIndex(where: { $0.id == id }) else { return }
        rods[i].insertion = max(0.0, rods[i].insertion - holdReductionPerTick)
        recomputeReactivity()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
        #endif
    }

    func reset() {
        stopAlarmHaptics()
        stopFlashEffect()
        rods = (0..<25).map { ControlRod(id: $0, insertion: Double.random(in: 0.1...0.3)) }
        reactivity = 0.0
        isMeltdown = false
        elapsedTicks = 0
        startSimulation()
    }
}

// MARK: - Hex Rod Cell

struct HexRodCell: View {
    let rod: ControlRod
    let onTap: () -> Void
    let onHold: () -> Void

    @State private var isPressing = false
    @State private var holdTimer: Timer?

    var body: some View {
        Hexagon()
            .fill(rod.color)
            .overlay(Hexagon().stroke(Color.black.opacity(0.5), lineWidth: 1.5))
            .overlay(
                Hexagon().stroke(Color.white.opacity(isPressing ? 0.55 : 0.0), lineWidth: 2)
            )
            .shadow(
                color: rod.color.opacity(rod.insertion > 0.6 ? 0.75 : 0.2),
                radius: rod.insertion > 0.6 ? 7 : 1
            )
            .scaleEffect(isPressing ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.15), value: rod.insertion)
            .animation(.easeOut(duration: 0.1), value: isPressing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressing else { return }
                        isPressing = true
                        onTap()
                        let t = Timer(timeInterval: 0.1, repeats: true) { _ in onHold() }
                        RunLoop.main.add(t, forMode: .common)
                        holdTimer = t
                    }
                    .onEnded { _ in
                        isPressing = false
                        holdTimer?.invalidate()
                        holdTimer = nil
                    }
            )
    }
}

// MARK: - Honeycomb Grid

struct HoneycombGrid: View {
    let rods: [ControlRod]
    let onTap: (Int) -> Void
    let onHold: (Int) -> Void

    private let cols = 5, rows = 5
    private let gap: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            // Size hexes to fill available space in whichever dimension is tighter.
            // Width bound: fit 5 cols + half-col odd-row offset (5.5 col-widths total)
            let hexRFromW = (geo.size.width - 4.5 * gap) / (5.5 * sqrt(3))
            // Height bound: totalHeight = 8*hexR + 4*gap  (derived from 5-row honeycomb)
            let hexRFromH = (geo.size.height - 4 * gap) / 8
            let hexR = min(hexRFromW, hexRFromH)

            let hexW = sqrt(3) * hexR
            let hexH = 2 * hexR
            let colSpacing = hexW + gap
            let rowSpacing = hexH * 0.75 + gap

            // Center the hex content within whatever space the grid receives
            let actualW = 5.5 * hexW + 4.5 * gap
            let actualH = hexH + CGFloat(rows - 1) * rowSpacing
            let xOrigin = (geo.size.width - actualW) / 2
            let yOrigin = (geo.size.height - actualH) / 2

            ZStack(alignment: .topLeading) {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<cols, id: \.self) { col in
                        let idx = row * cols + col
                        let xOff: CGFloat = row % 2 == 1 ? colSpacing / 2 : 0
                        let x = xOrigin + xOff + CGFloat(col) * colSpacing + hexW / 2
                        let y = yOrigin + CGFloat(row) * rowSpacing + hexH / 2
                        HexRodCell(
                            rod: rods[idx],
                            onTap: { onTap(idx) },
                            onHold: { onHold(idx) }
                        )
                        .frame(width: hexW, height: hexH)
                        .position(x: x, y: y)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Help Modal

struct HelpModal: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("OPERATOR BRIEFING")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                        .tracking(1.5)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Text("✕")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.bottom, 16)

                divider

                section(title: "SITUATION") {
                    "You are the night-shift operator at Chornobyl Nuclear Power Plant, Unit 4. The RBMK-1000 reactor's control rods are slowly retracting on their own — a known design flaw. If average core reactivity reaches 100%, the reactor runs away and you lose."
                }

                divider

                section(title: "CONTROL RODS") {
                    "The 5×5 hexagonal grid represents the reactor's control rod channels. Each cell colour indicates its insertion depth:\n\n  GREEN  — rod fully inserted, low reactivity\n  YELLOW — rod partially withdrawn\n  RED     — rod nearly fully withdrawn, critical"
                }

                divider

                section(title: "CONTROLS") {
                    "TAP a rod to quickly re-insert it (−30% insertion).\n\nHOLD a rod to continuously drive it down. The longer you hold, the deeper it goes. Useful when multiple rods are in the red."
                }

                divider

                section(title: "AZ-5") {
                    "Named after the emergency SCRAM button used during the 1986 Chornobyl disaster. In the real event, pressing AZ-5 caused a brief reactivity spike before shutdown — the reactor's fatal flaw. Keep that in mind."
                }

                divider
                    .padding(.bottom, 16)

                Button(action: { isPresented = false }) {
                    Text("ACKNOWLEDGED — BEGIN SHIFT")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(red: 0.35, green: 0.85, blue: 0.45))
                        .cornerRadius(6)
                }
            }
            .padding(20)
            .background(Color(white: 0.07))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.2, green: 0.55, blue: 0.25).opacity(0.6), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.18))
            .frame(height: 1)
            .padding(.vertical, 12)
    }

    private func section(title: String, body: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.6))
                .tracking(2)
            Text(body())
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.85))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Reactor Info Panel

struct ReactorInfoPanel: View {
    @ObservedObject var viewModel: ReactorViewModel
    let onHelp: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("RBMK-1000  ·  UNIT 4  ·  CHORNOBYL NPP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                    .tracking(1.0)
                Spacer()
                Button(action: onHelp) {
                    Text("?")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().stroke(Color(red: 0.35, green: 0.85, blue: 0.45).opacity(0.5), lineWidth: 1)
                        )
                }
            }

            HStack(spacing: 0) {
                readout(label: "TEMP", value: "\(viewModel.coreTemp)°C")
                separator
                readout(label: "POWER", value: "\(viewModel.powerMW) MW")
                separator
                readout(label: "FLUX n/cm²s", value: viewModel.neutronFlux)
                separator
                readout(label: "ELAPSED", value: viewModel.survivalTime)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(white: 0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.2, green: 0.55, blue: 0.25).opacity(0.6), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.25))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 6)
    }

    private func readout(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .regular, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.65))
                .tracking(0.5)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Main View

struct ReactorCoreView: View {
    @StateObject private var viewModel = ReactorViewModel()
    @State private var showHelp = false

    var body: some View {
        ZStack {
            mainContent
            if showHelp {
                HelpModal(isPresented: $showHelp)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showHelp)
        .onChange(of: showHelp) { paused in
            paused ? viewModel.pauseGame() : viewModel.resumeGame()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 12) {
            ReactorInfoPanel(viewModel: viewModel, onHelp: { showHelp = true })

            reactivityMeter

            Text("CONTROL ROD ARRAY  ·  AZ-5 GRID")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.4))
                .tracking(2)

            HoneycombGrid(
                rods: viewModel.rods,
                onTap: { viewModel.tapRod($0) },
                onHold: { viewModel.holdRod($0) }
            )
            .overlay(viewModel.isMeltdown ? AnyView(meltdownOverlay) : AnyView(EmptyView()))
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color(white: 0.05).ignoresSafeArea())
        .overlay(
            Color.red
                .opacity(redFlashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.06), value: viewModel.flashOn)
        )
    }

    private var redFlashOpacity: Double {
        guard viewModel.flashOn && viewModel.reactivity > 0.75 && !viewModel.isMeltdown else { return 0 }
        let t = (viewModel.reactivity - 0.75) / 0.25  // 0 at 75%, 1 at 100%
        return 0.12 + t * 0.30  // 12% at threshold, up to 42% at meltdown
    }

    private var reactivityMeter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CORE REACTIVITY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(1.5)
                Spacer()
                Text("\(Int(viewModel.reactivity * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(meterColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(meterColor)
                        .frame(width: geo.size.width * CGFloat(viewModel.reactivity))
                        .animation(.easeOut(duration: 0.2), value: viewModel.reactivity)
                }
            }
            .frame(height: 8)
        }
    }

    private var meterColor: Color {
        switch viewModel.reactivity {
        case ..<0.5: return Color(red: 0.1, green: 0.85, blue: 0.35)
        case ..<0.8: return .yellow
        default: return .red
        }
    }

    private var meltdownOverlay: some View {
        VStack(spacing: 10) {
            Text("⚠ MELTDOWN ⚠")
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .foregroundColor(.red)
            Text("REACTIVITY EXCURSION · CORE DESTROYED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.7))
                .tracking(0.8)
            Text("SURVIVAL: \(viewModel.survivalTime)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
            Button("RESET REACTOR") { viewModel.reset() }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(Color.red.opacity(0.85))
                .foregroundColor(.white)
                .cornerRadius(5)
        }
        .padding(16)
        .background(Color.black.opacity(0.92))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Preview

struct ReactorCoreView_Previews: PreviewProvider {
    static var previews: some View {
        ReactorCoreView()
    }
}
