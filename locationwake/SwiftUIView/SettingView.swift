import SwiftUI
import CoreLocation
import UserNotifications

struct SettingView: View {
    private enum AccessibilityFocusTarget: Hashable {
        case readinessStatus
        case issue(String)
    }

    @AppStorage("defaultRadius") private var defaultRadius: Double = Alarm.defaultGeofenceRadius
    @AppStorage("isSoundEnabled") private var isSoundEnabled: Bool = true
    @ObservedObject private var permissionReadiness: PermissionReadiness
    @AccessibilityFocusState private var accessibilityFocus: AccessibilityFocusTarget?
    @State private var showsLocationRestrictionExplanation = false
    @State private var pendingPermissionIssueID: String?

    init(permissionReadiness: PermissionReadiness = .shared) {
        _permissionReadiness = ObservedObject(wrappedValue: permissionReadiness)
    }

    var body: some View {
        Form {
            Section {
                Toggle("音を鳴らす", isOn: $isSoundEnabled)
                    .tint(AppDesign.tint)

                RadiusPickerControl(radius: $defaultRadius)
            } header: {
                Text("新しいアラームの初期設定")
            } footer: {
                Text("ここでの変更は、これから作成するアラームにだけ反映されます。")
            }

            Section("到着通知に必要な設定") {
                if !permissionReadiness.snapshot.hasLoadedNotificationSettings {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("設定を確認しています")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityFocused($accessibilityFocus, equals: .readinessStatus)
                } else if permissionReadiness.snapshot.isReadyForReliableArrival {
                    Label {
                        Text("到着通知の設定は完了しています")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppDesign.tint)
                    }
                    .accessibilityFocused($accessibilityFocus, equals: .readinessStatus)
                } else {
                    ForEach(permissionReadiness.snapshot.issues) { issue in
                        Button {
                            handlePermissionIssue(issue)
                        } label: {
                            settingsLabel(
                                issue.title,
                                systemImage: issue.systemImage,
                                iconColor: .orange
                            )
                        }
                        .accessibilityFocused($accessibilityFocus, equals: .issue(issue.id))
                    }
                }
            }

            Section("テスト") {
                Button {
                    SoundPlayer.shared.play(soundName: "modan", forDuration: 5)
                } label: {
                    settingsLabel("アラーム音をテスト", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.plain)

                Button {
                    HapticManager.triggerRepeated(.systemVibrate, count: 10, interval: 1.0)
                } label: {
                    settingsLabel("バイブレーションをテスト", systemImage: "iphone.gen3.radiowaves.left.and.right")
                }
                .buttonStyle(.plain)
            }

            Section("ヘルプ") {
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowHelpOverlay"), object: nil)
                } label: {
                    settingsLabel("使い方をもう一度見る", systemImage: "questionmark.circle")
                }
                .buttonStyle(.plain)
            }

            Section("サポート") {
                Link(destination: URL(string: "mailto:monkey.video.35@gmail.com")!) {
                    settingsLabel("ご意見・お問い合わせ", systemImage: "ellipsis.message")
                }
                .foregroundStyle(.primary)
            }
        }
        .tint(AppDesign.tint)
        .scrollContentBackground(.hidden)
        .background(AppDesign.background)
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            defaultRadius = Alarm.normalizedRadius(defaultRadius) ?? Alarm.defaultGeofenceRadius
            permissionReadiness.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            permissionReadiness.refresh {
                focusAfterPendingPermissionResult()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationAuthorizationDidChange)) { _ in
            permissionReadiness.refresh {
                focusAfterPendingPermissionResult()
            }
        }
        .onChange(of: permissionReadiness.snapshot) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if !focusAfterPendingPermissionResult() {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: readinessAnnouncement(for: newValue)
                )
            }
        }
        .alert(
            "位置情報が制限されています",
            isPresented: $showsLocationRestrictionExplanation
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("スクリーンタイムまたは端末管理の制限により、このアプリから変更できません。端末の管理者またはスクリーンタイム設定を確認してください。")
        }
    }

    private func handlePermissionIssue(_ issue: PermissionReadinessIssue) {
        switch issue {
        case .locationAlways:
            switch permissionReadiness.snapshot.locationAuthorization {
            case .notDetermined:
                prepareForPermissionResult(from: issue)
                permissionReadiness.requestAlwaysLocationAuthorization()
            case .authorizedWhenInUse:
                prepareForPermissionResult(from: issue)
                if permissionReadiness.canRequestAlwaysUpgradeInApp {
                    permissionReadiness.requestAlwaysLocationAuthorization()
                } else {
                    permissionReadiness.openAppSettings()
                }
            case .restricted:
                showsLocationRestrictionExplanation = true
            case .authorizedAlways, .denied:
                prepareForPermissionResult(from: issue)
                permissionReadiness.openAppSettings()
            @unknown default:
                prepareForPermissionResult(from: issue)
                permissionReadiness.openAppSettings()
            }
        case .notificationAuthorization:
            prepareForPermissionResult(from: issue)
            if permissionReadiness.snapshot.notificationAuthorization == .notDetermined {
                permissionReadiness.requestNotificationAuthorization {
                    focusAfterPendingPermissionResult()
                }
            } else {
                permissionReadiness.openAppSettings()
            }
        case .preciseLocation, .notificationSound:
            prepareForPermissionResult(from: issue)
            permissionReadiness.openAppSettings()
        }
    }

    private func prepareForPermissionResult(from issue: PermissionReadinessIssue) {
        pendingPermissionIssueID = issue.id
        accessibilityFocus = nil
    }

    @discardableResult
    private func focusAfterPendingPermissionResult() -> Bool {
        guard let pendingPermissionIssueID else { return false }
        self.pendingPermissionIssueID = nil

        let target = accessibilityTarget(
            afterResolving: pendingPermissionIssueID,
            in: permissionReadiness.snapshot
        )
        accessibilityFocus = nil
        DispatchQueue.main.async {
            accessibilityFocus = target
        }
        return true
    }

    private func accessibilityTarget(
        afterResolving issueID: String,
        in snapshot: PermissionReadinessSnapshot
    ) -> AccessibilityFocusTarget {
        guard snapshot.hasLoadedNotificationSettings,
              !snapshot.isReadyForReliableArrival,
              !snapshot.issues.isEmpty else {
            return .readinessStatus
        }

        if snapshot.issues.contains(where: { $0.id == issueID }) {
            return .issue(issueID)
        }

        if let previousIndex = PermissionReadinessIssue.allCases.firstIndex(where: { $0.id == issueID }),
           let successor = snapshot.issues.first(where: { issue in
               guard let index = PermissionReadinessIssue.allCases.firstIndex(where: { $0.id == issue.id }) else {
                   return false
               }
               return index > previousIndex
           }) {
            return .issue(successor.id)
        }

        return .issue(snapshot.issues[0].id)
    }

    private func readinessAnnouncement(
        for snapshot: PermissionReadinessSnapshot
    ) -> String {
        if snapshot.isReadyForReliableArrival {
            return AppStrings.text("到着通知の設定は完了しています")
        }
        return snapshot.issues.map(\.title).joined(separator: "。")
    }

    private func settingsLabel(
        _ title: String,
        systemImage: String,
        iconColor: Color = AppDesign.tint
    ) -> some View {
        Label {
            Text(AppStrings.text(title))
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
        }
    }

    /// 既存の判定テストと、3項目だけを扱う呼び出し元の互換性を保つ。
    static func areArrivalPermissionsComplete(
        locationAuthorization: CLAuthorizationStatus,
        notificationAuthorization: UNAuthorizationStatus,
        notificationSoundSetting: UNNotificationSetting
    ) -> Bool {
        let notificationsAllowed = notificationAuthorization == .authorized
            || notificationAuthorization == .provisional
            || notificationAuthorization == .ephemeral
        return locationAuthorization == .authorizedAlways
            && notificationsAllowed
            && notificationSoundSetting == .enabled
    }
}
