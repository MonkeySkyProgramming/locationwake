import UIKit

class OnboardingViewController: UIViewController, UIScrollViewDelegate {

    var isFromHelpButton: Bool = false

    // 事前にアセットカタログに追加しておいた画像名の配列
    let images = ["AppStore1", "AppStore2", "AppStore3", "AppStore4", "AppStore5"]
    var scrollView: UIScrollView!
    var pageControl: UIPageControl!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        
        // UIScrollView の作成と設定
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isPagingEnabled = true
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // 各ページ（画像＋ボタン）を追加
        var previousPage: UIView? = nil
        for (index, imageName) in images.enumerated() {
            let pageView = UIView()
            pageView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(pageView)
            
            // 横に並べるための制約
            NSLayoutConstraint.activate([
                pageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
                pageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                pageView.widthAnchor.constraint(equalTo: view.widthAnchor),
                pageView.heightAnchor.constraint(equalTo: view.heightAnchor)
            ])
            if let previous = previousPage {
                pageView.leadingAnchor.constraint(equalTo: previous.trailingAnchor).isActive = true
            } else {
                pageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor).isActive = true
            }
            if index == images.count - 1 {
                pageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor).isActive = true
            }
            previousPage = pageView
            
            // 画像を表示する UIImageView を追加（画面の80%の大きさに設定）
            let imageView = UIImageView(image: UIImage(named: imageName))
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            pageView.addSubview(imageView)
            
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: pageView.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: pageView.centerYAnchor, constant: -40), // 少し上に配置してボタンスペース確保
                imageView.widthAnchor.constraint(equalTo: pageView.widthAnchor, multiplier: 0.8),
                imageView.heightAnchor.constraint(equalTo: pageView.heightAnchor, multiplier: 0.8)
            ])
            
            // 「Next」または「Get Started」ボタンを追加
            let nextButton = UIButton(type: .system)
            nextButton.translatesAutoresizingMaskIntoConstraints = false
            let buttonTitle = (index == images.count - 1) ? "終了" : "次へ"
            nextButton.setTitle(buttonTitle, for: .normal)
            nextButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
            nextButton.backgroundColor = .systemBlue
            nextButton.setTitleColor(.white, for: .normal)
            nextButton.layer.cornerRadius = 8
            nextButton.tag = index  // 現在のページインデックスをタグとして保存
            nextButton.addTarget(self, action: #selector(nextButtonTapped(_:)), for: .touchUpInside)
            pageView.addSubview(nextButton)
            
            NSLayoutConstraint.activate([
                nextButton.bottomAnchor.constraint(equalTo: pageView.safeAreaLayoutGuide.bottomAnchor, constant: -40),
                nextButton.centerXAnchor.constraint(equalTo: pageView.centerXAnchor),
                nextButton.widthAnchor.constraint(equalToConstant: 200),
                nextButton.heightAnchor.constraint(equalToConstant: 50)
            ])
        }
        
        // UIPageControl の設定（任意）
        pageControl = UIPageControl()
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = images.count
        pageControl.currentPage = 0
        view.addSubview(pageControl)
        
        NSLayoutConstraint.activate([
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    // ボタンタップ時の処理：次のページへスクロール、またはオンボーディング終了
    @objc func nextButtonTapped(_ sender: UIButton) {
        let currentIndex = sender.tag
        if currentIndex < images.count - 1 {
            let nextOffset = CGPoint(x: view.frame.width * CGFloat(currentIndex + 1), y: 0)
            scrollView.setContentOffset(nextOffset, animated: true)
        } else {
            if !isFromHelpButton {
                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
            }
            dismiss(animated: true, completion: nil)
        }
    }
    
    // UIScrollViewDelegate：スクロールに合わせて PageControl のページを更新
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let page = round(scrollView.contentOffset.x / view.frame.width)
        pageControl.currentPage = Int(page)
    }
}
