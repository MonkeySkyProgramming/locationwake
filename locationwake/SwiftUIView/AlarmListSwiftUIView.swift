import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct AlarmEditorRoute: Hashable {
    let alarm: Alarm
    let isNew: Bool

    static func == (lhs: AlarmEditorRoute, rhs: AlarmEditorRoute) -> Bool {
        lhs.alarm.id == rhs.alarm.id && lhs.isNew == rhs.isNew
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(alarm.id)
        hasher.combine(isNew)
    }
}

enum NavigationRoute: Hashable {
    case locationSelection
    case settings
    case alarmEditor(AlarmEditorRoute)
}

enum AppSheetDestination: Identifiable {
    case onboardingHelp

    var id: String {
        switch self {
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
        path.append(.alarmEditor(AlarmEditorRoute(alarm: alarm, isNew: isNew)))
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
    @State private var undoableDeletion: AlarmListViewModel.Deletion?
    @State private var undoDismissalToken = UUID()
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
                                case .alarmEditor(let editor):
                                    AlarmDetailView(
                                        alarm: editor.alarm,
                                        isNew: editor.isNew
                                    )
                                        .environmentObject(viewModel)
                                        .environmentObject(navigationModel)
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
                returnToHome()
                scheduleATTRequest()
            }
        } message: {
            Text(reliabilityAlertMessage)
        }
        .alert("アラームを追加できません", isPresented: $showsAlarmLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(AppStrings.format(
                "アラームは最大%lld件です。不要なアラームを削除してから、もう一度お試しください。",
                Alarm.maximumSavedAlarms
            ))
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
        .overlay(alignment: .bottom) {
            if let undoableDeletion {
                AlarmDeletionUndoBanner(
                    alarmName: undoableDeletion.alarm.name,
                    onUndo: undoAlarmDeletion
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("到着通知に必要な設定があります")
                                    .foregroundStyle(.primary)
                                Text(authorizationIssueSummary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityHint("必要な設定を確認します")
                }
            }

            if !viewModel.canAddAlarm {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("アラームを追加できません")
                            Text(AppStrings.format(
                                "最大%lld件です。追加するには、不要なアラームを削除してください。",
                                Alarm.maximumSavedAlarms
                            ))
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

            if viewModel.loadState == .loaded {
                Section {
                    // 最後の操作を広告や画面端から離し、スクロール後も押しやすくする。
                    Color.clear
                        .frame(height: 88)
                        .accessibilityHidden(true)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
                        Text("駅名や場所を検索して目的地を選ぶと、到着したときにお知らせします。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(action: openNewAlarmFlow) {
                            Label("目的地を追加", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.white)
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
                                deleteAlarm(alarm)
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

    private func deleteAlarm(_ alarm: Alarm) {
        guard let deletion = viewModel.deleteAlarm(id: alarm.id) else { return }
        showUndo(for: deletion)
    }

    private func undoAlarmDeletion() {
        guard let deletion = undoableDeletion else { return }
        undoableDeletion = nil
        undoDismissalToken = UUID()
        _ = viewModel.restore(deletion)
    }

    private func showUndo(for deletion: AlarmListViewModel.Deletion) {
        let token = UUID()
        undoDismissalToken = token
        withAnimation {
            undoableDeletion = deletion
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard undoDismissalToken == token else { return }
            withAnimation {
                undoableDeletion = nil
            }
        }
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

    private func returnToHome() {
        navigationModel.presentedSheet = nil
        navigationModel.path = []
    }

    private var authorizationIssueSummary: String {
        let issues = permissionReadiness.snapshot.authorizationIssues
        switch (
            issues.contains(.locationAlways),
            issues.contains(.notificationAuthorization)
        ) {
        case (true, true):
            return AppStrings.text("位置情報を「常に許可」にし、通知を許可してください")
        case (true, false):
            return AppStrings.text("位置情報を「常に許可」にしてください")
        case (false, true):
            return AppStrings.text("通知を許可してください")
        case (false, false):
            return AppStrings.text("設定を確認してください")
        }
    }

    private var reliabilityAlertMessage: String {
        let issueText: String
        switch (
            reliabilityAlertIssues.contains(.locationAlways),
            reliabilityAlertIssues.contains(.notificationAuthorization)
        ) {
        case (true, true):
            issueText = AppStrings.text("位置情報を「常に許可」にし、通知を許可してください。")
        case (true, false):
            issueText = AppStrings.text("位置情報を「常に許可」にしてください。")
        case (false, true):
            issueText = AppStrings.text("通知を許可してください。")
        case (false, false):
            issueText = AppStrings.text("位置情報と通知の設定を確認してください。")
        }
        return AppStrings.format(
            "アラームが作動しないことがあります。%@設定にかかわらず監視は開始します。",
            issueText
        )
    }
}

enum AlarmListLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class AlarmListViewModel: ObservableObject {
    struct Deletion {
        let alarm: Alarm
        let originalIndex: Int
    }

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
            argument: enabled
                ? AppStrings.text("アラームをオンにしました")
                : AppStrings.text("アラームをオフにしました")
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

    @discardableResult
    func deleteAlarm(id: String) -> Deletion? {
        guard case .success(var latestAlarms) = AlarmStore.loadResult() else {
            loadAlarms()
            return nil
        }
        guard let index = latestAlarms.firstIndex(where: { $0.id == id }) else {
            loadAlarms()
            return nil
        }
        let alarm = latestAlarms.remove(at: index)
        guard persist(latestAlarms) else { return nil }
        if !AppRuntime.shouldSuppressExternalSideEffects {
            LocationManager.shared.stopMonitoringForAlarm(alarm: alarm)
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: AppStrings.format("%@を削除しました", alarm.name)
        )
        return Deletion(alarm: alarm, originalIndex: index)
    }

    @discardableResult
    func restore(_ deletion: Deletion) -> Bool {
        guard case .success(var latestAlarms) = AlarmStore.loadResult() else {
            loadAlarms()
            return false
        }
        guard !latestAlarms.contains(where: { $0.id == deletion.alarm.id }),
              latestAlarms.count < Alarm.maximumSavedAlarms else {
            loadAlarms()
            return false
        }

        let insertionIndex = min(deletion.originalIndex, latestAlarms.count)
        latestAlarms.insert(deletion.alarm, at: insertionIndex)
        guard persist(latestAlarms) else { return false }
        UIAccessibility.post(
            notification: .announcement,
            argument: AppStrings.format("%@を復元しました", deletion.alarm.name)
        )
        return true
    }
}

private struct AlarmListRow: View {
    let alarm: Alarm
    @Binding var isEnabled: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    rowButton
                    HStack {
                        Toggle(AppStrings.format("%@を有効にする", alarm.name), isOn: $isEnabled)
                        Spacer(minLength: 8)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    rowButton
                    enabledToggle
                }
            }
        }
        .tint(AppDesign.tint)
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .accessibilityAction(named: Text("削除")) {
            onDelete()
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
                    if isEnabled {
                        Text(scheduleDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 8) {
                            Image(systemName: soundIconName)
                            Image(systemName: vibrationIconName)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    } else {
                        Text(AppStrings.text("オフ"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(alarm.name)
        .accessibilityValue(isEnabled ? detail : AppStrings.text("オフ"))
        .accessibilityHint("ダブルタップして設定を編集")
        .accessibilityIdentifier("home.alarm.\(alarm.id)")
    }

    private var enabledToggle: some View {
        Toggle("アラームを有効にする", isOn: $isEnabled)
            .labelsHidden()
            .accessibilityLabel(AppStrings.format("%@を有効にする", alarm.name))
            .accessibilityValue(AppStrings.text(isEnabled ? "オン" : "オフ"))
    }

    private var detail: String {
        AppStrings.format(
            "%@、%@、%@",
            scheduleDetail,
            soundStatus,
            vibrationStatus
        )
    }

    private var scheduleDetail: String {
        let names = ["日", "月", "火", "水", "木", "金", "土"].map(AppStrings.text)
        let validDays = (alarm.repeatWeekdays ?? [])
            .filter { names.indices.contains($0) }
            .sorted()
        let repeatText = validDays.isEmpty
            ? AppStrings.text("繰り返さない")
            : validDays.map { names[$0] }.joined(separator: "・")
        return AppStrings.format(
            "到着範囲 %lld m・%@",
            Int(alarm.geofenceRadius ?? Alarm.defaultGeofenceRadius),
            repeatText
        )
    }

    private var soundStatus: String {
        alarm.isSoundEnabled
            ? AppStrings.text("音あり")
            : AppStrings.text("音なし")
    }

    private var vibrationStatus: String {
        alarm.isVibrationEnabled
            ? AppStrings.text("バイブあり")
            : AppStrings.text("バイブなし")
    }

    private var soundIconName: String {
        alarm.isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
    }

    private var vibrationIconName: String {
        alarm.isVibrationEnabled
            ? "iphone.radiowaves.left.and.right"
            : "iphone"
    }
}

private struct AlarmDeletionUndoBanner: View {
    let alarmName: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(AppStrings.format("%@を削除しました", alarmName))
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("取り消す", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("home.undoDelete")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.86), in: Capsule())
        .accessibilityElement(children: .contain)
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

                Text(AppStrings.format("%@に到着しました", activeAlarm.name))
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
                            argument: AppStrings.text("アラームを停止しました")
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
