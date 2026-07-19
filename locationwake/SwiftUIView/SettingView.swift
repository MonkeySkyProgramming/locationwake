import SwiftUI
import CoreLocation
import UserNotifications

struct SettingView: View {
    @AppStorage("defaultRadius") private var defaultRadius: Double = Alarm.defaultGeofenceRadius
    @AppStorage("isSoundEnabled") private var isSoundEnabled: Bool = true
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = true
    @State private var locationAuthorization = CLLocationManager().authorizationStatus
    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    @State private var notificationSoundSetting: UNNotificationSetting = .notSupported

    var body: some View {
        Form {
            Section("アラーム") {
                Toggle("アラーム音を有効にする", isOn: $isSoundEnabled)
                    .tint(AppDesign.tint)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("デフォルトの到着範囲")
                        Spacer()
                        Text("\(Int(defaultRadius)) m")
                            .foregroundStyle(.primary)
                    }

                    Slider(value: $defaultRadius, in: Alarm.minimumGeofenceRadius...Alarm.maximumGeofenceRadius, step: 50)

                    HStack {
                        Text("\(Int(Alarm.minimumGeofenceRadius).formatted()) m")
                        Spacer()
                        Text("\(Int((Alarm.minimumGeofenceRadius + Alarm.maximumGeofenceRadius) / 2).formatted()) m")
                        Spacer()
                        Text("\(Int(Alarm.maximumGeofenceRadius).formatted()) m")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("到着通知に必要な設定") {
                if permissionsComplete {
                    Label {
                        Text("到着通知の設定は完了しています")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppDesign.tint)
                    }
                } else {
                    if locationAuthorization != .authorizedAlways {
                        Button(action: openAppSettings) {
                            settingsLabel(
                                "位置情報を「常に許可」にしてください",
                                systemImage: "exclamationmark.triangle.fill",
                                iconColor: .orange
                            )
                        }
                    }

                    if !notificationAllowed {
                        Button {
                            if notificationAuthorization == .notDetermined {
                                NotificationManager.shared.requestNotificationPermission()
                            } else {
                                openAppSettings()
                            }
                        } label: {
                            settingsLabel(
                                "通知を許可してください",
                                systemImage: "exclamationmark.triangle.fill",
                                iconColor: .orange
                            )
                        }
                    }

                    if notificationAllowed && !notificationSoundAllowed {
                        Button(action: openAppSettings) {
                            settingsLabel(
                                "通知のサウンドをオンにしてください",
                                systemImage: "speaker.slash.fill",
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
                    hasSeenOnboarding = false
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

            Section {
                AdListClearance()
            }
            .listRowBackground(Color.clear)
        }
        .tint(AppDesign.tint)
        .scrollContentBackground(.hidden)
        .background(AppDesign.background)
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: hasSeenOnboarding) { _, newValue in
            if newValue == false {
                NotificationCenter.default.post(name: NSNotification.Name("ShowHelpOverlay"), object: nil)
            }
        }
        .onAppear {
            defaultRadius = Alarm.normalizedRadius(defaultRadius) ?? Alarm.defaultGeofenceRadius
            refreshAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshAuthorization()
        }
    }

    private func refreshAuthorization() {
        locationAuthorization = CLLocationManager().authorizationStatus
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationAuthorization = settings.authorizationStatus
                notificationSoundSetting = settings.soundSetting
            }
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

    private var notificationAllowed: Bool {
        notificationAuthorization == .authorized || notificationAuthorization == .provisional || notificationAuthorization == .ephemeral
    }

    private var permissionsComplete: Bool {
        Self.areArrivalPermissionsComplete(
            locationAuthorization: locationAuthorization,
            notificationAuthorization: notificationAuthorization,
            notificationSoundSetting: notificationSoundSetting
        )
    }

    private var notificationSoundAllowed: Bool {
        notificationSoundSetting == .enabled
    }

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

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
