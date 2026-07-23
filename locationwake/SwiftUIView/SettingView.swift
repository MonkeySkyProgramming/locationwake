import SwiftUI
import CoreLocation
import UserNotifications

struct SettingView: View {
    @AppStorage("defaultRadius") private var defaultRadius: Double = Alarm.defaultGeofenceRadius
    @AppStorage("isSoundEnabled") private var isSoundEnabled: Bool = true
    @ObservedObject private var permissionReadiness: PermissionReadiness

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
                } else if permissionReadiness.snapshot.isReadyForReliableArrival {
                    Label {
                        Text("到着通知の設定は完了しています")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppDesign.tint)
                    }
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
            permissionReadiness.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationAuthorizationDidChange)) { _ in
            permissionReadiness.refresh()
        }
    }

    private func handlePermissionIssue(_ issue: PermissionReadinessIssue) {
        switch issue {
        case .locationAlways:
            switch permissionReadiness.snapshot.locationAuthorization {
            case .notDetermined, .authorizedWhenInUse:
                permissionReadiness.requestAlwaysLocationAuthorization()
            case .authorizedAlways, .denied, .restricted:
                permissionReadiness.openAppSettings()
            @unknown default:
                permissionReadiness.openAppSettings()
            }
        case .notificationAuthorization:
            if permissionReadiness.snapshot.notificationAuthorization == .notDetermined {
                permissionReadiness.requestNotificationAuthorization()
            } else {
                permissionReadiness.openAppSettings()
            }
        case .preciseLocation, .notificationSound, .backgroundRefresh:
            permissionReadiness.openAppSettings()
        }
    }

    private func settingsLabel(
        _ title: String,
        systemImage: String,
        iconColor: Color = AppDesign.tint
    ) -> some View {
        Label {
            Text(title)
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
