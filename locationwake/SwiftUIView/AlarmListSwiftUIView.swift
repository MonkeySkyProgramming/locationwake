import CoreLocation
import MapKit
import SwiftUI
import UIKit

enum NavigationRoute: Hashable {
    case locationSelection
    case settings
}

enum AppSheetDestination: Identifiable {
    case alarmEditor(alarm: Alarm, isNew: Bool)
    case onboardingHelp

    var id: String {
        switch self {
        case .alarmEditor(let alarm, let isNew):
            return "alarm-editor-\(alarm.id)-\(isNew)"
        case .onboardingHelp:
            return "onboarding-help"
        }
    }
}

private enum AlarmListAccessibilityFocus: Hashable {
    case listHeading
    case retryButton
}

@MainActor
final class NavigationModel: ObservableObject {
    @Published var path: [NavigationRoute] = []
    @Published var presentedSheet: AppSheetDestination?

    func presentAlarmEditor(_ alarm: Alarm, isNew: Bool) {
        presentedSheet = .alarmEditor(alarm: alarm, isNew: isNew)
    }
}

struct AlarmListSwiftUIView: View {
    @StateObject private var viewModel = AlarmListViewModel()
    @StateObject private var navigationModel = NavigationModel()
    @StateObject private var activityCenter = AlarmActivityCenter.shared
    @StateObject private var permissionReadiness = PermissionReadiness.shared

    @AppStorage(AppLifecycleDefaultsKey.onboardingCompleted)
    private var hasSeenOnboarding = false

    @State private var showsFirstRunOnboarding = false
    @State private var showsReliabilityAlert = false
    @State private var showsAlarmLimitAlert = false
    @State private var pendingPostSaveReview = false
    @State private var postSaveRefreshCompleted = false
    @State private var pendingAuthorizationIssues: [PermissionReadinessIssue] = []
    @State private var reliabilityAlertIssues: [PermissionReadinessIssue] = []
    @AccessibilityFocusState private var accessibilityFocus: AlarmListAccessibilityFocus?

    var body: some View {
        ZStack {
            if !showsFirstRunOnboarding && activityCenter.activeAlarm == nil {
                BaseContainerView {
                    NavigationStack(path: $navigationModel.path) {
                        alarmList
                            .navigationDestination(for: NavigationRoute.self) { route in
                                switch route {
                                case .locationSelection:
                                    LocationSelectionView()
                                case .settings:
                                    SettingView()
                                }
                            }
                    }
                }
                .accessibilityHidden(navigationModel.presentedSheet != nil)
            } else {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            if let activeAlarm = activityCenter.activeAlarm {
                AlarmRingingView(activeAlarm: activeAlarm)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .environmentObject(viewModel)
        .environmentObject(navigationModel)
        .sheet(
            item: $navigationModel.presentedSheet,
            onDismiss: handlePresentedSheetDismissed
        ) { destination in
            Group {
                switch destination {
                case .alarmEditor(let alarm, let isNew):
                    NavigationStack {
                        AlarmDetailView(alarm: alarm, isNew: isNew)
                    }
                    .environmentObject(viewModel)
                    .environmentObject(navigationModel)
                case .onboardingHelp:
                    OnboardingView(presentationMode: .help)
                }
            }
        }
        .fullScreenCover(isPresented: $showsFirstRunOnboarding) {
            OnboardingView(presentationMode: .firstRun) {
                hasSeenOnboarding = true
                permissionReadiness.refresh()
                ATTAuthorizationCoordinator.shared.requestIfEligible()
            }
        }
        .alert(
            "到着通知の設定を確認してください",
            isPresented: $showsReliabilityAlert
        ) {
            Button("設定を確認") {
                navigationModel.path = [.settings]
                scheduleATTRequest()
            }
            Button("あとで", role: .cancel) {
                scheduleATTRequest()
            }
        } message: {
            Text(reliabilityAlertMessage)
        }
        .alert("アラームを追加できません", isPresented: $showsAlarmLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("アラームは最大\(Alarm.maximumSavedAlarms)件です。不要なアラームを削除してから、もう一度お試しください。")
        }
        .onAppear(perform: handleInitialAppearance)
        .onReceive(NotificationCenter.default.publisher(for: .alarmUpdated)) { _ in
            viewModel.loadAlarms()
        }
        .onReceive(NotificationCenter.default.publisher(for: .alarmSaved)) { _ in
            handleAlarmSaved()
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationAuthorizationDidChange)) { _ in
            permissionReadiness.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            permissionReadiness.refresh()
            AlarmActivityCenter.shared.presentCurrentAlarmIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboardingHelp)) { _ in
            guard activityCenter.activeAlarm == nil else { return }
            navigationModel.presentedSheet = .onboardingHelp
        }
        .onChange(of: navigationModel.path) { _, newPath in
            guard newPath.isEmpty else { return }
            viewModel.loadAlarms()
        }
        .onChange(of: activityCenter.activeAlarm) { previousAlarm, activeAlarm in
            if activeAlarm != nil {
                prepareForRingingAlarmPresentation()
            } else if previousAlarm != nil {
                restoreFocusAfterStoppingAlarm()
            }
        }
        .onChange(of: viewModel.loadState) { _, loadState in
            guard case .failed = loadState,
                  activityCenter.activeAlarm == nil else {
                return
            }
            DispatchQueue.main.async {
                accessibilityFocus = .retryButton
            }
        }
    }

    private var alarmList: some View {
        List {
            Section {
                Text("目的地に近づいたら、通知・音・バイブレーションでお知らせします。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } header: {
                Text("アラーム一覧")
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(
                        $accessibilityFocus,
                        equals: .listHeading
                    )
            }

            if hasAuthorizationIssue {
                Section {
                    Button {
                        navigationModel.path.append(.settings)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("到着通知に必要な設定があります")
                                    .foregroundStyle(.primary)
                                Text(authorizationIssueSummary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .accessibilityHint("設定画面を開きます")
                }
            }

            if !viewModel.canAddAlarm {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("アラームを追加できません")
                            Text("最大\(Alarm.maximumSavedAlarms)件です。追加するには、不要なアラームを削除してください。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            alarmContent

            if viewModel.loadState == .loaded && !viewModel.alarms.isEmpty {
                Section("アラームを追加") {
                    Button(action: openNewAlarmFlow) {
                        Label("目的地を追加", systemImage: "plus.circle.fill")
                            .foregroundStyle(AppDesign.tint)
                    }
                    .disabled(!viewModel.canAddAlarm)
                    .accessibilityIdentifier("home.addDestination")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppDesign.background)
        .navigationTitle("アラーム")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    navigationModel.path.append(.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("設定")
                .accessibilityIdentifier("home.settings")
            }
        }
    }

    @ViewBuilder
    private var alarmContent: some View {
        switch viewModel.loadState {
        case .loading:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("アラームを読み込んでいます")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        case .failed(let message):
            Section {
                ContentUnavailableView {
                    Label("読み込めませんでした", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("もう一度試す", action: viewModel.loadAlarms)
                        .buttonStyle(.borderedProminent)
                        .tint(AppDesign.prominentButtonTint)
                        .accessibilityFocused(
                            $accessibilityFocus,
                            equals: .retryButton
                        )
                }
                .frame(maxWidth: .infinity, minHeight: 260)
                .listRowBackground(Color.clear)
            }
        case .loaded:
            if viewModel.alarms.isEmpty {
                Section {
                    VStack(spacing: 18) {
                        Image(systemName: "bell.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("アラームはまだありません")
                            .font(.title3.bold())
                        Text("目的地を追加すると、到着したときにお知らせします。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(action: openNewAlarmFlow) {
                            Label("目的地を追加", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(AppDesign.prominentButtonTint)
                        .accessibilityIdentifier("home.addDestination")
                    }
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, minHeight: 330)
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: 20,
                        bottom: 0,
                        trailing: 20
                    ))
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(viewModel.alarms) { alarm in
                        AlarmListRow(
                            alarm: alarm,
                            isEnabled: Binding(
                                get: {
                                    viewModel.alarms
                                        .first(where: { $0.id == alarm.id })?
                                        .isAlarmEnabled ?? alarm.isAlarmEnabled
                                },
                                set: { enabled in
                                    viewModel.setAlarmEnabled(
                                        id: alarm.id,
                                        enabled: enabled
                                    )
                                }
                            ),
                            onOpen: {
                                navigationModel.presentAlarmEditor(
                                    alarm,
                                    isNew: false
                                )
                            },
                            onDelete: {
                                viewModel.deleteAlarm(id: alarm.id)
                            }
                        )
                    }
                } header: {
                    Text("保存済みアラーム")
                } footer: {
                    Text("アラームは、目的地の範囲外に出てから再び入ると通知します。")
                }
            }
        }
    }

    private var hasAuthorizationIssue: Bool {
        !permissionReadiness.snapshot.authorizationIssues.isEmpty
    }

    private func openNewAlarmFlow() {
        guard viewModel.canAddAlarm else {
            showsAlarmLimitAlert = true
            return
        }
        navigationModel.path.append(.locationSelection)
    }

    private func handleInitialAppearance() {
        viewModel.loadAlarms()
        permissionReadiness.refresh()

        // 読み込みに失敗した時に空配列を正しい状態として監視へ渡すと、
        // 公開版から引き継いだ既存regionまで停止してしまう。保存データを
        // 正常に確認できた場合だけ、画面側のスナップショットを同期する。
        if !AppRuntime.shouldSuppressExternalSideEffects,
           viewModel.loadState == .loaded {
            LocationManager.shared.startMonitoring(alarms: viewModel.alarms)
        }

        if AppRuntime.shouldForceOnboarding {
            showsFirstRunOnboarding = true
        } else if AppRuntime.isUITesting {
            hasSeenOnboarding = true
        } else if !hasSeenOnboarding {
            showsFirstRunOnboarding = true
        }

        if AppRuntime.shouldSimulateActiveAlarm {
            let simulatedAlarm = Alarm(
                id: "ui-test-active-alarm",
                name: "テスト目的地",
                sound: "modan",
                isAlarmEnabled: true,
                isSoundEnabled: false,
                isVibrationEnabled: false
            )
            _ = activityCenter.registerArrival(for: simulatedAlarm)
        }
        AlarmActivityCenter.shared.presentCurrentAlarmIfNeeded()
        if activityCenter.activeAlarm != nil {
            prepareForRingingAlarmPresentation()
        }
    }

    private func prepareForRingingAlarmPresentation() {
        // 鳴動画面を唯一のモーダル相当画面にする。既存のsheet・cover・alertを
        // 先に閉じ、背後の画面からアクセシビリティフォーカスを奪わない。
        accessibilityFocus = nil
        showsReliabilityAlert = false
        showsAlarmLimitAlert = false
        pendingPostSaveReview = false
        postSaveRefreshCompleted = false
        pendingAuthorizationIssues = []
        reliabilityAlertIssues = []
        navigationModel.presentedSheet = nil
        showsFirstRunOnboarding = false
        navigationModel.path = []
    }

    private func restoreFocusAfterStoppingAlarm() {
        // 停止アナウンスを読み終え、リストが再構築された後に移動する。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard activityCenter.activeAlarm == nil else { return }
            accessibilityFocus = .listHeading
        }
    }

    private func handleAlarmSaved() {
        guard activityCenter.activeAlarm == nil else { return }
        viewModel.loadAlarms()
        pendingPostSaveReview = true
        postSaveRefreshCompleted = false
        permissionReadiness.refresh {
            guard activityCenter.activeAlarm == nil else {
                pendingAuthorizationIssues = []
                postSaveRefreshCompleted = false
                return
            }
            pendingAuthorizationIssues = permissionReadiness.snapshot.authorizationIssues
            postSaveRefreshCompleted = true
            handlePresentedSheetDismissed()
        }
    }

    private func handlePresentedSheetDismissed() {
        guard activityCenter.activeAlarm == nil,
              pendingPostSaveReview,
              postSaveRefreshCompleted,
              navigationModel.presentedSheet == nil else {
            return
        }
        pendingPostSaveReview = false
        postSaveRefreshCompleted = false
        reliabilityAlertIssues = pendingAuthorizationIssues
        pendingAuthorizationIssues = []

        if reliabilityAlertIssues.isEmpty {
            scheduleATTRequest()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard activityCenter.activeAlarm == nil else { return }
                showsReliabilityAlert = true
            }
        }
    }

    private func scheduleATTRequest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard activityCenter.activeAlarm == nil else { return }
            ATTAuthorizationCoordinator.shared.requestIfEligible()
        }
    }

    private var authorizationIssueSummary: String {
        let issues = permissionReadiness.snapshot.authorizationIssues
        switch (
            issues.contains(.locationAlways),
            issues.contains(.notificationAuthorization)
        ) {
        case (true, true):
            return "位置情報を「常に許可」にし、通知を許可してください"
        case (true, false):
            return "位置情報を「常に許可」にしてください"
        case (false, true):
            return "通知を許可してください"
        case (false, false):
            return "設定を確認してください"
        }
    }

    private var reliabilityAlertMessage: String {
        let issueText: String
        switch (
            reliabilityAlertIssues.contains(.locationAlways),
            reliabilityAlertIssues.contains(.notificationAuthorization)
        ) {
        case (true, true):
            issueText = "位置情報を「常に許可」にし、通知を許可してください。"
        case (true, false):
            issueText = "位置情報を「常に許可」にしてください。"
        case (false, true):
            issueText = "通知を許可してください。"
        case (false, false):
            issueText = "位置情報と通知の設定を確認してください。"
        }
        return "アラームが作動しないことがあります。\(issueText)設定にかかわらず監視は開始します。"
    }
}

enum AlarmListLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class AlarmListViewModel: ObservableObject {
    @Published var alarms: [Alarm] = []
    @Published var loadState: AlarmListLoadState = .loading

    init() {
        loadAlarms()
    }

    var canAddAlarm: Bool {
        alarms.count < Alarm.maximumSavedAlarms
    }

    func loadAlarms() {
        loadState = .loading
        switch AlarmStore.loadResult() {
        case .success(let alarms):
            self.alarms = alarms
            loadState = .loaded
        case .failure(let error):
            alarms = []
            loadState = .failed(error.localizedDescription)
        }
    }

    func setAlarmEnabled(id: String, enabled: Bool) {
        guard case .success(var latestAlarms) = AlarmStore.loadResult() else {
            loadAlarms()
            return
        }
        guard let index = latestAlarms.firstIndex(where: { $0.id == id }) else {
            loadAlarms()
            return
        }
        guard latestAlarms[index].isAlarmEnabled != enabled else {
            alarms = latestAlarms
            return
        }

        if enabled {
            var alarm = latestAlarms[index]
            alarm.isAlarmEnabled = true
            latestAlarms[index] = LocationManager.preparedForInitialStateCheck(
                alarm,
                currentLocation: LocationManager.shared.locationManager.location
            )
        } else {
            latestAlarms[index].isAlarmEnabled = false
        }
        guard persist(latestAlarms) else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: enabled ? "アラームをオンにしました" : "アラームをオフにしました"
        )
    }

    @discardableResult
    private func persist(_ updatedAlarms: [Alarm]) -> Bool {
        let normalized = Alarm.normalizedForPersistence(updatedAlarms)
        switch AlarmStore.save(normalized) {
        case .success:
            alarms = normalized
            loadState = .loaded
        case .failure(let error):
            loadState = .failed(error.localizedDescription)
            UIAccessibility.post(
                notification: .announcement,
                argument: error.localizedDescription
            )
            return false
        }
        if !AppRuntime.shouldSuppressExternalSideEffects {
            LocationManager.shared.startMonitoring(alarms: alarms)
        }
        return true
    }

    func deleteAlarm(id: String) {
        guard case .success(var latestAlarms) = AlarmStore.loadResult() else {
            loadAlarms()
            return
        }
        guard let index = latestAlarms.firstIndex(where: { $0.id == id }) else {
            loadAlarms()
            return
        }
        let alarm = latestAlarms.remove(at: index)
        guard persist(latestAlarms) else { return }
        if !AppRuntime.shouldSuppressExternalSideEffects {
            LocationManager.shared.stopMonitoringForAlarm(alarm: alarm)
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(alarm.name)を削除しました"
        )
    }
}

private struct AlarmListRow: View {
    let alarm: Alarm
    @Binding var isEnabled: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsDeleteConfirmation = false

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    rowButton
                    HStack {
                        Toggle("\(alarm.name)を有効にする", isOn: $isEnabled)
                        Spacer(minLength: 8)
                        actionMenu
                    }
                }
            } else {
                HStack(spacing: 12) {
                    rowButton
                    VStack(spacing: 2) {
                        Toggle("アラームを有効にする", isOn: $isEnabled)
                            .labelsHidden()
                            .accessibilityLabel("\(alarm.name)を有効にする")
                            .accessibilityValue(isEnabled ? "オン" : "オフ")
                        actionMenu
                    }
                }
            }
        }
        .tint(AppDesign.tint)
        .padding(.vertical, 8)
        .confirmationDialog(
            "「\(alarm.name)」を削除しますか？",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive, action: onDelete)
            Button("キャンセル", role: .cancel) {}
        }
    }

    private var rowButton: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                if let location = alarm.location {
                    AlarmMapPreview(
                        location: location,
                        radius: alarm.geofenceRadius ?? Alarm.defaultGeofenceRadius
                    )
                    .frame(width: 96, height: 96)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(alarm.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(isEnabled ? detail : "オフ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .accessibilityLabel(alarm.name)
        .accessibilityValue(isEnabled ? detail : "オフ")
        .accessibilityHint("ダブルタップして設定を編集")
        .accessibilityIdentifier("home.alarm.\(alarm.id)")
    }

    private var actionMenu: some View {
        Menu {
            Button("設定を開く", systemImage: "slider.horizontal.3", action: onOpen)
            Button("アラームを削除", systemImage: "trash", role: .destructive) {
                showsDeleteConfirmation = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("\(alarm.name)の操作")
    }

    private var detail: String {
        let names = ["日", "月", "火", "水", "木", "金", "土"]
        let validDays = (alarm.repeatWeekdays ?? [])
            .filter { names.indices.contains($0) }
            .sorted()
        let repeatText = validDays.isEmpty
            ? "繰り返さない"
            : validDays.map { names[$0] }.joined(separator: "・")
        let soundText = alarm.isSoundEnabled ? "音あり" : "音なし"
        let vibrationText = alarm.isVibrationEnabled ? "、バイブあり" : ""
        return "半径 \(Int(alarm.geofenceRadius ?? Alarm.defaultGeofenceRadius)) m、\(repeatText)、\(soundText)\(vibrationText)"
    }
}

private struct AlarmMapPreview: View {
    let location: Location
    let radius: Double

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    var body: some View {
        Map(
            initialPosition: .region(MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: max(radius * 3.2, 900),
                longitudinalMeters: max(radius * 3.2, 900)
            )),
            interactionModes: []
        ) {
            MapCircle(center: coordinate, radius: radius)
                .foregroundStyle(AppDesign.tint.opacity(0.18))
                .stroke(AppDesign.tint, lineWidth: 2)
            Marker("目的地", coordinate: coordinate)
                .tint(AppDesign.tint)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct AlarmRingingView: View {
    let activeAlarm: ActiveAlarmPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isStopButtonFocused: Bool

    // 白文字とのWCAGコントラスト比は約7.5:1。
    private let stopButtonTint = Color(red: 0.66, green: 0.08, blue: 0.08)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 72)

                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.system(size: 82, weight: .regular))
                    .foregroundStyle(AppDesign.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                    .accessibilityHidden(true)

                Text("\(activeAlarm.name)に到着しました")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("停止ボタンを押すまで、アラームの再生状態は終了しません。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    if AlarmActivityCenter.shared.stop(
                        alarmID: activeAlarm.alarmID
                    ) {
                        UIAccessibility.post(
                            notification: .announcement,
                            argument: "アラームを停止しました"
                        )
                    }
                } label: {
                    Label("アラームを停止", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(stopButtonTint)
                .foregroundStyle(.white)
                .accessibilityIdentifier("alarm.stop")
                .accessibilityFocused($isStopButtonFocused)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
        .onAppear {
            DispatchQueue.main.async {
                isStopButtonFocused = true
            }
        }
    }
}

extension Notification.Name {
    static let showOnboardingHelp = Notification.Name("ShowHelpOverlay")
}
