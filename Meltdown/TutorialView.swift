//
//  TutorialView.swift
//  Step-by-step tutorial modes + paged in-game help modals.
//
//  Provides:
//    • PagedHelpModal       – used by the in-game ? button in both modes
//    • StandardTutorialView – interactive walkthrough for the click-based game
//    • LongPlayTutorialView – interactive walkthrough for the slider simulation
//

import SwiftUI

// MARK: - Tutorial element (drives per-element highlight rings)

enum TutorialElement {
    case infoPanel, reactivityMeter, grid
    case coolantSlider, turbineSlider, setpointSlider, demandMeter
}

// MARK: - Highlight modifier (used by both tutorial views)

extension View {
    func tutorialHighlight(_ active: Bool, pulse: Bool) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(active ? Color.yellow.opacity(pulse ? 0.95 : 0.30) : .clear, lineWidth: 2)
                .animation(active
                    ? .easeInOut(duration: 0.65).repeatForever(autoreverses: true)
                    : .default,
                           value: pulse && active)
        )
        .shadow(color: active ? Color.yellow.opacity(0.25) : .clear, radius: active ? 8 : 0)
    }
}

// MARK: - Paged help modal (in-game ?)

struct HelpPage: Identifiable {
    let id    = UUID()
    let icon:   String
    let title:  String
    let body:   String
}

struct PagedHelpModal: View {
    @Binding var isPresented: Bool
    let pages: [HelpPage]

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text("OPERATOR REFERENCE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                        .tracking(1)
                    Spacer()
                    Button { isPresented = false } label: {
                        Text("✕")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)

                TabView {
                    ForEach(pages) { page in
                        pageCard(page)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 300)

                Button { isPresented = false } label: {
                    Text("CLOSE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Color(red: 0.35, green: 0.85, blue: 0.45))
                        .cornerRadius(6)
                }
                .padding([.horizontal, .bottom], 20)
            }
            .background(Color(white: 0.07))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.2, green: 0.55, blue: 0.25).opacity(0.6), lineWidth: 1))
            .padding(.horizontal, 16)
        }
    }

    private func pageCard(_ page: HelpPage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(page.icon).font(.system(size: 18))
                Text(page.title)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                    .tracking(1)
            }
            Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
            Text(page.body)
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.85))
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(16)
        .background(Color(white: 0.10))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(red: 0.2, green: 0.55, blue: 0.25).opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Help page content

let standardHelpPages: [HelpPage] = [
    HelpPage(icon: "⬡", title: "CONTROL RODS",
             body: "25 rods control the reactor. Green = inserted (safe). Red = withdrawn (dangerous). Rods drift toward withdrawal automatically.\n\nTAP a rod for a quick −30% insertion. HOLD to continuously push it in. Rod bodies move at fixed velocity — you feel the inertia."),
    HelpPage(icon: "⚡", title: "POSITIVE VOID COEFFICIENT",
             body: "When coolant exceeds 100°C, it flashes to steam. Steam absorbs fewer neutrons than water, so more steam = more reactivity = more heat. It feeds itself.\n\nWatch COOLANT and STEAM in the panel. If steam builds, insert rods aggressively."),
    HelpPage(icon: "☢", title: "XENON-135 PIT",
             body: "Fission produces I-135 → Xe-135, a strong neutron absorber. High power burns xenon off.\n\nDrop power suddenly → xenon spikes (xenon pit). When xenon clears, power surges. Don't over-insert all rods at once or you'll cause a spike on recovery."),
    HelpPage(icon: "▼", title: "GRAPHITE TIP FLAW",
             body: "Control rods have graphite tips. When a nearly-withdrawn rod first re-enters the core, the graphite tip briefly ADDS reactivity for ~0.5 s.\n\nAffected rods flash CYAN. This is the flaw that destroyed Unit 4. Avoid inserting many rods simultaneously from a fully-withdrawn state."),
    HelpPage(icon: "🔵", title: "ROD STRESS & JAMS",
             body: "Rapid tapping overheats the drive mechanism (orange stress ring). Four rapid taps on the same rod jams it — turns BLUE, ignores input, retracts uncontrolled for 3.5 s.\n\nSpread taps across multiple rods. Don't fixate on one rod."),
]

let longPlayHelpPages: [HelpPage] = [
    HelpPage(icon: "💧", title: "COOLANT PUMP",
             body: "Higher flow = more cooling = lower temperature = less steam = less reactivity amplification.\n\nRaise it during a crisis (pump fault, temperature spike). Lower it slightly to nudge temperature higher for more steam output."),
    HelpPage(icon: "⚙", title: "TURBINE VALVE",
             body: "Drains steam from the core to the turbine. Higher valve = more power output + less void fraction = less reactivity amplification.\n\nOpening the valve is generally safe — it removes steam. Your primary power output lever."),
    HelpPage(icon: "📊", title: "POWER SETPOINT",
             body: "APS moves all rods toward this withdrawal fraction. Higher = more fission = more heat = more steam.\n\nMake gradual changes. A large sudden increase while xenon is high causes a power surge. This is your primary reactivity dial."),
    HelpPage(icon: "☢", title: "XENON PIT",
             body: "Watch XE-135 ↑↓ in the panel. Running hot burns xenon off. Cut power fast and xenon builds, suppressing the core.\n\nWhen xenon burns off (XE BURNOFF banner), rods may be over-withdrawn — that surge can exceed 330°C before you can react. Ease setpoint changes slowly."),
    HelpPage(icon: "⚠", title: "DISTURBANCES",
             body: "PUMP FAULT — coolant flow drops 20–45% for up to 35 s. Lower the APS setpoint immediately and raise coolant flow as high as you can.\n\nSPONTANEOUS JAM — a random rod jams for 4 s. Nothing you can do; watch the JAMMED counter and wait it out."),
]

// MARK: - Tutorial step

struct TutorialStep {
    let title:     String
    let body:      String
    let tip:       String?
    let highlight: TutorialElement?
    var isLast:    Bool = false

    init(_ title: String, _ body: String,
         tip: String? = nil, highlight: TutorialElement? = nil, isLast: Bool = false) {
        self.title = title; self.body = body; self.tip = tip
        self.highlight = highlight; self.isLast = isLast
    }
}

// MARK: - Standard tutorial steps

private let standardSteps: [TutorialStep] = [
    TutorialStep("WELCOME",
                 "You are the night shift operator. You have 20 minutes.\n\nThe reactor's control rods drift out of position on their own. If core reactivity reaches 100%, the reactor runs away. Keep it below that.",
                 tip: "Rods start safe. The game is live — try tapping."),
    TutorialStep("CONTROL RODS",
                 "Each hexagon is a control rod. Green = inserted (safe). Red/orange = withdrawn (dangerous).\n\nAll rods slowly drift toward withdrawal. Your job is to fight the drift by inserting them faster than they retract.",
                 highlight: .grid),
    TutorialStep("TAP TO INSERT",
                 "TAP any rod to insert it 30% toward safety. HOLD to continuously push it in.\n\nThe rod body moves at fixed speed — tapping sets a target, and the rod catches up with visible inertia.\n\nTry holding a rod down now and watch it move.",
                 tip: "Hold a rod and watch it slide.",
                 highlight: .grid),
    TutorialStep("ROD STRESS & JAMS",
                 "Rapid tapping on the same rod accumulates stress (orange ring around the hex).\n\nFour quick taps on the same rod jams it — it turns BLUE, ignores all input, and retracts uncontrolled for 3.5 seconds.\n\nSpread your taps across many rods. Don't fixate on one.",
                 highlight: .grid),
    TutorialStep("REACTIVITY METER",
                 "This bar is your survival gauge. It rises as rods withdraw.\n\nAt 100%, the reactor runs away. If you see it above 80%, insert rods across the board immediately — you have very little time.",
                 highlight: .reactivityMeter),
    TutorialStep("STATUS PANEL",
                 "The panel shows:\n· COOLANT — temperature of the coolant loop\n· STATUS — threat level (STABLE → EXCURSION)\n· STEAM — void fraction (more steam = more reactive)\n· XE-135 — Xenon poisoning level\n\nWatch COOLANT and STATUS most closely.",
                 highlight: .infoPanel),
    TutorialStep("XENON-135 PIT",
                 "Fission produces Xe-135, a neutron absorber. At high power it burns off fast.\n\nSudden power drop → xenon spikes → reactor suppressed → tempting to over-insert rods. When xenon then clears, those withdrawn rods cause a surge.\n\nDon't over-insert all rods at once during a lull.",
                 tip: "You'll feel this in longer shifts.",
                 highlight: .infoPanel),
    TutorialStep("GRAPHITE TIP FLAW",
                 "Control rods have graphite tips. When a nearly-withdrawn rod first re-enters the core, the graphite section enters first — briefly ADDING reactivity for ~0.5 s before the boron absorber takes effect.\n\nAffected rods flash CYAN. This is the design flaw that destroyed Unit 4.",
                 highlight: .grid),
    TutorialStep("START SHIFT",
                 "Survive as long as you can. The longer you last, the more the drift rate increases.\n\nIf STATUS shows EXCURSION, insert rods across the entire board immediately.\n\nThe ? button in-game shows a quick reference for every mechanic.\n\nGood luck, operator.",
                 tip: "Starting a fresh shift now.",
                 isLast: true),
]

// MARK: - LongPlay tutorial steps

private let longPlaySteps: [TutorialStep] = [
    TutorialStep("WELCOME",
                 "You have 20 minutes. Keep the reactor from melting down.\n\nThree sliders control everything. The APS manages rod positions. Your job: balance power output against stability and respond to random events.",
                 tip: "Reactor is live — all sliders work now."),
    TutorialStep("INFO PANEL",
                 "The panel shows:\n· COOLANT temp  · THREAT status\n· POWER output  · Grid DEMAND\n· XE-135 ↑↓ trend  · STEAM void ratio\n· JAMMED count  · SHIFT countdown\n\nCOOLANT and THREAT are your most important readouts.",
                 highlight: .infoPanel),
    TutorialStep("GRID DEMAND",
                 "The GRID LOAD bar shows your current output (green fill) vs what the grid needs (yellow marker).\n\nStay within ±150 MW of the marker for a 1.5× score multiplier on every MWh generated. Demand changes every 1–5 minutes — chase the target.",
                 tip: "Match the yellow marker for bonus score.",
                 highlight: .demandMeter),
    TutorialStep("COOLANT PUMP",
                 "Higher flow = more cooling = lower temperature = less steam in the core.\n\nThis is your safety valve. Raise it during pump faults or temperature spikes. Lower it slightly to push temperature up for more steam output — but carefully.",
                 tip: "Try sliding it and watch COOLANT temp change.",
                 highlight: .coolantSlider),
    TutorialStep("TURBINE VALVE",
                 "Routes steam from the core to the turbine. Higher valve = more power output.\n\nOpening the valve also drains steam from the core — which reduces the positive void coefficient. Opening it is generally safe. This is your primary MW lever.",
                 tip: "Open it and watch POWER rise.",
                 highlight: .turbineSlider),
    TutorialStep("POWER SETPOINT",
                 "APS-N1 moves all rods toward this withdrawal fraction. Higher = more fission = hotter = more steam = more power.\n\nMake gradual changes. A sudden large increase while xenon is high will cause a dangerous power surge. This is your primary reactivity dial.",
                 tip: "Move it slowly and watch the grid change.",
                 highlight: .setpointSlider),
    TutorialStep("XENON PIT",
                 "Watch XE-135 ↑↓ in the panel. Running hot burns xenon off fast. Cut power suddenly and xenon builds, suppressing the core — the APS opens rods to compensate.\n\nWhen xenon burns off (XE BURNOFF warning), those over-withdrawn rods cause a surge. The XE BURNOFF banner is your early warning. Ease changes slowly.",
                 highlight: .infoPanel),
    TutorialStep("DISTURBANCES",
                 "PUMP FAULT — coolant flow drops 20–45% for up to 35 s. The orange banner appears. Lower your APS setpoint immediately and push coolant flow up.\n\nSPONTANEOUS JAM — a random rod locks for 4 s (blue, uncontrolled). Watch the JAMMED counter and wait. These are random and unavoidable.",
                 tip: "The first fault usually hits within 2 minutes."),
    TutorialStep("START SHIFT",
                 "Meltdown at 330°C. Match grid demand to maximize score. Manage disturbances. Watch xenon.\n\nThe ? button in-game opens a quick reference for every control.\n\nGood luck, operator.",
                 tip: "Starting your shift now.",
                 isLast: true),
]

// MARK: - Tutorial coaching card

private struct TutorialCard: View {
    let step:        TutorialStep
    let stepIndex:   Int
    let stepCount:   Int
    let reactorName: String
    let onPrev:      () -> Void
    let onNext:      () -> Void
    let onExit:      () -> Void

    private func resolve(_ s: String) -> String { s.replacingOccurrences(of: "{REACTOR}", with: reactorName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("STEP \(stepIndex + 1) / \(stepCount)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.50)).tracking(1)
                Spacer()
                Button(action: onExit) {
                    Text("EXIT TUTORIAL")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.45))
                }
            }
            .padding(.bottom, 8)

            Text(resolve(step.title))
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                .tracking(1.5)

            Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                .padding(.vertical, 8)

            Text(resolve(step.body))
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.85))
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)

            if let tip = step.tip {
                Text("▸ \(resolve(tip))")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.70))
                    .padding(.top, 7)
            }

            Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                .padding(.vertical, 10)

            HStack {
                if stepIndex > 0 {
                    Button(action: onPrev) {
                        Text("◀ BACK")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45).opacity(0.55))
                    }
                }
                Spacer()
                Button(action: onNext) {
                    Text(step.isLast ? "▶  START SHIFT" : "NEXT  ▶")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(step.isLast
                            ? Color(red: 0.35, green: 0.85, blue: 0.45)
                            : Color(red: 0.22, green: 0.55, blue: 0.30))
                        .cornerRadius(5)
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.07).opacity(0.97))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color(red: 0.2, green: 0.55, blue: 0.25).opacity(0.7), lineWidth: 1))
        .padding(.horizontal, 8)
        .shadow(color: .black.opacity(0.55), radius: 18)
    }
}

// MARK: - Standard tutorial view

struct StandardTutorialView: View {
    let onReturnToMenu: () -> Void

    @StateObject private var vm = ReactorViewModel()
    @State private var stepIndex  = 0
    @State private var done       = false
    @State private var pulse      = false
    @State private var reactorName = reactorNames.randomElement()!

    private var step: TutorialStep { standardSteps[stepIndex] }

    var body: some View {
        ZStack {
            if done {
                // Hand off to the real game — fresh ReactorViewModel, full feature set.
                ReactorCoreView(mode: .standard, onReturnToMenu: onReturnToMenu)
                    .transition(.opacity)
            } else {
                tutorialContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: done)
    }

    private var tutorialContent: some View {
        ZStack(alignment: .bottom) {
            gamePreview

            TutorialCard(
                step:        step,
                stepIndex:   stepIndex,
                stepCount:   standardSteps.count,
                reactorName: reactorName,
                onPrev:      { advance(by: -1) },
                onNext:      { step.isLast ? finish() : advance(by: 1) },
                onExit:      { onReturnToMenu() }
            )
            .padding(.bottom, 10)
        }
        .onAppear {
            vm.resetToSafe()
            pulse = true
        }
        .onChange(of: stepIndex) { _, _ in
            pulse = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pulse = true }
        }
    }

    private var gamePreview: some View {
        VStack(spacing: 12) {
            ReactorInfoPanel(viewModel: vm, onHelp: {}, onMenu: { onReturnToMenu() }, reactorName: reactorName)
                .tutorialHighlight(step.highlight == .infoPanel, pulse: pulse)

            reactivityMeter
                .tutorialHighlight(step.highlight == .reactivityMeter, pulse: pulse)

            Text("CONTROL ROD ARRAY  ·  AZ-5 GRID")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.4)).tracking(2)

            HoneycombGrid(rods: vm.rods, onTap: { vm.tapRod($0) }, onHold: { vm.holdRod($0) })
                .tutorialHighlight(step.highlight == .grid, pulse: pulse)

            // Reserve vertical space for the coaching card.
            Spacer().frame(height: 230)
        }
        .padding(.horizontal, 8).padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.05).ignoresSafeArea())
    }

    private var reactivityMeter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CORE REACTIVITY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white).tracking(1.5)
                Spacer()
                Text("\(Int(vm.reactivity * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(meterColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(meterColor)
                        .frame(width: geo.size.width * CGFloat(vm.reactivity))
                        .animation(.easeOut(duration: 0.15), value: vm.reactivity)
                }
            }
            .frame(height: 8)
        }
    }

    private var meterColor: Color {
        vm.reactivity < 0.5 ? Color(red: 0.1, green: 0.85, blue: 0.35)
            : vm.reactivity < 0.8 ? .yellow : .red
    }

    private func advance(by delta: Int) {
        stepIndex = max(0, min(standardSteps.count - 1, stepIndex + delta))
    }

    private func finish() {
        vm.stopSimulation()
        withAnimation { done = true }
    }
}

// MARK: - LongPlay tutorial view

struct LongPlayTutorialView: View {
    let onReturnToMenu: () -> Void

    @StateObject private var vm = LongPlayViewModel()
    @State private var stepIndex  = 0
    @State private var done       = false
    @State private var pulse      = false
    @State private var reactorName = reactorNames.randomElement()!

    private var step: TutorialStep { longPlaySteps[stepIndex] }

    var body: some View {
        ZStack {
            if done {
                LongPlayView(onReturnToMenu: onReturnToMenu)
                    .transition(.opacity)
            } else {
                tutorialContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: done)
    }

    private var tutorialContent: some View {
        ZStack(alignment: .bottom) {
            gamePreview

            TutorialCard(
                step:        step,
                stepIndex:   stepIndex,
                stepCount:   longPlaySteps.count,
                reactorName: reactorName,
                onPrev:      { advance(by: -1) },
                onNext:      { step.isLast ? finish() : advance(by: 1) },
                onExit:      { onReturnToMenu() }
            )
            .padding(.bottom, 10)
        }
        .onAppear { pulse = true }
        .onChange(of: stepIndex) { _, _ in
            pulse = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pulse = true }
        }
    }

    private var gamePreview: some View {
        VStack(spacing: 10) {
            LongPlayInfoPanel(viewModel: vm, onHelp: {}, onMenu: { onReturnToMenu() }, reactorName: reactorName)
                .tutorialHighlight(step.highlight == .infoPanel, pulse: pulse)

            if !vm.activeDisturbances.isEmpty {
                DisturbanceBanner(disturbances: vm.activeDisturbances)
            }
            if let alert = vm.xenonAlert {
                XenonAlertBanner(text: alert)
            }

            DemandMeterView(
                produced: vm.megawattsProduced,
                demanded: vm.gridDemand.targetMW,
                nominal:  vm.nominalPower
            )
            .tutorialHighlight(step.highlight == .demandMeter, pulse: pulse)

            Text("CONTROL ROD ARRAY  ·  AZ-5 GRID")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.4)).tracking(2)

            HoneycombGrid(rods: vm.rods, onTap: { vm.tapRod($0) }, onHold: { vm.holdRod($0) })

            ControlPanelView(
                coolantFlowRate:   $vm.coolantFlowRate,
                turbineValveOpen:  $vm.turbineValveOpen,
                autoPowerSetpoint: $vm.autoPowerSetpoint,
                tutorialFocus:     step.highlight
            )

            Spacer().frame(height: 240)
        }
        .padding(.horizontal, 8).padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.05).ignoresSafeArea())
    }

    private func advance(by delta: Int) {
        stepIndex = max(0, min(longPlaySteps.count - 1, stepIndex + delta))
    }

    private func finish() {
        vm.stopSimulation()
        withAnimation { done = true }
    }
}
