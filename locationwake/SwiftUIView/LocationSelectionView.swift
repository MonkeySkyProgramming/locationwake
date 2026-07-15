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
            if matchingItems.isEmpty {
                AppNavigationHeader(title: "目的地を検索", showsBackButton: true) {
                    dismiss()
                }
            } else {
                searchResultsHeader
            }

            searchField

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
        .navigationBarBackButtonHidden(true)
    }

    private var searchResultsHeader: some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .semibold))
                    Text("アラーム")
                        .font(.system(size: 17))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppDesign.tint)
            .frame(width: 102, height: 52, alignment: .leading)

            Text("起きなはれ")
                .font(.system(size: 20, weight: .bold))
                .frame(maxWidth: .infinity)

            Button("キャンセル") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 17))
            .foregroundStyle(AppDesign.tint)
            .frame(width: 102, height: 52, alignment: .trailing)
        }
        .frame(height: 58)
        .padding(.horizontal, 12)
        .background(AppDesign.background)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField("駅名・場所を検索", text: $searchText)
                .font(.system(size: 17))
                .submitLabel(.search)
                .onSubmit {
                    performSearch(searchText: searchText)
                }
            if searchText.isEmpty {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    searchText = ""
                    matchingItems = []
                    region = initialRegion
                    cameraPosition = .region(initialRegion)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var emptyResults: some View {
        VStack(spacing: 16) {
            Text("検索結果")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 12)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("場所を検索して目的地を選択")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var resultList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("検索結果")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                AppCard {
                    VStack(spacing: 0) {
                        ForEach(Array(matchingItems.prefix(3).enumerated()), id: \.element.id) { index, item in
                            NavigationLink(destination: alarmDetail(for: item)) {
                                resultRow(item)
                            }
                            .buttonStyle(.plain)

                            if index < min(matchingItems.count, 3) - 1 {
                                Divider().padding(.leading, 72)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                AdScrollClearance()
            }
        }
    }

    private func resultRow(_ item: IdentifiableMapItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "mappin")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
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
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 66)
        .contentShape(Rectangle())
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
