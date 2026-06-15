//
//  ReactorCoreGame.swift
//  Reactor Core — standard click-based physics game.
//
//  Physics: positive void coefficient · Xenon-135 poisoning · graphite tip displacement flaw.
//  Gameplay: rods drift toward withdrawal; tap / hold individual rods to re-insert.
//  Meltdown triggers when core reactivity reaches 100%.
//

import SwiftUI
import Combine

// MARK: - Game Mode

enum GameMode {
    case standard          // click-based crisis management
    case longPlay          // thermodynamic simulation with slider controls
    case tutorialStandard  // guided walkthrough of the standard game
    case tutorialLongPlay  // guided walkthrough of the longplay mode
}

// MARK: - Hexagon Shape

struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let r  = min(rect.width, rect.height) / 2
        var path = Path()
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 - .pi / 6
            let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - ControlRod

struct ControlRod: Identifiable {
    let id: Int
    var currentPosition: Double       // 0.0 = inserted/safe, 1.0 = withdrawn/critical
    var targetPosition:  Double       // rod body follows this at rodVelocity per tick
    var stress: Double = 0.0
    var isJammed: Bool = false
    var jamRemaining: Double = 0.0
    var graphiteTipTicksRemaining: Int = 0

    var insertion: Double { currentPosition }

    var color: Color {
        if isJammed { return Color(red: 0.28, green: 0.22, blue: 0.80) }
        if graphiteTipTicksRemaining > 0 { return Color(red: 0.0, green: 0.85, blue: 0.85) }
        return currentPosition < 0.5
            ? Color(red: currentPosition / 0.5, green: 1.0, blue: 0.0)
            : Color(red: 1.0, green: 1.0 - (currentPosition - 0.5) / 0.5, blue: 0.0)
    }
}

// MARK: - ReactorViewModel

final class ReactorViewModel: ObservableObject {

    // MARK: Published state

    @Published var rods: [ControlRod]
    @Published var reactivity: Double = 0.0    // 0.0–1.0; meltdown at 1.0
    @Published var isMeltdown:   Bool  = false
    @Published var elapsedTicks: Int   = 0
    @Published var flashOn:      Bool  = false

    // Physics readouts shown in the info panel
    @Published var coolantTemperature: Double = 30.0
    @Published var steamVoidRatio:     Double = 0.0
    @Published var iodineLevel:        Double = 0.0
    @Published var xenonLevel:         Double = 0.0

    // MARK: Physics constants

    private let tickInterval: TimeInterval = 0.10
    private let rodVelocity:  Double = 0.05

    // Rod drift: target positions naturally creep toward full withdrawal each tick.
    private let baseDrift: Double = 0.005

    private let graphiteTipDuration:    Int    = 5
    private let graphiteTipBoostPerRod: Double = 0.40

    // Steam / thermal
    private let heatGainFactor:  Double = 0.50   // °C/tick per unit effective reactivity
    private let heatDissipation: Double = 0.003  // fraction of excess heat lost per tick
    private let boilingPoint:    Double = 100.0
    private let steamAmplification: Double = 3.5 // PVC: effR = netR × (1 + SVR × this)
    private let steamRiseRate:   Double = 0.06
    private let steamFallRate:   Double = 0.08

    // Xenon / Iodine (~1000× real timescale compression)
    private let iodineProductionRate: Double = 0.0012
    private let iodineDecayRate:      Double = 0.0007
    private let xenonBurnRate:        Double = 0.0030
    private let xenonNaturalDecay:    Double = 0.00015

    // Stress / jam
    private let stressPerTap:       Double = 0.28
    private let stressPerHold:      Double = 0.012
    private let stressDecayPerTick: Double = 0.028
    private let jamDuration:        Double = 3.5
    let tapReduction:        Double = 0.30
    let holdReductionPerTick:Double = 0.025

    // MARK: Timers

    private var timer:         Timer?
    private var alarmTimer:    Timer?
    private var alarmInterval: TimeInterval = 0
    private var flashTimer:    Timer?
    private var flashInterval: TimeInterval = 0

    // MARK: Derived display properties

    var jammedCount: Int { rods.filter(\.isJammed).count }
    var coreTemp:    Int { Int(coolantTemperature) }
    var powerMW:     Int { Int(reactivity * 3200) }

    var survivalTime: String {
        let s = Int(Double(elapsedTicks) * tickInterval)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // Combined thermal + neutronic stress drives the threat indicator.
    var thermalStress: Double {
        max(reactivity, min(1.0, (coolantTemperature - 30.0) / 470.0))
    }

    var threatLabel: String {
        switch thermalStress {
        case ..<0.20: return "STABLE"
        case ..<0.40: return "NOMINAL"
        case ..<0.55: return "ELEVATED"
        case ..<0.70: return "HIGH"
        case ..<0.85: return "CRITICAL"
        default:      return "EXCURSION"
        }
    }

    var threatColor: Color {
        switch thermalStress {
        case ..<0.40: return Color(red: 0.35, green: 0.85, blue: 0.45)
        case ..<0.55: return .yellow
        case ..<0.70: return .orange
        default:      return .red
        }
    }

    // MARK: Init

    init() {
        rods = (0..<25).map { id in
            let p = Double.random(in: 0.10...0.30)
            return ControlRod(id: id, currentPosition: p, targetPosition: p)
        }
        startSimulation()
    }

    // MARK: Lifecycle

    func startSimulation() {
        timer?.invalidate()
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopSimulation() {
        timer?.invalidate(); timer = nil
        stopAlarmHaptics(); stopFlashEffect()
    }

    func pauseGame()  { stopSimulation() }
    func resumeGame() { guard !isMeltdown else { return }; startSimulation() }

    func reset() {
        stopAlarmHaptics(); stopFlashEffect()
        rods = (0..<25).map { id in
            let p = Double.random(in: 0.10...0.30)
            return ControlRod(id: id, currentPosition: p, targetPosition: p)
        }
        reactivity = 0.0; isMeltdown = false; elapsedTicks = 0
        coolantTemperature = 30.0; steamVoidRatio = 0.0
        iodineLevel = 0.0; xenonLevel = 0.0
        startSimulation()
    }

    // Starts with all rods fully inserted and safe — used by StandardTutorialView.
    func resetToSafe() {
        stopAlarmHaptics(); stopFlashEffect()
        rods = (0..<25).map { id in ControlRod(id: id, currentPosition: 0.0, targetPosition: 0.0) }
        reactivity = 0.0; isMeltdown = false; elapsedTicks = 0
        coolantTemperature = 30.0; steamVoidRatio = 0.0
        iodineLevel = 0.0; xenonLevel = 0.0
        startSimulation()
    }

    // MARK: Physics tick

    private func tick() {
        guard !isMeltdown else { return }
        elapsedTicks += 1

        // 1. Rod mechanics: natural drift, inertia, graphite tip detection.
        stepRodPhysics()

        // 2. Base reactivity from rod positions + graphite tip bursts.
        let base = computeBaseReactivity()

        // 3. Xenon penalty from the previous tick's absorber level.
        let xenonPenalty = xenonLevel * 0.45
        let net          = max(0.0, base - xenonPenalty)

        // 4. Steam void amplification (positive void coefficient).
        reactivity = min(1.0, net * (1.0 + steamVoidRatio * steamAmplification))

        // 5. Xe/I chain and coolant dynamics driven by effective reactivity.
        stepXenonIodine(reactivity: reactivity)
        stepSteamDynamics(reactivity: reactivity)

        updateAlarmHaptics()
        updateFlashEffect()
        if reactivity >= 1.0 { triggerMeltdown() }
    }

    // MARK: Rod physics (drift-based)

    private func stepRodPhysics() {
        for i in rods.indices {
            if rods[i].isJammed {
                // Jammed rod retracts at 3× drift speed until the jam clears.
                rods[i].currentPosition = min(1.0, rods[i].currentPosition + baseDrift * 3.0)
                rods[i].jamRemaining -= tickInterval
                if rods[i].jamRemaining <= 0 {
                    rods[i].isJammed       = false
                    rods[i].stress         = 0.25
                    rods[i].targetPosition = rods[i].currentPosition
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
                    #endif
                }
                continue
            }

            // Natural withdrawal drift with per-rod randomness.
            rods[i].targetPosition = min(1.0,
                rods[i].targetPosition + baseDrift * Double.random(in: 0.6...1.4))

            // Graphite tip displacement flaw: entering the core from a near-withdrawn position
            // adds reactivity for ~0.5 s before the boron absorber section takes over.
            if rods[i].currentPosition >= 0.90
                && rods[i].targetPosition < rods[i].currentPosition
                && rods[i].graphiteTipTicksRemaining == 0 {
                rods[i].graphiteTipTicksRemaining = graphiteTipDuration
            }

            let delta = rods[i].targetPosition - rods[i].currentPosition
            if abs(delta) <= rodVelocity { rods[i].currentPosition = rods[i].targetPosition }
            else { rods[i].currentPosition += delta > 0 ? rodVelocity : -rodVelocity }
            rods[i].currentPosition = max(0.0, min(1.0, rods[i].currentPosition))

            rods[i].stress = max(0.0, rods[i].stress - stressDecayPerTick)
            if rods[i].graphiteTipTicksRemaining > 0 { rods[i].graphiteTipTicksRemaining -= 1 }
        }
    }

    private func computeBaseReactivity() -> Double {
        var total = 0.0
        for rod in rods {
            var c = rod.currentPosition
            if rod.graphiteTipTicksRemaining > 0 {
                let fade = Double(rod.graphiteTipTicksRemaining) / Double(graphiteTipDuration)
                c += graphiteTipBoostPerRod * fade
            }
            total += c
        }
        return min(1.5, total / Double(rods.count))
    }

    // MARK: Xenon / Iodine

    private func stepXenonIodine(reactivity r: Double) {
        let iodineProduced = r * iodineProductionRate
        let iodineDecayed  = iodineLevel * iodineDecayRate
        iodineLevel = max(0.0, min(1.0, iodineLevel + iodineProduced - iodineDecayed))

        let xenonProduced = iodineDecayed
        let xenonBurned   = xenonLevel * r * xenonBurnRate
        let xenonDecayed  = xenonLevel * xenonNaturalDecay
        xenonLevel = max(0.0, min(1.0, xenonLevel + xenonProduced - xenonBurned - xenonDecayed))
    }

    // MARK: Steam / thermal

    private func stepSteamDynamics(reactivity r: Double) {
        coolantTemperature += r * heatGainFactor
        coolantTemperature -= (coolantTemperature - 30.0) * heatDissipation
        coolantTemperature  = max(30.0, coolantTemperature)

        if coolantTemperature > boilingPoint {
            let excessHeat = (coolantTemperature - boilingPoint) / 300.0
            let targetVoid = min(1.0, excessHeat)
            steamVoidRatio += (targetVoid - steamVoidRatio) * steamRiseRate
        } else {
            steamVoidRatio -= steamVoidRatio * steamFallRate
        }
        steamVoidRatio = max(0.0, min(1.0, steamVoidRatio))
    }

    // MARK: Rod interaction

    func tapRod(_ id: Int) {
        guard !isMeltdown, let i = rods.firstIndex(where: { $0.id == id }) else { return }
        if rods[i].isJammed {
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
            return
        }
        rods[i].stress = min(1.0, rods[i].stress + stressPerTap)
        if rods[i].stress >= 1.0 {
            rods[i].isJammed       = true
            rods[i].jamRemaining   = jamDuration
            rods[i].currentPosition = min(1.0, rods[i].currentPosition + 0.12)
            rods[i].targetPosition  = rods[i].currentPosition
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
            #endif
        } else {
            rods[i].targetPosition = max(0.0, rods[i].targetPosition - tapReduction)
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }
    }

    func holdRod(_ id: Int) {
        guard !isMeltdown, let i = rods.firstIndex(where: { $0.id == id }) else { return }
        guard !rods[i].isJammed else { return }
        rods[i].stress = min(1.0, rods[i].stress + stressPerHold)
        rods[i].targetPosition = max(0.0, rods[i].targetPosition - holdReductionPerTick)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
        #endif
    }

    // MARK: Alarm haptics

    private func updateAlarmHaptics() {
        #if os(iOS)
        guard thermalStress > 0.40 && !isMeltdown else { stopAlarmHaptics(); return }
        let t      = (thermalStress - 0.40) / 0.60
        let target = max(0.05, 0.45 * pow(0.11, t))
        guard alarmTimer == nil || abs(target - alarmInterval) > 0.02 else { return }
        alarmInterval = target; alarmTimer?.invalidate()
        let genA = UIImpactFeedbackGenerator(style: .heavy)
        let genB = UIImpactFeedbackGenerator(style: .heavy)
        genA.prepare(); genB.prepare()
        var flip = false
        let at = Timer(timeInterval: target, repeats: true) { [weak self] _ in
            guard let self, !self.isMeltdown else { return }
            let live      = max(0.0, (self.thermalStress - 0.40) / 0.60)
            let intensity = CGFloat(min(1.0, 0.75 + live * 0.25))
            (flip ? genA : genB).impactOccurred(intensity: intensity)
            flip.toggle()
            if live > 0.3 {
                let sec = flip ? genA : genB
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                    guard let self, !self.isMeltdown else { return }
                    sec.impactOccurred(intensity: intensity)
                }
            }
        }
        RunLoop.main.add(at, forMode: .common)
        alarmTimer = at
        #endif
    }

    private func stopAlarmHaptics() {
        alarmTimer?.invalidate(); alarmTimer = nil; alarmInterval = 0
    }

    // MARK: Flash effect

    private func updateFlashEffect() {
        guard reactivity > 0.75 && !isMeltdown else { stopFlashEffect(); return }
        let t      = (reactivity - 0.75) / 0.25
        let target = max(0.07, 0.5 * pow(0.14, t))
        guard flashTimer == nil || abs(target - flashInterval) > 0.02 else { return }
        flashInterval = target; flashTimer?.invalidate()
        let ft = Timer(timeInterval: target, repeats: true) { [weak self] _ in self?.flashOn.toggle() }
        RunLoop.main.add(ft, forMode: .common)
        flashTimer = ft
    }

    private func stopFlashEffect() {
        flashTimer?.invalidate(); flashTimer = nil; flashInterval = 0; flashOn = false
    }

    // MARK: Meltdown

    private func triggerMeltdown() {
        reactivity = 1.0; isMeltdown = true
        stopSimulation()
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
}

// MARK: - Hex Rod Cell

struct HexRodCell: View {
    let rod: ControlRod
    let onTap: () -> Void
    let onHold: () -> Void

    @State private var isPressing = false
    @State private var holdTimer: Timer?
    @State private var jamPulse = false

    var body: some View {
        Hexagon()
            .fill(rod.color)
            .overlay(Hexagon().stroke(Color.black.opacity(0.5), lineWidth: 1.5))
            .overlay(
                Hexagon()
                    .stroke(Color.orange.opacity(rod.isJammed ? 0 : rod.stress * 0.7), lineWidth: 3)
            )
            .overlay(
                Hexagon()
                    .stroke(
                        Color(red: 0.45, green: 0.4, blue: 1.0)
                            .opacity(rod.isJammed ? (jamPulse ? 0.9 : 0.2) : 0),
                        lineWidth: 2.5
                    )
                    .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: jamPulse)
            )
            .overlay(
                Hexagon()
                    .stroke(
                        Color(red: 0.0, green: 0.9, blue: 0.9)
                            .opacity(rod.graphiteTipTicksRemaining > 0 ? 0.85 : 0),
                        lineWidth: 2.5
                    )
            )
            .overlay(
                Hexagon().stroke(Color.white.opacity(isPressing && !rod.isJammed ? 0.55 : 0.0), lineWidth: 2)
            )
            .shadow(
                color: rod.isJammed
                    ? Color(red: 0.35, green: 0.3, blue: 1.0).opacity(0.65)
                    : rod.color.opacity(rod.insertion > 0.6 ? 0.75 : 0.2),
                radius: rod.isJammed ? 9 : (rod.insertion > 0.6 ? 7 : 1)
            )
            .scaleEffect(isPressing && !rod.isJammed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.15), value: rod.insertion)
            .animation(.easeOut(duration: 0.10), value: isPressing)
            .onAppear { jamPulse = true }
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
                        holdTimer?.invalidate(); holdTimer = nil
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
            let hexRFromW = (geo.size.width  - 4.5 * gap) / (5.5 * sqrt(3))
            let hexRFromH = (geo.size.height - 4.0 * gap) / 8
            let hexR      = min(hexRFromW, hexRFromH)
            let hexW      = sqrt(3) * hexR
            let hexH      = 2 * hexR
            let colSpacing = hexW + gap
            let rowSpacing = hexH * 0.75 + gap
            let xOrigin   = (geo.size.width  - (5.5 * hexW + 4.5 * gap)) / 2
            let yOrigin   = (geo.size.height - (hexH + CGFloat(rows - 1) * rowSpacing)) / 2

            ZStack(alignment: .topLeading) {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<cols, id: \.self) { col in
                        let idx = row * cols + col
                        let xOff: CGFloat = row % 2 == 1 ? colSpacing / 2 : 0
                        let x = xOrigin + xOff + CGFloat(col) * colSpacing + hexW / 2
                        let y = yOrigin + CGFloat(row) * rowSpacing + hexH / 2
                        HexRodCell(rod: rods[idx],
                                   onTap: { onTap(idx) },
                                   onHold: { onHold(idx) })
                            .frame(width: hexW, height: hexH)
                            .position(x: x, y: y)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Reactor Info Panel

struct ReactorInfoPanel: View {
    @ObservedObject var viewModel: ReactorViewModel
    let onHelp: () -> Void
    let onMenu: () -> Void
    let reactorName: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: onMenu) {
                    Text("←")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color(red: 0.35, green: 0.85, blue: 0.45).opacity(0.5), lineWidth: 1))
                }
                Text(reactorName)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                    .tracking(1.0)
                    .frame(maxWidth: .infinity)
                Spacer()
                Button(action: onHelp) {
                    Text("?")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color(red: 0.35, green: 0.85, blue: 0.45).opacity(0.5), lineWidth: 1))
                }
            }

            HStack(spacing: 0) {
                readout("COOLANT", "\(viewModel.coreTemp)°C", color: coolantColor(viewModel.coolantTemperature))
                sep
                readout("STATUS",  viewModel.threatLabel, color: viewModel.threatColor)
                sep
                readout("JAMMED",  "\(viewModel.jammedCount)",
                        color: viewModel.jammedCount > 0 ? Color(red: 0.45, green: 0.4, blue: 1.0) : .white)
                sep
                readout("ELAPSED", viewModel.survivalTime)
            }

            Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)

            HStack(spacing: 0) {
                readout("XE-135",  String(format: "%.0f%%", viewModel.xenonLevel * 100),
                        color: viewModel.xenonLevel > 0.5 ? .orange : viewModel.xenonLevel > 0.25 ? .yellow : .white)
                sep
                readout("STEAM",   String(format: "%.0f%%", viewModel.steamVoidRatio * 100),
                        color: viewModel.steamVoidRatio > 0.4 ? .red : viewModel.steamVoidRatio > 0.1 ? .yellow : .white)
                sep
                readout("I-135",   String(format: "%.0f%%", viewModel.iodineLevel * 100),
                        color: Color.white.opacity(0.7))
                sep
                readout("POWER",   "\(viewModel.powerMW) MW")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(white: 0.06))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(red: 0.2, green: 0.55, blue: 0.25).opacity(0.6), lineWidth: 1))
        .cornerRadius(8)
    }

    private func coolantColor(_ t: Double) -> Color {
        t < 100 ? Color(red: 0.35, green: 0.85, blue: 0.45) : t < 200 ? .yellow : t < 270 ? .orange : .red
    }

    private var sep: some View {
        Rectangle().fill(Color.gray.opacity(0.25)).frame(width: 1, height: 28).padding(.horizontal, 5)
    }

    private func readout(_ label: String, _ value: String, color: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .regular, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.65))
                .tracking(0.4)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}


// MARK: - Main View (standard game)

struct ReactorCoreView: View {
    let mode: GameMode
    let onReturnToMenu: () -> Void

    @StateObject private var viewModel = ReactorViewModel()
    @State private var showHelp = false
    @State private var reactorName = reactorNames.randomElement()!

    var body: some View {
        ZStack {
            mainContent
            if showHelp {
                PagedHelpModal(isPresented: $showHelp, pages: standardHelpPages).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showHelp)
        .onChange(of: showHelp) { _, paused in
            paused ? viewModel.pauseGame() : viewModel.resumeGame()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 12) {
            ReactorInfoPanel(viewModel: viewModel, onHelp: { showHelp = true }, onMenu: {
                viewModel.pauseGame()
                onReturnToMenu()
            }, reactorName: reactorName)

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
        let t = (viewModel.reactivity - 0.75) / 0.25
        return 0.12 + t * 0.30
    }

    private var reactivityMeter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CORE REACTIVITY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white).tracking(1.5)
                Spacer()
                Text("\(Int(viewModel.reactivity * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(meterColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(meterColor)
                        .frame(width: geo.size.width * CGFloat(viewModel.reactivity))
                        .animation(.easeOut(duration: 0.15), value: viewModel.reactivity)
                }
            }
            .frame(height: 8)
        }
    }

    private var meterColor: Color {
        switch viewModel.reactivity {
        case ..<0.5: return Color(red: 0.1, green: 0.85, blue: 0.35)
        case ..<0.8: return .yellow
        default:     return .red
        }
    }

    private var meltdownOverlay: some View {
        VStack(spacing: 10) {
            Text("⚠ MELTDOWN ⚠")
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .foregroundColor(.red)
            Text("REACTIVITY EXCURSION · CORE DESTROYED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.7)).tracking(0.8)
            Text("SURVIVAL: \(viewModel.survivalTime)")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
            Button("RESET REACTOR") { viewModel.reset() }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 20).padding(.vertical, 9)
                .background(Color.red.opacity(0.85))
                .foregroundColor(.white).cornerRadius(5)
            Button("RETURN TO MENU") { onReturnToMenu() }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45).opacity(0.75))
                .padding(.top, 2)
        }
        .padding(16)
        .background(Color.black.opacity(0.92))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Launch Menu

let reactorNames: [String] = [
    "CHORNOBYL NUCLEAR POWER PLANT · UNIT 4",   // Ukraine
    "FUKUSHIMA DAIICHI · UNIT 1",                // Japan
    "THREE MILE ISLAND · UNIT 2",               // USA
    "WINDSCALE PILE NO. 1",                     // UK
    "LENINGRAD NPP · UNIT 1",                   // Russia
    "SAINT-LAURENT · UNIT A2",                  // France
    "SL-1 EXPERIMENTAL REACTOR",               // USA (Idaho)
    "KOZLODUY NPP · UNIT 1",                    // Bulgaria
    "GREIFSWALD NPP · UNIT 5",                  // Germany (East)
    "CHALK RIVER NRX",                          // Canada
    "LUCENS EXPERIMENTAL REACTOR",              // Switzerland
    "ENRICO FERMI · UNIT 1",                    // USA (Michigan)
    "BOHUNICE A1 · UNIT 1",                     // Slovakia
    "VANDELLOS I NPP",                          // Spain
    "JASLOVSKÉ BOHUNICE NPP",                   // Slovakia
]

struct LaunchMenuView: View {
    let onStart: (GameMode) -> Void

    @State private var glow = false
    @State private var reactorIndex = 0
    @State private var reactorVisible = true

    var body: some View {
        ZStack {
            Color(white: 0.03).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                titleBlock
                Spacer().frame(height: 52)
                buttonBlock
                Spacer()
                footerText
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            glow = true
            Timer.scheduledTimer(withTimeInterval: 3.2, repeats: true) { _ in
                withAnimation { reactorVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    reactorIndex = (reactorIndex + 1) % reactorNames.count
                    withAnimation { reactorVisible = true }
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 14) {
            hazardStripe
            VStack(spacing: 8) {
                Text("MELTDOWN")
                    .font(.system(size: 52, weight: .black, design: .monospaced))
                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                    .tracking(6)
                    .shadow(
                        color: Color(red: 0.1, green: 0.7, blue: 0.2).opacity(glow ? 0.95 : 0.25),
                        radius: glow ? 22 : 5
                    )
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: glow)
                Text("REACTOR SIMULATION")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45).opacity(0.65))
                    .tracking(2.5)
                Text(reactorNames[reactorIndex])
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(Color.gray.opacity(0.4))
                    .tracking(1.2)
                    .opacity(reactorVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: reactorVisible)
            }
            hazardStripe
        }
    }

    private var hazardStripe: some View {
        Canvas { ctx, size in
            let sw: CGFloat = 11
            var x: CGFloat  = -size.height
            var alt          = false
            while x < size.width + size.height {
                var path = Path()
                path.move(to:    CGPoint(x: x,                y: 0))
                path.addLine(to: CGPoint(x: x + sw,           y: 0))
                path.addLine(to: CGPoint(x: x + sw + size.height, y: size.height))
                path.addLine(to: CGPoint(x: x      + size.height, y: size.height))
                path.closeSubpath()
                ctx.fill(path, with: .color(alt
                    ? Color.yellow.opacity(0.72)
                    : Color.black.opacity(0.80)))
                x  += sw
                alt.toggle()
            }
        }
        .frame(height: 9)
        .clipShape(Rectangle())
    }

    private var buttonBlock: some View {
        VStack(spacing: 14) {
            Button { onStart(.longPlay) } label: {
                VStack(spacing: 4) {
                    Text("▶  BEGIN SHIFT")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(red: 0.35, green: 0.85, blue: 0.45))
                        .cornerRadius(6)
                    Text("THERMODYNAMIC MODEL · XENON · COOLANT · SLIDER CONTROLS")
                        .font(.system(size: 7.5, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45).opacity(0.45))
                        .tracking(1)
                }
            }

            Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1).padding(.vertical, 2)

            tutorialButton("▸  TUTORIAL") { onStart(.tutorialLongPlay) }
        }
    }

    private func tutorialButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45).opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(red: 0.35, green: 0.85, blue: 0.45).opacity(0.18), lineWidth: 1))
        }
    }

    private var footerText: some View {
        Text("26 APRIL 1986  ·  01:23:40 MSK")
            .font(.system(size: 8, weight: .regular, design: .monospaced))
            .foregroundColor(Color.gray.opacity(0.25))
            .tracking(1)
            .padding(.bottom, 24)
    }
}

// MARK: - Root View

struct RootView: View {
    @State private var showGame = false
    @State private var gameMode: GameMode = .standard

    private var returnToMenu: () -> Void {
        { withAnimation(.easeInOut(duration: 0.30)) { showGame = false } }
    }

    var body: some View {
        ZStack {
            if showGame {
                activeGameView
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                LaunchMenuView { mode in
                    gameMode = mode
                    withAnimation(.easeInOut(duration: 0.30)) { showGame = true }
                }
                .transition(.opacity)
                .zIndex(0)
            }
        }
    }

    @ViewBuilder
    private var activeGameView: some View {
        switch gameMode {
        case .standard:
            ReactorCoreView(mode: .standard, onReturnToMenu: returnToMenu)
        case .longPlay:
            LongPlayView(onReturnToMenu: returnToMenu)
        case .tutorialStandard:
            StandardTutorialView(onReturnToMenu: returnToMenu)
        case .tutorialLongPlay:
            LongPlayTutorialView(onReturnToMenu: returnToMenu)
        }
    }
}

// MARK: - Preview

struct ReactorCoreView_Previews: PreviewProvider {
    static var previews: some View {
        ReactorCoreView(mode: .standard, onReturnToMenu: {})
    }
}
