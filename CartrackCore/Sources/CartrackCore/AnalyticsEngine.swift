import Foundation

struct TankCycle: Identifiable {
    let id: UUID
    let vehicleID: UUID
    let vehicleName: String
    let openingFillID: UUID
    let closingFillID: UUID
    let startDate: Date
    let endDate: Date
    let distanceKilometers: Double
    let gallons: Double
    let totalCost: Double
    let pricePerGallon: Double
    let endFuelLevelRemaining: Double

    var kmPerGallon: Double {
        gallons > 0 ? distanceKilometers / gallons : 0
    }

    var costPerKilometer: Double {
        distanceKilometers > 0 ? totalCost / distanceKilometers : 0
    }
}

struct MonthlySummary: Identifiable {
    let id: Date
    let monthStart: Date
    let vehicleID: UUID?
    var spend: Double
    var gallons: Double
    var distanceKilometers: Double
    var cycleCount: Int
    var manualDistanceKilometers: Double

    var totalDistanceKilometers: Double { distanceKilometers + manualDistanceKilometers }
    var kmPerGallon: Double { gallons > 0 ? totalDistanceKilometers / gallons : 0 }
    var costPerKilometer: Double { totalDistanceKilometers > 0 ? spend / totalDistanceKilometers : 0 }
}

struct CurrentTankStatus {
    let latestFill: FuelFillEvent?
    let latestReadingDate: Date?
    let distanceKilometers: Double
    let spacesRemaining: Double?
    let estimatedAutonomyKilometers: Double?
    let estimatedFuelCostConsumed: Double?
}

struct MonthlyProjection {
    let monthStart: Date
    let elapsedDays: Int
    let totalDays: Int
    let projectedSpend: Double
    let projectedGallons: Double
    let projectedDistanceKilometers: Double
    let projectedKmPerGallon: Double
    let projectedCostPerKilometer: Double
}

enum AnalyticsEngine {
    static func tankCycles(
        fills: [FuelFillEvent],
        vehicleID: UUID? = nil
    ) -> [TankCycle] {
        let scoped = fills
            .filter { vehicleID == nil || $0.vehicle?.id == vehicleID }
            .sorted { $0.date < $1.date }

        guard scoped.count > 1 else { return [] }

        return zip(scoped, scoped.dropFirst()).compactMap { opening, closing in
            guard let vehicle = closing.vehicle else { return nil }
            let distance = max(0, closing.odometerKilometers - opening.odometerKilometers)
            return TankCycle(
                id: closing.id,
                vehicleID: vehicle.id,
                vehicleName: vehicle.displayName,
                openingFillID: opening.id,
                closingFillID: closing.id,
                startDate: opening.date,
                endDate: closing.date,
                distanceKilometers: distance,
                gallons: closing.gallons,
                totalCost: closing.totalCost,
                pricePerGallon: closing.pricePerGallon,
                endFuelLevelRemaining: closing.fuelLevelRemaining
            )
        }
    }

    static func monthlySummaries(
        fills: [FuelFillEvent],
        adjustments: [MonthlyManualAdjustment],
        vehicleID: UUID? = nil,
        mode: MonthlyAllocationMode,
        calendar: Calendar = .current
    ) -> [MonthlySummary] {
        var buckets: [Date: MonthlySummary] = [:]
        let cycles = tankCycles(fills: fills, vehicleID: vehicleID)

        for cycle in cycles {
            switch mode {
            case .finalFillMonth:
                let monthStart = cycle.endDate.startOfMonth(using: calendar)
                var summary = buckets[monthStart] ?? MonthlySummary(
                    id: monthStart,
                    monthStart: monthStart,
                    vehicleID: vehicleID,
                    spend: 0,
                    gallons: 0,
                    distanceKilometers: 0,
                    cycleCount: 0,
                    manualDistanceKilometers: 0
                )
                summary.spend += cycle.totalCost
                summary.gallons += cycle.gallons
                summary.distanceKilometers += cycle.distanceKilometers
                summary.cycleCount += 1
                buckets[monthStart] = summary
            case .prorated:
                for (monthStart, ratio) in proratedBreakdown(for: cycle, calendar: calendar) {
                    var summary = buckets[monthStart] ?? MonthlySummary(
                        id: monthStart,
                        monthStart: monthStart,
                        vehicleID: vehicleID,
                        spend: 0,
                        gallons: 0,
                        distanceKilometers: 0,
                        cycleCount: 0,
                        manualDistanceKilometers: 0
                    )
                    summary.spend += cycle.totalCost * ratio
                    summary.gallons += cycle.gallons * ratio
                    summary.distanceKilometers += cycle.distanceKilometers * ratio
                    summary.cycleCount += ratio > 0 ? 1 : 0
                    buckets[monthStart] = summary
                }
            }
        }

        for adjustment in adjustments where vehicleID == nil || adjustment.vehicle?.id == vehicleID {
            let monthStart = adjustment.monthStart.startOfMonth(using: calendar)
            var summary = buckets[monthStart] ?? MonthlySummary(
                id: monthStart,
                monthStart: monthStart,
                vehicleID: vehicleID,
                spend: 0,
                gallons: 0,
                distanceKilometers: 0,
                cycleCount: 0,
                manualDistanceKilometers: 0
            )
            summary.manualDistanceKilometers += adjustment.manualDistanceKilometers ?? adjustment.manualDistanceMiles.map(UnitConversion.milesToKilometers) ?? 0
            buckets[monthStart] = summary
        }

        return buckets.values.sorted { $0.monthStart > $1.monthStart }
    }

    static func currentTankStatus(
        fills: [FuelFillEvent],
        snapshots: [SnapshotEvent],
        vehicleID: UUID,
        calendar: Calendar = .current
    ) -> CurrentTankStatus {
        let scopedFills = fills
            .filter { $0.vehicle?.id == vehicleID }
            .sorted { $0.date < $1.date }

        guard let latestFill = scopedFills.last else {
            return CurrentTankStatus(latestFill: nil, latestReadingDate: nil, distanceKilometers: 0, spacesRemaining: nil, estimatedAutonomyKilometers: nil, estimatedFuelCostConsumed: nil)
        }

        let scopedSnapshots = snapshots
            .filter { $0.vehicle?.id == vehicleID && $0.date >= latestFill.date }
            .sorted { $0.date < $1.date }

        let latestSnapshot = scopedSnapshots.last
        let latestReadingOdometer = latestSnapshot?.odometerKilometers ?? latestFill.odometerKilometers
        let distance = max(0, latestReadingOdometer - latestFill.odometerKilometers)
        let remainingSpaces = latestSnapshot?.fuelLevelRemaining ?? latestFill.fuelLevelRemaining
        let recentCycles = tankCycles(fills: fills, vehicleID: vehicleID).suffix(3)
        let avgKmPerGallon = recentCycles.isEmpty ? 0 : recentCycles.map(\.kmPerGallon).reduce(0, +) / Double(recentCycles.count)
        let estimatedFullGallons = max(latestFill.gallons, recentCycles.map(\.gallons).reduce(0, +) / Double(max(recentCycles.count, 1)))
        let remainingGallons = estimatedFullGallons * (remainingSpaces / max(latestFill.vehicle?.fuelScaleMax ?? FuelLevelScale.defaultMax, 1))
        let autonomy = avgKmPerGallon > 0 ? avgKmPerGallon * remainingGallons : nil
        let costConsumed = avgKmPerGallon > 0 ? (distance / avgKmPerGallon) * latestFill.pricePerGallon : nil

        return CurrentTankStatus(
            latestFill: latestFill,
            latestReadingDate: latestSnapshot?.date ?? latestFill.date,
            distanceKilometers: distance,
            spacesRemaining: remainingSpaces,
            estimatedAutonomyKilometers: autonomy,
            estimatedFuelCostConsumed: costConsumed
        )
    }

    static func monthlyProjection(
        from summary: MonthlySummary?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> MonthlyProjection? {
        guard let summary else { return nil }
        let currentMonthStart = now.startOfMonth(using: calendar)
        guard calendar.isDate(summary.monthStart, equalTo: currentMonthStart, toGranularity: .month),
              let dayRange = calendar.range(of: .day, in: .month, for: now)
        else { return nil }

        let elapsedDays = max(calendar.component(.day, from: now), 1)
        let totalDays = max(dayRange.count, elapsedDays)
        let ratio = Double(totalDays) / Double(elapsedDays)
        let projectedSpend = summary.spend * ratio
        let projectedGallons = summary.gallons * ratio
        let projectedDistance = summary.totalDistanceKilometers * ratio

        return MonthlyProjection(
            monthStart: currentMonthStart,
            elapsedDays: elapsedDays,
            totalDays: totalDays,
            projectedSpend: projectedSpend,
            projectedGallons: projectedGallons,
            projectedDistanceKilometers: projectedDistance,
            projectedKmPerGallon: projectedGallons > 0 ? projectedDistance / projectedGallons : 0,
            projectedCostPerKilometer: projectedDistance > 0 ? projectedSpend / projectedDistance : 0
        )
    }

    private static func proratedBreakdown(
        for cycle: TankCycle,
        calendar: Calendar
    ) -> [(Date, Double)] {
        let start = cycle.startDate
        let end = cycle.endDate
        let total = max(end.timeIntervalSince(start), 1)
        var cursor = start.startOfMonth(using: calendar)
        var results: [(Date, Double)] = []

        while cursor <= end {
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) ?? end
            let segmentStart = max(start, cursor)
            let segmentEnd = min(end, nextMonth)
            let overlap = max(segmentEnd.timeIntervalSince(segmentStart), 0)
            if overlap > 0 {
                results.append((cursor, overlap / total))
            }
            cursor = nextMonth
        }

        if results.isEmpty {
            results.append((end.startOfMonth(using: calendar), 1))
        }
        return results
    }
}
