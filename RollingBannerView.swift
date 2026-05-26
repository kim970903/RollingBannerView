import UIKit
import WiggleSDK

final class UI_RollingBannerData {
    var rollingList: [Any] = []

    var cvMaxItemSize: CGSize = .zero
    var cvCurrentIndex: Int = 0
    var cvPageControlData: UI_RollingControlView?
}

final class RollingBannerView: UIView {
    @IBInspectable var cellName: String = "" {
        didSet {
            self.cellType = swiftClassFromString(cellName).self as? BaseCollectionViewCell.Type
        }
    }
    @IBInspectable var itemSpacing: CGFloat = 0.0 {
        didSet {
            guard oldValue != self.itemSpacing else { return }
            self.updateCollectionView()
        }
    }
    @IBInspectable var leftInset: CGFloat = 0.0 {
        didSet {
            guard oldValue != self.leftInset else { return }
            self.edgeInsets.left = self.leftInset
        }
    }
    @IBInspectable var rightInset: CGFloat = 0.0 {
        didSet {
            guard oldValue != self.rightInset else { return }
            self.edgeInsets.right = self.rightInset
        }
    }
    @IBInspectable var topInset: CGFloat = 0.0 {
        didSet {
            guard oldValue != self.topInset else { return }
            self.edgeInsets.top = self.topInset
        }
    }
    @IBInspectable var bottomInset: CGFloat = 0.0 {
        didSet {
            guard oldValue != self.bottomInset else { return }
            self.edgeInsets.bottom = self.bottomInset
        }
    }
    var edgeInsets: UIEdgeInsets = .zero {
        didSet {
            guard oldValue != edgeInsets else { return }
            self.updateCollectionView()
        }
    }

    private var data: UI_RollingBannerData?
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
    private var clickLog: DIR_ClickLog?
    private var timeInterval: TimeInterval = 3.0
    private var impressionDic: [Int: Bool] = [:]
    private var impressionPended: [Int: DIR_DIReactingLog] = [:]
    private var isAlwaysSend: Bool = false

    // 전체버튼 액션
    var allButtonClosure: (() -> Void)?
    // 자동재생/정지 액션
    var autoRollingButtonClosure: (() -> Void)?

    // 스크롤 되는동안 호출
    var scrollClosure: ((UICollectionView) -> Void)?
    // 스크롤중 인덱스가 바뀔때만 호출
    var scrollIndexClosure: ((Int) -> Void)?
    // 셀이 등장할때 호출
    var cellDisplayClosure: ((UICollectionView, UICollectionViewCell) -> Void)?
    // 스크롤 끝나면 호출
    var scrollFinishClosure: ((UICollectionView, Int) -> Void)?
    var scrollFinishCellClosure: ((UICollectionView, UICollectionViewCell) -> Void)?

    // 무한롤링 여부
    private var enableInfinite: Bool = false
    private var isInfinite: Bool {
        return enableInfinite && self.data?.rollingList.count > 1
    }
    private var isBannerAutoRolling: Bool = false
    private weak var timer: Timer?
    private var pageIndex: Int = 0

    private var collectionView: UICollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

    private var pageControlBoxType: BaseRollingControlView.Type?
    private var pageControlBoxView: BaseRollingControlView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setup()
    }

    deinit {
        self.timer?.invalidate()
        self.timer = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.window != nil {
            self.startAutoRolling()
        }
    }

    private func setup() {
        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.isPagingEnabled = false
        self.collectionView.decelerationRate = .fast
        self.collectionView.showsHorizontalScrollIndicator = false
        self.viewDidAppear = {
            [weak self] isVisible in
            guard let self else { return }
            if isVisible, self.impressionPended.count > 0 {
                for dic in self.impressionPended {
                    var impression = dic.value
                    impression.sendLog()
                    self.impressionDic[dic.key] = true
                }
                self.impressionPended.removeAll()
            }

            if isVisible {
                self.startAutoRolling()
            }
        }
    }

    func configure(
        data: UI_RollingBannerData?,
        cellType: BaseCollectionViewCell.Type? = nil,
        enableInfinite: Bool = false,
        enableAutoRolling: Bool = false,
        clickLog: DIR_ClickLog?,
        isAlwaysSend: Bool = false,
        timeInterval: TimeInterval = 3.0,
        pageControlBoxType: BaseRollingControlView.Type? = nil
    ) {
        guard let data else { return }
        self.data = data
        if self.cellName.isValid == false, let cellType {
            self.cellType = cellType
        }
        self.enableInfinite = enableInfinite
        if enableAutoRolling {
            self.isBannerAutoRolling = data.cvPageControlData?.isAutoRolling ?? true
        }
        else {
            self.isBannerAutoRolling = false
            self.data?.cvPageControlData?.isAutoRolling = false
        }
        self.clickLog = clickLog
        self.isAlwaysSend = isAlwaysSend
        self.timeInterval = timeInterval
        self.pageControlBoxType = pageControlBoxType
        self.setupCollectionView()
        self.setupPageControl()
    }

    // MARK: Set function
    private func setSelfHeight() {
        let collectionViewHeight = RollingBannerView.getRollingBannerSize(width: self.frame.width, data: self.data, cellType: self.cellType, sideInsets: self.edgeInsets).height
        self.height = collectionViewHeight
        if self.ec.isHeight {
            self.ec.height = collectionViewHeight
        }
    }

    private func setupPageControl() {
        pageControlBoxView?.isHidden = true
        guard let pageControlBoxType, let data, data.rollingList.count > 1 else { return }
        if self.pageControlBoxView == nil {
            let pcbView = pageControlBoxType.init()
            self.pageControlBoxView = pcbView
            self.addSubview(pcbView)
            pcbView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                pcbView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                pcbView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                pcbView.heightAnchor.constraint(equalToConstant: 32),
                pcbView.widthAnchor.constraint(equalToConstant: 102)
            ])
        }
        self.pageControlBoxView?.isHidden = false
        pageControlBoxView?.configure(data: data.cvPageControlData, clickLog: self.clickLog) { [weak self] actionType, actionData in
            guard let self,
                  let actionData = actionData as? UI_RollingControlView,
                  let actionName = RollingControlViewEvent(rawValue: actionType) else { return }
            switch actionName {
            case .showAll:
                self.allButtonClosure?()
            case .autoRolling:
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
        guard let data, data.rollingList.count > 0 else { return }
        if self.collectionView.superview == nil {
            self.addSubViewAutoLayout(collectionView)
        }
        self.collectionView.isScrollEnabled = data.rollingList.count > 1
        if let layout = self.collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.scrollDirection = .horizontal
            layout.minimumInteritemSpacing = 0
            layout.sectionInset = self.edgeInsets
            layout.minimumLineSpacing = self.itemSpacing
        }

        self.scrollWithSafeIndex(isInfinite ? ((data.cvCurrentIndex % data.rollingList.count) + data.rollingList.count) : data.cvCurrentIndex)
        self.startAutoRolling()
    }

    private func updateCollectionView() {
        if let layout = self.collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.scrollDirection = .horizontal
            layout.minimumInteritemSpacing = 0
            layout.sectionInset = self.edgeInsets
            layout.minimumLineSpacing = self.itemSpacing
        }
        self.collectionView.reloadData()
        self.startAutoRolling()
    }

    private func scrollWithSafeIndex(_ index: Int) {
        self.collectionView.reloadData()
        self.collectionView.layoutIfNeeded()
        guard data?.rollingList.count > 1 else { return }

        guard index >= 0, self.collectionView.numberOfSections > 0, self.collectionView.numberOfItems(inSection: 0) > 0, index < self.collectionView.numberOfItems(inSection: 0) else { return }
        self.collectionView.scrollToItem(at: IndexPath(row: index, section: 0), at: .centeredHorizontally, animated: false)
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

    // 중앙 보내기
    private var beforeWidth: CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()
        guard beforeWidth != self.frame.width else { return }
        beforeWidth = self.frame.width
        self.setInitialState()
        if let superView = self.superview {
            superView.setNeedsLayout()
        }
    }

    private func setInitialState() {
        guard let data, data.rollingList.count > 0 else { return }
        data.cvMaxItemSize = .zero
        self.collectionView.flowLayout?.invalidateLayout()
        self.setSelfHeight()
        self.scrollWithSafeIndex(self.isInfinite ? ((data.cvCurrentIndex % data.rollingList.count) + data.rollingList.count) : data.cvCurrentIndex)
    }

    // MARK: AutoRolling
    // 다음 페이지로 이동
    private func toNextPage() {
        guard let data, data.rollingList.count > 0, data.cvMaxItemSize.width > 0 else { return }
        let currentOffset = self.collectionView.contentOffset.x
        let targetOffset: CGFloat
        targetOffset = currentOffset + data.cvMaxItemSize.width + self.itemSpacing
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
        guard data?.rollingList.count > 1 else { return }
        guard isBannerAutoRolling else { return }
        guard timer == nil else { return }
        guard UIAccessibility.isVoiceOverRunning == false else { return }

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

    /// PageControllBox API
    func setPageControlUI(cornerRadius: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        guard let pageControlBoxView else { return }
        pageControlBoxView.cornerRadius = cornerRadius
        pageControlBoxView.ec.bottom = bottom
        pageControlBoxView.ec.trailing = trailing
    }

    // 롤링배너뷰 의 높이 (배너중 최대높이 + 상하 인셋) 리턴
    class func getRollingBannerSize(width: CGFloat, data: UI_RollingBannerData?, cellType: BaseCollectionViewCell.Type?, sideInsets: UIEdgeInsets) -> CGSize {
        guard let data, data.rollingList.count > 0 else { return .zero }
        let height: CGFloat = sideInsets.top + sideInsets.bottom
        let itemSize = RollingBannerView.setItemSize(width: width, data: data, cellType: cellType, sideInsets: sideInsets)
        return CGSize(width: itemSize.width, height: itemSize.height + height)
    }

    class func setItemSize(width: CGFloat, data: UI_RollingBannerData, cellType: BaseCollectionViewCell.Type?, sideInsets: UIEdgeInsets) -> CGSize {
        guard data.rollingList.count > 0, let cellType else { return .zero }
        if data.cvMaxItemSize != .zero, data.cvMaxItemSize.width == width { return data.cvMaxItemSize }
        let cellWidth = width - sideInsets.left - sideInsets.right
        var cellHeight: CGFloat = 0
        for banr in data.rollingList {
            let newCellHeight = cellType.getSize(data: banr, width: cellWidth).height
            if cellHeight < newCellHeight {
                cellHeight = newCellHeight
            }
        }
        data.cvMaxItemSize = CGSize(width: cellWidth, height: cellHeight)
        return data.cvMaxItemSize
    }

    // MARK: Impression
    private func sendImpressionLog(collectionView: UICollectionView, cell: BaseCollectionViewCell, indexPath: IndexPath) {
        guard let clickLog = cell.clickLog, let data, data.rollingList.count > 0 else { return }
        for var diImpressionLog in clickLog.diImpressionLogs {
            var index = indexPath.row
            if isInfinite {
                index = indexPath.row % data.rollingList.count
            }
            if diImpressionLog?.isAlwaysSend == true || ( self.impressionDic.keys.contains(index) == false || self.impressionDic[index] == false) {
                if collectionView.isVisible {
                    diImpressionLog?.sendLog()
                    self.impressionDic[index] = true
                }
                else {
                    self.impressionPended[index] = diImpressionLog
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

    private func sendAdsPVLog(data: Any?) {
        guard let data = data else { return }
        if let data = data as? DI_TBannerListItem {
            guard data.cvSendAdsPVLog == false else { return }
            data.cvSendAdsPVLog = true
            data.sendPVAdsLog(self.clickLog)
        }
        else if let data = data as? DI_ProductItem {
            data.sendPVAdsLog(self.clickLog)
        }
    }

    private func setClickLog(index: Int, rollingItem: Any?) -> DIR_ClickLog {
        guard let rollingItem else { return DIR_ClickLog() }
        var logData = self.clickLog
        logData?.diImpressionLogs.removeAll()
        var clickLog = self.clickLog
        clickLog?.diReactingLog?.data.tarea_dtl_info.unit_inx = "\(index)"
        clickLog?.diReactingLog?.data.tarea_dtl_cd = .t10000
        if let data = rollingItem as? DIReactiongLogItemProtocol {
            data.setDIReactionLog(&clickLog)
        }
        clickLog?.diReactingLog?.isAlwaysSend = self.isAlwaysSend
        logData?.diImpressionLogs.append(clickLog?.diReactingLog)
        return logData ?? DIR_ClickLog()
    }
}

extension RollingBannerView: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let data else { return .zero }
        var count = data.rollingList.count
        if self.isInfinite {
            count = data.rollingList.count * 3
        }
        return count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let data, data.rollingList.count > 0, let cellType else { return BaseCollectionViewCell() }
        let cell = collectionView.dequeueReusableCell(cellType, for: indexPath)
        var index = indexPath.row
        if self.isInfinite {
            index = indexPath.row % data.rollingList.count
        }
        cell.actionClosure = { [weak self] actionType, _ in
            guard let self else { return }
            self.onMovieAction(actionType: actionType)
        }
        let logData = self.setClickLog(index: index, rollingItem: data.rollingList[safe: index])
        cell.configure(data: data.rollingList[safe: index], clickLog: logData)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let data, data.rollingList.count > 0, let cellType else { return .zero }
        return RollingBannerView.setItemSize(width: collectionView.frame.width, data: data, cellType: cellType, sideInsets: self.edgeInsets)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? BaseCollectionViewCell else { return }
        guard let data, data.rollingList.count > 0 else { return }
        self.cellDisplayClosure?(collectionView, cell)
        self.sendImpressionLog(collectionView: collectionView, cell: cell, indexPath: indexPath)
        var index = indexPath.row
        if isInfinite {
            index = index % data.rollingList.count
        }
        self.sendAdsPVLog(data: data.rollingList[safe: index])
    }

    // 페이징
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard let scrollView = scrollView as? UICollectionView else { return }
        guard let data, data.cvMaxItemSize.width > 0 else { return }
        let cellWidthIncludingSpacing = data.cvMaxItemSize.width + self.itemSpacing
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

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard let scrollView = scrollView as? UICollectionView else { return }
        guard let data, data.rollingList.count > 0, data.cvMaxItemSize.width > 0 else { return }
        self.scrollFinishClosure?(scrollView, data.cvCurrentIndex)
        let contentOffset = collectionView.contentOffset
        let pageSize = data.cvMaxItemSize.width + self.itemSpacing
        let pageIndex = (Int(round(contentOffset.x / pageSize)) % data.rollingList.count) + data.rollingList.count
        guard let cell = scrollView.cellForItem(at: IndexPath(item: pageIndex, section: 0)) else { return }
        self.scrollFinishCellClosure?(scrollView, cell)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard let scrollView = scrollView as? UICollectionView else { return }
        guard let data, data.rollingList.count > 0, data.cvMaxItemSize.width > 0 else { return }
        self.scrollFinishClosure?(scrollView, data.cvCurrentIndex)
        if self.isBannerAutoRolling {
            self.startAutoRolling()
        }
        let contentOffset = collectionView.contentOffset
        let pageSize = data.cvMaxItemSize.width + self.itemSpacing
        let pageIndex = (Int(round(contentOffset.x / pageSize)) % data.rollingList.count) + data.rollingList.count
        guard let cell = scrollView.cellForItem(at: IndexPath(item: pageIndex, section: 0)) else { return }
        self.scrollFinishCellClosure?(scrollView, cell)
    }

    // 무한 옮겨주기
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let collectionView = scrollView as? UICollectionView else { return }
        guard let data, data.rollingList.count > 0, data.cvMaxItemSize.width > 0 else { return }
        let contentOffset = collectionView.contentOffset
        let pageSize = data.cvMaxItemSize.width + self.itemSpacing
        if isInfinite {
            let maxX = pageSize * CGFloat(data.rollingList.count * 2)
            let minX = pageSize * CGFloat(data.rollingList.count)
            if contentOffset.x > maxX - pageSize * 0.3 {
                collectionView.contentOffset = CGPoint(x: contentOffset.x - pageSize * CGFloat(data.rollingList.count), y: 0)
            }
            else if contentOffset.x < minX - pageSize * 0.3 {
                collectionView.contentOffset = CGPoint(x: contentOffset.x + pageSize * CGFloat(data.rollingList.count), y: 0)
            }
        }

        self.scrollClosure?(collectionView)

        let pageIndex = Int(round(contentOffset.x / pageSize)) % data.rollingList.count
        guard self.pageIndex != pageIndex else { return }
        self.pageIndex = pageIndex
        data.cvCurrentIndex = pageIndex
        self.scrollIndexClosure?(pageIndex)
        guard let pageControlData = data.cvPageControlData else { return }
        if pageControlData.isAutoRolling {
            self.isBannerAutoRolling = pageControlData.isAutoRolling
        }
        pageControlData.currentPageIndex = pageIndex
        self.pageControlBoxView?.updateData(data: pageControlData)
    }
}

extension RollingBannerView {
    func getVisibleCells() -> [UICollectionViewCell] {
        let cells = self.collectionView.visibleCells
        guard cells.count > 0 else { return [] }
        return cells
    }
}
