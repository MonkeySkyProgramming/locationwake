import AVFoundation

final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    // シングルトンインスタンスの定義
    static let shared = SoundPlayer()
    
    var player: AVAudioPlayer?
    private var stopTimer: Timer?
    private var isPlaybackRequested = false
    
    // プライベートイニシャライザで外部からのインスタンス化を防ぐ
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func playSound(named soundName: String) {
        stopTimer?.invalidate()
        stopTimer = nil
        player?.stop()
        player = nil
        isPlaybackRequested = false

        guard let url = Bundle.main.url(forResource: soundName, withExtension: "mp3") else {
            print("サウンドファイルが見つかりません: \(soundName)")
            deactivateAudioSession()
            return
        }

        do {
            // 長時間のアラームでは他アプリの音声を一時停止し、停止後に再開可能であることを通知する。
            // duckOthers は短時間利用向けのため、ループ再生するアラームでは使用しない。
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.numberOfLoops = -1
            newPlayer.prepareToPlay()
            guard newPlayer.play() else {
                throw SoundPlayerError.playbackDidNotStart
            }
            player = newPlayer
            isPlaybackRequested = true
        } catch {
            player = nil
            isPlaybackRequested = false
            deactivateAudioSession()
            print("サウンド再生エラー: \(error.localizedDescription)")
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
        isPlaybackRequested = false
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

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaybackRequested = false
        self.player = nil
        stopTimer?.invalidate()
        stopTimer = nil
        deactivateAudioSession()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaybackRequested = false
        self.player = nil
        stopTimer?.invalidate()
        stopTimer = nil
        deactivateAudioSession()
        if let error {
            print("サウンドのデコード中にエラーが発生しました: \(error.localizedDescription)")
        }
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            if isPlaybackRequested {
                player?.pause()
            }
        case .ended:
            guard isPlaybackRequested, let player else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                guard player.play() else {
                    throw SoundPlayerError.playbackDidNotStart
                }
            } catch {
                isPlaybackRequested = false
                self.player = nil
                deactivateAudioSession()
                print("割り込み後のアラーム再開に失敗しました: \(error.localizedDescription)")
            }
        @unknown default:
            break
        }
    }

    private enum SoundPlayerError: LocalizedError {
        case playbackDidNotStart

        var errorDescription: String? {
            "音声再生を開始できませんでした"
        }
    }
}
