//
//  LongPlayViewModel.swift
//  Physics simulation and game state for LongPlay mode.
//
//  Views live in LongPlayViews.swift.
//  Event types live in LongPlayEvents.swift.
//  Shared grid types (ControlRod, HoneycombGrid, …) live in ReactorCoreGame.swift.
//

import SwiftUI
import Combine

final class LongPlayViewModel: ObservableObject {

    // MARK: - Player controls (slider bindings)

    @Published var coolantFlowRate:   Double = 0.60   // primary pump speed
    @Published var turbineValveOpen:  Double = 0.50   // steam-to-turbine valve
    @Published var autoPowerSetpoint: Double = 0.50   // APS target rod withdrawal

    // MARK: - Physics state

    @Published var rods: [ControlRod]
    @Published var coolantTemperature: Double = 30.0
    @Published var steamVoidRatio:     Double = 0.0
    @Published var iodineLevel:        Double = 0.0
    @Published var xenonLevel:         Double = 0.0
    @Published var xenonTrend:         Double = 0.0   // per-tick Δ; positive = rising
    @Published var megawattsProduced:  Double = 0.0
    @Published var cumulativeEnergy:   Double = 0.0   // MWh (demand-weighted)

    // MARK: - Game state

    @Published var isMeltdown:    Bool = false
    @Published var shiftEnded:    Bool = false
    @Published var elapsedTicks:  Int  = 0
    @Published var demandHitTicks:Int  = 0   // ticks within ±150 MW of grid demand
    @Published var peakTemp:      Double = 30.0
    @Published var flashOn:       Bool  = false

    // MARK: - Events

    @Published var gridDemand          = GridDemand()
    @Published var activeDisturbances: [ActiveDisturbance] = []

    // MARK: - Constants

    let shiftDurationTicks: Int    = 12000   // 20 min × 10 ticks/s
    let nominalPower:       Double = 3200.0  // MWt

    private let tickInterval:   TimeInterval = 0.10
    private let rodVelocity:    Double = 0.05
    private let apsRate:        Double = 0.02    // fast enough that setpoint changes feel immediate

    private let graphiteTipDuration:    Int    = 5
    private let graphiteTipBoostPerRod: Double = 0.40

    // Scaled up together so equilibrium temperatures are similar but response is ~5× faster.
    private let heatGainFactor:  Double = 1.5
    private let heatDissipCoeff: Double = 3.0
    private let boilingPoint:    Double = 100.0
    private let meltdownTemp:    Double = 330.0

    private let steamAmplification:   Double = 0.60
    private let steamGenFactor:       Double = 0.001   // 3× faster steam build
    private let steamTurbineDrain:    Double = 0.15    // scaled to match
    private let steamCoolantCondense: Double = 0.08

    private let iodineProductionRate: Double = 0.0012
    private let iodineDecayRate:      Double = 0.0007
    private let xenonBurnRate:        Double = 0.0030
    private let xenonNaturalDecay:    Double = 0.00015
    private let xenonPenaltyFactor:   Double = 0.50

    private let stressPerTap:        Double = 0.28
    private let stressPerHold:       Double = 0.012
    private let stressDecayPerTick:  Double = 0.028
    private let tapReduction:        Double = 0.40
    private let holdReductionPerTick:Double = 0.025
    private let jamDuration:         Double = 3.5

    // MARK: - Private

    private var timer:         Timer?
    private var flashTimer:    Timer?
    private var flashInterval: TimeInterval = 0
    private var scheduler      = DisturbanceScheduler()
    private var prevXenon:     Double = 0.0

    // MARK: - Derived display properties

    var coreTemp:    Int { Int(coolantTemperature) }
    var jammedCount: Int { rods.filter(\.isJammed).count }

    var remainingTicks: Int { max(0, shiftDurationTicks - elapsedTicks) }

    var shiftTimeRemaining: String {
        let s = Int(Double(remainingTicks) * tickInterval)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
    var survivalTime: String {
        let s = Int(Double(elapsedTicks) * tickInterval)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var effectiveCoolantFlow: Double {
        let maxLoss = activeDisturbances
            .filter { $0.kind == .pumpFault }
            .map    { $0.magnitude }
            .max() ?? 0.0
        return max(0.05, coolantFlowRate * (1.0 - maxLoss))
    }

    var thermalStress: Double { min(1.0, (coolantTemperature - 30.0) / (meltdownTemp - 30.0)) }

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

    var demandGapMW: Double { abs(megawattsProduced - gridDemand.targetMW) }
    var isOnDemand:  Bool   { demandGapMW < 150 }

    var demandColor: Color {
        demandGapMW < 150 ? Color(red: 0.35, green: 0.85, blue: 0.45)
            : demandGapMW < 400 ? .yellow : .red
    }

    var demandEfficiencyPercent: Double {
        guard elapsedTicks > 0 else { return 0 }
        return Double(demandHitTicks) / Double(elapsedTicks) * 100.0
    }

    // Warning shown in the UI when xenon is moving dangerously fast.
    var xenonAlert: String? {
        if xenonTrend > 0.00035 && xenonLevel > 0.35   { return "XE-135 RISING" }
        if xenonTrend < -0.00035 && xenonLevel > 0.25  { return "XE BURNOFF — SURGE RISK" }
        return nil
    }

    // MARK: - Init

    init() {
        // Start warm so the player sees power immediately rather than waiting for the boiler.
        rods = (0..<25).map { id in
            let p = Double.random(in: 0.40...0.65)
            return ControlRod(id: id, currentPosition: p, targetPosition: p)
        }
        coolantTemperature = 120.0
        steamVoidRatio     = 0.15
        startSimulation()
    }

    // MARK: - Lifecycle

    func startSimulation() {
        timer?.invalidate()
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopSimulation() {
        timer?.invalidate(); timer = nil
        stopFlash()
    }

    func pauseGame()  { stopSimulation() }
    func resumeGame() { guard !isMeltdown && !shiftEnded else { return }; startSimulation() }

    func reset() {
        stopSimulation()
        rods = (0..<25).map { id in
            let p = Double.random(in: 0.40...0.65)
            return ControlRod(id: id, currentPosition: p, targetPosition: p)
        }
        coolantTemperature = 120.0; steamVoidRatio = 0.15
        iodineLevel = 0.0;          xenonLevel = 0.0;    xenonTrend = 0.0
        megawattsProduced = 0.0;    cumulativeEnergy = 0.0
        isMeltdown = false;         shiftEnded = false
        elapsedTicks = 0;           demandHitTicks = 0;  peakTemp = 30.0
        gridDemand = GridDemand();  activeDisturbances = []
        coolantFlowRate = 0.60;     turbineValveOpen = 0.50;  autoPowerSetpoint = 0.50
        scheduler = DisturbanceScheduler();  prevXenon = 0.0
        startSimulation()
    }

    // MARK: - Main tick

    private func tick() {
        guard !isMeltdown && !shiftEnded else { return }
        elapsedTicks += 1

        if elapsedTicks >= shiftDurationTicks { endShift(); return }

        // Events
        gridDemand.tick(nominalPower: nominalPower)
        if let ev = scheduler.nextEvent(rodCount: rods.count) { applyDisturbance(ev) }
        tickDisturbances()

        // Physics
        stepRodPhysics()
        let base        = computeBaseReactivity()
        let xenonPenalty = xenonLevel * xenonPenaltyFactor
        let net         = max(0.0, base - xenonPenalty)
        let effR        = min(1.5, net * (1.0 + steamVoidRatio * steamAmplification))

        stepThermalLoop(reactivity: min(1.2, effR))
        stepSteamDynamics()
        stepXenonIodine(reactivity: min(1.0, effR))

        xenonTrend = xenonLevel - prevXenon
        prevXenon  = xenonLevel

        // Power and score
        megawattsProduced = steamVoidRatio * turbineValveOpen * nominalPower
        let gap   = demandGapMW
        let bonus = gap < 150 ? 1.5 : gap < 350 ? 1.1 : 1.0
        cumulativeEnergy += megawattsProduced * bonus * tickInterval / 3600.0
        if isOnDemand { demandHitTicks += 1 }

        if coolantTemperature > peakTemp { peakTemp = coolantTemperature }

        updateFlash()
        if coolantTemperature >= meltdownTemp { triggerMeltdown() }
    }

    // MARK: - Disturbances

    private func applyDisturbance(_ d: ActiveDisturbance) {
        switch d.kind {
        case .pumpFault:
            activeDisturbances.append(d)
            hapticWarning()

        case .rodJam:
            guard let rid = d.affectedRodId,
                  let i   = rods.firstIndex(where: { $0.id == rid }),
                  !rods[i].isJammed else { return }
            rods[i].isJammed     = true
            rods[i].jamRemaining = 4.0
            hapticWarning()
        }
    }

    private func tickDisturbances() {
        for i in activeDisturbances.indices { activeDisturbances[i].remainingTicks -= 1 }
        activeDisturbances.removeAll { $0.remainingTicks <= 0 }
    }

    // MARK: - Rod physics (APS-driven)

    private func stepRodPhysics() {
        for i in rods.indices {
            if rods[i].isJammed {
                rods[i].currentPosition = min(1.0, rods[i].currentPosition + 0.003)
                rods[i].jamRemaining   -= tickInterval
                if rods[i].jamRemaining <= 0 {
                    rods[i].isJammed = false; rods[i].stress = 0.2
                    rods[i].targetPosition = rods[i].currentPosition
                }
                continue
            }

            rods[i].targetPosition += (autoPowerSetpoint - rods[i].targetPosition) * apsRate
            rods[i].targetPosition  = max(0.0, min(1.0, rods[i].targetPosition))

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

    // MARK: - Thermal loop

    private func stepThermalLoop(reactivity r: Double) {
        let flow    = effectiveCoolantFlow
        let heatIn  = r * heatGainFactor
        let heatOut = flow * heatDissipCoeff * max(0.0, coolantTemperature - 30.0) / 300.0
        coolantTemperature += heatIn - heatOut
        coolantTemperature  = max(30.0, coolantTemperature)
    }

    private func stepSteamDynamics() {
        let flow       = effectiveCoolantFlow
        let gen        = max(0.0, coolantTemperature - boilingPoint) * steamGenFactor
        let viaTurbine = steamVoidRatio * turbineValveOpen * steamTurbineDrain
        let condensed  = steamVoidRatio * flow * steamCoolantCondense
        steamVoidRatio = max(0.0, min(1.0, steamVoidRatio + gen - viaTurbine - condensed))
    }

    private func stepXenonIodine(reactivity r: Double) {
        let iodineProduced = r * iodineProductionRate
        let iodineDecayed  = iodineLevel * iodineDecayRate
        iodineLevel = max(0.0, min(1.0, iodineLevel + iodineProduced - iodineDecayed))

        let xenonProduced = iodineDecayed
        let xenonBurned   = xenonLevel * r * xenonBurnRate
        let xenonDecayed  = xenonLevel * xenonNaturalDecay
        xenonLevel = max(0.0, min(1.0, xenonLevel + xenonProduced - xenonBurned - xenonDecayed))
    }

    // MARK: - Player rod interaction (APS override)

    func tapRod(_ id: Int) {
        guard !isMeltdown, let i = rods.firstIndex(where: { $0.id == id }) else { return }
        if rods[i].isJammed { hapticError(); return }
        rods[i].stress = min(1.0, rods[i].stress + stressPerTap)
        if rods[i].stress >= 1.0 {
            rods[i].isJammed = true; rods[i].jamRemaining = jamDuration
            rods[i].currentPosition = min(1.0, rods[i].currentPosition + 0.10)
            rods[i].targetPosition  = rods[i].currentPosition
            hapticWarning(); hapticHeavy()
        } else {
            rods[i].targetPosition = max(0.0, rods[i].targetPosition - tapReduction)
            hapticMedium()
        }
    }

    func holdRod(_ id: Int) {
        guard !isMeltdown, let i = rods.firstIndex(where: { $0.id == id }) else { return }
        guard !rods[i].isJammed else { return }
        rods[i].stress = min(1.0, rods[i].stress + stressPerHold)
        rods[i].targetPosition = max(0.0, rods[i].targetPosition - holdReductionPerTick)
        hapticLight()
    }

    // MARK: - Flash effect

    private func updateFlash() {
        guard thermalStress > 0.70 && !isMeltdown else { stopFlash(); return }
        let t      = (thermalStress - 0.70) / 0.30
        let target = max(0.07, 0.5 * pow(0.14, t))
        guard flashTimer == nil || abs(target - flashInterval) > 0.02 else { return }
        flashInterval = target; flashTimer?.invalidate()
        let ft = Timer(timeInterval: target, repeats: true) { [weak self] _ in self?.flashOn.toggle() }
        RunLoop.main.add(ft, forMode: .common)
        flashTimer = ft
    }

    private func stopFlash() {
        flashTimer?.invalidate(); flashTimer = nil; flashInterval = 0; flashOn = false
    }

    // MARK: - End states

    private func endShift() {
        stopSimulation()
        shiftEnded = true
    }

    private func triggerMeltdown() {
        stopSimulation()
        isMeltdown = true
        hapticError()
        #if os(iOS)
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.prepare()
        for i in 1...8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                gen.impactOccurred(intensity: min(1.0, CGFloat(i) * 0.13))
            }
        }
        #endif
    }

    // MARK: - Haptics

    private func hapticWarning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
    private func hapticError() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
    private func hapticHeavy() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
        #endif
    }
    private func hapticMedium() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    private func hapticLight() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
        #endif
    }
}
