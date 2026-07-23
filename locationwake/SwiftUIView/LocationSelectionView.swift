import SwiftUI
import CoreLocation
import MapKit

struct LocationSelectionView: View {
    private struct IdentifiableMapItem: Identifiable {
        let id = UUID()
        let mapItem: MKMapItem
    }

    private enum SearchState {
        case idle
        case loading(query: String)
        case results([IdentifiableMapItem])
        case empty(query: String)
        case failure(query: String, message: String)
    }

    @State private var searchText = ""
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.6873, longitude: 135.5262),
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
    )
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.6873, longitude: 135.5262),
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
    ))
    @State private var searchState: SearchState = .idle
    @State private var activeSearch: MKLocalSearch?
    @State private var searchGeneration = 0
    @State private var lastSubmittedQuery = ""
    @AppStorage("defaultRadius") private var defaultRadius: Double = Alarm.defaultGeofenceRadius
    @AppStorage("isSoundEnabled") private var defaultSoundEnabled: Bool = true
    @EnvironmentObject private var navigationModel: NavigationModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var resultItems: [IdentifiableMapItem] {
        guard case .results(let items) = searchState else { return [] }
        return items
    }

    private var mapHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 180
        }
        return resultItems.isEmpty ? 300 : 260
    }

    private var mapAccessibilityValue: String {
        switch searchState {
        case .idle:
            return "検索結果はありません"
        case .loading:
            return "検索中です"
        case .results(let items):
            return "検索結果を\(items.count)件表示しています"
        case .empty:
            return "検索結果は0件です"
        case .failure:
            return "検索に失敗しました"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                ForEach(resultItems) { item in
                    Marker(
                        item.mapItem.name ?? "名称不明",
                        coordinate: item.mapItem.placemark.coordinate
                    )
                    .tint(AppDesign.tint)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
            }
            .frame(height: mapHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("検索範囲の地図")
            .accessibilityValue(mapAccessibilityValue)
            .accessibilityHint("地図を移動すると、次に検索する範囲が変わります")
            .accessibilityIdentifier("locationSelection.map")

            searchContent
        }
        .tint(AppDesign.tint)
        .background(AppDesign.background.ignoresSafeArea())
        .navigationTitle("目的地を検索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "駅名・場所を検索"
        )
        .onSubmit(of: .search) {
            performSearch(searchText: searchText)
        }
        .onChange(of: searchText) { _, newValue in
            handleSearchTextChange(newValue)
        }
        .onDisappear {
            cancelActiveSearch()
        }
        .accessibilityIdentifier("locationSelection.screen")
    }

    @ViewBuilder
    private var searchContent: some View {
        switch searchState {
        case .idle:
            ContentUnavailableView {
                Label("場所を検索", systemImage: "magnifyingglass")
            } description: {
                Text("駅名・場所を入力して目的地を選択します。")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("locationSelection.idle")

        case .loading(let query):
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("「\(query)」を検索中")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("locationSelection.loading")

        case .results:
            resultList

        case .empty(let query):
            ContentUnavailableView {
                Label("場所が見つかりません", systemImage: "magnifyingglass")
            } description: {
                Text("「\(query)」に一致する場所はありません。検索語や地図の範囲を変えてください。")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("locationSelection.empty")

        case .failure(let query, let message):
            ContentUnavailableView {
                Label("検索できませんでした", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("もう一度検索") {
                    performSearch(searchText: query)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("同じ検索語でもう一度検索します")
                .accessibilityIdentifier("locationSelection.retry")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("locationSelection.error")
        }
    }

    private var resultList: some View {
        List {
            Section("検索結果") {
                ForEach(Array(resultItems.enumerated()), id: \.element.id) { index, item in
                    Button {
                        navigationModel.presentAlarmEditor(alarm(for: item), isNew: true)
                    } label: {
                        resultRow(item)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.mapItem.name ?? "名称不明")
                    .accessibilityValue(item.mapItem.placemark.title ?? "住所情報なし")
                    .accessibilityHint("新しいアラームの編集画面を開きます")
                    .accessibilityIdentifier("locationSelection.result.\(index)")
                }
            }

        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppDesign.background)
        .accessibilityIdentifier("locationSelection.results")
    }

    private func resultRow(_ item: IdentifiableMapItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)
                .frame(minHeight: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.mapItem.name ?? "名称不明")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.mapItem.placemark.title ?? "住所情報なし")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func alarm(for item: IdentifiableMapItem) -> Alarm {
        Alarm(
            name: item.mapItem.name ?? "",
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
    }

    private func handleSearchTextChange(_ text: String) {
        let query = normalizedQuery(text)
        guard !query.isEmpty else {
            cancelActiveSearch()
            lastSubmittedQuery = ""
            searchState = .idle
            return
        }

        if !lastSubmittedQuery.isEmpty, query != lastSubmittedQuery {
            cancelActiveSearch()
            lastSubmittedQuery = ""
            searchState = .idle
        }
    }

    private func performSearch(searchText: String) {
        let query = normalizedQuery(searchText)
        guard !query.isEmpty else {
            cancelActiveSearch()
            lastSubmittedQuery = ""
            searchState = .idle
            return
        }

        cancelActiveSearch()
        lastSubmittedQuery = query
        searchState = .loading(query: query)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region

        let search = MKLocalSearch(request: request)
        activeSearch = search
        let generation = searchGeneration

        search.start { response, error in
            DispatchQueue.main.async {
                guard generation == self.searchGeneration,
                      self.normalizedQuery(self.searchText) == query,
                      self.lastSubmittedQuery == query else {
                    return
                }

                self.activeSearch = nil

                guard let response else {
                    self.searchState = .failure(
                        query: query,
                        message: error?.localizedDescription ?? "通信環境を確認して、もう一度お試しください。"
                    )
                    return
                }

                let items = response.mapItems.map(IdentifiableMapItem.init(mapItem:))
                guard !items.isEmpty else {
                    self.searchState = .empty(query: query)
                    return
                }

                self.searchState = .results(items)
                let resultRegion = self.region(containing: items)
                self.region = resultRegion
                self.cameraPosition = .region(resultRegion)
            }
        }
    }

    private func cancelActiveSearch() {
        activeSearch?.cancel()
        activeSearch = nil
        searchGeneration &+= 1
    }

    private func normalizedQuery(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func region(containing items: [IdentifiableMapItem]) -> MKCoordinateRegion {
        let coordinates = items.map(\.mapItem.placemark.coordinate)
        guard let first = coordinates.first else { return region }
        guard coordinates.count > 1 else {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minimumLatitude = latitudes.min(),
              let maximumLatitude = latitudes.max(),
              let minimumLongitude = longitudes.min(),
              let maximumLongitude = longitudes.max() else {
            return region
        }

        let latitudeDelta = max((maximumLatitude - minimumLatitude) * 1.35, 0.01)
        let longitudeDelta = max((maximumLongitude - minimumLongitude) * 1.35, 0.01)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }
}
