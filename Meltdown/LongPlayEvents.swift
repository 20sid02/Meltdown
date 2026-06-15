//
//  LongPlayEvents.swift
//  Types for LongPlay disturbances, grid demand, and event scheduling.
//

import SwiftUI

// MARK: - Disturbance

enum DisturbanceKind {
    case pumpFault   // MCP coolant pump partially fails — effective flow drops
    case rodJam      // a random rod spontaneously jams without player input

    var title: String {
        switch self {
        case .pumpFault: return "PUMP FAULT — MCP-A01"
        case .rodJam:    return "SPONTANEOUS ROD JAM"
        }
    }

    var color: Color {
        switch self {
        case .pumpFault: return .orange
        case .rodJam:    return Color(red: 0.45, green: 0.4, blue: 1.0)
        }
    }
}

struct ActiveDisturbance: Identifiable {
    let id            = UUID()
    let kind:           DisturbanceKind
    var remainingTicks: Int
    let magnitude:      Double     // pump fault: fraction of flow lost (0–1)
    let affectedRodId:  Int?       // rod jam only

    var secondsRemaining: Int { max(0, Int(ceil(Double(remainingTicks) * 0.10))) }
}

// MARK: - Grid Demand

struct GridDemand {
    // Current MW the grid is requesting. Changes every 90–300 ticks (9–30 s).
    private(set) var targetMW: Double = 2000.0
    private var ticksUntilChange: Int = 180

    mutating func tick(nominalPower: Double) {
        ticksUntilChange -= 1
        guard ticksUntilChange <= 0 else { return }
        // Demand in 100 MW steps, 1000–nominalPower range.
        let steps     = Int.random(in: 10...Int(nominalPower / 100))
        targetMW      = Double(steps) * 100.0
        ticksUntilChange = Int.random(in: 90...300)
    }
}

// MARK: - Disturbance Scheduler

struct DisturbanceScheduler {
    // Randomise initial cooldowns so disturbances don't always fire at the same intervals.
    private var pumpCooldown: Int = Int.random(in: 500...1200)
    private var jamCooldown:  Int = Int.random(in: 900...2000)

    // Returns a new disturbance if one fires this tick; nil otherwise.
    mutating func nextEvent(rodCount: Int) -> ActiveDisturbance? {
        pumpCooldown -= 1
        jamCooldown  -= 1

        if pumpCooldown <= 0 {
            pumpCooldown = Int.random(in: 600...1800)
            return ActiveDisturbance(
                kind: .pumpFault,
                remainingTicks: Int.random(in: 150...350),
                magnitude: Double.random(in: 0.20...0.45),
                affectedRodId: nil)
        }

        if jamCooldown <= 0 {
            jamCooldown = Int.random(in: 900...2400)
            return ActiveDisturbance(
                kind: .rodJam,
                remainingTicks: 1,   // applied immediately; ControlRod tracks its own jam timer
                magnitude: 1.0,
                affectedRodId: Int.random(in: 0..<rodCount))
        }

        return nil
    }
}
