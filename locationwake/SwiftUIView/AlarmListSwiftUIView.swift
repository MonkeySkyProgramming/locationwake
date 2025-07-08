//
//  AlarmListSwiftUIView.swift
//  locationwake
//
//  Created by 井上晴斗 on 2025/06/17.
//

import SwiftUI
import CoreLocation

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
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var showAddAlarm = false
    @State private var selectedAlarm: Alarm?
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @State private var navigationTrigger = false
    @StateObject private var navigationModel = NavigationModel()

    var body: some View {
        BaseContainerView {
            NavigationStack(path: $navigationModel.path) {
                List {
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
                .navigationTitle("アラーム一覧")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            navigationModel.path.append(.settings)
                        }) {
                            Image(systemName: "gear")
                                .foregroundColor(Color("NavBarTintColor"))
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            navigationModel.path.append(.locationSelection)
                        }) {
                            Image(systemName: "plus")
                                .foregroundColor(Color("NavBarTintColor"))
                        }
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
            .toolbarBackground(Color("NavBarColor"), for: .navigationBar)
            .toolbar(.visible, for: .navigationBar)
            .environmentObject(viewModel)
            .environmentObject(navigationModel)
            .sheet(isPresented: $showHelp) {
                OnboardingView()
            }
            .onAppear {
                viewModel.loadAlarms()
                print("🔁 アラームリスト再読み込み onAppear")

                print("🧭 startMonitoringに渡すアラーム: \(viewModel.alarms.map { "\($0.name): \($0.isAlarmEnabled)" })")
                LocationManager.shared.startMonitoring(alarms: viewModel.alarms)

                if !hasSeenOnboarding {
                    showHelp = true
                    hasSeenOnboarding = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowHelpOverlay"))) { _ in
                showHelp = true
            }
            .onChange(of: navigationModel.path) { newPath in
                if newPath.isEmpty {
                    print("他の画面から戻ったため再読み込み")
                    viewModel.loadAlarms()
                    LocationManager.shared.startMonitoring(alarms: viewModel.alarms)
                }
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

    func loadAlarms() {
        if let savedAlarms = UserDefaults.standard.object(forKey: "SavedAlarms") as? Data {
            let decoder = JSONDecoder()
            if let loadedAlarms = try? decoder.decode([Alarm].self, from: savedAlarms) {
                // Backward compatibility: patch missing properties
                self.alarms = loadedAlarms.map { alarm in
                    var patchedAlarm = alarm
                    if patchedAlarm.repeatWeekdays == nil {
                        patchedAlarm.repeatWeekdays = []
                    }
                    if patchedAlarm.hasTriggered == nil {
                        patchedAlarm.hasTriggered = false
                    }
                    if patchedAlarm.hasTriggeredUntilExit == nil {
                        patchedAlarm.hasTriggeredUntilExit = false
                    }
                    if patchedAlarm.id == nil {
                        patchedAlarm.id = UUID().uuidString
                    }
                    return patchedAlarm
                }
                print("✅ 読み込み成功: \(alarms.map { $0.name })")
            }
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
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(alarms) {
            UserDefaults.standard.set(encoded, forKey: "SavedAlarms")
            print("💾 アラーム保存: \(alarms.map { $0.name })")
        }
        LocationManager.shared.startMonitoring(alarms: alarms)
    }

    func deleteAlarm(at offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
        saveAlarms()
        LocationManager.shared.startMonitoring(alarms: alarms)
    }

    @objc private func handleAlarmUpdated() {
        DispatchQueue.main.async {
            self.loadAlarms()
        }
    }
}

// Wrapper to present UIKit ViewControllers from Storyboard in SwiftUI
struct StoryboardViewControllerWrapper: UIViewControllerRepresentable {
    let storyboardName: String
    let viewControllerIdentifier: String
    var alarm: Alarm? = nil

    func makeUIViewController(context: Context) -> UIViewController {
        let storyboard = UIStoryboard(name: storyboardName, bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: viewControllerIdentifier)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No update logic needed
    }
}
