# RollingBannerView

`RollingBannerView`는 `UICollectionView` 기반의 가로형 배너 컴포넌트입니다. 배너 스냅, 무한 롤링, 자동 롤링, 페이지 컨트롤과 노출 로그 처리를 지원합니다.

## 기본 구성

`RollingBannerView`를 사용하려면 배너 목록을 담은 `UI_RollingBannerData`와 화면에 표시할 셀 타입을 준비한 뒤, 롤링 방식과 페이지 컨트롤 등의 옵션을 설정합니다.

```swift
let rollingData = UI_RollingBannerData()
rollingData.rollingList = banners
rollingData.subData = subData
rollingData.cvPageControlData = pageControlData

rollingBannerView.edgeInsets = UIEdgeInsets(
    top: 0,
    left: 16,
    bottom: 0,
    right: 16
)
rollingBannerView.itemSpacing = 8

rollingBannerView.configure(
    data: rollingData,
    cellType: BannerUnitCell.self,
    alignment: .center,
    enableInfinite: true,
    enableAutoRolling: true,
    clickLog: clickLog,
    timeInterval: 3,
    pageControlBoxType: IndexRollingControlView.self
)
```

Interface Builder의 `cellName`에 셀 클래스명을 지정했다면 `cellType`은 생략할 수 있습니다.

## 주요 옵션

| 옵션 | 설명 |
| --- | --- |
| `alignment` | 배너 정렬 방식 (`center`, `left`) |
| `enableInfinite` | 무한 롤링 사용 여부 |
| `enableAutoRolling` | 자동 롤링 사용 여부 |
| `timeInterval` | 자동 롤링 간격. 기본값은 3초 |
| `pageControlBoxType` | `BaseRollingControlView` 기반 페이지 컨트롤 타입 |
| `edgeInsets`, `itemSpacing` | 배너 영역의 여백과 셀 간격 |

페이지 이동은 `toNextPage()`, `toPrevPage()`, `toPage(page:)`로 제어할 수 있습니다. 배너 높이가 필요한 경우 아래 API를 사용합니다.

```swift
let size = RollingBannerView.getRollingBannerSize(
    width: width,
    data: rollingData,
    cellType: BannerUnitCell.self,
    sideInsets: rollingBannerView.edgeInsets
)
```

스크롤 상태나 셀 노출에 따른 처리가 필요하면 `scrollClosure`, `scrollIndexClosure`, `scrollFinishClosure`, `cellDisplayClosure` 등의 클로저를 연결합니다.

## 접근성 지원

`RollingBannerAccessibilityView`는 VoiceOver 사용 시 현재 배너를 하나의 조절 가능한 요소로 제공하는 보조 뷰입니다. 상하 스와이프로 배너를 이동하고, 이중 탭으로 현재 배너의 액션을 실행합니다. 영상 배너의 재생·정지·음소거 액션도 전달할 수 있습니다.

접근성을 제공할 배너 셀은 `RollingBannerCellAccessibilityProtocol`을 구현합니다.

```swift
final class BannerUnitCell: BaseCollectionViewCell,
                            RollingBannerCellAccessibilityProtocol {
    var bannerAccessibilityLabel = ""
    var accessibilityActionClosure: (() -> Void)?
    var accessibilityMovieCustomActions: [UIAccessibilityCustomAction] = []
}
```

`RollingBannerAccessibilityView`를 `RollingBannerView`와 같은 영역에 배치한 뒤 VoiceOver가 활성화된 경우에만 연결합니다.

```swift
accessibilityView.isHidden = true

if WG_CommonFunc.isVoiceOverState() {
    accessibilityView.setAccessibilityView(rollingBannerView)
}
```

접근성 뷰를 연결하면 내부 컬렉션 뷰의 접근성 포커스는 비활성화되고, 현재 배너의 라벨·클릭 액션·영상 커스텀 액션이 래퍼 뷰를 통해 제공됩니다. VoiceOver 사용 중에는 무한 롤링이 자동으로 비활성화됩니다.
