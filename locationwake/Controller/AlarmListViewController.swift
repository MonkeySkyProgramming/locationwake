import UIKit
import CoreLocation

class AlarmListViewController: BaseViewController, UITableViewDelegate, UITableViewDataSource, AlarmDetailViewControllerDelegate, CLLocationManagerDelegate, AlarmTableViewCellDelegate ,LocationManagerDelegate{
    
    
    // UITableViewをIBOutletとして接続
    @IBOutlet weak var tableView: UITableView!
    
    var alarms: [Alarm] = []
    var locationManager: CLLocationManager! // 追加
    var currentLocation: CLLocation? // 現在の位置情報を保持するプロパティ

    
    override func viewDidLoad() {
        super.viewDidLoad()
                
        let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
        if !hasSeenOnboarding {
            presentOnboarding()
        }

        LocationManager.shared.delegate = self // デリゲート設定

        // デリゲートとデータソースを設定
        tableView.delegate = self
        tableView.dataSource = self

        // xib ファイルを使用してカスタムセルを登録
        let nib = UINib(nibName: "AlarmTableViewCell", bundle: nil)
        tableView.register(nib, forCellReuseIdentifier: "AlarmCell")

        // locationManagerの初期化
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true  // バックグラウンドでの位置情報更新を許可
        locationManager.pausesLocationUpdatesAutomatically = false  // 位置情報更新の自動停止を無効化
        
        // 位置情報サービスの確認とリクエスト
        checkLocationAuthorization()
        
        // 通知の許可をリクエスト
        NotificationManager.shared.requestNotificationPermission()
        
        // 保存されたアラームを読み込む
        loadAlarms()
        printAlarms()
        
        
        // テーブルビューをリロードして、スイッチに反映
        tableView.reloadData()

        // 画面右下にヘルプボタン(UIButton)を追加
        let helpButton = UIButton(type: .system)
        helpButton.translatesAutoresizingMaskIntoConstraints = false
        helpButton.setImage(UIImage(systemName: "questionmark.circle"), for: .normal)
        helpButton.tintColor = .systemBlue
        helpButton.addTarget(self, action: #selector(helpButtonTapped), for: .touchUpInside)
        view.addSubview(helpButton)

        NSLayoutConstraint.activate([
            helpButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            helpButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            helpButton.widthAnchor.constraint(equalToConstant: 50),
            helpButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    func presentOnboarding() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let onboardingVC = storyboard.instantiateViewController(withIdentifier: "OnboardingViewController") as? OnboardingViewController {
            onboardingVC.modalPresentationStyle = .fullScreen
            present(onboardingVC, animated: true, completion: nil)
        }
    }
    
    // LocationManagerからのアラーム状態更新通知を受け取る
    func didUpdateAlarmStatus(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.name == alarm.name }) {
            alarms[index] = alarm
            saveAlarms()
            tableView.reloadData() // テーブルビューをリロードしてスイッチに反映
            print("アラーム \(alarm.name) の状態が更新されました")
        }
    }
    
    // 位置情報サービスの権限を確認し、必要であればリクエスト
    func checkLocationAuthorization() {
        if CLLocationManager.locationServicesEnabled() {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .restricted, .denied:
                promptForLocationServices()
            case .authorizedWhenInUse:
                // アプリ使用中のみの許可がある場合に常に許可をリクエスト
                showAlwaysAuthorizationPrompt()
                locationManager.startUpdatingLocation()
            case .authorizedAlways:
                locationManager.startUpdatingLocation()
            @unknown default:
                break
            }
        } else {
            promptForLocationServices()
        }
    }

    // 「常に許可」に設定するようユーザーに促す
    func showAlwaysAuthorizationPrompt() {
        let alertController = UIAlertController(
            title: "常に位置情報の使用許可が必要です",
            message: "このアプリでは、バックグラウンドでも位置情報を利用するために「常に許可」が必要です。",
            preferredStyle: .alert
        )
        
        let settingsAction = UIAlertAction(title: "常に許可を設定する", style: .default) { _ in
            self.locationManager.requestAlwaysAuthorization()
        }
        alertController.addAction(settingsAction)
        
        let cancelAction = UIAlertAction(title: "キャンセル", style: .cancel)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true, completion: nil)
    }

    // 位置情報の権限が変更された場合に呼ばれる
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            print("常に位置情報の利用許可が得られました。")
            locationManager.startUpdatingLocation()
        case .authorizedWhenInUse:
            print("アプリ使用中のみ位置情報の利用許可が得られました。")
            showAlwaysAuthorizationPrompt()
        case .denied, .restricted:
            print("位置情報の利用が拒否されました。")
            promptForLocationServices()
        case .notDetermined:
            print("位置情報の許可がまだ決定されていません。")
        @unknown default:
            break
        }
    }

    // 位置情報の許可が拒否された場合に設定アプリを開くよう促す
    func promptForLocationServices() {
        let alertController = UIAlertController(
            title: "位置情報サービスの許可が必要",
            message: "このアプリは位置情報を使用してアラーム機能を提供します。設定で位置情報サービスを有効にしてください。",
            preferredStyle: .alert
        )
        
        let settingsAction = UIAlertAction(title: "設定へ", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        alertController.addAction(settingsAction)
        
        let cancelAction = UIAlertAction(title: "キャンセル", style: .cancel)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true, completion: nil)
    }

    // CLLocationManagerDelegate - 位置情報の更新
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            currentLocation = location
            print("現在の位置情報: 緯度 \(location.coordinate.latitude), 経度 \(location.coordinate.longitude)")
        }
    }

    // CLLocationManagerDelegate - 位置情報の取得に失敗した場合
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("位置情報の取得に失敗しました: \(error)")
    }
    
    // 画面が再表示されたときにリストをリロード
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadAlarms()
        tableView.reloadData() // アラームリストを再読み込み
        printAlarms()
        // 画面が再表示されたときにジオフェンスの監視を再設定
        LocationManager.shared.startMonitoring(alarms: alarms)
        LocationManager.shared.printGeodefence()
        
        
        // テーブルビューをリロードして、スイッチに反映
        tableView.reloadData()
    }
    
    // AlarmListViewController.swift
    func alarmSwitchDidChange(_ cell: AlarmTableViewCell, isOn: Bool) {
        // 変更されたセルの位置を取得
        if let indexPath = tableView.indexPath(for: cell) {
            // 該当するアラームのisEnabledプロパティを更新
            alarms[indexPath.row].isAlarmEnabled = isOn
            
            // アラームリストを保存
            saveAlarms()
            
            // ログ出力や他の処理を実行
            print("アラーム \(alarms[indexPath.row].name) のスイッチが \(isOn ? "オン" : "オフ") になりました")
            
            printAlarms()
            // すべてのアラームでジオフェンスの再設定を行う
            LocationManager.shared.startMonitoring(alarms: alarms)
        }
    }

    // UITableViewDataSourceメソッドの実装
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return alarms.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // ここでセルのアンラップを安全に行う
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "AlarmCell", for: indexPath) as? AlarmTableViewCell else {
            fatalError("AlarmTableViewCellが見つかりません")
        }
        let alarm = alarms[indexPath.row]
        
        // アラーム名とスイッチの状態を設定
        cell.alarmNameLabel.text = alarm.name
        cell.alarmSwitch.isOn = alarm.isAlarmEnabled
        cell.delegate = self // デリゲートを設定
        
        return cell
    }
    
    // セルが選択されたときに設定画面に移動する処理
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let alarmDetailVC = storyboard.instantiateViewController(withIdentifier: "AlarmDetailViewController") as? AlarmDetailViewController {
            let selectedAlarm = alarms[indexPath.row]
            alarmDetailVC.alarm = selectedAlarm // 選択されたアラームを渡す
            alarmDetailVC.delegate = self
            navigationController?.pushViewController(alarmDetailVC, animated: true)
        }
    }

    // アラームを保存するメソッド
    func saveAlarms() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(alarms) {
            UserDefaults.standard.set(encoded, forKey: "SavedAlarms")
        }
    }

    // アラームをUserDefaultsから読み込むメソッド
    func loadAlarms() {
        var loaded = false

        if let savedAlarms = UserDefaults.standard.object(forKey: "SavedAlarms") as? Data {
            let decoder = JSONDecoder()
            if let loadedAlarms = try? decoder.decode([Alarm].self, from: savedAlarms) {
                alarms = loadedAlarms
                loaded = true
            }
        }

        // アラームが全く保存されてなかった場合のみサンプルを追加
        if !loaded || alarms.isEmpty {
            let sampleAlarm = Alarm(
                name: "サンプルアラーム",
                repeatDays: [],
                sound: "modan",
                isAlarmEnabled: false, // ← アラームはオフ
                isSoundEnabled: true,
                location: Location(latitude: 34.702485, longitude: 135.495951), // 大阪駅
                radius: 300.0
            )
            alarms = [sampleAlarm]
            saveAlarms()
        }
    }

    // アラームを保存・更新するメソッド
    func didSaveAlarm(_ alarm: Alarm) {
        // アラームが既に存在するか確認
        if let index = alarms.firstIndex(where: { $0.name == alarm.name }) {
            // 既存のアラームを更新
            alarms[index] = alarm
        } else {
            // 新しいアラームとして追加
            alarms.append(alarm)
        }
        
        saveAlarms()  // アラーム保存
        tableView.reloadData()
        printAlarms()
        // ジオフェンスの監視を再設定
        LocationManager.shared.startMonitoring(alarms: alarms)
        LocationManager.shared.printGeodefence()
    }

    func printAlarms() {
        print("現在のアラームリスト:")
        for alarm in alarms {
            print("アラーム名: \(alarm.name), 有効: \(alarm.isAlarmEnabled),サウンド有効: \(alarm.isSoundEnabled),  サウンド: \(alarm.sound), 半径: \(String(describing: alarm.radius))")
        }
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // 削除するアラームを取得
            let alarmToDelete = alarms[indexPath.row]
            
            // アラームをリストから削除
            alarms.remove(at: indexPath.row)
            
            // アラーム削除後のリストを保存
            saveAlarms()
            
            // 削除後のリストを確認
            print("削除後のアラームリスト: \(alarms.map { $0.name })")
            
            // ジオフェンス監視を削除したアラームに対して停止
            LocationManager.shared.stopMonitoringForAlarm(alarm: alarmToDelete)
            
            // TableViewの行を削除
            tableView.deleteRows(at: [indexPath], with: .fade)
            
            // 全てのアラームをクリアしてから最新のリストで監視を再設定
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                LocationManager.shared.startMonitoring(alarms: self.alarms)
            }
        }
    }
    // ナビゲーションバーのボタンが押されたときの処理
    @IBAction func addButtonTapped(_ sender: UIBarButtonItem) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let locationVC = storyboard.instantiateViewController(withIdentifier: "LocationSelectionViewController") as? LocationSelectionViewController {
            if let alarmDetailVC = storyboard.instantiateViewController(withIdentifier: "AlarmDetailViewController") as? AlarmDetailViewController {
                alarmDetailVC.delegate = self
                navigationController?.pushViewController(locationVC, animated: true)
            }
        }
    }

    @IBAction func settingsButtonTapped(_ sender: UIBarButtonItem) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let settingsVC = storyboard.instantiateViewController(withIdentifier: "SettingViewController") as? SettingsViewController {
            navigationController?.pushViewController(settingsVC, animated: true)
        }
    }
    
    @objc func helpButtonTapped() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let onboardingVC = storyboard.instantiateViewController(withIdentifier: "OnboardingViewController") as? OnboardingViewController {
            onboardingVC.modalPresentationStyle = .fullScreen
            onboardingVC.isFromHelpButton = true
            present(onboardingVC, animated: true, completion: nil)
        }
    }
}
