import MapKit
import SwiftUI

struct RefuelLocationsView: View {
    let locations: [RefuelLocationPoint]

    @State private var position: MapCameraPosition

    init(locations: [RefuelLocationPoint]) {
        self.locations = locations
        if let first = locations.first {
            _position = State(initialValue: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
                )
            ))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    var body: some View {
        List {
            if !locations.isEmpty {
                Section("Mapa") {
                    Map(position: $position) {
                        ForEach(locations) { location in
                            Marker(location.stationName, coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
                        }
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("refuel.map")
                }
            }

            Section("Recargas registradas") {
                if locations.isEmpty {
                    Text("Aun no hay recargas con geolocalizacion guardada.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(locations) { location in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(location.stationName)
                                .font(.subheadline.weight(.semibold))
                            Text(location.vehicleName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(location.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("\(CartrackFormatters.decimal(location.gallons, suffix: "gal")) • \(CartrackFormatters.currency(location.totalCost)) • \(CartrackFormatters.currency(location.pricePerGallon))/gal")
                                .font(.footnote)
                            Text("Lat \(CartrackFormatters.decimal(location.latitude)), Lon \(CartrackFormatters.decimal(location.longitude))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Puntos de recarga")
    }
}
