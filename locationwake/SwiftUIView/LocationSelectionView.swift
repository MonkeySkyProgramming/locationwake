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
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125),
        span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
    ))
    @State private var matchingItems: [IdentifiableMapItem] = []
    @AppStorage("defaultRadius") private var defaultRadius: Double = 300.0
    @AppStorage("isSoundEnabled") private var defaultSoundEnabled: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                AppNavigationHeader(title: "場所を選択", showsBackButton: true) {
                    dismiss()
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color("NavBarTintColor"))
                    TextField("場所を検索", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            performSearch(searchText: searchText)
                        }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .background(Color("NavBarColor"))
            }

            Map(position: $cameraPosition) {
                ForEach(matchingItems) { item in
                    Marker(item.mapItem.name ?? "", coordinate: item.mapItem.placemark.coordinate)
                }
            }
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
                        destination: AlarmDetailView(
                            alarm: Alarm(
                                name: item.mapItem.name ?? "未命名",
                                repeatWeekdays: [],
                                sound: "modan",
                                isAlarmEnabled: true,
                                isSoundEnabled: defaultSoundEnabled,
                                isVibrationEnabled: true,
                                location: Location(
                                    latitude: item.mapItem.placemark.coordinate.latitude,
                                    longitude: item.mapItem.placemark.coordinate.longitude
                                ),
                                radius: defaultRadius
                            )
                        )
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
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    private func performSearch(searchText: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = region
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
                cameraPosition = .region(region)
            }
        }
    }
}
