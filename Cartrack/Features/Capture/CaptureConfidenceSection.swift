import SwiftUI

struct CaptureConfidenceSection: View {
    private struct QualityIssueGroup: Identifiable {
        let kind: CaptureImageKind
        let issues: [CaptureImageIssue]
        var id: String { kind.rawValue }
    }

    let fields: [FieldResult]
    let imageIssues: [CaptureImageKind: [CaptureImageIssue]]
    let isManuallyResolved: (CaptureField) -> Bool
    let retake: (CaptureImageKind) -> Void

    private var actionableIssues: [QualityIssueGroup] {
        CaptureImageKind.allCases.compactMap { kind in
            let issues = (imageIssues[kind] ?? []).filter { $0 != .orientationCorrected }
            return issues.isEmpty ? nil : QualityIssueGroup(kind: kind, issues: issues)
        }
    }

    var body: some View {
        if !fields.isEmpty {
            Section("Confianza de lectura") {
                ForEach(fields, id: \.field) { result in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(result.field.displayTitle)
                                .font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier("capture.confidence.\(result.field.rawValue)")
                            Spacer()
                            Text(label(for: result))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(for: result))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(result.field.displayTitle): \(label(for: result))")
                        .accessibilityHint("El estado se expresa también con texto, no solo con color.")
                        if let selected = result.candidates.first(where: {
                            $0.candidate.id == result.selectedCandidateID
                        }) {
                            Text("Fuente: \(result.field.sourceTitle) · \(selected.candidate.rawText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let candidate = result.candidates.first {
                            Text("Posible lectura: \(candidate.candidate.rawText). Confírmala manualmente.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Sin lectura confiable; ingresa el dato o repite la foto.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(result.validationCodes, id: \.self) { code in
                            if let explanation = CaptureConfidencePresentation.explanation(for: code) {
                                Text(explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if CaptureConfidencePresentation.requiresRetake(result.band) {
                            Button("Repetir solo \(result.field.sourceTitle.lowercased())") {
                                retake(result.field.sourceKind)
                            }
                            .font(.caption)
                            .accessibilityIdentifier("capture.retake.\(result.field.rawValue)")
                        }
                    }
                }
            }
        }
        if !actionableIssues.isEmpty {
            Section("Calidad de fotos") {
                ForEach(actionableIssues) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.kind.title).font(.subheadline.weight(.semibold))
                        ForEach(group.issues, id: \.rawValue) { issue in
                            Text(CaptureConfidencePresentation.explanation(for: issue))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Button("Repetir solo \(group.kind.title.lowercased())") { retake(group.kind) }
                    }
                }
            }
        }
    }

    private func label(for result: FieldResult) -> String {
        CaptureConfidencePresentation.label(result.band,
                                            manuallyResolved: isManuallyResolved(result.field))
    }

    private func color(for result: FieldResult) -> Color {
        switch CaptureConfidencePresentation.tone(result.band,
                                                  manuallyResolved: isManuallyResolved(result.field)) {
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

enum CaptureConfidencePresentation {
    enum Tone: Equatable { case success, warning, error }

    static func label(_ band: FieldConfidenceBand, manuallyResolved: Bool) -> String {
        if requiresRetake(band) && manuallyResolved { return "Corregido manualmente" }
        return switch band {
        case .high: "Alta"
        case .medium: "Media · revisar"
        case .low: "Baja · corregir"
        case .critical: "Conflicto · corregir"
        }
    }

    static func tone(_ band: FieldConfidenceBand, manuallyResolved: Bool) -> Tone {
        if requiresRetake(band) && manuallyResolved { return .success }
        return switch band {
        case .high: .success
        case .medium, .low: .warning
        case .critical: .error
        }
    }

    static func requiresRetake(_ band: FieldConfidenceBand) -> Bool {
        band == .low || band == .critical
    }

    static func explanation(for code: String) -> String? {
        return switch code {
        case "field.conflict": "Dos lecturas confiables no coinciden; elige o escribe el valor correcto."
        case "field.financialMismatch": "Galones × precio no coincide con el total de la factura."
        case "field.odometerRegression": "La lectura es menor que el odómetro anterior."
        case "field.tripMismatch": "El trip no coincide con la distancia desde el último llenado."
        case "field.outOfRange", "field.offGaugeStep": "El valor está fuera de la escala configurada."
        case "field.weakAlternative": "Otra lectura difiere; revisa la foto antes de confirmar."
        case "field.noCandidate": nil
        default: "La lectura necesita revisión manual."
        }
    }

    static func explanation(for issue: CaptureImageIssue) -> String {
        return switch issue {
        case .lowResolution: "La foto tiene poca resolución."
        case .tooBlurred: "La foto está desenfocada."
        case .overexposed: "La foto tiene demasiada luz."
        case .underexposed: "La foto está demasiado oscura."
        case .possibleGlare: "Hay un posible reflejo sobre la lectura."
        case .possibleCrop: "Puede faltar parte de la lectura."
        case .wrongKind: "La foto no parece corresponder a este campo."
        case .orientationCorrected: "La orientación se corrigió automáticamente."
        }
    }
}

private extension CaptureField {
    var displayTitle: String {
        switch self {
        case .odometerKilometers: "Odómetro"
        case .tripKilometers: "Trip"
        case .fuelLevelRemaining: "Nivel de tanque"
        case .volumeGallons: "Galones"
        case .unitPrice: "Precio por galón"
        case .totalCost: "Total"
        case .stationName: "Gasolinera"
        case .occurredAt: "Fecha"
        }
    }

    var sourceTitle: String {
        switch sourceKind {
        case .invoice: "factura"
        case .odometer: "tablero"
        case .fuelLevel: "medidor"
        }
    }

    var sourceKind: CaptureImageKind {
        switch self {
        case .odometerKilometers, .tripKilometers: .odometer
        case .fuelLevelRemaining: .fuelLevel
        case .volumeGallons, .unitPrice, .totalCost, .stationName, .occurredAt: .invoice
        }
    }
}
