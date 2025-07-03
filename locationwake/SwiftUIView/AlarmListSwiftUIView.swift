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
            hasher.combine(alarm.name)
            hasher.combine(alarm.location?.latitude ?? 0)
            hasher.combine(alarm.location?.longitude ?? 0)
        case .settings:
            hasher.combine("settings")
        }
    }

    static func == (lhs: NavigationRoute, rhs: NavigationRoute) -> Bool {
        switch (lhs, rhs) {
        case (.locationSelection, .locationSelection):
            return true
        case (.alarmDetail(let a1), .alarmDetail(let a2)):
            return a1.name == a2.name &&
                   a1.location?.latitude == a2.location?.latitude &&
                   a1.location?.longitude == a2.location?.longitude
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
                    ForEach(viewModel.alarms.indices, id: \.self) { index in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(viewModel.alarms[index].name)
                                    .font(.headline)
                                let alarm = viewModel.alarms[index]
                                let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
                                let repeatText = (alarm.repeatWeekdays?.isEmpty ?? true) ? "" : "（" + alarm.repeatWeekdays!.sorted().map { weekdays[$0] }.joined(separator: "・") + "）"
                                let vibrationText = alarm.isVibrationEnabled ? "・バイブレーション" : ""
                                let soundText = alarm.isSoundEnabled ? "・\(alarm.sound)" : ""
                                Text((alarm.isAlarmEnabled ? "有効" : "無効") + soundText + vibrationText  + repeatText)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Toggle("", isOn: $viewModel.alarms[index].isAlarmEnabled)
                                .labelsHidden()
                                .onChange(of: viewModel.alarms[index].isAlarmEnabled) { _ in
                                    viewModel.saveAlarms()
                                }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let alarm = viewModel.alarms[index]
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
                StoryboardViewControllerWrapper(storyboardName: "Main", viewControllerIdentifier: "OnboardingViewController")
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
                self.alarms = loadedAlarms
                print("✅ 読み込み成功: \(loadedAlarms.map { $0.name })")
            }
        }
        // データが読み込めなかった・空だった場合はサンプルアラームを追加
        if self.alarms.isEmpty {
            let sampleAlarm = Alarm(
                name: "サンプルアラーム",
                repeatWeekdays: [],
                sound: "modan",
                isAlarmEnabled: false,
                isSoundEnabled: true,
                isVibrationEnabled: false,
                location: Location(latitude: 34.702485, longitude: 135.495951),
                radius: 300.0
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

        if let alarmDetailVC = vc as? AlarmDetailViewController, let alarm = alarm {
            alarmDetailVC.alarm = alarm
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No update logic needed
    }
}
