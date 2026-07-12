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
    @Environment(\.dismiss) var dismiss
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
            span: MKCoordinateSpan(
                latitudeDelta: geofenceRadius / 80000,
                longitudeDelta: geofenceRadius / 80000))))
        _isVibrationEnabled = State(initialValue: alarm.isVibrationEnabled)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(title: "アラーム設定", showsBackButton: true, backAction: {
                dismiss()
            }) {
                Button("保存") {
                    saveCurrentAlarm()
                }
                .buttonStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color("NavBarTintColor"))
            }

            Form {
                Section(header: Text("アラーム名")) {
                    TextField("アラーム名を入力", text: $alarmName)
                }

                Section(header: Text("位置情報")) {
                    Map(position: $cameraPosition) {
                        Annotation("", coordinate: selectedCoordinate) {
                            Image(systemName: "mappin")
                                .foregroundColor(.red)
                        }
                    }
                    .overlay(
                        GeometryReader { geo in
                            let mapWidth = geo.size.width
                            let metersPerPoint = (radius * 2) / (mapWidth / 1.2)  // Remove padding effect
                            let visualRadius = radius / metersPerPoint

                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: visualRadius * 2, height: visualRadius * 2)
                                Circle()
                                    .stroke(Color.blue, lineWidth: 2)
                                    .frame(width: visualRadius * 2, height: visualRadius * 2)
                            }
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .listRowInsets(EdgeInsets())
                    .onChange(of: radius) { _, newValue in
                        let paddingFactor = 1.2  // Add 20% extra margin
                        cameraPosition = .region(MKCoordinateRegion(
                            center: selectedCoordinate,
                            latitudinalMeters: newValue * 2 * paddingFactor,
                            longitudinalMeters: newValue * 2 * paddingFactor
                        ))
                    }
                    Text("緯度: \(selectedCoordinate.latitude), 経度: \(selectedCoordinate.longitude)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Section(header: Text("半径")) {
                    Slider(value: $radius, in: Alarm.minimumGeofenceRadius...Alarm.maximumGeofenceRadius, step: 100)
                    Text("\(Int(radius)) メートル")
                    Text(monitoringMethodDescription)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if let monitoringFailure {
                    Section(header: Text("到着通知を確認してください")) {
                        Text("このアラームの監視を開始できませんでした。")
                        Text(monitoringFailure)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("アラーム音")) {
                    Toggle("音を鳴らす", isOn: $isSoundEnabled)
                    NavigationLink(destination: SoundSelectionView(selectedSound: $selectedSound)) {
                        HStack {
                            Text("選択中の音")
                            Spacer()
                            Text(selectedSound)
                                .foregroundColor(.gray)
                        }
                    }
                }

                Section(header: Text("バイブレーション")) {
                    Toggle("バイブレーションを有効にする", isOn: $isVibrationEnabled)
                }

                Section(header: Text("繰り返し")) {
                    NavigationLink(destination: RepeatWeekdaySelectionView(selectedWeekdays: $repeatWeekdays)) {
                        HStack {
                            Text("選択された曜日")
                            Spacer()
                            Text(repeatWeekdays.sorted().map { ["日","月","火","水","木","金","土"][$0] }.joined(separator: ", "))
                                .foregroundColor(.gray)
                        }
                    }
                }

                // Removed the "保存" button section from the bottom of the form
            }
        }
        .padding(.bottom, 60) // Prevent overlap with AdBanner in root BaseContainerView
        .alert("アラームを追加できません", isPresented: $isAlarmLimitAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("アラームは最大\(Alarm.maximumSavedAlarms)件まで登録できます。不要なアラームを削除してください。")
        }
        .onAppear {
            monitoringFailure = UserDefaults.standard.string(forKey: "MonitoringFailure_\(alarmID)")
        }
        .navigationBarBackButtonHidden(true)
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

    private var monitoringMethodDescription: String {
        guard let geofenceMaximum = LocationManager.shared.maximumGeofenceRadius else {
            return "この設定では現在地を確認して到着をお知らせするため、電池の減りが早くなることがあります。"
        }
        let roundedMaximum = Int(geofenceMaximum)
        if radius <= geofenceMaximum {
            return "この半径では、電池への負担を抑えて到着をお知らせします。"
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
        if let userLocation = manager.location?.coordinate {
            let center = CLLocation(latitude: alarm.location?.latitude ?? 0, longitude: alarm.location?.longitude ?? 0)
            let current = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            let distance = current.distance(from: center)
            let isInside = distance <= (alarm.geofenceRadius ?? Alarm.defaultGeofenceRadius)
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

// 簡易的な音選択ビュー
struct SoundSelectionView: View {
    @Binding var selectedSound: String
    let sounds = ["kind", "modan", "siren"]
    @State private var audioPlayer: AVAudioPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(title: "サウンド選択", showsBackButton: true) {
                dismiss()
            }

            List {
                ForEach(sounds, id: \.self) { sound in
                    HStack {
                        Text(sound)
                        Spacer()
                        if sound == selectedSound {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSound = sound
                        if let url = Bundle.main.url(forResource: sound, withExtension: "mp3") {
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
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

struct RepeatWeekdaySelectionView: View {
    @Binding var selectedWeekdays: Set<Int>
    let days = ["日", "月", "火", "水", "木", "金", "土"]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(title: "繰り返し設定", showsBackButton: true) {
                dismiss()
            }

            List {
                ForEach(0..<days.count, id: \.self) { index in
                    HStack {
                        Text(days[index])
                        Spacer()
                        if selectedWeekdays.contains(index) {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedWeekdays.contains(index) {
                            selectedWeekdays.remove(index)
                        } else {
                            selectedWeekdays.insert(index)
                        }
                        print("タップした曜日: \(index)")
                        print("現在の選択: \(selectedWeekdays.sorted())")
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// 曜日選択のビュー
struct WeekdayPickerView: View {
    @Binding var selectedWeekdays: Set<Int>
    let days = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        HStack {
            ForEach(0..<7, id: \.self) { i in
                Button(action: {
                    if selectedWeekdays.contains(i) {
                        selectedWeekdays.remove(i)
                    } else {
                        selectedWeekdays.insert(i)
                    }
                    print("タップした曜日: \(i)")
                    print("現在の選択: \(selectedWeekdays.sorted())")
                }) {
                    Text(days[i])
                        .font(.caption)
                        .padding(8)
                        .background(selectedWeekdays.contains(i) ? Color.accentColor : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: selectedWeekdays) { _, newValue in
            print("選択された曜日: \(newValue.sorted())")
        }
    }
}

struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
