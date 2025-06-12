import UIKit
import MapKit

class LocationSelectionViewController: BaseViewController, MKMapViewDelegate ,UISearchBarDelegate,UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var tableView: UITableView!
    
    var selectedLocation: CLLocationCoordinate2D?
    var searchBar: UISearchBar!
    var matchingItems: [MKMapItem] = []
    var placeholderLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LocationCell")

        mapView.delegate = self
        tableView.delegate = self
        tableView.dataSource = self

        // 検索バーをセットアップ
        setupSearchBar()
        setupPlaceholderLabel()
        
    }

    // 検索バーをナビゲーションバーに表示する設定
    func setupSearchBar() {
        if let navigationBarFrame = navigationController?.navigationBar.bounds {
            let searchBar = UISearchBar(frame: navigationBarFrame)
            searchBar.delegate = self
            searchBar.searchBarStyle = .minimal
            searchBar.backgroundColor = .clear
            searchBar.barTintColor = .clear
            searchBar.searchTextField.backgroundColor = .white
            searchBar.placeholder = "場所を検索"
            searchBar.tintColor = UIColor.gray
            searchBar.keyboardType = .default
            navigationItem.titleView = searchBar
            navigationItem.titleView?.frame = searchBar.frame
            self.searchBar = searchBar
        }
    }

    // プレースホルダーラベルをセットアップ
    private func setupPlaceholderLabel() {
        placeholderLabel = UILabel()
        placeholderLabel.text = "検索結果がここに表示されます"
        placeholderLabel.textColor = .lightGray
        placeholderLabel.textAlignment = .center
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        tableView.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: tableView.leadingAnchor, constant: 20),
            placeholderLabel.trailingAnchor.constraint(equalTo: tableView.trailingAnchor, constant: -20)
        ])
    }

    // 検索バーの編集が開始された時、キャンセルボタンを表示
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        searchBar.showsCancelButton = true
        return true
    }

    // キャンセルボタンが押された時、検索バーをキャンセルしてフォーカスを外す
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.showsCancelButton = false
        searchBar.resignFirstResponder()
    }

    // 検索バーに入力があったときの処理
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let searchText = searchBar.text else { return }
        performSearch(searchText: searchText)
        searchBar.resignFirstResponder()
    }

    // MKLocalSearchを使った場所検索
    func performSearch(searchText: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = mapView.region
        
        let search = MKLocalSearch(request: request)
        search.start { (response, error) in
            guard let response = response else {
                print("Error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            // 検索結果をマップとテーブルに表示
            self.matchingItems = response.mapItems
            self.mapView.removeAnnotations(self.mapView.annotations) // 既存のピンを削除
            self.updateMapAnnotations()  // マップにアノテーションを追加
            self.tableView.reloadData()
            self.placeholderLabel.isHidden = !self.matchingItems.isEmpty
        }
    }

    // マップにアノテーションを追加するメソッド
    private func updateMapAnnotations() {
        mapView.removeAnnotations(mapView.annotations)
        for item in matchingItems {
            let annotation = MKPointAnnotation()
            annotation.title = item.name
            annotation.coordinate = item.placemark.coordinate
            mapView.addAnnotation(annotation)

            // 検索結果が1つだけの場合は、その場所にズームインする
            if matchingItems.count == 1 {
                let region = MKCoordinateRegion(center: annotation.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
                mapView.setRegion(region, animated: true)
            }
        }
        
        // 複数の検索結果がある場合は、全てのアノテーションを含む領域にズームアウトする
        if matchingItems.count > 1 {
            mapView.showAnnotations(mapView.annotations, animated: true)
        }
    }

    // UITableViewDataSourceメソッド - 検索結果をテーブルに表示
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return matchingItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LocationCell", for: indexPath)
        let selectedItem = matchingItems[indexPath.row].placemark
        cell.textLabel?.text = selectedItem.name
        cell.detailTextLabel?.text = selectedItem.title
        return cell
    }

    // UITableViewDelegateメソッド - 検索結果がタップされたときの処理
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedItem = matchingItems[indexPath.row].placemark
        selectedLocation = selectedItem.coordinate

        // 選択された場所にピンを立てる
        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = selectedItem.coordinate
        annotation.title = selectedItem.name
        mapView.addAnnotation(annotation)

        // 次の画面に遷移する処理
        let alarmDetailVC = storyboard?.instantiateViewController(withIdentifier: "AlarmDetailViewController") as! AlarmDetailViewController
        alarmDetailVC.selectedLocation = selectedItem.coordinate
        alarmDetailVC.selectedLocationName = selectedItem.name  // 場所の名前を渡す
        navigationController?.pushViewController(alarmDetailVC, animated: true)
    }
}
