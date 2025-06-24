import SwiftUI
import CoreLocation
import MapKit

struct LocationSelectionView: View {
    struct IdentifiableMapItem: Identifiable {
        let id = UUID()
        let mapItem: MKMapItem
    }

    @State private var searchText = ""
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125), // 日本中心
        span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
    )
    @State private var matchingItems: [IdentifiableMapItem] = []

var body: some View {
    VStack(spacing: 0) {
                Map(coordinateRegion: $region, annotationItems: matchingItems, annotationContent: { item in
                    MapMarker(coordinate: item.mapItem.placemark.coordinate)
                })
                .frame(height: 350)

                if matchingItems.isEmpty {
                    Spacer()
                    Text("検索結果がここに表示されます")
                        .foregroundColor(.gray)
                        .padding()
                    Spacer()
                } else {
                    List(matchingItems) { item in
                        NavigationLink(
                            destination: {
                                let selectedName = item.mapItem.name ?? "nil"
                                let selectedPlacemark = item.mapItem.placemark.title ?? "nil"
                                print("Selected Name: \(selectedName)")
                                print("Selected Placemark Title: \(selectedPlacemark)")
                                return AlarmDetailView(
                                    coordinate: item.mapItem.placemark.coordinate,
                                    placeName: item.mapItem.name ?? item.mapItem.placemark.name ?? item.mapItem.placemark.title
                                )
                            }()
                        ) {
                            VStack(alignment: .leading) {
                                Text(item.mapItem.name ?? "不明な場所")
                                Text(item.mapItem.placemark.title ?? "")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
        .navigationTitle("場所を選択")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("場所を検索", text: $searchText, onCommit: {
                        performSearch(searchText: searchText)
                    })
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                }
            }
        }
    }

    private func performSearch(searchText: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response else {
                print("検索エラー: \(error?.localizedDescription ?? "不明なエラー")")
                return
            }
            matchingItems = response.mapItems.map { IdentifiableMapItem(mapItem: $0) }
            if let first = response.mapItems.first {
                region = MKCoordinateRegion(
                    center: first.placemark.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
        }
    }
}
