//
//  ReactorCoreGame.swift
//  A 5x5 control rod balancing prototype, built with pure SwiftUI.
//
//  Concept:
//  - Each cell represents a control rod with an "insertion" value from 0 (fully
//    inserted / safe / green) to 1 (fully withdrawn / dangerous / red).
//  - A timer ticks every fraction of a second, nudging every rod's insertion
//    value down (rods "retract" due to boiling/voiding).
//  - Tapping a rod pushes it back toward fully inserted (0).
//  - Overall reactivity is the average insertion value across all 25 rods.
//  - If reactivity hits 1.0 (100%), it's a meltdown — AZ-5 style game over.
//

import SwiftUI

// MARK: - Model

struct ControlRod: Identifiable {
    let id: Int
    var insertion: Double = 0.0 // 0 = fully inserted (safe), 1 = fully withdrawn (danger)

    /// Color interpolates from green (safe) to yellow to red (danger).
    var color: Color {
        if insertion < 0.5 {
            // Green -> Yellow
            let t = insertion / 0.5
            return Color(
                red: t,
                green: 1.0,
                blue: 0.0
            )
        } else {
            // Yellow -> Red
            let t = (insertion - 0.5) / 0.5
            return Color(
                red: 1.0,
                green: 1.0 - t,
                blue: 0.0
            )
        }
    }
}

// MARK: - View Model

final class ReactorViewModel: ObservableObject {
    @Published var rods: [ControlRod]
    @Published var reactivity: Double = 0.0
    @Published var isMeltdown: Bool = false
    @Published var elapsedSeconds: Int = 0

    private var timer: Timer?
    private let gridSize = 5

    // Tuning knobs
    private let driftPerTick: Double = 0.012     // how fast rods retract per tick
    private let tapReduction: Double = 0.30      // how much a tap pushes a rod back in
    private let tickInterval: TimeInterval = 0.2 // simulation tick rate

    init() {
        self.rods = (0..<25).map { ControlRod(id: $0, insertion: Double.random(in: 0.1...0.3)) }
        startSimulation()
    }

    func startSimulation() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopSimulation() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !isMeltdown else { return }

        elapsedSeconds += 1

        // Each rod drifts toward fully withdrawn at a slightly randomized rate,
        // so the player can't fall into a perfectly repeatable rhythm.
        for i in rods.indices {
            let drift = driftPerTick * Double.random(in: 0.6...1.4)
            rods[i].insertion = min(1.0, rods[i].insertion + drift)
        }

        updateReactivity()
    }

    private func updateReactivity() {
        let total = rods.reduce(0.0) { $0 + $1.insertion }
        reactivity = total / Double(rods.count)

        if reactivity >= 1.0 {
            triggerMeltdown()
        }
    }

    private func triggerMeltdown() {
        reactivity = 1.0
        isMeltdown = true
        stopSimulation()
    }

    func tapRod(_ id: Int) {
        guard !isMeltdown else { return }
        guard let index = rods.firstIndex(where: { $0.id == id }) else { return }

        rods[index].insertion = max(0.0, rods[index].insertion - tapReduction)
        updateReactivity()
    }

    func reset() {
        rods = (0..<25).map { ControlRod(id: $0, insertion: Double.random(in: 0.1...0.3)) }
        reactivity = 0.0
        isMeltdown = false
        elapsedSeconds = 0
        startSimulation()
    }
}

// MARK: - Views

struct ReactorCoreView: View {
    @StateObject private var viewModel = ReactorViewModel()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(spacing: 20) {
            header

            reactivityMeter

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(viewModel.rods) { rod in
                    RodCell(rod: rod) {
                        viewModel.tapRod(rod.id)
                    }
                }
            }
            .padding()
            .background(Color.black)
            .cornerRadius(12)

            if viewModel.isMeltdown {
                meltdownOverlay
            }

            Spacer()
        }
        .padding()
        .background(Color(white: 0.08).edgesIgnoringSafeArea(.all))
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("REACTOR CORE BALANCING")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("Survival time: \(viewModel.elapsedSeconds)s")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    private var reactivityMeter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CORE REACTIVITY")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(viewModel.reactivity * 100))%")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(meterColor)
                        .frame(width: geo.size.width * viewModel.reactivity)
                        .animation(.easeOut(duration: 0.2), value: viewModel.reactivity)
                }
            }
            .frame(height: 14)
        }
    }

    private var meterColor: Color {
        switch viewModel.reactivity {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .red
        }
    }

    private var meltdownOverlay: some View {
        VStack(spacing: 12) {
            Text("⚠️ MELTDOWN ⚠️")
                .font(.title.bold())
                .foregroundColor(.red)
            Text("Reactivity reached 100%. The core has run away.")
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Button("Reset Reactor") {
                viewModel.reset()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
        .background(Color.black.opacity(0.85))
        .cornerRadius(12)
    }
}

struct RodCell: View {
    let rod: ControlRod
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 6)
                .fill(rod.color)
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: rod.color.opacity(0.6), radius: rod.insertion > 0.7 ? 6 : 0)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeOut(duration: 0.15), value: rod.insertion)
    }
}

// MARK: - Preview / App Entry

struct ReactorCoreView_Previews: PreviewProvider {
    static var previews: some View {
        ReactorCoreView()
    }
}

/*
 To run this as a standalone app, drop this file into an Xcode SwiftUI
 project and add an App struct, e.g.:

 @main
 struct ReactorGameApp: App {
     var body: some Scene {
         WindowGroup {
             ReactorCoreView()
         }
     }
 }
*/
