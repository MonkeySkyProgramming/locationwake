import AVFoundation

class Sound {
    var audioPlayer: AVAudioPlayer?

    func play(soundName: String, forDuration duration: TimeInterval) {
        guard let soundURL = Bundle.main.url(forResource: soundName, withExtension: "mp3") else {
            print("音声ファイルが見つかりません: \(soundName)")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.play()

            // 指定された時間（秒数）後に再生を停止
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.stop()
            }
        } catch {
            print("音声ファイルの再生に失敗しました: \(error)")
        }
    }

    func stop() {
        audioPlayer?.stop()
    }
}
