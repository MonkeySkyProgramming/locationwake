import SwiftUI
import MapKit
import AVFoundation

struct AlarmDetailView: View {
    private let alarmID: String
    var coordinate: CLLocationCoordinate2D
    var placeName: String?

    @State private var alarmName: String = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var radius: Double = Alarm.defaultGeofenceRadius
    @State private var isSoundEnabled: Bool = true
    @State private var selectedSound: String = "未選択"
    @State private var repeatWeekdays: Set<Int> = []
    @State private var cameraPosition: MapCameraPosition
    @State private var isVibrationEnabled: Bool = true
    @State private var isAlarmLimitAlertPresented = false
    @State private var monitoringFailure: String?
    @EnvironmentObject var navigationModel: NavigationModel
    @EnvironmentObject var viewModel: AlarmListViewModel

    init(alarm: Alarm) {
        let coordinate = CLLocationCoordinate2D(
            latitude: alarm.location?.latitude ?? 0,
            longitude: alarm.location?.longitude ?? 0
        )
        self.alarmID = alarm.id
        self.coordinate = coordinate
        self.placeName = alarm.name
        _selectedCoordinate = State(initialValue: coordinate)
        _alarmName = State(initialValue: alarm.name)
        let geofenceRadius = alarm.geofenceRadius ?? Alarm.defaultGeofenceRadius
        _radius = State(initialValue: geofenceRadius)
        _isSoundEnabled = State(initialValue: alarm.isSoundEnabled)
        _selectedSound = State(initialValue: alarm.sound)
        _repeatWeekdays = State(initialValue: Set(alarm.repeatWeekdays ?? []))
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: geofenceRadius * 3.2,
            longitudinalMeters: geofenceRadius * 3.2
        )))
        _isVibrationEnabled = State(initialValue: alarm.isVibrationEnabled)
    }

    var body: some View {
        Form {
            alarmNameSection
            locationSection
            radiusSection
            monitoringFailureSection
            notificationSection
            repeatSection
            Section {
                AdListClearance()
            }
            .listRowBackground(Color.clear)
        }
        .tint(AppDesign.tint)
        .scrollContentBackground(.hidden)
        .background(AppDesign.background)
        .alert("アラームを追加できません", isPresented: $isAlarmLimitAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("アラームは最大\(Alarm.maximumSavedAlarms)件まで登録できます。不要なアラームを削除してください。")
        }
        .onAppear {
            monitoringFailure = UserDefaults.standard.string(forKey: "MonitoringFailure_\(alarmID)")
        }
        .navigationTitle("アラームを編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    saveCurrentAlarm()
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppDesign.tint)
                .accessibilityHint("アラームの変更を保存します")
            }
        }
    }

    private var alarmNameSection: some View {
        Section("アラーム名") {
            HStack {
                Label("アラーム名", systemImage: "tag")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(AppDesign.tint)
                TextField("アラーム名を入力", text: $alarmName)
                if !alarmName.isEmpty {
                    Button {
                        alarmName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var locationSection: some View {
        Section("位置情報") {
            AlarmDetailMapPreview(
                cameraPosition: $cameraPosition,
                coordinate: selectedCoordinate,
                radius: radius,
                title: alarmName.isEmpty ? "目的地" : alarmName
            )

            Label {
                Text(String(format: "%.6f° N, %.6f° E", selectedCoordinate.latitude, selectedCoordinate.longitude))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "mappin")
                    .foregroundStyle(AppDesign.tint)
            }
        }
        .onChange(of: radius) { _, newValue in
            cameraPosition = .region(MKCoordinateRegion(
                center: selectedCoordinate,
                latitudinalMeters: newValue * 3.2,
                longitudinalMeters: newValue * 3.2
            ))
        }
    }

    private var radiusSection: some View {
        Section("到着範囲") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("到着範囲", systemImage: "scope")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(AppDesign.tint)
                    Slider(value: $radius, in: Alarm.minimumGeofenceRadius...Alarm.maximumGeofenceRadius, step: 50)
                    Text("\(Int(radius)) m")
                        .frame(width: 62, alignment: .trailing)
                }

                HStack {
                    Text(Int(Alarm.minimumGeofenceRadius).formatted())
                    Spacer()
                    Text(Int((Alarm.minimumGeofenceRadius + Alarm.maximumGeofenceRadius) / 2).formatted())
                    Spacer()
                    Text(Int(Alarm.maximumGeofenceRadius).formatted())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 30)
                .padding(.trailing, 66)
            }
        }
    }

    @ViewBuilder
    private var monitoringFailureSection: some View {
        if let monitoringFailure {
            Section {
                Label(monitoringFailure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle(isOn: $isSoundEnabled) {
                Label("音を鳴らす", systemImage: "bell")
            }
            .tint(AppDesign.tint)

            Toggle(isOn: $isVibrationEnabled) {
                Label("バイブレーション", systemImage: "iphone.gen3.radiowaves.left.and.right")
            }
            .tint(AppDesign.tint)

            NavigationLink(destination: SoundSelectionView(selectedSound: $selectedSound)) {
                HStack {
                    Label("サウンド", systemImage: "music.note")
                    Spacer()
                    Text(selectedSound)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("通知")
        } footer: {
            Label("到着後は、通知をタップしてアプリを開くとアラームを停止できます。", systemImage: "info.circle")
        }
    }

    private var repeatSection: some View {
        Section("繰り返し") {
            NavigationLink(destination: RepeatWeekdaySelectionView(selectedWeekdays: $repeatWeekdays)) {
                HStack {
                    Label("繰り返し", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text(weekdaySummary)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    func saveCurrentAlarm() {
        let newAlarm = Alarm(
            id: alarmID,
            name: alarmName,
            repeatWeekdays: Array(repeatWeekdays).sorted(),
            sound: selectedSound,
            isAlarmEnabled: true,
            isSoundEnabled: isSoundEnabled,
            isVibrationEnabled: isVibrationEnabled,
            location: Location(latitude: selectedCoordinate.latitude, longitude: selectedCoordinate.longitude),
            radius: Alarm.normalizedRadius(radius)
        )

        // Debug print
        print("🔍 保存するアラーム:")
        print("名前: \(newAlarm.name)")
        print("繰り返し: \(newAlarm.repeatWeekdays ?? [])")
        print("音: \(newAlarm.sound)")
        print("有効: \(newAlarm.isAlarmEnabled), 音有効: \(newAlarm.isSoundEnabled)")
        print("バイブレーション有効: \(newAlarm.isVibrationEnabled)")
        if let location = newAlarm.location {
            print("位置: 緯度 \(location.latitude), 経度 \(location.longitude)")
        } else {
            print("位置情報が設定されていません")
        }
        print("半径: \(newAlarm.radius ?? 0)")

        let allAlarms = loadSavedAlarms()
        print("📦 現在保存されているアラーム一覧:")
        for (i, alarm) in allAlarms.enumerated() {
            print("🔔 [\(i)] \(alarm.name), 繰り返し: \(alarm.repeatWeekdays ?? []), 音: \(alarm.sound), 緯度: \(alarm.location?.latitude ?? 0), 経度: \(alarm.location?.longitude ?? 0), 半径: \(alarm.radius ?? 0)")
        }

        let skipTimestampKey = "SkipTriggerAt_\(newAlarm.id)"
        UserDefaults.standard.set(Date(), forKey: skipTimestampKey)

        guard saveAlarmSetting(newAlarm) else {
            isAlarmLimitAlertPresented = true
            return
        }
        viewModel.loadAlarms()
        navigationModel.path = []
    }

    private var weekdaySummary: String {
        let names = ["日", "月", "火", "水", "木", "金", "土"]
        guard !repeatWeekdays.isEmpty else { return "繰り返さない" }
        return repeatWeekdays.sorted().map { names[$0] }.joined(separator: "・")
    }

    private var monitoringMethodDescription: String? {
        guard let geofenceMaximum = LocationManager.shared.maximumGeofenceRadius else {
            return "この設定では現在地を確認して到着をお知らせするため、電池の減りが早くなることがあります。"
        }
        let roundedMaximum = Int(geofenceMaximum)
        if radius <= geofenceMaximum {
            return nil
        }
        return "この端末では\(roundedMaximum)mを超える設定のため、電池の減りが早くなることがあります。"
    }
    
    func saveAlarmSetting(_ alarm: Alarm) -> Bool {
        var savedAlarms = loadSavedAlarms()
        let isExistingAlarm = savedAlarms.contains(where: { $0.id == alarm.id })
        guard isExistingAlarm || savedAlarms.count < Alarm.maximumSavedAlarms else {
            return false
        }
        // Insert geofence check and update hasTriggeredUntilExit before saving
        let manager: CLLocationManager = LocationManager.shared.locationManager
        let radius = alarm.geofenceRadius ?? Alarm.defaultGeofenceRadius
        if let userLocation = manager.location,
           LocationManager.isUsableLocation(
               userLocation,
               maximumHorizontalAccuracy: LocationManager.maximumHorizontalAccuracy(for: radius)
           ) {
            let center = CLLocation(latitude: alarm.location?.latitude ?? 0, longitude: alarm.location?.longitude ?? 0)
            let current = CLLocation(
                latitude: userLocation.coordinate.latitude,
                longitude: userLocation.coordinate.longitude
            )
            let distance = current.distance(from: center)
            let isInside = distance <= radius
            var updatedAlarm = alarm
            if updatedAlarm.id.isEmpty {
                updatedAlarm.id = UUID().uuidString
            }
            updatedAlarm.hasTriggeredUntilExit = isInside
            if let index = savedAlarms.firstIndex(where: { $0.id == updatedAlarm.id }) {
                savedAlarms[index] = updatedAlarm
            } else {
                var newAlarm = updatedAlarm
                if newAlarm.id.isEmpty {
                    newAlarm.id = UUID().uuidString
                }
                savedAlarms.append(newAlarm)
            }
        } else {
            // Use id-based matching instead of name-based matching
            if let index = savedAlarms.firstIndex(where: { $0.id == alarm.id }) {
                savedAlarms[index] = alarm
            } else {
                var newAlarm = alarm
                if newAlarm.id.isEmpty {
                    newAlarm.id = UUID().uuidString
                }
                savedAlarms.append(newAlarm)
            }
        }
        AlarmStore.save(savedAlarms)
        return true
    }

    func loadSavedAlarms() -> [Alarm] {
        AlarmStore.load()
    }
}

private struct AlarmDetailMapPreview: View {
    @Binding var cameraPosition: MapCameraPosition
    let coordinate: CLLocationCoordinate2D
    let radius: Double
    let title: String

    var body: some View {
        Map(position: $cameraPosition) {
            MapCircle(center: coordinate, radius: radius)
                .foregroundStyle(AppDesign.tint.opacity(0.22))
                .stroke(AppDesign.tint, lineWidth: 2)
            Marker(title, coordinate: coordinate)
                .tint(AppDesign.tint)
        }
        .frame(height: 214)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// 簡易的な音選択ビュー
struct SoundSelectionView: View {
    @Binding var selectedSound: String
    let sounds = ["kind", "modan", "siren"]
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        Form {
            Section("アラーム音") {
                ForEach(sounds, id: \.self) { sound in
                    HStack {
                        Button {
                            selectedSound = sound
                        } label: {
                            HStack {
                                Label(sound, systemImage: "speaker.wave.2")
                                Spacer()
                                if sound == selectedSound {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppDesign.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            preview(sound)
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(sound)を試聴")
                    }
                }
            }

            Section {
                AdListClearance()
            } footer: {
                Text("タップすると試聴できます")
            }
            .listRowBackground(Color.clear)
        }
        .tint(AppDesign.tint)
        .scrollContentBackground(.hidden)
        .background(AppDesign.background)
        .navigationTitle("サウンド")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func preview(_ sound: String) {
        guard let url = Bundle.main.url(forResource: sound, withExtension: "mp3") else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                audioPlayer?.stop()
            }
        } catch {
            print("Error playing sound: \(error.localizedDescription)")
        }
    }
}

struct RepeatWeekdaySelectionView: View {
    @Binding var selectedWeekdays: Set<Int>
    let days = ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]
    let shortDays = ["日", "月", "火", "水", "木", "金", "土"]

    private var selectedDaySummary: String {
        let selected = selectedWeekdays.sorted().map { shortDays[$0] }
        return selected.isEmpty ? "繰り返さない" : selected.joined(separator: "・") + "曜日"
    }

    var body: some View {
        Form {
            Section("繰り返し") {
                Button {
                    selectedWeekdays.removeAll()
                } label: {
                    HStack {
                        Text("繰り返さない")
                        Spacer()
                        if selectedWeekdays.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppDesign.tint)
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(0..<days.count, id: \.self) { index in
                    Button {
                        if selectedWeekdays.contains(index) {
                            selectedWeekdays.remove(index)
                        } else {
                            selectedWeekdays.insert(index)
                        }
                    } label: {
                        HStack {
                            Text(days[index])
                            Spacer()
                            if selectedWeekdays.contains(index) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppDesign.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selectedWeekdays.contains(index) ? "選択済み" : "未選択")
                }
            }

            Section {
                AdListClearance()
            } footer: {
                Text(selectedWeekdays.isEmpty ? "繰り返さない場合は、次回の到着時に一度だけお知らせします。" : "\(selectedDaySummary)に、到着をお知らせします。")
            }
            .listRowBackground(Color.clear)
        }
        .tint(AppDesign.tint)
        .scrollContentBackground(.hidden)
        .background(AppDesign.background)
        .navigationTitle("繰り返し")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
