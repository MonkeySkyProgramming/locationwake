//
//  AlarmListSwiftUIView.swift
//  locationwake
//
//  Created by 井上晴斗 on 2025/06/17.
//

import SwiftUI


struct AlarmListSwiftUIView: View {
    @ObservedObject var viewModel = AlarmListViewModel()
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var showAddAlarm = false
    @State private var selectedAlarm: Alarm?
    @State private var showDetail = false
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @State private var navigationTrigger = false

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.alarms.indices, id: \.self) { index in
                    Button(action: {
                        selectedAlarm = viewModel.alarms[index]
                        showDetail = true
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(viewModel.alarms[index].name)
                                    .font(.headline)
                                let alarm = viewModel.alarms[index]
                                let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
                                let repeatText = (alarm.repeatWeekdays?.isEmpty ?? true) ? "" : "（" + alarm.repeatWeekdays!.sorted().map { weekdays[$0] }.joined(separator: "・") + "）"
                                Text((alarm.isAlarmEnabled ? "有効" : "無効") + repeatText)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.alarms[index].isAlarmEnabled)
                                .labelsHidden()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .onDelete(perform: viewModel.deleteAlarm)
            }
            .navigationTitle("アラーム一覧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: LocationSelectionView()) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            StoryboardViewControllerWrapper(storyboardName: "Main", viewControllerIdentifier: "SettingViewController")
        }
        .sheet(isPresented: $showHelp) {
            StoryboardViewControllerWrapper(storyboardName: "Main", viewControllerIdentifier: "OnboardingViewController")
        }
        .sheet(isPresented: $showDetail) {
            StoryboardViewControllerWrapper(storyboardName: "Main", viewControllerIdentifier: "AlarmDetailViewController", alarm: selectedAlarm)
        }
        .onAppear {
            if !hasSeenOnboarding {
                showHelp = true
                hasSeenOnboarding = true
            }
        }
        .overlay(
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        showHelp = true
                    }) {
                        Image(systemName: "questionmark.circle")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundColor(.blue)
                            .padding()
                    }
                }
            }
        )
    }
}

class AlarmListViewModel: ObservableObject {
    @Published var alarms: [Alarm] = []

    init() {
        loadAlarms()
    }

    func loadAlarms() {
        if let savedAlarms = UserDefaults.standard.object(forKey: "SavedAlarms") as? Data {
            let decoder = JSONDecoder()
            if let loadedAlarms = try? decoder.decode([Alarm].self, from: savedAlarms) {
                self.alarms = loadedAlarms
            }
        }
    }

    func saveAlarms() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(alarms) {
            UserDefaults.standard.set(encoded, forKey: "SavedAlarms")
        }
    }

    func deleteAlarm(at offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
        saveAlarms()
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
