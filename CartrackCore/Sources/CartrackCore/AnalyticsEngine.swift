import Foundation
import SwiftData

struct TankCycle: Identifiable {
    let id: UUID
    let vehicleID: UUID
    let vehicleName: String
    let openingFillID: UUID
    let closingFillID: UUID
    let startDate: Date
    let endDate: Date
    let openingOdometerKilometers: Double
    let closingOdometerKilometers: Double
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
    let latestReadingKilometers: Double?
    let distanceKilometers: Double
    let spacesRemaining: Double?
    let estimatedAutonomyKilometers: Double?
    let estimatedFuelCostConsumed: Double?
    let insight: CurrentTankInsight?
}

struct CurrentTankInsight {
    let latestSnapshotDate: Date
    let latestOdometerKilometers: Double
    let latestOdometerMiles: Double?
    let latestTripKilometers: Double?
    let latestTripMiles: Double?
    let previousSnapshotDate: Date?
    let previousTripKilometers: Double?
    let previousTripMiles: Double?
    let tripDeltaKilometers: Double?
    let tripDeltaMiles: Double?
    let fuelSpacesConsumed: Double?
    let fuelRemainingRatio: Double?
    let estimatedTankRangeKilometers: Double?
    let likelyTankRangeKilometers: Double?
    let likelyTankRangeLowerKilometers: Double?
    let likelyTankRangeUpperKilometers: Double?
    let remainingRangeLowerKilometers: Double?
    let remainingRangeUpperKilometers: Double?
    let currentFillSpend: Double?
    let currentCostPerKilometer: Double?
}

struct CurrentTankInsightCopy {
    let state: String
    let comparison: String?
    let estimate: String?
}

enum CurrentTankInsightFormatter {
    static func copy(for insight: CurrentTankInsight, vehicleName: String? = nil) -> CurrentTankInsightCopy {
        let trip = milesAndKilometers(
            label: "Trip",
            miles: insight.latestTripMiles,
            kilometers: insight.latestTripKilometers,
            separator: "="
        ) ?? "Trip: N/A"
        let odometer = insight.latestOdometerMiles.map {
            "Odometro: \(wholeNumber($0)) millas"
        } ?? "Odometro: \(oneDecimal(insight.latestOdometerKilometers)) km"
        let fuel = fuelText(for: insight)

        let comparison = comparisonText(for: insight)
        let estimate = estimateText(for: insight, vehicleName: vehicleName)

        return CurrentTankInsightCopy(
            state: [trip, odometer, fuel].joined(separator: "\n"),
            comparison: comparison,
            estimate: estimate
        )
    }

    private static func fuelText(for insight: CurrentTankInsight) -> String {
        guard let consumed = insight.fuelSpacesConsumed,
              let remainingRatio = insight.fuelRemainingRatio
        else {
            return "Nivel de combustible: pendiente de confirmar manualmente"
        }

        let remainingPercent = (remainingRatio * 100 / 10).rounded() * 10
        return "Nivel de combustible: aproximadamente \(oneDecimal(consumed)) espacios consumidos, queda alrededor del \(wholeNumber(remainingPercent))% del tanque"
    }

    private static func comparisonText(for insight: CurrentTankInsight) -> String? {
        guard let previousTripKilometers = insight.previousTripKilometers,
              let tripDeltaKilometers = insight.tripDeltaKilometers
        else { return nil }

        let previous = milesAndKilometers(
            label: "Medicion anterior",
            miles: insight.previousTripMiles,
            kilometers: previousTripKilometers,
            separator: nil
        )
        let current = milesAndKilometers(
            label: "Ahora",
            miles: insight.latestTripMiles,
            kilometers: insight.latestTripKilometers,
            separator: nil
        )
        let delta = milesAndKilometers(
            label: "Recorrido desde entonces",
            miles: insight.tripDeltaMiles,
            kilometers: tripDeltaKilometers,
            separator: "="
        )

        return [previous, current, delta, "La aguja del Z4 puede bajar de forma no lineal, asi que una pequena variacion adicional es normal."]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private static func estimateText(for insight: CurrentTankInsight, vehicleName: String?) -> String? {
        guard let likelyRangeKilometers = insight.likelyTankRangeKilometers else { return nil }

        var lines: [String] = []
        if let lower = insight.likelyTankRangeLowerKilometers,
           let upper = insight.likelyTankRangeUpperKilometers {
            lines.append("Autonomia total real: \(roundedRange(lower: lower, upper: upper)) km")
        }

        let likelyRounded = roundToNearestFive(likelyRangeKilometers)
        lines.append("Lo mas probable: ≈\(wholeNumber(likelyRounded)) km por tanque")

        if let lower = insight.remainingRangeLowerKilometers,
           let upper = insight.remainingRangeUpperKilometers {
            if (insight.fuelRemainingRatio ?? 1) <= 0.20 {
                lines.append("Combustible restante: \(roundedRange(lower: lower, upper: upper)) km de autonomia estimada")
            } else {
                lines.append("Combustible restante: \(roundedRange(lower: lower, upper: upper)) km antes de llegar a reserva")
            }
        }

        if let spend = insight.currentFillSpend,
           let costPerKilometer = insight.currentCostPerKilometer,
           let distance = insight.latestTripKilometers {
            lines.append("Referencia de gasto: \(CartrackFormatters.currency(spend)) / \(oneDecimal(distance)) km = \(CartrackFormatters.currency(costPerKilometer))/km")
        }

        let vehicleText = (vehicleName?.trimmed).nilIfBlank ?? "tu vehiculo"
        lines.append("Patron actual: \(vehicleText) esta mostrando alrededor de 400-410 km por tanque lleno en tu uso real.")
        return lines.joined(separator: "\n")
    }

    private static func milesAndKilometers(label: String, miles: Double?, kilometers: Double?, separator: String?) -> String? {
        switch (miles, kilometers) {
        case let (miles?, kilometers?):
            if let separator {
                return "\(label): \(oneDecimal(miles)) millas \(separator) \(oneDecimal(kilometers)) km"
            }
            return "\(label): \(oneDecimal(miles)) millas (\(oneDecimal(kilometers)) km)"
        case let (miles?, nil):
            return "\(label): \(oneDecimal(miles)) millas"
        case let (nil, kilometers?):
            return "\(label): \(oneDecimal(kilometers)) km"
        default:
            return nil
        }
    }

    private static func roundedRange(lower: Double, upper: Double) -> String {
        let roundedLower = (lower / 5).rounded(.down) * 5
        let roundedUpper = (upper / 5).rounded(.up) * 5
        return "\(wholeNumber(roundedLower))-\(wholeNumber(roundedUpper))"
    }

    private static func roundToNearestFive(_ value: Double) -> Double {
        (value / 5).rounded() * 5
    }

    private static func oneDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    private static func wholeNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }
}

struct MonthlyPurchaseSummary {
    let monthStart: Date
    let vehicleID: UUID?
    let spend: Double
    let gallons: Double
    let fillCount: Int

    var averagePricePerGallon: Double? {
        gallons > 0 ? spend / gallons : nil
    }

    var liters: Double {
        UnitConversion.gallonsToLiters(gallons)
    }

    func litersPerKilometer(using distanceKilometers: Double) -> Double? {
        guard distanceKilometers > 0 else { return nil }
        return liters / distanceKilometers
    }
}

struct WeeklyPurchaseSummary {
    let weekStart: Date
    let vehicleID: UUID?
    let spend: Double
    let gallons: Double
    let fillCount: Int

    var averagePricePerGallon: Double? {
        gallons > 0 ? spend / gallons : nil
    }

    var liters: Double {
        UnitConversion.gallonsToLiters(gallons)
    }

    func litersPerKilometer(using distanceKilometers: Double) -> Double? {
        guard distanceKilometers > 0 else { return nil }
        return liters / distanceKilometers
    }
}

struct MonthlyCaptureSummary {
    let monthStart: Date
    let vehicleID: UUID?
    let fillCount: Int
    let snapshotCount: Int
    let latestCaptureDate: Date?
    let latestSnapshotTripKilometers: Double?
    let latestSnapshotOdometerKilometers: Double?
    let latestSnapshotFuelLevelRemaining: Double?

    var totalCaptureCount: Int { fillCount + snapshotCount }
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

struct WeeklySummary: Identifiable {
    let id: Date
    let weekStart: Date
    let vehicleID: UUID?
    var spend: Double
    var gallons: Double
    var distanceKilometers: Double
    var cycleCount: Int

    var kmPerGallon: Double { gallons > 0 ? distanceKilometers / gallons : 0 }
    var costPerKilometer: Double { distanceKilometers > 0 ? spend / distanceKilometers : 0 }
}

enum ReportValueOrigin: String {
    case real
    case estimated
    case mixed

    var title: String {
        switch self {
        case .real:
            return "Real"
        case .estimated:
            return "Estimado"
        case .mixed:
            return "Mixto"
        }
    }
}

struct DetailedWeeklyReport: Identifiable {
    let id: Date
    let weekStart: Date
    let vehicleID: UUID?
    let distanceKilometers: Double
    let gallons: Double?
    let totalCost: Double?
    let kmPerGallon: Double?
    let daysOfUse: Int
    let averageDailyKilometers: Double
    let cycleCount: Int
    let valueOrigin: ReportValueOrigin

    var distanceMiles: Double {
        UnitConversion.kilometersToMiles(distanceKilometers)
    }
}

struct DetailedMonthlyReport: Identifiable {
    let id: Date
    let monthStart: Date
    let vehicleID: UUID?
    let fillCount: Int
    let totalPaid: Double
    let distanceKilometers: Double
    let gallonsConsumed: Double?
    let consumptionOrigin: ReportValueOrigin
    let costPerKilometer: Double?
    let averageAutonomyKilometers: Double?
    let bestTank: TankComparisonReport?
    let worstTank: TankComparisonReport?
    let estimatedConsumedCost: Double?
    let paidVsConsumedDelta: Double?
    let cycleCount: Int
    let daysOfUse: Int
    let averageDailyKilometers: Double

    var distanceMiles: Double {
        UnitConversion.kilometersToMiles(distanceKilometers)
    }

    var kmPerGallon: Double? {
        guard let gallonsConsumed, gallonsConsumed > 0 else { return nil }
        return distanceKilometers / gallonsConsumed
    }
}

struct TankComparisonReport: Identifiable {
    let id: UUID
    let vehicleID: UUID
    let vehicleName: String
    let startDate: Date
    let endDate: Date
    let openingOdometerKilometers: Double
    let closingOdometerKilometers: Double
    let distanceKilometers: Double
    let gallons: Double
    let totalCost: Double
    let kmPerGallon: Double
    let costPerKilometer: Double
    let isBest: Bool
    let isWorst: Bool
}

struct RefuelLocationPoint: Identifiable {
    let id: UUID
    let vehicleID: UUID
    let vehicleName: String
    let date: Date
    let stationName: String
    let latitude: Double
    let longitude: Double
    let gallons: Double
    let totalCost: Double
    let pricePerGallon: Double
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

        var cycles: [TankCycle] = []
        var openingFill: FuelFillEvent?
        var pendingGallons = 0.0
        var pendingCost = 0.0

        for fill in scoped {
            if openingFill != nil {
                pendingGallons += fill.gallons
                pendingCost += fill.totalCost
            }
            guard fill.isFullTank else { continue }
            guard let vehicle = fill.vehicle else { continue }

            if let openingFill {
                let distance = max(0, fill.odometerKilometers - openingFill.odometerKilometers)
                cycles.append(
                    TankCycle(
                        id: fill.id,
                        vehicleID: vehicle.id,
                        vehicleName: vehicle.displayName,
                        openingFillID: openingFill.id,
                        closingFillID: fill.id,
                        startDate: openingFill.date,
                        endDate: fill.date,
                        openingOdometerKilometers: openingFill.odometerKilometers,
                        closingOdometerKilometers: fill.odometerKilometers,
                        distanceKilometers: distance,
                        gallons: pendingGallons,
                        totalCost: pendingCost,
                        pricePerGallon: pendingGallons > 0 ? pendingCost / pendingGallons : 0,
                        endFuelLevelRemaining: fill.fuelLevelRemaining
                    )
                )
            }

            openingFill = fill
            pendingGallons = 0
            pendingCost = 0
        }

        return cycles
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
        let scopedSnapshots = snapshots
            .filter { $0.vehicle?.id == vehicleID }
            .sorted { $0.date < $1.date }

        guard let latestFullFill = scopedFills.last(where: \.isFullTank) else {
            let latestReading = latestReading(fill: scopedFills.last, snapshot: scopedSnapshots.last)
            return CurrentTankStatus(
                latestFill: nil,
                latestReadingDate: latestReading.date,
                latestReadingKilometers: latestReading.odometerKilometers,
                distanceKilometers: 0,
                spacesRemaining: latestReading.fuelLevelRemaining,
                estimatedAutonomyKilometers: nil,
                estimatedFuelCostConsumed: nil,
                insight: nil
            )
        }

        let latestSnapshot = scopedSnapshots.last(where: { $0.date >= latestFullFill.date })
        let latestFillReading = scopedFills.last(where: { $0.date >= latestFullFill.date })
        let latestReading = latestReading(fill: latestFillReading, snapshot: latestSnapshot)
        let latestReadingOdometer = latestReading.odometerKilometers ?? latestFullFill.odometerKilometers
        let distance = max(0, latestReadingOdometer - latestFullFill.odometerKilometers)
        let remainingSpaces = latestReading.fuelLevelRemaining ?? latestFullFill.fuelLevelRemaining
        let recentCycles = tankCycles(fills: fills, vehicleID: vehicleID).suffix(3)
        let vehicle = latestFullFill.vehicle
        let recentAverageKmPerGallon = recentCycles.isEmpty ? nil : recentCycles.map(\.kmPerGallon).reduce(0, +) / Double(recentCycles.count)
        let kmPerGallonReference = recentAverageKmPerGallon ?? vehicle?.fuelEconomyReferenceKilometersPerGallon
        let configuredCapacity = vehicle?.tankCapacityGallons ?? 0
        let recentAverageGallons = recentCycles.isEmpty ? nil : recentCycles.map(\.gallons).reduce(0, +) / Double(recentCycles.count)
        let fullTankGallons = max(max(configuredCapacity, recentAverageGallons ?? 0), latestFullFill.gallons)
        let remainingGallons = fullTankGallons * (remainingSpaces / max(vehicle?.fuelScaleMax ?? FuelLevelScale.defaultMax, 1))
        let autonomy: Double?
        if let kmPerGallonReference, kmPerGallonReference > 0 {
            autonomy = kmPerGallonReference * remainingGallons
        } else {
            autonomy = nil
        }
        let latestPricePerGallon = latestFillReading?.pricePerGallon ?? latestFullFill.pricePerGallon
        let costConsumed: Double?
        if let kmPerGallonReference, kmPerGallonReference > 0 {
            costConsumed = (distance / kmPerGallonReference) * latestPricePerGallon
        } else {
            costConsumed = nil
        }
        let insight = currentTankInsight(
            latestFullFill: latestFullFill,
            latestFillReading: latestFillReading,
            scopedSnapshots: scopedSnapshots,
            recentCycles: Array(recentCycles),
            vehicle: vehicle,
            distanceKilometers: distance,
            remainingSpaces: remainingSpaces
        )

        return CurrentTankStatus(
            latestFill: latestFullFill,
            latestReadingDate: latestReading.date ?? latestFullFill.date,
            latestReadingKilometers: latestReadingOdometer,
            distanceKilometers: distance,
            spacesRemaining: remainingSpaces,
            estimatedAutonomyKilometers: autonomy,
            estimatedFuelCostConsumed: costConsumed,
            insight: insight
        )
    }

    static func weeklySummaries(
        fills: [FuelFillEvent],
        vehicleID: UUID? = nil,
        calendar: Calendar = .current
    ) -> [WeeklySummary] {
        var buckets: [Date: WeeklySummary] = [:]

        for cycle in tankCycles(fills: fills, vehicleID: vehicleID) {
            let weekStart = cycle.endDate.startOfWeek(using: calendar)
            var summary = buckets[weekStart] ?? WeeklySummary(
                id: weekStart,
                weekStart: weekStart,
                vehicleID: vehicleID,
                spend: 0,
                gallons: 0,
                distanceKilometers: 0,
                cycleCount: 0
            )
            summary.spend += cycle.totalCost
            summary.gallons += cycle.gallons
            summary.distanceKilometers += cycle.distanceKilometers
            summary.cycleCount += 1
            buckets[weekStart] = summary
        }

        return buckets.values.sorted { $0.weekStart > $1.weekStart }
    }

    static func monthlyPurchases(
        fills: [FuelFillEvent],
        vehicleID: UUID? = nil,
        monthStart: Date,
        calendar: Calendar = .current
    ) -> MonthlyPurchaseSummary {
        let normalizedMonth = monthStart.startOfMonth(using: calendar)
        let scoped = fills.filter { fill in
            (vehicleID == nil || fill.vehicle?.id == vehicleID) &&
            calendar.isDate(fill.date, equalTo: normalizedMonth, toGranularity: .month)
        }

        return MonthlyPurchaseSummary(
            monthStart: normalizedMonth,
            vehicleID: vehicleID,
            spend: scoped.map(\.totalCost).reduce(0, +),
            gallons: scoped.map(\.gallons).reduce(0, +),
            fillCount: scoped.count
        )
    }

    static func weeklyPurchases(
        fills: [FuelFillEvent],
        vehicleID: UUID? = nil,
        weekStart: Date,
        calendar: Calendar = .current
    ) -> WeeklyPurchaseSummary {
        let normalizedWeek = weekStart.startOfWeek(using: calendar)
        let scoped = fills.filter { fill in
            guard vehicleID == nil || fill.vehicle?.id == vehicleID else { return false }
            return fill.date.startOfWeek(using: calendar) == normalizedWeek
        }

        return WeeklyPurchaseSummary(
            weekStart: normalizedWeek,
            vehicleID: vehicleID,
            spend: scoped.map(\.totalCost).reduce(0, +),
            gallons: scoped.map(\.gallons).reduce(0, +),
            fillCount: scoped.count
        )
    }

    static func monthlyCaptures(
        fills: [FuelFillEvent],
        snapshots: [SnapshotEvent],
        vehicleID: UUID? = nil,
        monthStart: Date,
        calendar: Calendar = .current
    ) -> MonthlyCaptureSummary {
        let normalizedMonth = monthStart.startOfMonth(using: calendar)
        let scopedFills = fills.filter { fill in
            (vehicleID == nil || fill.vehicle?.id == vehicleID) &&
            calendar.isDate(fill.date, equalTo: normalizedMonth, toGranularity: .month)
        }
        let scopedSnapshots = snapshots.filter { snapshot in
            (vehicleID == nil || snapshot.vehicle?.id == vehicleID) &&
            calendar.isDate(snapshot.date, equalTo: normalizedMonth, toGranularity: .month)
        }
        let latestFillDate = scopedFills.map(\.date).max()
        let latestSnapshot = scopedSnapshots.max { $0.date < $1.date }
        let latestCaptureDate = [latestFillDate, latestSnapshot?.date]
            .compactMap { $0 }
            .max()

        return MonthlyCaptureSummary(
            monthStart: normalizedMonth,
            vehicleID: vehicleID,
            fillCount: scopedFills.count,
            snapshotCount: scopedSnapshots.count,
            latestCaptureDate: latestCaptureDate,
            latestSnapshotTripKilometers: latestSnapshot?.tripKilometers,
            latestSnapshotOdometerKilometers: latestSnapshot?.odometerKilometers,
            latestSnapshotFuelLevelRemaining: latestSnapshot?.fuelLevelRemaining
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

    static func detailedWeeklyReports(
        fills: [FuelFillEvent],
        snapshots: [SnapshotEvent],
        vehicleID: UUID? = nil,
        calendar: Calendar = .current
    ) -> [DetailedWeeklyReport] {
        guard let vehicleID else {
            let scopedVehicleIDs = scopedVehicleIDs(fills: fills, snapshots: snapshots)
            var buckets: [Date: DetailedWeeklyReport] = [:]

            for scopedVehicleID in scopedVehicleIDs {
                for report in detailedWeeklyReports(
                    fills: fills,
                    snapshots: snapshots,
                    vehicleID: scopedVehicleID,
                    calendar: calendar
                ) {
                    let existing = buckets[report.weekStart]
                    buckets[report.weekStart] = mergeWeeklyReports(
                        existing: existing,
                        incoming: report
                    )
                }
            }

            return buckets.values.sorted { $0.weekStart > $1.weekStart }
        }

        let scopedFills = fills
            .filter { $0.vehicle?.id == vehicleID }
            .sorted { $0.date < $1.date }
        let scopedSnapshots = snapshots
            .filter { $0.vehicle?.id == vehicleID }
            .sorted { $0.date < $1.date }
        let cycles = tankCycles(fills: fills, vehicleID: vehicleID)
        let weeks = Set(cycles.map { $0.endDate.startOfWeek(using: calendar) })
            .union(scopedFills.map { $0.date.startOfWeek(using: calendar) })
            .union(scopedSnapshots.map { $0.date.startOfWeek(using: calendar) })
            .sorted(by: >)

        return weeks.compactMap { weekStart in
            let weekCycles = cycles.filter { calendar.isDate($0.endDate, equalTo: weekStart, toGranularity: .weekOfYear) }
            let weekFills = scopedFills.filter { calendar.isDate($0.date, equalTo: weekStart, toGranularity: .weekOfYear) }
            let weekSnapshots = scopedSnapshots.filter { calendar.isDate($0.date, equalTo: weekStart, toGranularity: .weekOfYear) }
            let daysOfUse = usageDaysCount(fills: weekFills, snapshots: weekSnapshots, calendar: calendar)

            if !weekCycles.isEmpty {
                let distance = weekCycles.map(\.distanceKilometers).reduce(0, +)
                let gallons = weekCycles.map(\.gallons).reduce(0, +)
                let cost = weekCycles.map(\.totalCost).reduce(0, +)

                return DetailedWeeklyReport(
                    id: weekStart,
                    weekStart: weekStart,
                    vehicleID: vehicleID,
                    distanceKilometers: distance,
                    gallons: gallons,
                    totalCost: cost,
                    kmPerGallon: gallons > 0 ? distance / gallons : nil,
                    daysOfUse: daysOfUse,
                    averageDailyKilometers: daysOfUse > 0 ? distance / Double(daysOfUse) : 0,
                    cycleCount: weekCycles.count,
                    valueOrigin: .real
                )
            }

            let estimatedDistance = estimatedDistanceKilometers(
                fills: weekFills,
                snapshots: weekSnapshots
            )
            guard estimatedDistance > 0 else { return nil }

            let scopedVehicle = scopedFills.last?.vehicle ?? scopedSnapshots.last?.vehicle
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let reference = referenceKilometersPerGallon(
                fills: fills,
                vehicleID: vehicleID,
                vehicle: scopedVehicle,
                upTo: weekEnd
            )
            let gallons = reference.map { $0 > 0 ? estimatedDistance / $0 : nil } ?? nil
            let latestPrice = latestPricePerGallon(
                fills: fills,
                vehicleID: vehicleID,
                onOrBefore: weekEnd
            )
            let totalCost = gallons.flatMap { gallons in
                latestPrice.map { gallons * $0 }
            }

            return DetailedWeeklyReport(
                id: weekStart,
                weekStart: weekStart,
                vehicleID: vehicleID,
                distanceKilometers: estimatedDistance,
                gallons: gallons,
                totalCost: totalCost,
                kmPerGallon: gallons.flatMap { $0 > 0 ? estimatedDistance / $0 : nil } ?? reference,
                daysOfUse: daysOfUse,
                averageDailyKilometers: daysOfUse > 0 ? estimatedDistance / Double(daysOfUse) : 0,
                cycleCount: 0,
                valueOrigin: .estimated
            )
        }
    }

    static func detailedMonthlyReports(
        fills: [FuelFillEvent],
        snapshots: [SnapshotEvent],
        adjustments: [MonthlyManualAdjustment],
        vehicleID: UUID? = nil,
        mode: MonthlyAllocationMode,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [DetailedMonthlyReport] {
        guard let vehicleID else {
            let scopedVehicleIDs = scopedVehicleIDs(fills: fills, snapshots: snapshots, adjustments: adjustments)
            var buckets: [Date: DetailedMonthlyReport] = [:]

            for scopedVehicleID in scopedVehicleIDs {
                for report in detailedMonthlyReports(
                    fills: fills,
                    snapshots: snapshots,
                    adjustments: adjustments,
                    vehicleID: scopedVehicleID,
                    mode: mode,
                    calendar: calendar,
                    now: now
                ) {
                    let existing = buckets[report.monthStart]
                    buckets[report.monthStart] = mergeMonthlyReports(
                        existing: existing,
                        incoming: report
                    )
                }
            }

            return buckets.values.sorted { $0.monthStart > $1.monthStart }
        }

        let scopedFills = fills
            .filter { $0.vehicle?.id == vehicleID }
            .sorted { $0.date < $1.date }
        let scopedSnapshots = snapshots
            .filter { $0.vehicle?.id == vehicleID }
            .sorted { $0.date < $1.date }
        let scopedAdjustments = adjustments.filter { $0.vehicle?.id == vehicleID }
        let summaries = monthlySummaries(
            fills: fills,
            adjustments: adjustments,
            vehicleID: vehicleID,
            mode: mode,
            calendar: calendar
        )
        let cycles = tankCycles(fills: fills, vehicleID: vehicleID)
        let monthStarts = Set(summaries.map(\.monthStart))
            .union(scopedFills.map { $0.date.startOfMonth(using: calendar) })
            .union(scopedSnapshots.map { $0.date.startOfMonth(using: calendar) })
            .union(scopedAdjustments.map { $0.monthStart.startOfMonth(using: calendar) })
            .sorted(by: >)
        let currentMonthStart = now.startOfMonth(using: calendar)

        return monthStarts.compactMap { monthStart in
            let summary = summaries.first(where: { calendar.isDate($0.monthStart, equalTo: monthStart, toGranularity: .month) })
            let purchases = monthlyPurchases(
                fills: fills,
                vehicleID: vehicleID,
                monthStart: monthStart,
                calendar: calendar
            )
            let monthFills = scopedFills.filter { calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
            let monthSnapshots = scopedSnapshots.filter { calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
            let monthCycles = cycles.filter { calendar.isDate($0.endDate, equalTo: monthStart, toGranularity: .month) }
            let daysOfUse = usageDaysCount(fills: monthFills, snapshots: monthSnapshots, calendar: calendar)
            let baseDistance = summary?.totalDistanceKilometers ?? 0
            var estimatedDistance = 0.0

            if calendar.isDate(monthStart, equalTo: currentMonthStart, toGranularity: .month) {
                let status = currentTankStatus(
                    fills: fills,
                    snapshots: snapshots,
                    vehicleID: vehicleID,
                    calendar: calendar
                )
                if let latestFillDate = status.latestFill?.date,
                   calendar.isDate(latestFillDate, equalTo: monthStart, toGranularity: .month) {
                    estimatedDistance += status.distanceKilometers
                } else if baseDistance == 0 {
                    estimatedDistance += estimatedDistanceKilometers(
                        fills: monthFills,
                        snapshots: monthSnapshots
                    )
                }
            } else if baseDistance == 0 {
                estimatedDistance += estimatedDistanceKilometers(
                    fills: monthFills,
                    snapshots: monthSnapshots
                )
            }

            let totalDistance = baseDistance + estimatedDistance
            let scopedVehicle = scopedFills.last?.vehicle ?? scopedSnapshots.last?.vehicle ?? scopedAdjustments.last?.vehicle
            let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart
            let reference = referenceKilometersPerGallon(
                fills: fills,
                vehicleID: vehicleID,
                vehicle: scopedVehicle,
                upTo: monthEnd
            )
            let realGallons = summary?.gallons ?? 0
            let estimatedGallons = reference.flatMap { $0 > 0 ? estimatedDistance / $0 : nil } ?? nil
            let totalGallons = totalGallons(realGallons: realGallons, estimatedGallons: estimatedGallons)

            if totalDistance <= 0, purchases.fillCount == 0, monthCycles.isEmpty {
                return nil
            }

            let consumptionOrigin = reportOrigin(
                hasRealComponent: realGallons > 0 || !monthCycles.isEmpty,
                hasEstimatedComponent: (estimatedGallons ?? 0) > 0
            )
            let averagePricePerGallon = purchases.gallons > 0
                ? purchases.spend / purchases.gallons
                : latestPricePerGallon(fills: fills, vehicleID: vehicleID, onOrBefore: monthEnd)
            let estimatedConsumedCost = totalGallons.flatMap { gallons in
                averagePricePerGallon.map { gallons * $0 }
            }
            let comparisons = tankComparisonReports(
                fills: fills,
                vehicleID: vehicleID
            ).filter { calendar.isDate($0.endDate, equalTo: monthStart, toGranularity: .month) }
            let bestTank = comparisons.max(by: { $0.kmPerGallon < $1.kmPerGallon })
            let worstTank = comparisons.min(by: { $0.kmPerGallon < $1.kmPerGallon })
            let averageAutonomy = averageAutonomyKilometers(
                comparisons: comparisons,
                vehicle: scopedVehicle
            )

            return DetailedMonthlyReport(
                id: monthStart,
                monthStart: monthStart,
                vehicleID: vehicleID,
                fillCount: purchases.fillCount,
                totalPaid: purchases.spend,
                distanceKilometers: totalDistance,
                gallonsConsumed: totalGallons,
                consumptionOrigin: consumptionOrigin,
                costPerKilometer: totalDistance > 0 ? purchases.spend / totalDistance : nil,
                averageAutonomyKilometers: averageAutonomy,
                bestTank: bestTank,
                worstTank: worstTank,
                estimatedConsumedCost: estimatedConsumedCost,
                paidVsConsumedDelta: estimatedConsumedCost.map { purchases.spend - $0 },
                cycleCount: monthCycles.count,
                daysOfUse: daysOfUse,
                averageDailyKilometers: daysOfUse > 0 ? totalDistance / Double(daysOfUse) : 0
            )
        }
    }

    static func tankComparisonReports(
        fills: [FuelFillEvent],
        vehicleID: UUID? = nil
    ) -> [TankComparisonReport] {
        let cycles = tankCycles(fills: fills, vehicleID: vehicleID)
        let bestCycleID = cycles.max(by: { $0.kmPerGallon < $1.kmPerGallon })?.id
        let worstCycleID = cycles.min(by: { $0.kmPerGallon < $1.kmPerGallon })?.id

        return cycles
            .sorted { $0.endDate > $1.endDate }
            .map { cycle in
                TankComparisonReport(
                    id: cycle.id,
                    vehicleID: cycle.vehicleID,
                    vehicleName: cycle.vehicleName,
                    startDate: cycle.startDate,
                    endDate: cycle.endDate,
                    openingOdometerKilometers: cycle.openingOdometerKilometers,
                    closingOdometerKilometers: cycle.closingOdometerKilometers,
                    distanceKilometers: cycle.distanceKilometers,
                    gallons: cycle.gallons,
                    totalCost: cycle.totalCost,
                    kmPerGallon: cycle.kmPerGallon,
                    costPerKilometer: cycle.costPerKilometer,
                    isBest: cycle.id == bestCycleID,
                    isWorst: cycle.id == worstCycleID
                )
            }
    }

    static func weeklyReportCSVRows(
        _ reports: [DetailedWeeklyReport]
    ) -> [[String]] {
        var rows = [[
            "semana_inicio",
            "distancia_km",
            "distancia_millas",
            "galones",
            "costo_total",
            "km_por_galon",
            "dias_uso",
            "promedio_diario_km",
            "origen",
            "ciclos_cerrados"
        ]]

        for report in reports {
            rows.append([
                csvDate(report.weekStart),
                csvNumber(report.distanceKilometers),
                csvNumber(report.distanceMiles),
                csvNumber(report.gallons),
                csvNumber(report.totalCost),
                csvNumber(report.kmPerGallon),
                String(report.daysOfUse),
                csvNumber(report.averageDailyKilometers),
                report.valueOrigin.rawValue,
                String(report.cycleCount)
            ])
        }

        return rows
    }

    static func monthlyReportCSVRows(
        _ reports: [DetailedMonthlyReport]
    ) -> [[String]] {
        var rows = [[
            "mes_inicio",
            "llenados",
            "pagado_total",
            "distancia_km",
            "distancia_millas",
            "galones_consumidos",
            "km_por_galon",
            "costo_por_km",
            "dias_uso",
            "promedio_diario_km",
            "autonomia_promedio_km",
            "mejor_tanque_km_por_galon",
            "peor_tanque_km_por_galon",
            "costo_consumido_estimado",
            "delta_pagado_vs_consumido",
            "origen_consumo",
            "ciclos_cerrados"
        ]]

        for report in reports {
            rows.append([
                csvDate(report.monthStart),
                String(report.fillCount),
                csvNumber(report.totalPaid),
                csvNumber(report.distanceKilometers),
                csvNumber(report.distanceMiles),
                csvNumber(report.gallonsConsumed),
                csvNumber(report.kmPerGallon),
                csvNumber(report.costPerKilometer),
                String(report.daysOfUse),
                csvNumber(report.averageDailyKilometers),
                csvNumber(report.averageAutonomyKilometers),
                csvNumber(report.bestTank?.kmPerGallon),
                csvNumber(report.worstTank?.kmPerGallon),
                csvNumber(report.estimatedConsumedCost),
                csvNumber(report.paidVsConsumedDelta),
                report.consumptionOrigin.rawValue,
                String(report.cycleCount)
            ])
        }

        return rows
    }

    static func tankComparisonCSVRows(
        _ comparisons: [TankComparisonReport]
    ) -> [[String]] {
        var rows = [[
            "inicio",
            "cierre",
            "odometro_inicio_km",
            "odometro_fin_km",
            "distancia_km",
            "galones",
            "total",
            "km_por_galon",
            "costo_por_km",
            "etiqueta"
        ]]

        for comparison in comparisons {
            rows.append([
                csvDate(comparison.startDate),
                csvDate(comparison.endDate),
                csvNumber(comparison.openingOdometerKilometers),
                csvNumber(comparison.closingOdometerKilometers),
                csvNumber(comparison.distanceKilometers),
                csvNumber(comparison.gallons),
                csvNumber(comparison.totalCost),
                csvNumber(comparison.kmPerGallon),
                csvNumber(comparison.costPerKilometer),
                comparison.isBest ? "mejor" : comparison.isWorst ? "peor" : ""
            ])
        }

        return rows
    }

    static func refuelLocations(
        fills: [FuelFillEvent],
        vehicleID: UUID? = nil
    ) -> [RefuelLocationPoint] {
        fills
            .filter { fill in
                (vehicleID == nil || fill.vehicle?.id == vehicleID) &&
                fill.latitude != nil &&
                fill.longitude != nil &&
                fill.vehicle != nil
            }
            .sorted { $0.date > $1.date }
            .compactMap { fill in
                guard let vehicle = fill.vehicle,
                      let latitude = fill.latitude,
                      let longitude = fill.longitude
                else {
                    return nil
                }
                return RefuelLocationPoint(
                    id: fill.id,
                    vehicleID: vehicle.id,
                    vehicleName: vehicle.displayName,
                    date: fill.date,
                    stationName: Optional(fill.stationName).nilIfBlank ?? "Recarga \(fill.date.formatted(date: .abbreviated, time: .shortened))",
                    latitude: latitude,
                    longitude: longitude,
                    gallons: fill.gallons,
                    totalCost: fill.totalCost,
                    pricePerGallon: fill.pricePerGallon
                )
            }
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

    private static func latestReading(fill: FuelFillEvent?, snapshot: SnapshotEvent?) -> LatestReading {
        switch (fill, snapshot) {
        case let (fill?, snapshot?) where snapshot.date > fill.date:
            return LatestReading(
                date: snapshot.date,
                odometerKilometers: snapshot.odometerKilometers,
                fuelLevelRemaining: snapshot.fuelLevelRemaining
            )
        case let (fill?, _):
            return LatestReading(
                date: fill.date,
                odometerKilometers: fill.odometerKilometers,
                fuelLevelRemaining: fill.fuelLevelRemaining
            )
        case let (_, snapshot?):
            return LatestReading(
                date: snapshot.date,
                odometerKilometers: snapshot.odometerKilometers,
                fuelLevelRemaining: snapshot.fuelLevelRemaining
            )
        default:
            return LatestReading(date: nil, odometerKilometers: nil, fuelLevelRemaining: nil)
        }
    }

    private static func currentTankInsight(
        latestFullFill: FuelFillEvent,
        latestFillReading: FuelFillEvent?,
        scopedSnapshots: [SnapshotEvent],
        recentCycles: [TankCycle],
        vehicle: Vehicle?,
        distanceKilometers: Double,
        remainingSpaces: Double
    ) -> CurrentTankInsight? {
        let snapshotsAfterFill = scopedSnapshots.filter { $0.date >= latestFullFill.date }
        guard let latestSnapshot = snapshotsAfterFill.last else { return nil }

        let comparisonAnchorDate = latestFillReading?.date ?? latestFullFill.date
        let snapshotsAfterComparisonAnchor = snapshotsAfterFill
            .filter { $0.date >= comparisonAnchorDate && $0.id != latestSnapshot.id }
        let previousSnapshot = snapshotsAfterComparisonAnchor.first ?? snapshotsAfterFill.dropLast().last
        let tankRangeKilometers = estimatedTankRangeKilometers(
            recentCycles: recentCycles,
            vehicle: vehicle
        )
        let rangeBounds = likelyTankRangeBounds(
            recentCycles: recentCycles,
            estimatedTankRangeKilometers: tankRangeKilometers
        )
        let fuelScaleMax = max(vehicle?.fuelScaleMax ?? FuelLevelScale.defaultMax, 1)
        let fuelRemainingRatio = remainingSpaces / fuelScaleMax
        let remainingRange = rangeBounds.map { bounds in
            if fuelRemainingRatio <= 0.20 {
                return (
                    lower: bounds.lower * fuelRemainingRatio,
                    upper: bounds.upper * fuelRemainingRatio
                )
            }
            return (
                lower: max(0, bounds.lower - distanceKilometers),
                upper: max(0, bounds.upper - distanceKilometers)
            )
        }

        return CurrentTankInsight(
            latestSnapshotDate: latestSnapshot.date,
            latestOdometerKilometers: latestSnapshot.odometerKilometers,
            latestOdometerMiles: latestSnapshot.odometerMilesOriginal ?? UnitConversion.kilometersToMiles(latestSnapshot.odometerKilometers),
            latestTripKilometers: latestSnapshot.tripKilometers,
            latestTripMiles: latestSnapshot.tripMilesOriginal ?? latestSnapshot.tripKilometers.map(UnitConversion.kilometersToMiles),
            previousSnapshotDate: previousSnapshot?.date,
            previousTripKilometers: previousSnapshot?.tripKilometers,
            previousTripMiles: previousSnapshot?.tripMilesOriginal ?? previousSnapshot?.tripKilometers.map(UnitConversion.kilometersToMiles),
            tripDeltaKilometers: optionalDifference(latestSnapshot.tripKilometers, previousSnapshot?.tripKilometers),
            tripDeltaMiles: optionalDifference(
                latestSnapshot.tripMilesOriginal ?? latestSnapshot.tripKilometers.map(UnitConversion.kilometersToMiles),
                previousSnapshot?.tripMilesOriginal ?? previousSnapshot?.tripKilometers.map(UnitConversion.kilometersToMiles)
            ),
            fuelSpacesConsumed: FuelLevelScale.consumed(
                remaining: remainingSpaces,
                maxValue: fuelScaleMax,
                step: vehicle?.fuelScaleStep ?? FuelLevelScale.defaultStep
            ),
            fuelRemainingRatio: fuelRemainingRatio,
            estimatedTankRangeKilometers: tankRangeKilometers,
            likelyTankRangeKilometers: tankRangeKilometers,
            likelyTankRangeLowerKilometers: rangeBounds?.lower,
            likelyTankRangeUpperKilometers: rangeBounds?.upper,
            remainingRangeLowerKilometers: remainingRange?.lower,
            remainingRangeUpperKilometers: remainingRange?.upper,
            currentFillSpend: latestFullFill.totalCost > 0 ? latestFullFill.totalCost : nil,
            currentCostPerKilometer: latestFullFill.totalCost > 0 && distanceKilometers > 0
                ? latestFullFill.totalCost / distanceKilometers
                : nil
        )
    }

    private static func estimatedTankRangeKilometers(
        recentCycles: [TankCycle],
        vehicle: Vehicle?
    ) -> Double? {
        if !recentCycles.isEmpty {
            return recentCycles.map(\.distanceKilometers).reduce(0, +) / Double(recentCycles.count)
        }

        guard let vehicle,
              vehicle.fuelEconomyReferenceKilometersPerGallon > 0,
              vehicle.tankCapacityGallons > 0
        else { return nil }

        return vehicle.fuelEconomyReferenceKilometersPerGallon * vehicle.tankCapacityGallons
    }

    private static func likelyTankRangeBounds(
        recentCycles: [TankCycle],
        estimatedTankRangeKilometers: Double?
    ) -> (lower: Double, upper: Double)? {
        if !recentCycles.isEmpty {
            let distances = recentCycles.map(\.distanceKilometers)
            let lower = distances.min() ?? 0
            let upper = distances.max() ?? lower
            return (lower, max(upper, lower + 10))
        }

        guard let estimatedTankRangeKilometers else { return nil }
        return (
            max(0, estimatedTankRangeKilometers - 10),
            estimatedTankRangeKilometers + 10
        )
    }

    private static func optionalDifference(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return lhs - rhs
    }

    private static func scopedVehicleIDs(
        fills: [FuelFillEvent],
        snapshots: [SnapshotEvent],
        adjustments: [MonthlyManualAdjustment] = []
    ) -> [UUID] {
        Set(
            fills.compactMap { $0.vehicle?.id } +
            snapshots.compactMap { $0.vehicle?.id } +
            adjustments.compactMap { $0.vehicle?.id }
        )
        .sorted { $0.uuidString < $1.uuidString }
    }

    private static func mergeWeeklyReports(
        existing: DetailedWeeklyReport?,
        incoming: DetailedWeeklyReport
    ) -> DetailedWeeklyReport {
        guard let existing else { return incoming }
        let gallons = sumOptional(existing.gallons, incoming.gallons)
        let totalCost = sumOptional(existing.totalCost, incoming.totalCost)
        let distance = existing.distanceKilometers + incoming.distanceKilometers
        let days = existing.daysOfUse + incoming.daysOfUse

        return DetailedWeeklyReport(
            id: existing.weekStart,
            weekStart: existing.weekStart,
            vehicleID: nil,
            distanceKilometers: distance,
            gallons: gallons,
            totalCost: totalCost,
            kmPerGallon: gallons.flatMap { $0 > 0 ? distance / $0 : nil },
            daysOfUse: days,
            averageDailyKilometers: days > 0 ? distance / Double(days) : 0,
            cycleCount: existing.cycleCount + incoming.cycleCount,
            valueOrigin: combineOrigins(existing.valueOrigin, incoming.valueOrigin)
        )
    }

    private static func mergeMonthlyReports(
        existing: DetailedMonthlyReport?,
        incoming: DetailedMonthlyReport
    ) -> DetailedMonthlyReport {
        guard let existing else { return incoming }
        let gallons = sumOptional(existing.gallonsConsumed, incoming.gallonsConsumed)
        let distance = existing.distanceKilometers + incoming.distanceKilometers
        let days = existing.daysOfUse + incoming.daysOfUse
        let estimatedConsumedCost = sumOptional(existing.estimatedConsumedCost, incoming.estimatedConsumedCost)
        let averageAutonomy = averageOptional([existing.averageAutonomyKilometers, incoming.averageAutonomyKilometers])
        let bestTank = bestComparison(existing.bestTank, incoming.bestTank)
        let worstTank = worstComparison(existing.worstTank, incoming.worstTank)

        return DetailedMonthlyReport(
            id: existing.monthStart,
            monthStart: existing.monthStart,
            vehicleID: nil,
            fillCount: existing.fillCount + incoming.fillCount,
            totalPaid: existing.totalPaid + incoming.totalPaid,
            distanceKilometers: distance,
            gallonsConsumed: gallons,
            consumptionOrigin: combineOrigins(existing.consumptionOrigin, incoming.consumptionOrigin),
            costPerKilometer: distance > 0 ? (existing.totalPaid + incoming.totalPaid) / distance : nil,
            averageAutonomyKilometers: averageAutonomy,
            bestTank: bestTank,
            worstTank: worstTank,
            estimatedConsumedCost: estimatedConsumedCost,
            paidVsConsumedDelta: estimatedConsumedCost.map { (existing.totalPaid + incoming.totalPaid) - $0 },
            cycleCount: existing.cycleCount + incoming.cycleCount,
            daysOfUse: days,
            averageDailyKilometers: days > 0 ? distance / Double(days) : 0
        )
    }

    private static func usageDaysCount(
        fills: [FuelFillEvent],
        snapshots: [SnapshotEvent],
        calendar: Calendar
    ) -> Int {
        Set(
            fills.map { calendar.startOfDay(for: $0.date) } +
            snapshots.map { calendar.startOfDay(for: $0.date) }
        ).count
    }

    private static func estimatedDistanceKilometers(
        fills: [FuelFillEvent],
        snapshots: [SnapshotEvent]
    ) -> Double {
        let readings = (fills.map { ReportReading(date: $0.date, odometerKilometers: $0.odometerKilometers, tripKilometers: $0.tripKilometers) } +
            snapshots.map { ReportReading(date: $0.date, odometerKilometers: $0.odometerKilometers, tripKilometers: $0.tripKilometers) })
            .sorted { $0.date < $1.date }
        let odometerDelta: Double
        if let first = readings.first?.odometerKilometers,
           let last = readings.last?.odometerKilometers {
            odometerDelta = max(0, last - first)
        } else {
            odometerDelta = 0
        }
        let tripSum = readings.compactMap(\.tripKilometers).reduce(0, +)
        return max(odometerDelta, tripSum)
    }

    private static func referenceKilometersPerGallon(
        fills: [FuelFillEvent],
        vehicleID: UUID,
        vehicle: Vehicle?,
        upTo date: Date
    ) -> Double? {
        let recentCycles = tankCycles(
            fills: fills.filter { $0.date <= date },
            vehicleID: vehicleID
        ).suffix(3)
        if !recentCycles.isEmpty {
            return recentCycles.map(\.kmPerGallon).reduce(0, +) / Double(recentCycles.count)
        }
        if let vehicle, vehicle.fuelEconomyReferenceKilometersPerGallon > 0 {
            return vehicle.fuelEconomyReferenceKilometersPerGallon
        }
        return nil
    }

    private static func latestPricePerGallon(
        fills: [FuelFillEvent],
        vehicleID: UUID,
        onOrBefore date: Date
    ) -> Double? {
        fills
            .filter { $0.vehicle?.id == vehicleID && $0.date <= date }
            .sorted { $0.date < $1.date }
            .last?
            .pricePerGallon
    }

    private static func totalGallons(
        realGallons: Double,
        estimatedGallons: Double?
    ) -> Double? {
        if realGallons > 0 || (estimatedGallons ?? 0) > 0 {
            return realGallons + (estimatedGallons ?? 0)
        }
        return nil
    }

    private static func reportOrigin(
        hasRealComponent: Bool,
        hasEstimatedComponent: Bool
    ) -> ReportValueOrigin {
        switch (hasRealComponent, hasEstimatedComponent) {
        case (true, true):
            return .mixed
        case (true, false):
            return .real
        default:
            return .estimated
        }
    }

    private static func averageAutonomyKilometers(
        comparisons: [TankComparisonReport],
        vehicle: Vehicle?
    ) -> Double? {
        let autonomyValues = comparisons.compactMap { comparison -> Double? in
            let gallons = vehicle?.tankCapacityGallons ?? comparison.gallons
            guard gallons > 0 else { return nil }
            return comparison.kmPerGallon * gallons
        }
        guard !autonomyValues.isEmpty else { return nil }
        return autonomyValues.reduce(0, +) / Double(autonomyValues.count)
    }

    private static func combineOrigins(
        _ lhs: ReportValueOrigin,
        _ rhs: ReportValueOrigin
    ) -> ReportValueOrigin {
        lhs == rhs ? lhs : .mixed
    }

    private static func sumOptional(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs + rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private static func averageOptional(_ values: [Double?]) -> Double? {
        let resolved = values.compactMap { $0 }
        guard !resolved.isEmpty else { return nil }
        return resolved.reduce(0, +) / Double(resolved.count)
    }

    private static func bestComparison(
        _ lhs: TankComparisonReport?,
        _ rhs: TankComparisonReport?
    ) -> TankComparisonReport? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs.kmPerGallon >= rhs.kmPerGallon ? lhs : rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private static func worstComparison(
        _ lhs: TankComparisonReport?,
        _ rhs: TankComparisonReport?
    ) -> TankComparisonReport? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs.kmPerGallon <= rhs.kmPerGallon ? lhs : rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private static func csvDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func csvNumber(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.4f", value)
    }
}

enum LocalDataRepairService {
    @discardableResult
    static func repairReceiptDecimalArtifacts(fills: [FuelFillEvent], now: Date = .now) -> Int {
        var repairedCount = 0

        for fill in fills {
            guard fill.gallons > 100,
                  fill.pricePerGallon > 0,
                  fill.pricePerGallon < 250,
                  fill.totalCost > 0
            else { continue }

            let inferredGallons = fill.totalCost / fill.pricePerGallon
            guard (0.1...30).contains(inferredGallons) else { continue }

            fill.gallons = inferredGallons
            fill.updatedAt = now
            repairedCount += 1
        }

        return repairedCount
    }

    @discardableResult
    static func repairReceiptDecimalArtifacts(in context: ModelContext, now: Date = .now) throws -> Int {
        let fills = try context.fetch(FetchDescriptor<FuelFillEvent>())
        let repairedCount = repairReceiptDecimalArtifacts(fills: fills, now: now)
        if repairedCount > 0 {
            try context.save()
        }
        return repairedCount
    }
}

private struct LatestReading {
    let date: Date?
    let odometerKilometers: Double?
    let fuelLevelRemaining: Double?
}

private struct ReportReading {
    let date: Date
    let odometerKilometers: Double
    let tripKilometers: Double?
}
