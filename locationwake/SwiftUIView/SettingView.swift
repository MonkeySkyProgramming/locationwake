import SwiftUI
import CoreLocation
import UserNotifications

struct SettingView: View {
    @AppStorage("defaultRadius") private var defaultRadius: Double = Alarm.defaultGeofenceRadius
    @AppStorage("isSoundEnabled") private var isSoundEnabled: Bool = true
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = true
    @Environment(\.dismiss) private var dismiss
    @State private var locationAuthorization = CLLocationManager().authorizationStatus
    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    @State private var notificationSoundSetting: UNNotificationSetting = .notSupported

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(title: "設定", showsBackButton: true) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AppSectionTitle(title: "アラーム")
                        .padding(.top, 28)
                        .padding(.bottom, 8)
                    AppCard {
                        VStack(spacing: 0) {
                            HStack {
                                Text("アラーム音を有効にする")
                                    .font(.system(size: 17))
                                Spacer()
                                Toggle("アラーム音を有効にする", isOn: $isSoundEnabled)
                                    .labelsHidden()
                                    .tint(AppDesign.tint)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 58)
                            Divider().padding(.horizontal, 16)
                            VStack(spacing: 12) {
                                HStack {
                                    Text("デフォルトの到着範囲")
                                        .font(.system(size: 17))
                                    Spacer()
                                    Text("\(Int(defaultRadius)) m")
                                        .font(.system(size: 17))
                                        .foregroundStyle(AppDesign.tint)
                                }
                                Slider(value: $defaultRadius, in: Alarm.minimumGeofenceRadius...Alarm.maximumGeofenceRadius, step: 50)
                                HStack {
                                    Text("50 m")
                                    Spacer()
                                    Text("300 m")
                                    Spacer()
                                    Text("1,000 m")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(16)
                        }
                    }
                    .padding(.horizontal, AppDesign.horizontalPadding)

                    AppSectionTitle(title: "到着通知に必要な設定")
                        .padding(.top, 28)
                        .padding(.bottom, 8)
                    AppCard {
                        VStack(spacing: 0) {
                            if permissionsComplete {
                                HStack(spacing: 16) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 36, height: 36)
                                        .background(AppDesign.tint, in: Circle())
                                    Text("到着通知の設定は完了しています")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 64)
                            } else {
                                if locationAuthorization != .authorizedAlways {
                                    Button(action: openAppSettings) {
                                        SettingsActionRow(
                                            icon: "exclamationmark.triangle.fill",
                                            iconColor: .orange,
                                            title: "位置情報を「常に許可」\nにしてください",
                                            trailing: "設定を開く"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                if locationAuthorization != .authorizedAlways && !notificationAllowed {
                                    Divider().padding(.leading, 58)
                                }

                                if !notificationAllowed {
                                    Button {
                                        if notificationAuthorization == .notDetermined {
                                            NotificationManager.shared.requestNotificationPermission()
                                        } else {
                                            openAppSettings()
                                        }
                                    } label: {
                                        SettingsActionRow(
                                            icon: "exclamationmark.triangle.fill",
                                            iconColor: .orange,
                                            title: "通知を許可してください",
                                            trailing: notificationAuthorization == .notDetermined ? "通知を許可する" : "設定を開く"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                if notificationAllowed && !notificationSoundAllowed {
                                    if locationAuthorization != .authorizedAlways {
                                        Divider().padding(.leading, 58)
                                    }
                                    Button(action: openAppSettings) {
                                        SettingsActionRow(
                                            icon: "speaker.slash.fill",
                                            iconColor: .orange,
                                            title: "通知のサウンドをオンにしてください",
                                            trailing: "設定を開く"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppDesign.horizontalPadding)

                    AppSectionTitle(title: "テスト")
                        .padding(.top, 28)
                        .padding(.bottom, 8)
                    AppCard {
                        VStack(spacing: 0) {
                            Button {
                                SoundPlayer.shared.play(soundName: "modan", forDuration: 5)
                            } label: {
                                SettingsActionRow(icon: "speaker.wave.2.fill", title: "アラーム音をテスト")
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 58)
                            Button {
                                HapticManager.triggerRepeated(.systemVibrate, count: 10, interval: 1.0)
                            } label: {
                                SettingsActionRow(icon: "iphone.gen3.radiowaves.left.and.right", title: "バイブレーションをテスト")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppDesign.horizontalPadding)

                    AppSectionTitle(title: "ヘルプ")
                        .padding(.top, 28)
                        .padding(.bottom, 8)
                    AppCard {
                        Button {
                            hasSeenOnboarding = false
                            NotificationCenter.default.post(name: NSNotification.Name("ShowHelpOverlay"), object: nil)
                        } label: {
                            SettingsActionRow(icon: "questionmark.circle", title: "使い方をもう一度見る")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, AppDesign.horizontalPadding)

                    AppSectionTitle(title: "サポート")
                        .padding(.top, 28)
                        .padding(.bottom, 8)
                    AppCard {
                        Link(destination: URL(string: "mailto:monkey.video.35@gmail.com")!) {
                            SettingsActionRow(icon: "ellipsis.message", title: "ご意見・お問い合わせ")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, AppDesign.horizontalPadding)

                    AdScrollClearance()
                }
            }
            .tint(AppDesign.tint)
            .background(AppDesign.background)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
        .navigationBarBackButtonHidden(true)
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

private struct SettingsActionRow: View {
    let icon: String
    var iconColor: Color = AppDesign.tint
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 15))
                    .foregroundStyle(AppDesign.tint)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}
