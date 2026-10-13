import UIKit

protocol RollingBannerCellAccessibilityProtocol {
    // 래퍼뷰에 전달할 접근성 텍스트
    var bannerAccessibilityLabel: String { get }
    // 래퍼뷰에 전달할 클릭액션
    var accessibilityActionClosure: (() -> Void)? { get set }
    // 래퍼뷰에 전달할 동영상 커스텀 액션 ( 정지 / 재생 / 음소거 )
    var accessibilityMovieCustomActions: [UIAccessibilityCustomAction] { get }
}

// 롤링배너의 접근성 제어를 위한 커스텀 뷰
final class RollingBannerAccessibilityView: BaseView {
    // 대표로 읽을 접근성 라벨 전달
    var accessibilityLabelClosure: (() -> String?)?
    // 대표로 읽을 접근성 상태 변화 텍스트 전달
    var accessibilityValueClosure: (() -> String?)?

    // 접근성 상/하 스와이프로 값 조절 액션
    var incrementClosure: (() -> Void)?
    var decrementClosure: (() -> Void)?
    // 접근성 클릭 액션
    var activateActionClosure: (() -> Bool)?
    // 래퍼뷰 클릭 뚫을지 여부 (컨트롤러 클릭시 사용)
    var needClickThroughClosure: ((CGPoint) -> Bool)?
    // 현재 배너에 영상이 있을 경우 제공할 추가 액션
    var customActionsClosure: (() -> [UIAccessibilityCustomAction])?

    override func setup() {
        super.setup()
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = true
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let needClickThroughClosure else { return false }
        if needClickThroughClosure(point) {
            return false
        }
        return super.point(inside: point, with: event)
    }

    override var isAccessibilityElement: Bool {
        get { true }
        set {}
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { [.button, .adjustable] }
        set {}
    }

    override var accessibilityLabel: String? {
        get { accessibilityLabelClosure?() }
        set {}
    }

    override var accessibilityValue: String? {
        get { accessibilityValueClosure?() }
        set {}
    }

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get { customActionsClosure?() }
        set {}
    }

    override func accessibilityIncrement() {
        incrementClosure?()
    }

    override func accessibilityDecrement() {
        decrementClosure?()
    }

    override func accessibilityActivate() -> Bool {
        return activateActionClosure?() ?? false
    }

    func setAccessibilityView(_ rollingBannerView: RollingBannerView) {
        self.isHidden = false
        self.isAccessibilityElement = true
        self.accessibilityTraits = [.button, .adjustable]
        rollingBannerView.setRollingBannerViewAccessibility(false)
        self.incrementClosure = { [weak rollingBannerView] in
            guard let rollingBannerView else { return }
            rollingBannerView.toNextPage()
        }
        self.decrementClosure = { [weak rollingBannerView] in
            guard let rollingBannerView else { return }
            rollingBannerView.toPrevPage()
        }
        self.accessibilityValueClosure = { [weak rollingBannerView] in
            guard let rollingBannerView else { return "" }
            return rollingBannerView.getCurrentCellAccessibilityLabel()

        }
//        self.accessibilityLabelClosure = { [weak rollingBannerView] in
//            guard let rollingBannerView else { return "" }
//            return rollingBannerView.getCurrentCellAccessibilityLabel()
//        }

        self.activateActionClosure = { [weak rollingBannerView] in
            guard let rollingBannerView else { return false }
            return rollingBannerView.currentCellAccessibilityAction()
        }

        self.customActionsClosure = { [weak rollingBannerView] in
            guard let rollingBannerView else { return [] }
            return rollingBannerView.currentCellMovieAccessibilityCustomActions()
        }

        self.needClickThroughClosure = { [weak rollingBannerView] point in
            guard let rollingBannerView else { return false }
            return rollingBannerView.isPageControlBoxClick(point: point)
        }
    }
}
