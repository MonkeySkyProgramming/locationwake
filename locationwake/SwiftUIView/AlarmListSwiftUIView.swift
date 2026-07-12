//
//  AlarmListSwiftUIView.swift
//  locationwake
//
//  Created by 井上晴斗 on 2025/06/17.
//

import SwiftUI
import CoreLocation
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
    @State private var hasSettingsIssue = false
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @StateObject private var navigationModel = NavigationModel()

    var body: some View {
        BaseContainerView {
            NavigationStack(path: $navigationModel.path) {
                VStack(spacing: 0) {
                    AppNavigationHeader(title: "アラーム一覧") {
                        if viewModel.canAddAlarm {
                            AppIconButton(systemName: "plus") {
                                navigationModel.path.append(.locationSelection)
                            }
                        }
                    }
                    .overlay(alignment: .leading) {
                        AppIconButton(systemName: "gear") {
                            navigationModel.path.append(.settings)
                        }
                    }

                    if hasSettingsIssue {
                        Button {
                            navigationModel.path.append(.settings)
                        } label: {
                            Label("到着通知に必要な設定を確認してください", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                        }
                    }

                    List {
                        if !viewModel.canAddAlarm {
                            Text("アラームは最大\(Alarm.maximumSavedAlarms)件まで登録できます。不要なアラームを削除してください。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        ForEach(viewModel.alarms, id: \.id) { alarm in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(alarm.name)
                                        .font(.headline)
                                    let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
                                    let repeatText = (alarm.repeatWeekdays?.isEmpty ?? true) ? "" : "（" + alarm.repeatWeekdays!.sorted().map { weekdays[$0] }.joined(separator: "・") + "）"
                                    let vibrationText = alarm.isVibrationEnabled ? "・バイブレーション" : ""
                                    let soundText = alarm.isSoundEnabled ? "・\(alarm.sound)" : ""
                                    Text((alarm.isAlarmEnabled ? "有効" : "無効") + soundText + vibrationText  + repeatText)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { alarm.isAlarmEnabled },
                                    set: { newValue in
                                        if let index = viewModel.alarms.firstIndex(where: { $0.id == alarm.id }) {
                                            viewModel.alarms[index].isAlarmEnabled = newValue
                                            viewModel.saveAlarms()
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if alarm.location != nil {
                                    navigationModel.path.append(.alarmDetail(alarm: alarm))
                                }
                            }
                        }
                        .onDelete(perform: viewModel.deleteAlarm)
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
            .toolbar(.hidden, for: .navigationBar)
            .environmentObject(viewModel)
            .environmentObject(navigationModel)
            .sheet(isPresented: $showHelp) {
                OnboardingView()
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
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowHelpOverlay"))) { _ in
                showHelp = true
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
        // データが読み込めなかった・空だった場合はサンプルアラームを追加
        if self.alarms.isEmpty {
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
            self.alarms = [sampleAlarm]
            print("📦 アラームが空のためサンプルアラームを追加")
            saveAlarms()
        }
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

    @objc private func handleAlarmUpdated() {
        DispatchQueue.main.async {
            self.loadAlarms()
        }
    }
}
