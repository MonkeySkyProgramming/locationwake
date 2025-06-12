import AVFoundation

class SoundPlayer {
    // シングルトンインスタンスの定義
    static let shared = SoundPlayer()
    
    var player: AVAudioPlayer?
    private var stopTimer: Timer?
    
    // プライベートイニシャライザで外部からのインスタンス化を防ぐ
    private init() {}
    
    func playSound(named soundName: String) {
        do {
            // 他のアプリやシステムと音声の競合を防ぐための設定
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch let error {
            print("AVAudioSessionのアクティベーションエラー: \(error.localizedDescription)")
        }

        // サウンドの再生
        if let url = Bundle.main.url(forResource: soundName, withExtension: "mp3") {
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.play()
            } catch {
                print("サウンド再生エラー: \(error)")
            }
        } else {
            print("サウンドファイルが見つかりません: \(soundName)")
        }
    }
    
    func play(soundName: String, forDuration duration: TimeInterval) {
        playSound(named: soundName)
        
        // 既存のタイマーがあれば無効化
        stopTimer?.invalidate()
        
        // 指定した時間後にサウンドを停止
        stopTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.stopSound()
        }
    }
    
    func stopSound() {
        player?.stop()
        player = nil  // メモリを解放するためにplayerをnilに設定
        stopTimer?.invalidate()
        stopTimer = nil
        
        // 音量を元に戻す処理を実行
        deactivateAudioSession()
    }
    
    // 音量を元に戻すためのメソッド
    func deactivateAudioSession() {
        do {
            // AVAudioSessionを非アクティブ化して他のアプリの音量を元に戻す
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("AVAudioSessionの非アクティブ化に失敗しました: \(error.localizedDescription)")
        }
    }
}
