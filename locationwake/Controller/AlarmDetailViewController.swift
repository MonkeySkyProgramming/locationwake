import UIKit
import CoreLocation
import MapKit
import AVFoundation

protocol AlarmDetailViewControllerDelegate: AnyObject {
    func didSaveAlarm(_ alarm: Alarm)
}

class AlarmDetailViewController: BaseViewController, CLLocationManagerDelegate, MKMapViewDelegate {

    // UI部品のアウトレット接続
    @IBOutlet weak var alarmNameTextField: UITextField!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var rangeSlider: UISlider!
    @IBOutlet weak var radiusLabel: UILabel!
    @IBOutlet weak var soundSelectionButton: UIButton!
    @IBOutlet weak var soundSwitch: UISwitch!
    
    var alarm: Alarm?
    var locationManager: CLLocationManager!
    var selectedLocation: CLLocationCoordinate2D?
    var selectedRadius: Double?
    var selectedSoundFileName: String?
    var selectedLocationName: String?
    weak var delegate: AlarmDetailViewControllerDelegate?
    
    let soundPlayer = SoundPlayer.shared

    let repeatSelectionButton = UIButton(type: .system)
    var selectedRepeatWeekdays: Set<Int> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLocationManager()
        mapView.delegate = self
        
        if let alarm = alarm {
            // アラーム名をテキストフィールドに設定
            alarmNameTextField.text = alarm.name
            
            // アラームに関連する位置情報が存在する場合
            if let location = alarm.location {
                selectedLocation = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                selectedRadius = alarm.radius
            }
            
            // アラーム音をボタンに反映
            selectedSoundFileName = alarm.sound
            soundSelectionButton.setTitle(alarm.sound, for: .normal)
            selectedRepeatWeekdays = Set(alarm.repeatWeekdays ?? [])
        }
        
        // 位置名が設定されている場合、テキストフィールドに表示
        if let locationName = selectedLocationName {
            alarmNameTextField.text = locationName
        }
        
        // スライダーの初期値を設定（半径に基づく）
        let initialRadius = selectedRadius ?? 3000
        selectedRadius = initialRadius
        rangeSlider.value = Float(initialRadius) / 10000
        updateRadiusLabel(withRadius: initialRadius)
        
        // アラームスイッチの初期状態を設定
        soundSwitch.isOn = alarm?.isSoundEnabled ?? false
        soundSwitch.addTarget(self, action: #selector(alarmSwitchToggled(_:)), for: .valueChanged)
        
        // ナビゲーションバーに保存ボタンを追加
        let saveButton = UIBarButtonItem(title: "保存", style: .done, target: self, action: #selector(saveButtonTapped))
        navigationItem.rightBarButtonItem = saveButton

        setupRepeatSelectionButton()

        // updateMapDisplay(withRadius: initialRadius) // moved to viewDidAppear

        updateRepeatButtonTitle()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let radius = selectedRadius {
            updateMapDisplay(withRadius: radius)
        }
    }

    // 音声選択ボタンが押されたときの処理
    @IBAction func soundSelectionButtonTapped(_ sender: UIButton) {
        // 音声選択のためのアラートシートを表示
        let alertController = UIAlertController(title: "アラーム音を選択", message: nil, preferredStyle: .actionSheet)

        // 再生可能な音声ファイル名のリスト
        let soundOptions = ["modan", "siren", "kind"]
        
        // 各音声オプションをアラートシートに追加
        for soundOption in soundOptions {
            let action = UIAlertAction(title: soundOption, style: .default) { [weak self] _ in
                // 選択された音声ファイル名を保存
                self?.selectedSoundFileName = soundOption
                // 音声を再生
                self?.playSound(named: soundOption)
                // ボタンのタイトルを選択された音声名に変更
                self?.soundSelectionButton.setTitle(soundOption, for: .normal)
                // アラームスイッチをオンにする
                self?.soundSwitch.isOn = true
            }
            alertController.addAction(action)
        }
        
        // キャンセルボタン
        alertController.addAction(UIAlertAction(title: "キャンセル", style: .cancel, handler: nil))
        
        // アラートシートを表示
        present(alertController, animated: true, completion: nil)
    }
    
    @objc func alarmSwitchToggled(_ sender: UISwitch) {
        // スイッチの状態に応じて処理を行う
        if sender.isOn {
            print("スイッチがオンになりました")
        } else {
            print("スイッチがオフになりました")
        }
    }

    // 音声再生メソッド
    func playSound(named soundName: String) {
        soundPlayer.play(soundName: soundName, forDuration: 5) // 5秒間再生
    }
    
    // 保存ボタンが押されたときの処理
    @objc func saveButtonTapped() {
        let alarmName = alarmNameTextField.text ?? "New Alarm"
        let soundIsEnabled = soundSwitch.isOn
        
        guard let location = selectedLocation else {
            print("位置情報が選択されていません")
            return
        }

        let latitude = location.latitude
        let longitude = location.longitude
        let radius = selectedRadius ?? 3000
        let sound = selectedSoundFileName ?? "未設定"

        let newAlarm = Alarm(
            name: alarmName,
            repeatWeekdays: Array(selectedRepeatWeekdays).sorted(),
            sound: sound ,
            isAlarmEnabled: true,
            isSoundEnabled: soundIsEnabled,
            location: Location(latitude: latitude, longitude: longitude),
            radius: radius
        )

        saveAlarmSetting(newAlarm)
        delegate?.didSaveAlarm(newAlarm)
        // アラーム情報をデバッグ出力
        print("アラーム名: \(alarmName)")
        print("半径: \(radius)")
        print("緯度: \(latitude), 経度: \(longitude)")
        print("アラーム音: \(sound)")
        print("アラーム音のオンかどうか: \(soundIsEnabled)")

        // 保存後にAlarmListViewControllerに戻る
        if let alarmListVC = navigationController?.viewControllers.first(where: { $0 is AlarmListViewController }) {
            navigationController?.popToViewController(alarmListVC, animated: true)
        }
    }

    // アラーム設定を保存する処理
    func saveAlarmSetting(_ alarm: Alarm) {
        var savedAlarms = loadSavedAlarms()
        if let index = savedAlarms.firstIndex(where: { $0.name == alarm.name }) {
            savedAlarms[index] = alarm
        } else {
            savedAlarms.append(alarm)
        }

        saveAlarmsToUserDefaults(savedAlarms)
    }

    // UserDefaultsにアラーム設定を保存する
    func saveAlarmsToUserDefaults(_ alarms: [Alarm]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(alarms) {
            UserDefaults.standard.set(encoded, forKey: "SavedAlarms")
        }
    }

    // UserDefaultsからアラーム設定を読み込む
    func loadSavedAlarms() -> [Alarm] {
        if let savedAlarmsData = UserDefaults.standard.data(forKey: "SavedAlarms") {
            let decoder = JSONDecoder()
            if let loadedAlarms = try? decoder.decode([Alarm].self, from: savedAlarmsData) {
                return loadedAlarms
            }
        }
        return []
    }

    // マップの更新処理
    func updateMapDisplay(withRadius radius: CLLocationDistance) {
        guard let coordinate = selectedLocation else { return }
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)

        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        mapView.addAnnotation(annotation)

        let circle = MKCircle(center: coordinate, radius: radius)
        mapView.addOverlay(circle)

        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        mapView.setRegion(region, animated: true)
    }

    // CLLocationManagerの設定
    func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
    }

    // MKMapViewDelegateのオーバーレイ描画処理
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let circleOverlay = overlay as? MKCircle {
            let circleRenderer = MKCircleRenderer(circle: circleOverlay)
            circleRenderer.fillColor = UIColor.blue.withAlphaComponent(0.2)
            circleRenderer.strokeColor = .blue
            circleRenderer.lineWidth = 1
            return circleRenderer
        }
        return MKOverlayRenderer()
    }

    // スライダー変更時の半径更新処理
    @IBAction func rangeSliderChanged(_ sender: UISlider) {
        let radius = calculateRadius(forValue: sender.value)
        selectedRadius = radius
        updateRadiusLabel(withRadius: radius)
        updateMapDisplay(withRadius: radius)
    }

    // 半径を計算
    func calculateRadius(forValue value: Float) -> CLLocationDistance {
        return CLLocationDistance(value * 10000)
    }

    // 半径ラベルの更新
    func updateRadiusLabel(withRadius radius: CLLocationDistance) {
        let radiusInKm = radius / 1000
        radiusLabel.text = String(format: "半径: %.2f km", radiusInKm)
    }

    func setupRepeatSelectionButton() {
        repeatSelectionButton.setTitle("繰り返しを選択", for: .normal)
        repeatSelectionButton.addTarget(self, action: #selector(showRepeatSelection), for: .touchUpInside)
        repeatSelectionButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(repeatSelectionButton)
        
        NSLayoutConstraint.activate([
            repeatSelectionButton.topAnchor.constraint(equalTo: soundSelectionButton.bottomAnchor, constant: 20),
            repeatSelectionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc func showRepeatSelection() {
        let vc = RepeatSelectionViewController()
        vc.selected = selectedRepeatWeekdays
        vc.onSave = { [weak self] selected in
            self?.selectedRepeatWeekdays = selected
            self?.updateRepeatButtonTitle()
        }

        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    func updateRepeatButtonTitle() {
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        let selectedTitles = selectedRepeatWeekdays.sorted().map { weekdays[$0] }
        let title = selectedTitles.isEmpty ? "繰り返しを選択" : "繰り返し: " + selectedTitles.joined(separator: "・")
        repeatSelectionButton.setTitle(title, for: .normal)
    }
}

class RepeatSelectionViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    var weekdays = ["日", "月", "火", "水", "木", "金", "土"]
    var selected: Set<Int> = []
    var onSave: ((Set<Int>) -> Void)?

    let tableView = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "繰り返し"

        tableView.delegate = self
        tableView.dataSource = self
        tableView.frame = view.bounds
        view.addSubview(tableView)

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完了", style: .done, target: self, action: #selector(doneTapped))
    }

    @objc func doneTapped() {
        onSave?(selected)
        dismiss(animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        weekdays.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.textLabel?.text = weekdays[indexPath.row]
        cell.accessoryType = selected.contains(indexPath.row) ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if selected.contains(indexPath.row) {
            selected.remove(indexPath.row)
        } else {
            selected.insert(indexPath.row)
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
}
