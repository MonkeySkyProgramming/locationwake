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

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(title: "設定", showsBackButton: true) {
                dismiss()
            }

            Form {
                Section(header: Text("アラーム設定")) {
                    Toggle("アラーム音を有効にする", isOn: $isSoundEnabled)
                    
                    HStack {
                        Text("デフォルトの半径")
                        Spacer()
                        Text("\(Int(defaultRadius)) m")
                    }
                    Slider(value: $defaultRadius, in: Alarm.minimumGeofenceRadius...Alarm.maximumGeofenceRadius, step: 50)
                }

                Section(header: Text("ヘルプ")) {
                    Button("使い方をもう一度見る") {
                        hasSeenOnboarding = false
                        NotificationCenter.default.post(name: NSNotification.Name("ShowHelpOverlay"), object: nil)
                    }
                }
                
                Section(header: Text("システム設定")) {
                    if locationAuthorization != .authorizedAlways {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("位置情報を「常に許可」にしてください")
                                .font(.subheadline.weight(.semibold))
                            Text("バックグラウンドで到着を検知するために必要です。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Button("位置情報の設定を開く", action: openAppSettings)
                        }
                    }

                    if notificationAuthorization != .authorized && notificationAuthorization != .provisional && notificationAuthorization != .ephemeral {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("通知を許可してください")
                                .font(.subheadline.weight(.semibold))
                            Text("目的地への到着を通知するために必要です。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            if notificationAuthorization == .notDetermined {
                                Button("通知を許可する") {
                                    NotificationManager.shared.requestNotificationPermission()
                                }
                            } else {
                                Button("通知設定を開く", action: openAppSettings)
                            }
                        }
                    }

                    if locationAuthorization == .authorizedAlways && (notificationAuthorization == .authorized || notificationAuthorization == .provisional || notificationAuthorization == .ephemeral) {
                        Text("到着通知に必要な設定は完了しています。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    Button("通知設定を開く") {
                        openAppSettings()
                    }

                    Button("位置情報の設定を確認する") {
                        openAppSettings()
                    }
                }

                Section(header: Text("アラームテスト")) {
                    Button("アラームをテスト再生") {
                        SoundPlayer.shared.play(soundName: "modan", forDuration: 5)
                    }
                    Button("バイブレーションをテスト") {
                        HapticManager.triggerRepeated(.systemVibrate, count: 10, interval: 1.0)
                    }
                }

                Section(header: Text("サポート")) {
                    Link("ご意見・お問い合わせ", destination: URL(string: "mailto:monkey.video.35@gmail.com")!)
                }
                
                Section(header: Text("位置情報の使用目的")) {
                    Text("このアプリは、選択された場所に到達したときにアラームを鳴らすため、バックグラウンドでも位置情報を使用します。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
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
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
