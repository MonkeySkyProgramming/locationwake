//
//  AlarmListSwiftUIView.swift
//  locationwake
//
//  Created by 井上晴斗 on 2025/06/17.
//

import SwiftUI
import CoreLocation
import MapKit
import UserNotifications

struct CoordinateWrapper: Hashable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum NavigationRoute: Hashable {
    case locationSelection
    case alarmDetail(alarm: Alarm)
    case settings

    func hash(into hasher: inout Hasher) {
        switch self {
        case .locationSelection:
            hasher.combine("locationSelection")
        case .alarmDetail(let alarm):
            hasher.combine(alarm.id)
        case .settings:
            hasher.combine("settings")
        }
    }

    static func == (lhs: NavigationRoute, rhs: NavigationRoute) -> Bool {
        switch (lhs, rhs) {
        case (.locationSelection, .locationSelection):
            return true
        case (.alarmDetail(let a1), .alarmDetail(let a2)):
            return a1.id == a2.id
        case (.settings, .settings):
            return true
        default:
            return false
        }
    }
}

// NavigationModel to be shared across views for navigation state
class NavigationModel: ObservableObject {
    @Published var path: [NavigationRoute] = []
}

struct AlarmListSwiftUIView: View {
    @ObservedObject var viewModel = AlarmListViewModel()
    @State private var showHelp = false
    @State private var showAlarmStoppedScreen = false
    @State private var hasSettingsIssue = false
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @StateObject private var navigationModel = NavigationModel()

    var body: some View {
        BaseContainerView {
            NavigationStack(path: $navigationModel.path) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("目的地に近づいたら、アラームでお知らせします。")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .lineSpacing(5)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 34)

                        if hasSettingsIssue {
                            Button {
                                navigationModel.path.append(.settings)
                            } label: {
                                Label("到着通知に必要な設定を確認してください", systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }

                        if !viewModel.canAddAlarm {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("アラームを追加できません")
                                        .font(.subheadline.weight(.semibold))
                                    Text("最大\(Alarm.maximumSavedAlarms)件に達しています。追加するには、不要なアラームを削除してください。")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                                Text("\(viewModel.alarms.count)/\(Alarm.maximumSavedAlarms)")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                        }

                            AppSectionTitle(title: "有効なアラーム")
                                .padding(.bottom, 8)

                        if viewModel.alarms.isEmpty {
                            ContentUnavailableView {
                                Label("アラームはまだありません", systemImage: "bell.slash")
                            } description: {
                                Text("目的地を追加すると、近づいたときにお知らせします。")
                            } actions: {
                                Button("目的地を追加", systemImage: "plus.circle.fill") {
                                    navigationModel.path.append(.locationSelection)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppDesign.tint)

                                Button("サンプルを追加") {
                                    viewModel.createSampleAlarm()
                                }
                                .buttonStyle(.borderless)
                            }
                                .frame(maxWidth: .infinity, minHeight: 260)
                        } else {
                            AppCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(viewModel.alarms.enumerated()), id: \.element.id) { index, alarm in
                                        AlarmListRow(
                                            alarm: alarm,
                                            showsMap: true,
                                            isEnabled: Binding(
                                                get: { alarm.isAlarmEnabled },
                                                set: { newValue in
                                                    if let index = viewModel.alarms.firstIndex(where: { $0.id == alarm.id }) {
                                                        viewModel.alarms[index].setEnabled(newValue)
                                                        viewModel.saveAlarms()
                                                    }
                                                }
                                            ),
                                            onOpen: {
                                                if alarm.location != nil {
                                                    navigationModel.path.append(.alarmDetail(alarm: alarm))
                                                }
                                            },
                                            onDelete: {
                                                viewModel.deleteAlarm(id: alarm.id)
                                            }
                                        )
                                        if index < viewModel.alarms.count - 1 {
                                            Divider().padding(.leading, 126)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                            AppSectionTitle(title: "アラームを追加")
                                .padding(.top, 24)
                                .padding(.bottom, 8)

                            AppCard {
                                Button {
                                    navigationModel.path.append(.locationSelection)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 28))
                                        Text("目的地を追加")
                                            .font(.system(size: 18, weight: .semibold))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                    .foregroundStyle(AppDesign.tint)
                                    .padding(.horizontal, 14)
                                    .frame(height: 58)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)

                            AdScrollClearance()
                    }
                }
                .background(AppDesign.background)
                .navigationTitle("アラーム")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            navigationModel.path.append(.settings)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .foregroundStyle(AppDesign.tint)
                        .accessibilityLabel("設定")
                    }
                }
                .navigationDestination(for: NavigationRoute.self) { route in
                    switch route {
                    case .locationSelection:
                        LocationSelectionView()
                    case .alarmDetail(let alarm):
                        AlarmDetailView(alarm: alarm)
                            .environmentObject(viewModel)
                    case .settings:
                        SettingView()
                    }
                }
            }
            .environmentObject(viewModel)
            .environmentObject(navigationModel)
            .sheet(isPresented: $showHelp) {
                OnboardingView()
            }
            .sheet(isPresented: $showAlarmStoppedScreen) {
                AlarmStoppedView()
            }
            .onAppear {
                viewModel.loadAlarms()
                refreshSettingsIssue()
                print("🔁 アラームリスト再読み込み onAppear")

                print("🧭 startMonitoringに渡すアラーム: \(viewModel.alarms.map { "\($0.name): \($0.isAlarmEnabled)" })")
                if !AppRuntime.shouldSuppressExternalSideEffects {
                    LocationManager.shared.startMonitoring(alarms: viewModel.alarms)
                }

                if AppRuntime.isUITesting {
                    hasSeenOnboarding = true
                } else if !hasSeenOnboarding {
                    showHelp = true
                    hasSeenOnboarding = true
                }

                presentAlarmStoppedScreenIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowHelpOverlay"))) { _ in
                showHelp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .alarmStopRequested)) { _ in
                presentAlarmStoppedScreenIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                refreshSettingsIssue()
            }
            .onChange(of: navigationModel.path) { _, newPath in
                if newPath.isEmpty {
                    print("他の画面から戻ったため再読み込み")
                    viewModel.loadAlarms()
                    if !AppRuntime.shouldSuppressExternalSideEffects {
                        LocationManager.shared.startMonitoring(alarms: viewModel.alarms)
                    }
                }
            }
        }
    }

    private func refreshSettingsIssue() {
        let locationNeedsAttention = CLLocationManager().authorizationStatus != .authorizedAlways
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let notificationIsAllowed: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                notificationIsAllowed = true
            default:
                notificationIsAllowed = false
            }
            DispatchQueue.main.async {
                hasSettingsIssue = locationNeedsAttention || !notificationIsAllowed
            }
        }
    }

    private func presentAlarmStoppedScreenIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "ShouldShowAlarmStoppedScreen") else { return }
        UserDefaults.standard.set(false, forKey: "ShouldShowAlarmStoppedScreen")
        showAlarmStoppedScreen = true
    }
}

private struct AlarmStoppedView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppDesign.tint)
                .accessibilityHidden(true)

            Text("アラームを停止しました")
                .font(.title.bold())

            Text("アプリを起動したため、アラーム音とバイブレーションを停止しました。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("閉じる") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppDesign.tint)
        }
        .padding(32)
        .presentationDetents([.medium])
    }
}

class AlarmListViewModel: ObservableObject {
    @Published var alarms: [Alarm] = []

    init() {
        loadAlarms()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAlarmUpdated), name: Notification.Name("AlarmUpdated"), object: nil)
    }

    var canAddAlarm: Bool {
        alarms.count < Alarm.maximumSavedAlarms
    }

    func loadAlarms() {
        let loadedAlarms = AlarmStore.load()
        if !loadedAlarms.isEmpty {
            self.alarms = loadedAlarms
            print("✅ 読み込み成功: \(alarms.map { $0.name })")
        }
        if loadedAlarms.isEmpty {
            self.alarms = []
        }
    }

    func createSampleAlarm() {
        let sampleAlarm = Alarm(
            id: UUID().uuidString,
            name: "サンプルアラーム",
            repeatWeekdays: [],
            sound: "modan",
            isAlarmEnabled: false,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            location: Location(latitude: 34.702485, longitude: 135.495951),
            radius: 300.0,
            hasTriggered: false,
            hasTriggeredUntilExit: false
        )
        alarms = [sampleAlarm]
        saveAlarms()
    }

    func saveAlarms() {
        alarms = Alarm.normalizedForPersistence(alarms)
        AlarmStore.save(alarms)
        print("💾 アラーム保存: \(alarms.map { $0.name })")
        if !AppRuntime.shouldSuppressExternalSideEffects {
            LocationManager.shared.startMonitoring(alarms: alarms)
        }
    }

    func deleteAlarm(at offsets: IndexSet) {
        let deletedAlarms = offsets.map { alarms[$0] }
        alarms.remove(atOffsets: offsets)
        if !AppRuntime.shouldSuppressExternalSideEffects {
            deletedAlarms.forEach { LocationManager.shared.stopMonitoringForAlarm(alarm: $0) }
        }
        saveAlarms()
    }

    func deleteAlarm(id: String) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        let deletedAlarm = alarms.remove(at: index)
        if !AppRuntime.shouldSuppressExternalSideEffects {
            LocationManager.shared.stopMonitoringForAlarm(alarm: deletedAlarm)
        }
        saveAlarms()
    }

    @objc private func handleAlarmUpdated() {
        DispatchQueue.main.async {
            self.loadAlarms()
        }
    }
}

private struct AlarmListRow: View {
    let alarm: Alarm
    let showsMap: Bool
    @Binding var isEnabled: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var showsDeleteConfirmation = false

    private var detail: String {
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        let repeatText = (alarm.repeatWeekdays?.isEmpty ?? true) ? "繰り返さない" : alarm.repeatWeekdays!.sorted().map { weekdays[$0] }.joined(separator: "・")
        let soundText = alarm.isSoundEnabled ? "音" : "無音"
        let vibrationText = alarm.isVibrationEnabled ? "とバイブ" : ""
        return "半径 \(Int(alarm.geofenceRadius ?? Alarm.defaultGeofenceRadius)) m・\(repeatText)・\(soundText)\(vibrationText)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    if showsMap, let location = alarm.location {
                        AlarmMapPreview(location: location, radius: alarm.geofenceRadius ?? Alarm.defaultGeofenceRadius)
                            .frame(width: 112, height: 112)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                            .frame(width: 56, height: 56)
                            .overlay {
                                Image(systemName: "mappin")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(alarm.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(alarm.isAlarmEnabled ? detail : "オフ")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel("\(alarm.name)の設定を開く")

            Toggle("\(alarm.name)を有効にする", isOn: $isEnabled)
                .labelsHidden()
                .tint(AppDesign.tint)
            Menu {
                Button("設定を開く", systemImage: "slider.horizontal.3", action: onOpen)
                Button("アラームを削除", systemImage: "trash", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 44)
            }
            .accessibilityLabel("\(alarm.name)の操作")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: showsMap ? 130 : 82)
        .contentShape(Rectangle())
        .confirmationDialog(
            "「\(alarm.name)」を削除しますか？",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive, action: onDelete)
            Button("キャンセル", role: .cancel) {}
        }
    }
}

private struct AlarmMapPreview: View {
    let location: Location
    let radius: Double

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: max(radius * 3.2, 900),
            longitudinalMeters: max(radius * 3.2, 900)
        )), interactionModes: []) {
            MapCircle(center: coordinate, radius: radius)
                .foregroundStyle(AppDesign.tint.opacity(0.18))
                .stroke(AppDesign.tint, lineWidth: 2)
            Marker(alarmLabel, coordinate: coordinate)
                .tint(AppDesign.tint)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private var alarmLabel: String { "目的地" }
}
