import UIKit

final class RollingBannerView: UIView, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private var data: DI_TImageBanner?
    private var cellType: BaseCollectionViewCell.Type? {
        didSet {
            if let cellType {
                self.collectionView.register(cellType)
            }
            else {
                self.collectionView.register(BaseCollectionViewCell.self)
            }
        }
    }
    private var itemSpacing: CGFloat = 0.0
    private var sideInsets: UIEdgeInsets = .zero
    private var clickLog: DIR_ClickLog?
    private var displayMallInfo: DI_DisplayMallInfo = ServiceManager.shared.topDisplayMallInfo
    private var timeInterval: TimeInterval = 3.0
    private var impressionDic: [Int: Bool] = [:]
    private var impressionPended: [DIR_DIReactingLog] = []
    private var isAlwaysSend: Bool = true

    var cellActionClosure: ((String, Any?) -> Void)?
    // 전체버튼 액션
    var allButtonClosure: (() -> Void)?
    // 자동재생/정지 액션
    var autoRollingButtonClosure: (() -> Void)?
    // 리액팅 생성
    var impressionClosure: ((Int) -> DIR_ClickLog)?

    // 스크롤 되는동안 호출
    var scrollClosure: ((UICollectionView) -> Void)?
    // 스크롤중 인덱스가 바뀔때만 호출
    var scrollIndexClosure: ((Int) -> Void)?
    // 셀이 등장할때 호출
    var cellDisplayClosure: ((UICollectionView, UICollectionViewCell) -> Void)?
    // 스크롤 끝나면 호출
    var scrollFinishClosure: ((UICollectionView) -> Void)?

    private var isInfinite: Bool = true
    private var isBannerAutoRolling: Bool = false
    private weak var timer: Timer?
    private var pageIndex: Int = 0

    deinit {
        self.timer?.invalidate()
        self.timer = nil
    }

    private var collectionView: UICollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

    private var pageControlBoxType: BaseRollingControlView.Type?
    lazy var pageControlBoxView: BaseRollingControlView? = {
        guard let pageControlBoxType else { return nil }
        let pcbView = pageControlBoxType.init()
        self.addSubview(pcbView)
        pcbView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pcbView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            pcbView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            pcbView.heightAnchor.constraint(equalToConstant: 32),
            pcbView.widthAnchor.constraint(equalToConstant: 102)
        ])
        return pcbView
    }()

    func configure(
        data: DI_TImageBanner?,
        cellType: BaseCollectionViewCell.Type,
        itemSpacing: CGFloat,
        sideInsets: UIEdgeInsets,
        clickLog: DIR_ClickLog? = nil,
        isAlwaysSend: Bool = true,
        timeInterval: TimeInterval = 3.0,
        pageControlBoxType: BaseRollingControlView.Type? = nil,
        displayMallInfo: DI_DisplayMallInfo,
        cellActionClosure: ((String, Any?) -> Void)? = nil
    ) {
        guard let data else { return }
        self.data = data
        self.cellType = cellType
        self.sideInsets = sideInsets
        self.itemSpacing = itemSpacing
        self.clickLog = clickLog
        self.isAlwaysSend = isAlwaysSend
        self.timeInterval = timeInterval
        self.pageControlBoxType = pageControlBoxType
        self.displayMallInfo = displayMallInfo
        self.setupCollectionView()
        self.setupPageControl()
        self.setSelfHeight()
    }

    private func setSelfHeight() {
        let collectionViewHeight = self.getRollingBannerSize(width: self.frame.width).height
        self.height = collectionViewHeight
        if self.ec.isHeight {
            self.ec.height = collectionViewHeight
        }
    }

    private func setupPageControl() {
        guard let pageControlBoxView, let data else { return }
        pageControlBoxView.isHidden = data.banrList.count <= 1
        pageControlBoxView.configure(data: data.cvPageControlData, clickLog: self.clickLog) { [weak self] actionType, actionData in
            guard let self,
                  let actionData = actionData as? UI_RollingControlView,
                  let actionName = RollingControlViewEvent(rawValue: actionType) else { return }
            switch actionName {
            case .showAll:
//                self.onShowAllButton()
                self.allButtonClosure?()
            case .autoRolling:
//                self.onAutoRollingButton(actionData: actionData)
                self.autoRollingButtonClosure?()
                self.isBannerAutoRolling = actionData.isAutoRolling
                if actionData.isAutoRolling {
                    self.startAutoRolling()
                }
            default:
                break
            }
        }
    }

    private func setupCollectionView() {
        guard let data, data.banrList.count > 0 else { return }
        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.isPagingEnabled = false
        self.collectionView.decelerationRate = .fast
        self.collectionView.showsHorizontalScrollIndicator = false
        self.addSubViewAutoLayout(collectionView)

        if data.banrList.count <= 1 {
            self.isInfinite = false
            self.isAlwaysSend = false
        }
        if let layout = self.collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.scrollDirection = .horizontal
            layout.minimumInteritemSpacing = 0
            layout.sectionInset = self.sideInsets
            layout.minimumLineSpacing = self.itemSpacing
        }
        self.collectionView.reloadData()
        self.startAutoRolling()
    }

    private func onMovieAction(actionType: String) {
        guard let data else { return }
        if let action = MovieViewState(rawValue: actionType) {
            switch action {
            case .autoPlaying:
                // 동영상의 자동 재생일 경우 오토롤링은 일단 끄고 노티받으면 켜준다.
                self.isBannerAutoRolling = false
            case .playEnd:
                // 동영상이 모두 재생된 후 메인 롤링 넘어가야 한다.(GRCR011 1-1)
                if let isAutoRolling = data.cvPageControlData?.isAutoRolling {
                    self.isBannerAutoRolling = isAutoRolling
                    if isAutoRolling {
                        self.startAutoRolling()
                    }
                }
            default:
                break
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let data else { return .zero }
        var count = data.banrList.count
        if self.isInfinite {
            count = data.banrList.count * 3
        }
        return count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let data, data.banrList.count > 0, let cellType else { return BaseCollectionViewCell() }
        let cell = collectionView.dequeueReusableCell(cellType, for: indexPath)
        var index = indexPath.row
        if self.isInfinite {
            index = indexPath.row % data.banrList.count
        }
        cell.actionClosure = { [weak self] actionType, _ in
            guard let self else { return }
            self.onMovieAction(actionType: actionType)
        }
        let logData = self.setClickLog(index: index, banr: data.banrList[safe: index])
        cell.configure(data: data.banrList[safe: index], clickLog: logData)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if let layout = collectionViewLayout as? UICollectionViewFlowLayout {
            layout.itemSize = CGSize(width: collectionView.frame.width - self.sideInsets.left - self.sideInsets.right, height: collectionView.frame.height)
        }
        return CGSize(width: collectionView.frame.width - self.sideInsets.left - self.sideInsets.right, height: collectionView.frame.height)
    }

    // 페이징
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard let scrollView = scrollView as? UICollectionView else { return }
        guard let flowLayout = scrollView.collectionViewLayout as? UICollectionViewFlowLayout else { return }

        let cellWidthIncludingSpacing = flowLayout.itemSize.width + flowLayout.minimumLineSpacing
        let currentOffset = scrollView.contentOffset.x
        let velocityX = velocity.x
        var newPageOffset = currentOffset
        if velocityX < 0.0 {
            // Moving left
            newPageOffset = floor(currentOffset / cellWidthIncludingSpacing) * cellWidthIncludingSpacing
        }
        else if velocityX > 0.0 {
            // Moving right
            newPageOffset = ceil(currentOffset / cellWidthIncludingSpacing) * cellWidthIncludingSpacing

        }
        else {
            // No significant velocity, snap to nearest page
            newPageOffset = round(currentOffset / cellWidthIncludingSpacing) * cellWidthIncludingSpacing
        }

        targetContentOffset.pointee = CGPoint(x: newPageOffset, y: 0)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.stopAutoRolling()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard let scrollView = scrollView as? UICollectionView else { return }
        self.scrollFinishClosure?(scrollView)
        if self.isBannerAutoRolling {
            self.startAutoRolling()
        }
    }

    // 무한 옮겨주기
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let collectionView = scrollView as? UICollectionView else { return }
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        guard let data, data.banrList.count > 0 else { return }
        let contentOffset = collectionView.contentOffset
        let pageSize = layout.itemSize.width + layout.minimumLineSpacing
        if isInfinite {
            let maxX = pageSize * CGFloat(data.banrList.count * 2)
            let minX = pageSize * CGFloat(data.banrList.count)
            if contentOffset.x > maxX {
                collectionView.contentOffset = CGPoint(x: contentOffset.x - pageSize * CGFloat(data.banrList.count), y: 0)
            }
            else if contentOffset.x < minX {
                collectionView.contentOffset = CGPoint(x: contentOffset.x + pageSize * CGFloat(data.banrList.count), y: 0)
            }
        }

        self.scrollClosure?(collectionView)

        let pageIndex = Int(round(contentOffset.x / pageSize)) % data.banrList.count
        guard self.pageIndex != pageIndex else { return }
        self.pageIndex = pageIndex
        self.scrollIndexClosure?(pageIndex)
        guard let pageControlData = data.cvPageControlData else { return }
        if pageControlData.isAutoRolling {
            self.isBannerAutoRolling = pageControlData.isAutoRolling
        }
        data.cvCurrentIndex = pageIndex
        pageControlData.currentPageIndex = pageIndex
        self.pageControlBoxView?.updateData(data: pageControlData)
    }

    // 중앙 보내기
    private var beforeWidth: CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let data, data.banrList.count > 0 else { return }
        guard beforeWidth != self.frame.width else { return }
        beforeWidth = self.frame.width
        if self.isInfinite {
            self.collectionView.scrollToItem(at: IndexPath(row: data.banrList.count, section: 0), at: .centeredHorizontally, animated: false)
        }
    }

    // 다음 페이지로 이동, 자동롤링
    private func toNextPage() {
        guard let data, data.banrList.count > 0 else { return }
        let currentOffset = self.collectionView.contentOffset.x
        let targetOffset: CGFloat
        if let layout = self.collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            targetOffset = currentOffset + layout.itemSize.width
        }
        else {
            targetOffset = currentOffset + self.collectionView.frame.width
        }
        self.collectionView.setContentOffset(CGPoint(x: targetOffset, y: self.collectionView.contentOffset.y), animated: true)
    }

    private func isCellVisible() -> Bool {
        guard let window = self.window else { return false }

        var currentView: UIView = self
        while let superview = currentView.superview {
            if window.bounds.intersects(currentView.windowFrame) == false {
                return false
            }

            if (superview.bounds).intersects(currentView.frame) == false {
                return false
            }

            if currentView.isHidden {
                return false
            }

            if currentView.alpha == 0 {
                return false
            }

            currentView = superview
        }

        return true
    }

    private func startAutoRolling() {
        guard isBannerAutoRolling else { return }
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: self.timeInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.isBannerAutoRolling, self.isCellVisible() else {
                self.stopAutoRolling()
                return
            }
            self.toNextPage()
        }
    }

    private func stopAutoRolling() {
        timer?.invalidate()
        timer = nil
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        self.cellDisplayClosure?(collectionView, cell)
        guard let cell = cell as? BaseCollectionViewCell else { return }
        self.sendImpressionLog(collectionView: collectionView, cell: cell, indexPath: indexPath)
    }

    /// PageControllBox API
    func setPageControlUI(cornerRadius: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        guard let pageControlBoxView else { return }
        pageControlBoxView.cornerRadius = cornerRadius
        pageControlBoxView.ec.bottom = bottom
        pageControlBoxView.ec.trailing = trailing
    }

    // 롤링배너뷰 의 높이(배너중 최대높이)를 리턴
    func getRollingBannerSize(width: CGFloat) -> CGSize {
        guard let data, data.banrList.count > 0, let cellType, let layout = self.collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return .zero }
        if data.cvFirstItemSize != .zero {
            return data.cvFirstItemSize
        }
        let cellWidth = width - self.sideInsets.left - self.sideInsets.right
        let height: CGFloat = layout.sectionInset.top + layout.sectionInset.bottom
        var cellHeight: CGFloat = 0
        for banr in data.banrList {
            let newCellHeight = cellType.getSize(data: banr, width: cellWidth).height
            if cellHeight < newCellHeight {
                cellHeight = newCellHeight
            }
        }
        data.cvFirstItemSize = CGSize(width: width, height: height + cellHeight)
        return CGSize(width: width, height: height + cellHeight)
    }

    private func sendImpressionLog(collectionView: UICollectionView, cell: BaseCollectionViewCell, indexPath: IndexPath) {
        guard let clickLog = cell.clickLog, let data, data.banrList.count > 0 else { return }
        print("221231 !!!! sendImpressionLog")
        for var diImpressionLog in clickLog.diImpressionLogs {
            var index = indexPath.row
            if isInfinite {
                index = indexPath.row % data.banrList.count
            }
            if diImpressionLog?.isAlwaysSend == true || self.impressionDic[index] == false {
                if collectionView.isVisible {
                    diImpressionLog?.sendLog()
                    self.impressionDic[index] = true
                    print("221231 !!!! sendImpressionLog index: \(index) \(self.impressionDic[index]) set")
                }
            }
        }
        if DI_UserDefault.isDiReactionLogShow {
            diImpressionLogShowLabel(view: cell, clickLog: clickLog)
        }
    }

    private func diImpressionLogShowLabel(view: ImpressionLabelProtocol, clickLog: DIR_ClickLog?) {
        view.resetImpressionLabels()
        if let clickLog, clickLog.diImpressionLogs.count > 0 {
            for diImpressionLog in clickLog.diImpressionLogs {
                guard let diImpressionLog else { continue }
                let label = view.getImpressionUseAbleLabel()
                label.isHidden = false
                label.text = "\(diImpressionLog.data.tarea_dtl_cd)"
                label.tag_value = diImpressionLog
                if diImpressionLog.data.tarea_dtl_cd == .t00000 {
                    label.backgroundColor = UIColor(r: 129, g: 79, b: 227, a: 0.7)
                    if diImpressionLog.data.tarea_dtl_info.advert_yn == "Y" {
                        label.adsview0.isHidden = false
                    }
                }
                else if diImpressionLog.data.tarea_dtl_cd == .t10000 {
                    label.backgroundColor = UIColor(r: 191, g: 180, b: 92, a: 0.7)
                    if diImpressionLog.data.tarea_dtl_info.advert_yn == "Y" {
                        label.adsview1.isHidden = false
                    }
                }
                label.sizeToFit()
            }
        }

        view.impressionLabels.forEachEnumerated { offset, label in
            if label.isHidden == false {
                label.y = (CGFloat(offset) * (label.h)) + 3
                view.bringSubviewToFront(label)
            }
        }
    }

    private func setClickLog(index: Int, banr: DI_TImageBannerUnit?) -> DIR_ClickLog {
        guard let banr else { return DIR_ClickLog() }
        var logData = self.clickLog
        logData?.diImpressionLogs.removeAll()
        var clickLog = self.clickLog
        clickLog?.diReactingLog?.data.tarea_dtl_info.unit_inx = "\(index)"
        clickLog?.diReactingLog?.data.tarea_dtl_cd = .t10000
        banr.setDIReactionLog(&clickLog)
        clickLog?.diReactingLog?.isAlwaysSend = self.isAlwaysSend
        logData?.diImpressionLogs.append(clickLog?.diReactingLog)
        return logData ?? DIR_ClickLog()
    }
}
