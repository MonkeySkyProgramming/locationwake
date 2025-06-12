import UIKit

class SettingsViewController: BaseViewController, UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak var tableView: UITableView!
    
    let settingsItems = ["通知回数", "プライバシーポリシー"]

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        self.title = "設定"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return settingsItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        cell.textLabel?.text = settingsItems[indexPath.row]
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.row {
        case 0:
            // 通知回数設定の処理
            showNotificationCountPicker()
        case 1:
            // プライバシーポリシーの表示処理
            showPrivacyPolicy()
        default:
            break
        }
    }
    
    // 通知回数設定用のピッカーを表示する処理
    func showNotificationCountPicker() {
        let alert = UIAlertController(title: "通知回数設定", message: "\n\n\n\n\n\n", preferredStyle: .alert)
        
        let pickerFrame = UIPickerView(frame: CGRect(x: 5, y: 20, width: 250, height: 140))
        pickerFrame.dataSource = self
        pickerFrame.delegate = self
        
        alert.view.addSubview(pickerFrame)
        
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "設定", style: .default, handler: { action in
            let selectedRow = pickerFrame.selectedRow(inComponent: 0)
            let selectedValue = self.notificationValues[selectedRow]
            // 通知回数を保存する処理
            print("通知回数が \(selectedValue) に設定されました")
        }))
        
        present(alert, animated: true, completion: nil)
    }

    // プライバシーポリシーを表示する処理
    func showPrivacyPolicy() {
        if let url = URL(string: "https://monkeyskyprogramming.github.io/wakeprivacy/") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    @objc func hidePrivacyPolicy() {
        UIView.animate(withDuration: 0.5, animations: {
            if let scrollView = self.view.subviews.last as? UIScrollView {
                scrollView.frame.origin.y = self.view.frame.height
            }
        }) { _ in
            self.view.subviews.last?.removeFromSuperview()
        }
    }
    
    var notificationValues = ["1回", "2回", "3回", "4回", "5回"]
}

// UIPickerViewのデリゲートとデータソースの実装
extension SettingsViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return notificationValues.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return notificationValues[row]
    }
}
