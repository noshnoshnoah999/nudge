// LocationPickerView.swift — Nudge (iOS)
// Apple-Reminders-style place picker: type to search, live suggestions, a map
// preview of the pick, returns name + coordinates. No location permission needed
// (search only — we never read the user's location).

import SwiftUI
import MapKit
import Combine

@MainActor
final class SearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" { didSet { completer.queryFragment = query } }
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = completer.results
        Task { @MainActor in self.results = r }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> (name: String, coord: CLLocationCoordinate2D)? {
        let req = MKLocalSearch.Request(completion: completion)
        guard let resp = try? await MKLocalSearch(request: req).start(),
              let item = resp.mapItems.first else { return nil }
        let name = completion.title.isEmpty ? (item.name ?? "Location") : completion.title
        return (name, item.placemark.coordinate)
    }
}

struct LocationPickerView: View {
    @StateObject private var completer = SearchCompleter()
    @Environment(\.dismiss) private var dismiss

    var initialName: String
    var initialLat: Double?
    var initialLng: Double?
    var onSelect: (String, Double, Double) -> Void
    var onRemove: () -> Void

    @State private var pickedName: String?
    @State private var pickedCoord: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search address or place", text: $completer.query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !completer.query.isEmpty {
                        Button { completer.query = ""; completer.results = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(16)

                if let coord = pickedCoord {
                    Map(position: $camera) {
                        Marker(pickedName ?? "Location", coordinate: coord)
                            .tint(Theme.violet)
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)

                    Text(pickedName ?? "")
                        .font(.headline).foregroundStyle(Theme.textMain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.top, 12)

                    Button {
                        onSelect(pickedName ?? "", coord.latitude, coord.longitude); dismiss()
                    } label: {
                        Text("Use this location").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Theme.violetGrad, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(16)
                    Spacer()
                } else if !completer.results.isEmpty {
                    List(completer.results, id: \.self) { c in
                        Button { pick(c) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).foregroundStyle(Theme.textMain)
                                if !c.subtitle.isEmpty {
                                    Text(c.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Search for a place").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !initialName.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Remove", role: .destructive) { onRemove(); dismiss() }
                    }
                }
            }
            .onAppear {
                if let la = initialLat, let lo = initialLng {
                    let c = CLLocationCoordinate2D(latitude: la, longitude: lo)
                    pickedName = initialName; pickedCoord = c
                    camera = .region(MKCoordinateRegion(center: c,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                } else if !initialName.isEmpty {
                    completer.query = initialName
                }
            }
        }
        .tint(Theme.violet)
        .presentationBackground(Theme.bg)
    }

    private func pick(_ c: MKLocalSearchCompletion) {
        Task {
            guard let (name, coord) = await completer.resolve(c) else { return }
            pickedName = name; pickedCoord = coord
            camera = .region(MKCoordinateRegion(center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
            completer.results = []
        }
    }
}
