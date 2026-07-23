import AVFoundation

final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = SoundPlayer()

    /// The alarm that currently owns alarm playback. Physical playback can be
    /// interrupted or fail, but ownership is released only by `stopAlarm(id:)`.
    private(set) var activeAlarmID: String?
    private(set) var player: AVAudioPlayer?
    private var previewPlayer: AVAudioPlayer?
    private var previewStopTimer: Timer?
    private var isPlaybackRequested = false
    private var isPreviewPlaybackRequested = false

    // バックグラウンドでは、他アプリを完全に中断する非混在セッションを開始できない。
    // 音楽はダッキングし、Podcastなどの音声コンテンツは一時停止して共存する。
    static let alarmCategoryOptions: AVAudioSession.CategoryOptions = [
        .duckOthers,
        .interruptSpokenAudioAndMixWithOthers
    ]

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

    /// Claims alarm playback for `alarmID`.
    ///
    /// A different alarm can never replace the current owner. The return value
    /// indicates whether this alarm owns the channel, not whether iOS was able
    /// to produce audible output.
    @discardableResult
    func startAlarm(id alarmID: String, sound soundName: String) -> Bool {
        guard !alarmID.isEmpty else {
            print("アラームIDが空のためサウンドを開始できません")
            return false
        }
        if let activeAlarmID, activeAlarmID != alarmID {
            return false
        }

        activeAlarmID = alarmID
        if isPlaybackRequested, player != nil {
            return true
        }

        guard let url = Bundle.main.url(forResource: soundName, withExtension: "mp3") else {
            print("サウンドファイルが見つかりません: \(soundName)")
            return true
        }

        player?.stop()
        player = nil

        do {
            try activateAudioSession()
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
            deactivateAudioSessionIfIdle()
            print("サウンド再生エラー: \(error.localizedDescription)")
        }
        return true
    }

    /// Compatibility spelling for call sites that use the resource-name label.
    @discardableResult
    func startAlarm(id alarmID: String, soundName: String) -> Bool {
        startAlarm(id: alarmID, sound: soundName)
    }

    /// Stops alarm playback only when the caller owns the active alarm.
    @discardableResult
    func stopAlarm(id alarmID: String) -> Bool {
        guard activeAlarmID == alarmID else { return false }

        isPlaybackRequested = false
        player?.stop()
        player = nil
        activeAlarmID = nil
        deactivateAudioSessionIfIdle()
        return true
    }

    /// Plays an isolated settings preview. Preview replacement and its timer
    /// never mutate alarm ownership or stop the alarm player.
    @discardableResult
    func playPreview(soundName: String, forDuration duration: TimeInterval? = nil) -> Bool {
        stopPreview()

        guard let url = Bundle.main.url(forResource: soundName, withExtension: "mp3") else {
            print("サウンドファイルが見つかりません: \(soundName)")
            return false
        }

        do {
            try activateAudioSession()
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.numberOfLoops = 0
            newPlayer.prepareToPlay()
            guard newPlayer.play() else {
                throw SoundPlayerError.playbackDidNotStart
            }
            previewPlayer = newPlayer
            isPreviewPlaybackRequested = true

            if let duration {
                previewStopTimer = Timer.scheduledTimer(
                    withTimeInterval: max(duration, 0.1),
                    repeats: false
                ) { [weak self] _ in
                    self?.stopPreview()
                }
            }
            return true
        } catch {
            previewPlayer = nil
            isPreviewPlaybackRequested = false
            deactivateAudioSessionIfIdle()
            print("サウンド試聴エラー: \(error.localizedDescription)")
            return false
        }
    }

    func stopPreview() {
        isPreviewPlaybackRequested = false
        previewPlayer?.stop()
        previewPlayer = nil
        previewStopTimer?.invalidate()
        previewStopTimer = nil
        deactivateAudioSessionIfIdle()
    }

    /// Compatibility API used by the settings screen.
    func play(soundName: String, forDuration duration: TimeInterval) {
        playPreview(soundName: soundName, forDuration: duration)
    }

    /// Legacy unowned playback is treated as preview so it cannot replace an
    /// alarm. Alarm call sites must use `startAlarm(id:sound:)`.
    @available(*, deprecated, message: "Use startAlarm(id:sound:) for alarms or playPreview(soundName:forDuration:) for previews")
    func playSound(named soundName: String) {
        playPreview(soundName: soundName)
    }

    /// Legacy unowned stopping is preview-only. Alarm call sites must provide
    /// the exact ID to `stopAlarm(id:)`.
    @available(*, deprecated, message: "Use stopAlarm(id:) for alarms or stopPreview() for previews")
    func stopSound() {
        stopPreview()
    }

    private func activateAudioSession() throws {
        try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: Self.alarmCategoryOptions
        )
        try AVAudioSession.sharedInstance().setActive(true)
    }

    private func deactivateAudioSessionIfIdle() {
        guard player == nil, previewPlayer == nil else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("AVAudioSessionの非アクティブ化に失敗しました: \(error.localizedDescription)")
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if player === self.player {
            isPlaybackRequested = false
            self.player = nil
        } else if player === previewPlayer {
            isPreviewPlaybackRequested = false
            previewPlayer = nil
            previewStopTimer?.invalidate()
            previewStopTimer = nil
        }
        deactivateAudioSessionIfIdle()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if player === self.player {
            isPlaybackRequested = false
            self.player = nil
        } else if player === previewPlayer {
            isPreviewPlaybackRequested = false
            previewPlayer = nil
            previewStopTimer?.invalidate()
            previewStopTimer = nil
        }
        deactivateAudioSessionIfIdle()
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
            if isPreviewPlaybackRequested {
                previewPlayer?.pause()
            }
        case .ended:
            resumeAfterInterruption()
        @unknown default:
            break
        }
    }

    private func resumeAfterInterruption() {
        guard isPlaybackRequested || isPreviewPlaybackRequested else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("割り込み後のオーディオセッション再開に失敗しました: \(error.localizedDescription)")
            return
        }

        if isPlaybackRequested, let player, !player.play() {
            isPlaybackRequested = false
            self.player = nil
            print("割り込み後のアラーム再開に失敗しました")
        }
        if isPreviewPlaybackRequested, let previewPlayer, !previewPlayer.play() {
            isPreviewPlaybackRequested = false
            self.previewPlayer = nil
            previewStopTimer?.invalidate()
            previewStopTimer = nil
            print("割り込み後のサウンド試聴再開に失敗しました")
        }
        deactivateAudioSessionIfIdle()
    }

    private enum SoundPlayerError: LocalizedError {
        case playbackDidNotStart

        var errorDescription: String? {
            "音声再生を開始できませんでした"
        }
    }
}
