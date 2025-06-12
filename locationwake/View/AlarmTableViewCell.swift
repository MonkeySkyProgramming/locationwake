import UIKit

// デリゲートプロトコルを定義
protocol AlarmTableViewCellDelegate: AnyObject {
    func alarmSwitchDidChange(_ cell: AlarmTableViewCell, isOn: Bool)
}

class AlarmTableViewCell: UITableViewCell {
    
    @IBOutlet weak var alarmNameLabel: UILabel!
    @IBOutlet weak var alarmSwitch: UISwitch!
    
    // デリゲートプロパティを追加
    weak var delegate: AlarmTableViewCellDelegate?

    // スイッチが変更されたときに呼ばれるメソッド（@IBActionで接続）
    @IBAction func switchChanged(_ sender: UISwitch) {
        // デリゲートメソッドを呼び出す
        delegate?.alarmSwitchDidChange(self, isOn: sender.isOn)
    }
}
