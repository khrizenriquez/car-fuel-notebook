import SwiftUI

struct FuelLevelInputView: View {
    let title: String
    let maxValue: Double
    let step: Double
    let accessibilityPrefix: String

    @Binding var value: Double
    @State private var textValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text(CartrackFormatters.decimal(value, suffix: "espacios"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(accessibilityPrefix).fuelLevel.value")
            }

            HStack(spacing: 12) {
                Button {
                    updateValue(value - step)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Disminuir espacios")
                .accessibilityIdentifier("\(accessibilityPrefix).fuelLevel.decrement")

                TextField("Espacios", text: $textValue)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("\(accessibilityPrefix).fuelLevel")
                    .accessibilityValue(CartrackFormatters.decimal(value, suffix: "espacios"))
                    .onChange(of: textValue) { _, newValue in
                        guard let parsed = newValue.asDouble else { return }
                        updateValue(parsed, shouldSyncText: false)
                    }

                Button {
                    updateValue(value + step)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aumentar espacios")
                .accessibilityIdentifier("\(accessibilityPrefix).fuelLevel.increment")
            }

            Slider(value: normalizedBinding, in: 0...maxValue, step: step)
                .accessibilityIdentifier("\(accessibilityPrefix).fuelLevel.slider")

            Text("Rango 0 a \(CartrackFormatters.decimal(maxValue)); pasos de \(CartrackFormatters.decimal(step)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            syncText()
            updateValue(value)
        }
        .onChange(of: value) { _, _ in
            syncText()
        }
    }

    private var normalizedBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { updateValue($0) }
        )
    }

    private func updateValue(_ newValue: Double, shouldSyncText: Bool = true) {
        let normalized = FuelLevelScale.normalize(newValue, maxValue: maxValue, step: step)
        guard normalized != value || shouldSyncText else { return }
        value = normalized
        if shouldSyncText {
            textValue = CartrackFormatters.decimal(normalized)
        }
    }

    private func syncText() {
        let formatted = CartrackFormatters.decimal(value)
        if textValue != formatted {
            textValue = formatted
        }
    }
}
