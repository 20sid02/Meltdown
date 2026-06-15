//
//  LongPlayViews.swift
//  All SwiftUI views for LongPlay mode.
//
//  ViewModel: LongPlayViewModel.swift
//  Events:    LongPlayEvents.swift
//

import SwiftUI

// MARK: - LongPlay View (root)

struct LongPlayView: View {
    let onReturnToMenu: () -> Void

    @StateObject private var viewModel = LongPlayViewModel()
    @State private var showHelp = false
    @State private var reactorName = reactorNames.randomElement()!

    var body: some View {
        ZStack {
            mainContent
            if showHelp {
                PagedHelpModal(isPresented: $showHelp, pages: longPlayHelpPages).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showHelp)
        .onChange(of: showHelp) { _, paused in
            paused ? viewModel.pauseGame() : viewModel.resumeGame()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 10) {
            LongPlayInfoPanel(
                viewModel: viewModel,
                onHelp: { showHelp = true },
                onMenu: { viewModel.pauseGame(); onReturnToMenu() },
                reactorName: reactorName
            )

            if !viewModel.activeDisturbances.isEmpty {
                DisturbanceBanner(disturbances: viewModel.activeDisturbances)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let alert = viewModel.xenonAlert {
                XenonAlertBanner(text: alert)
                    .transition(.opacity)
            }

            DemandMeterView(
                produced: viewModel.megawattsProduced,
                demanded: viewModel.gridDemand.targetMW,
                nominal:  viewModel.nominalPower
            )

            Text("CONTROL ROD ARRAY  ·  AZ-5 GRID")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.4))
                .tracking(2)

            HoneycombGrid(
                rods:   viewModel.rods,
                onTap:  { viewModel.tapRod($0) },
                onHold: { viewModel.holdRod($0) }
            )

            ControlPanelView(
                coolantFlowRate:   $viewModel.coolantFlowRate,
                turbineValveOpen:  $viewModel.turbineValveOpen,
                autoPowerSetpoint: $viewModel.autoPowerSetpoint
            )
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
        .overlay(endOverlay)
        .animation(.easeInOut(duration: 0.30), value: viewModel.activeDisturbances.isEmpty)
        .animation(.easeInOut(duration: 0.30), value: viewModel.xenonAlert == nil)
    }

    private var redFlashOpacity: Double {
        guard viewModel.flashOn && viewModel.thermalStress > 0.70 && !viewModel.isMeltdown else { return 0 }
        let t = (viewModel.thermalStress - 0.70) / 0.30
        return 0.12 + t * 0.30
    }

    @ViewBuilder
    private var endOverlay: some View {
        if viewModel.isMeltdown {
            ZStack {
                Color.black.opacity(0.88).ignoresSafeArea()
                MeltdownOverlay(
                    peakTemp:    viewModel.peakTemp,
                    energy:      viewModel.cumulativeEnergy,
                    time:        viewModel.survivalTime,
                    onRestart:   { viewModel.reset() },
                    onMenu:      { onReturnToMenu() }
                )
            }
            .transition(.opacity)
        } else if viewModel.shiftEnded {
            ZStack {
                Color.black.opacity(0.88).ignoresSafeArea()
                ShiftSummaryView(
                    energy:           viewModel.cumulativeEnergy,
                    duration:         viewModel.survivalTime,
                    peakTemp:         viewModel.peakTemp,
                    demandEfficiency: viewModel.demandEfficiencyPercent,
                    onRestart:        { viewModel.reset() },
                    onMenu:           { onReturnToMenu() }
                )
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Meltdown Overlay

private struct MeltdownOverlay: View {
    let peakTemp: Double
    let energy:   Double
    let time:     String
    let onRestart: () -> Void
    let onMenu:    () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("⚠ MELTDOWN ⚠")
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .foregroundColor(.red)
            Text("COOLANT TEMPERATURE EXCURSION · CORE DESTROYED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.7)).tracking(0.8)
            Text("PEAK \(Int(peakTemp))°C   ·   \(String(format: "%.1f", energy)) MWh GENERATED")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(.gray)
            Text("SURVIVED: \(time)")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
            Button("RESTART SHIFT") { onRestart() }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 20).padding(.vertical, 9)
                .background(Color.red.opacity(0.85))
                .foregroundColor(.white).cornerRadius(5)
            Button("RETURN TO MENU") { onMenu() }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45).opacity(0.75))
                .padding(.top, 2)
        }
        .padding(20)
        .background(Color(white: 0.09))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, 20)
    }
}

// MARK: - Shift Summary

struct ShiftSummaryView: View {
    let energy:           Double
    let duration:         String
    let peakTemp:         Double
    let demandEfficiency: Double
    let onRestart: () -> Void
    let onMenu:    () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("SHIFT COMPLETE")
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                .padding(.bottom, 14)

            VStack(spacing: 0) {
                row("DURATION",         duration)
                div
                row("ENERGY GENERATED", String(format: "%.1f MWh", energy))
                div
                row("ON-DEMAND",        String(format: "%.0f%%", demandEfficiency),
                    warn: demandEfficiency < 40)
                div
                row("PEAK COOLANT",     "\(Int(peakTemp))°C",
                    warn: peakTemp > 200)
            }
            .background(Color(white: 0.09))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color(red: 0.2, green: 0.55, blue: 0.25).opacity(0.5), lineWidth: 1))
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                Button("RESTART SHIFT") { onRestart() }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color(red: 0.35, green: 0.85, blue: 0.45))
                    .cornerRadius(6)

                Button("MAIN MENU") { onMenu() }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(red: 0.35, green: 0.85, blue: 0.45).opacity(0.5), lineWidth: 1))
            }
        }
        .padding(20)
        .background(Color(white: 0.07))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color(red: 0.2, green: 0.55, blue: 0.25).opacity(0.6), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func row(_ label: String, _ value: String, warn: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.6)).tracking(1)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(warn ? .orange : .white)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var div: some View {
        Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)
    }
}

// MARK: - Info Panel

struct LongPlayInfoPanel: View {
    @ObservedObject var viewModel: LongPlayViewModel
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
                readout("COOLANT", "\(viewModel.coreTemp)°C",
                        color: coolantColor(viewModel.coolantTemperature))
                sep
                readout("STATUS", viewModel.threatLabel, color: viewModel.threatColor)
                sep
                readout("POWER",  "\(Int(viewModel.megawattsProduced)) MW")
                sep
                readout("DEMAND", "\(Int(viewModel.gridDemand.targetMW)) MW",
                        color: viewModel.demandColor)
            }

            Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)

            HStack(spacing: 0) {
                readout("XE-135",
                        String(format: "%.0f%%", viewModel.xenonLevel * 100) + xenonArrow,
                        color: xenonColor)
                sep
                readout("STEAM",
                        String(format: "%.0f%%", viewModel.steamVoidRatio * 100),
                        color: viewModel.steamVoidRatio > 0.5 ? .red
                             : viewModel.steamVoidRatio > 0.2 ? .yellow : .white)
                sep
                readout("JAMMED", "\(viewModel.jammedCount)",
                        color: viewModel.jammedCount > 0
                            ? Color(red: 0.45, green: 0.4, blue: 1.0) : .white)
                sep
                readout("SHIFT", viewModel.shiftTimeRemaining,
                        color: viewModel.remainingTicks < 600 ? .yellow : .white)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(white: 0.06))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(red: 0.2, green: 0.55, blue: 0.25).opacity(0.6), lineWidth: 1))
        .cornerRadius(8)
    }

    private var xenonArrow: String {
        if viewModel.xenonTrend >  0.0001 { return " ↑" }
        if viewModel.xenonTrend < -0.0001 { return " ↓" }
        return ""
    }

    private var xenonColor: Color {
        viewModel.xenonLevel > 0.6 ? .red
            : viewModel.xenonLevel > 0.3 ? .orange
            : viewModel.xenonLevel > 0.1 ? .yellow : .white
    }

    private func coolantColor(_ t: Double) -> Color {
        t < 100 ? Color(red: 0.35, green: 0.85, blue: 0.45)
            : t < 200 ? .yellow : t < 270 ? .orange : .red
    }

    private var sep: some View {
        Rectangle().fill(Color.gray.opacity(0.25)).frame(width: 1, height: 28).padding(.horizontal, 5)
    }

    private func readout(_ label: String, _ value: String, color: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .regular, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.65)).tracking(0.4)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Demand Meter

struct DemandMeterView: View {
    let produced: Double
    let demanded: Double
    let nominal:  Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("GRID LOAD")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white).tracking(1.5)
                Spacer()
                let gap  = abs(produced - demanded)
                let sign = produced >= demanded ? "+" : "−"
                Text("\(Int(produced)) MW  \(sign)\(Int(gap)) MW  TARGET \(Int(demanded)) MW")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(gapColor(gap))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(fillColor)
                        .frame(width: geo.size.width * CGFloat(min(1, produced / nominal)))
                        .animation(.easeOut(duration: 0.15), value: produced)
                    // Demand marker
                    Rectangle()
                        .fill(Color.yellow.opacity(0.85))
                        .frame(width: 2)
                        .offset(x: geo.size.width * CGFloat(min(1, demanded / nominal)) - 1)
                }
            }
            .frame(height: 8)
        }
    }

    private var fillColor: Color {
        let gap = abs(produced - demanded)
        return gap < 150 ? Color(red: 0.1, green: 0.85, blue: 0.35)
             : gap < 400 ? .yellow : .red
    }

    private func gapColor(_ gap: Double) -> Color {
        gap < 150 ? Color(red: 0.35, green: 0.85, blue: 0.45) : gap < 400 ? .yellow : .red
    }
}

// MARK: - Disturbance Banner

struct DisturbanceBanner: View {
    let disturbances: [ActiveDisturbance]
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 4) {
            ForEach(disturbances) { d in
                HStack(spacing: 8) {
                    Circle()
                        .fill(d.kind.color)
                        .frame(width: 6, height: 6)
                        .opacity(pulse ? 1.0 : 0.25)
                    Text("⚠ \(d.kind.title)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(d.kind.color)
                    Spacer()
                    Text("\(d.secondsRemaining)s")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(d.kind.color.opacity(0.8))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(d.kind.color.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(d.kind.color.opacity(0.35), lineWidth: 1))
                .cornerRadius(5)
            }
        }
        .onAppear { pulse = true }
        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: pulse)
    }
}

// MARK: - Xenon Alert Banner

struct XenonAlertBanner: View {
    let text: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 1.0 : 0.25)
            Text("⚡ \(text)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color.orange.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.orange.opacity(0.35), lineWidth: 1))
        .cornerRadius(5)
        .onAppear { pulse = true }
        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: pulse)
    }
}

// MARK: - Control Panel (sliders)

struct ControlPanelView: View {
    @Binding var coolantFlowRate:   Double
    @Binding var turbineValveOpen:  Double
    @Binding var autoPowerSetpoint: Double
    var tutorialFocus: TutorialElement? = nil   // nil during normal play

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 10) {
            Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)
            sliderRow("COOLANT PUMP  MCP-A01",  value: $coolantFlowRate,
                      color: Color(red: 0.3, green: 0.7, blue: 1.0),
                      element: .coolantSlider)
            sliderRow("TURBINE VALVE  TG-V03",  value: $turbineValveOpen,
                      color: Color(red: 1.0, green: 0.6, blue: 0.2),
                      element: .turbineSlider)
            sliderRow("PWR SETPOINT  APS-N1",   value: $autoPowerSetpoint,
                      color: Color(red: 0.35, green: 0.85, blue: 0.45),
                      element: .setpointSlider)
        }
        .onAppear { pulse = true }
        .onChange(of: tutorialFocus) { _, _ in
            pulse = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pulse = true }
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>,
                            color: Color, element: TutorialElement) -> some View {
        let active = tutorialFocus == element
        return VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(color.opacity(0.75)).tracking(1)
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue * 100))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .contentTransition(.numericText())
            }
            Slider(value: value, in: 0...1).tint(color)
        }
        .padding(active ? 6 : 0)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(active ? Color.yellow.opacity(pulse ? 0.95 : 0.30) : .clear, lineWidth: 2)
                .animation(active
                    ? .easeInOut(duration: 0.65).repeatForever(autoreverses: true)
                    : .default,
                           value: pulse && active)
        )
        .shadow(color: active ? Color.yellow.opacity(0.25) : .clear, radius: active ? 6 : 0)
        .animation(.easeInOut(duration: 0.2), value: active)
    }
}
