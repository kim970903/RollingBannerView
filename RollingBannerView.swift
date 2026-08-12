import UIKit
import WiggleSDK

final class UI_RollingBannerData {
    var rollingList: [Any] = []
    var subData: [String: Any?]?

    var cvMaxItemSize: CGSize = .zero
    var isUsingFirstCellSize: Bool = false
    var cvCurrentIndex: Int = 0
    var cvPageControlData: UI_RollingControlView?
    var cvPausedByMovie: Bool = false
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

    enum RollingBannerAlignment {
        case center
        case left
    }
    private var alignment: RollingBannerAlignment = .center

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
        return enableInfinite && self.data?.rollingList.count > 1 && UIAccessibility.isVoiceOverRunning == false
    }
    // 오토롤링
    private var enableAutoRolling: Bool = false // 오토롤링을 허용 O/X
    private var isBannerAutoRolling: Bool = false // 버튼동작으로 오토롤링 재생/일시정지
    private weak var timer: Timer?
    private var pageIndex: Int = 0

    private var collectionView: UICollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

    private var pageControlBoxType: BaseRollingControlView.Type?
    private var pageControlBoxView: BaseRollingControlView?
    private var pageControlBottomConstraint: NSLayoutConstraint?
    private var pageControlTrailingConstraint: NSLayoutConstraint?
    private var pageControlCenterXConstraint: NSLayoutConstraint?
    // 배너 영역 넘는 페이지 컨트롤 터치허용
    var allowOutSideTouch: Bool = false

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

    // 컨트롤러가 배너 영역 밖에 있을경우 터치 대응
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }

        guard self.allowOutSideTouch, let pageControlBoxView, pageControlBoxView.isHidden == false else {
            return false
        }

        let convertedPoint = pageControlBoxView.convert(point, from: self)
        return pageControlBoxView.point(inside: convertedPoint, with: event)
    }

    private func setup() {
        self.backgroundColor = .clear
        self.clipsToBounds = false
        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.isPagingEnabled = false
        self.collectionView.decelerationRate = .fast
        self.collectionView.showsHorizontalScrollIndicator = false
        self.collectionView.backgroundColor = .clear
        self.viewDidAppear = {
            [weak self] isVisible in
            guard let self else { return }
            guard let data else { return }
            if isVisible, self.impressionPended.count > 0 {
                for dic in self.impressionPended {
                    var impression = dic.value
                    impression.sendLog()
                    self.impressionDic[dic.key] = true
                }
                self.impressionPended.removeAll()
            }

            if isVisible, data.cvPausedByMovie == false {
                self.startAutoRolling()
            }
        }
    }

    func configure(
        data: UI_RollingBannerData?,
        cellType: BaseCollectionViewCell.Type? = nil,
        alignment: RollingBannerAlignment = .center,
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
        self.alignment = alignment
        self.enableInfinite = enableInfinite
        self.enableAutoRolling = enableAutoRolling
        if enableAutoRolling {
            self.isBannerAutoRolling = WG_CommonFunc.isVoiceOverState() ? false : data.cvPageControlData?.isAutoRolling ?? true
        }
        else {
            self.isBannerAutoRolling = false
            self.data?.cvPageControlData?.isAutoRolling = false
        }
        self.clickLog = clickLog
        self.isAlwaysSend = isAlwaysSend
        self.timeInterval = timeInterval
        if WG_CommonFunc.isVoiceOverState(), timeInterval < 5.0 {
            self.timeInterval = 5.0
        }
        self.pageControlBoxType = pageControlBoxType
        self.setupCollectionView()
        self.setupPageControl()
    }

    // MARK: Set function
    private func setSelfHeight() {
        let width = self.bounds.width
        guard width > 0 else { return }
        let collectionViewHeight = RollingBannerView.getRollingBannerSize(width: width, data: self.data, cellType: self.cellType, sideInsets: self.edgeInsets).height
        guard self.height != collectionViewHeight else { return }
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

            let bottomConstraint = pcbView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
            self.pageControlBottomConstraint = bottomConstraint
            let trailingConstraint = pcbView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
            self.pageControlTrailingConstraint = trailingConstraint
            pcbView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bottomConstraint,
                trailingConstraint,
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
        if data.cvPausedByMovie == false {
            self.startAutoRolling()
        }
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
        var scrollType: UICollectionView.ScrollPosition = .centeredHorizontally
        if self.alignment == .left {
            scrollType = .left
        }
        self.collectionView.scrollToItem(at: IndexPath(row: index, section: 0), at: scrollType, animated: false)
    }

    private func onMovieAction(actionType: String, index: Int) {
        guard let data else { return }
        if let action = MovieViewState(rawValue: actionType) {
            switch action {
            case .autoPlaying:
                // 동영상의 자동 재생일 경우 오토롤링은 일단 끄고 노티받으면 켜준다.
                guard index >= data.rollingList.count, index < data.rollingList.count * 2 else { return }
                self.isBannerAutoRolling = false
                data.cvPausedByMovie = true
            case .playEnd:
                data.cvPausedByMovie = false
                if let isAutoRolling = data.cvPageControlData?.isAutoRolling {
                    self.isBannerAutoRolling = isAutoRolling
                    if isAutoRolling {
                        guard data.rollingList.count > 1 else { return }
                        guard isBannerAutoRolling else { return }
                        self.toNextPage()
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
    func toNextPage() {
        guard let data, data.rollingList.count > 0, data.cvMaxItemSize.width > 0 else { return }
        let pageSize: CGFloat = data.cvMaxItemSize.width + self.itemSpacing
        let currentIndex: Int = self.isInfinite ? (((data.cvCurrentIndex) % data.rollingList.count) + data.rollingList.count) : (data.cvCurrentIndex)
        if self.isInfinite == false, (currentIndex + 1) >= data.rollingList.count {
            return
        }
        let correctedCurrentOffset = CGFloat(currentIndex) * pageSize
        let targetOffset: CGFloat = correctedCurrentOffset + pageSize
        self.collectionView.setContentOffset(CGPoint(x: targetOffset, y: self.collectionView.contentOffset.y), animated: true)
    }

    func toPrevPage() {
        guard let data, data.rollingList.count > 0, data.cvMaxItemSize.width > 0 else { return }
        let pageSize: CGFloat = data.cvMaxItemSize.width + self.itemSpacing
        let currentIndex: Int = self.isInfinite ? (((data.cvCurrentIndex) % data.rollingList.count) + data.rollingList.count) : (data.cvCurrentIndex)
        guard (currentIndex - 1) >= 0 else { return }
        let correctedCurrentOffset = CGFloat(currentIndex) * pageSize
        let targetOffset: CGFloat = correctedCurrentOffset - pageSize
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
    func setPageControlUI(bottom: CGFloat = 0, trailing: CGFloat = 0) {
        guard let pageControlBoxView else { return }
        pageControlBoxView.ec.bottom = bottom
        pageControlBoxView.ec.trailing = trailing
    }

    func setPageControlBottom(_ spacing: CGFloat) {
        guard let pageControlBoxView else { return }
        pageControlBoxView.ec.bottom = spacing
    }

    func setPageControlTrailing(_ spacing: CGFloat) {
        guard pageControlBoxView != nil else { return }
        pageControlCenterXConstraint?.isActive = false
        pageControlTrailingConstraint?.isActive = true
        pageControlTrailingConstraint?.constant = -spacing
    }

    func setPageControlCornerRadius(_ radius: CGFloat ) {
        guard let pageControlBoxView else { return }
        pageControlBoxView.layer.cornerRadius = radius
    }

    func setPageControlRoundCorners(_ corners: UIRectCorner, radiusToken: RadiusToken) {
        guard let pageControlBoxView else { return }
        pageControlBoxView.roundCorners(corners, radiusToken: radiusToken)
    }

    func setPageControlCenterX() {
        guard let pageControlBoxView else { return }
        if self.pageControlCenterXConstraint == nil {
            self.pageControlCenterXConstraint = pageControlBoxView.centerXAnchor.constraint(equalTo: self.centerXAnchor)
        }
        self.pageControlCenterXConstraint?.isActive = true
        self.pageControlTrailingConstraint?.isActive = false
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
        let cellWidth = width - sideInsets.left - sideInsets.right
        if data.cvMaxItemSize != .zero, data.cvMaxItemSize.width == cellWidth { return data.cvMaxItemSize }
        if data.isUsingFirstCellSize {
            if let firstBanr = data.rollingList.first {
                data.cvMaxItemSize = cellType.getSize(data: firstBanr, width: cellWidth)
            }
        }
        else {
            var cellHeight: CGFloat = 0
            for banr in data.rollingList {
                let newCellHeight = cellType.getSize(data: banr, width: cellWidth).height
                if cellHeight < newCellHeight {
                    cellHeight = newCellHeight
                }
            }
            data.cvMaxItemSize = CGSize(width: cellWidth, height: cellHeight)
        }
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
            self.onMovieAction(actionType: actionType, index: indexPath.row)
        }
        let logData = self.setClickLog(index: index, rollingItem: data.rollingList[safe: index])
        cell.configure(data: data.rollingList[safe: index], clickLog: logData, subData: data.subData)
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
        data.cvPausedByMovie = false
        self.scrollFinishClosure?(scrollView, data.cvCurrentIndex)
        let contentOffset = collectionView.contentOffset
        let pageSize = data.cvMaxItemSize.width + self.itemSpacing
        let pageIndex = self.isInfinite ? (Int(round(contentOffset.x / pageSize)) % data.rollingList.count) + data.rollingList.count : (Int(round(contentOffset.x / pageSize)) % data.rollingList.count)
        let adjustedOffset = CGFloat(pageIndex) * pageSize
        self.collectionView.setContentOffset(CGPoint(x: adjustedOffset, y: contentOffset.y), animated: false)
        guard let cell = scrollView.cellForItem(at: IndexPath(item: pageIndex, section: 0)) else { return }
        self.scrollFinishCellClosure?(scrollView, cell)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard let scrollView = scrollView as? UICollectionView else { return }
        guard let data, data.rollingList.count > 0, data.cvMaxItemSize.width > 0 else { return }
        data.cvPausedByMovie = false
        self.scrollFinishClosure?(scrollView, data.cvCurrentIndex)
        if self.isBannerAutoRolling {
            self.startAutoRolling()
        }
        let contentOffset = collectionView.contentOffset
        let pageSize = data.cvMaxItemSize.width + self.itemSpacing
        let pageIndex = self.isInfinite ? (Int(round(contentOffset.x / pageSize)) % data.rollingList.count) + data.rollingList.count : (Int(round(contentOffset.x / pageSize)) % data.rollingList.count)
        let adjustedOffset = CGFloat(pageIndex) * pageSize
        self.collectionView.setContentOffset(CGPoint(x: adjustedOffset, y: contentOffset.y), animated: false)
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

    func setControlBoxHidden(_ isHidden: Bool) {
        self.pageControlBoxView?.isHidden = isHidden
    }
}

// 접근성 API
extension RollingBannerView {
    // 접근성 래퍼뷰에 포커싱을 주기위해 컬렉션 뷰의 접근성 해제 ( 컨트롤러는 포커싱,클릭 되어야해서 해제하지 않음 )
    func setRollingBannerViewAccessibility(_ isEnabled: Bool) {
        self.collectionView.isAccessibilityElement = isEnabled
        self.collectionView.accessibilityElementsHidden = isEnabled == false
    }

    // 현재 중앙에 노출되고 있는 배너의 접근성 텍스트
    func getCurrentCellAccessibilityLabel() -> String {
        guard let data, data.rollingList.count > 0 else { return "" }
        guard let cell = self.collectionView.cellForItem(at: IndexPath(row: data.cvCurrentIndex, section: 0)) as? RollingBannerCellAccessibilityProtocol else { return "" }
        return cell.bannerAccessibilityLabel + " \(data.rollingList.count) 개 중 \(data.cvCurrentIndex + 1) 번째 배너 표시중"
    }

    // 접근성 상태 변화시에 제공하는 텍스트
//    func getAccessibilityValue() -> String {
//        guard let data, data.rollingList.count > 0 else { return "" }
//        let currentIndex = data.cvCurrentIndex
//        let totalCount = data.rollingList.count
//        return "\(totalCount) 개 중 \(currentIndex + 1) 번째 배너 표시중"
//    }

    // 현재 중앙의 배너 클릭 액션을 전달 -> 래퍼뷰가 이 액션을 받아서 처리
    func currentCellAccessibilityAction() -> Bool {
        guard let data, data.rollingList.count > 0 else { return false }
        guard let cell = self.collectionView.cellForItem(at: IndexPath(row: data.cvCurrentIndex, section: 0)) as? RollingBannerCellAccessibilityProtocol else { return false }
        cell.accessibilityActionClosure?()
        return true
    }

    // 래퍼뷰로 컨트롤러 클릭이 막히지 않게 클릭영역판단
    func isPageControlBoxClick(point: CGPoint) -> Bool {
        guard let pageControlBoxView else { return false }
        let convertedPoint = pageControlBoxView.convert(point, from: self)
        return pageControlBoxView.point(inside: convertedPoint, with: nil)
    }
}
