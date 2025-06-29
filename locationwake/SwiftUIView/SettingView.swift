import SwiftUI

struct SettingView: View {
    @AppStorage("defaultRadius") private var defaultRadius: Double = 300.0
    @AppStorage("isSoundEnabled") private var isSoundEnabled: Bool = true
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = true

    var body: some View {
        Form {
            Section(header: Text("アラーム設定")) {
                Toggle("アラーム音を有効にする", isOn: $isSoundEnabled)
                
                HStack {
                    Text("デフォルトの半径")
                    Spacer()
                    Text("\(Int(defaultRadius)) m")
                }
                Slider(value: $defaultRadius, in: 100...1000, step: 50)
            }

            Section(header: Text("ヘルプ")) {
                Button("使い方をもう一度見る") {
                    hasSeenOnboarding = false
                    NotificationCenter.default.post(name: NSNotification.Name("ShowHelpOverlay"), object: nil)
                }
            }
            
            Section(header: Text("システム設定")) {
                Button("通知設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }

                Button("位置情報の設定を確認する") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }

            Section(header: Text("アラームテスト")) {
                Button("アラームをテスト再生") {
                    SoundPlayer.shared.play(soundName: "modan", forDuration: 5)
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
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: hasSeenOnboarding) { newValue in
            if newValue == false {
                NotificationCenter.default.post(name: NSNotification.Name("ShowHelpOverlay"), object: nil)
            }
        }
    }
}
