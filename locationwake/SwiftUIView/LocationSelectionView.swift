import SwiftUI
import CoreLocation
import MapKit

struct LocationSelectionView: View {
    struct IdentifiableMapItem: Identifiable {
        let id = UUID()
        let mapItem: MKMapItem
    }

    private let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.6873, longitude: 135.5262),
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
    )

    @State private var searchText = ""
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.6873, longitude: 135.5262),
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
    )
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.6873, longitude: 135.5262),
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
    ))
    @State private var matchingItems: [IdentifiableMapItem] = []
    @AppStorage("defaultRadius") private var defaultRadius: Double = Alarm.defaultGeofenceRadius
    @AppStorage("isSoundEnabled") private var defaultSoundEnabled: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                ForEach(matchingItems) { item in
                    Marker(item.mapItem.name ?? "", coordinate: item.mapItem.placemark.coordinate)
                        .tint(item.id == matchingItems.first?.id ? AppDesign.tint : .gray)
                }
            }
            .frame(height: matchingItems.isEmpty ? 330 : 315)

            if matchingItems.isEmpty {
                emptyResults
            } else {
                resultList
            }
        }
        .tint(AppDesign.tint)
        .background(AppDesign.background.ignoresSafeArea())
        .navigationTitle("目的地を検索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "駅名・場所を検索")
        .onSubmit(of: .search) {
            performSearch(searchText: searchText)
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                matchingItems = []
                region = initialRegion
                cameraPosition = .region(initialRegion)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("キャンセル") {
                    dismiss()
                }
                .foregroundStyle(AppDesign.tint)
            }
        }
    }

    private var emptyResults: some View {
        ContentUnavailableView {
            Label("場所を検索", systemImage: "magnifyingglass")
        } description: {
            Text("駅名・場所を入力して目的地を選択します。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultList: some View {
        List {
            Section("検索結果") {
                ForEach(Array(matchingItems.prefix(3)), id: \.id) { item in
                    NavigationLink(destination: alarmDetail(for: item)) {
                        resultRow(item)
                    }
                }
            }

            Section {
                AdListClearance()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppDesign.background)
    }

    private func resultRow(_ item: IdentifiableMapItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.mapItem.name ?? "不明な場所")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.mapItem.placemark.title ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private func alarmDetail(for item: IdentifiableMapItem) -> AlarmDetailView {
        AlarmDetailView(
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
                radius: Alarm.normalizedRadius(defaultRadius) ?? Alarm.defaultGeofenceRadius
            )
        )
    }

    private func performSearch(searchText: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = region
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response else {
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
