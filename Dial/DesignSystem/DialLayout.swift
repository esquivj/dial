import SwiftUI

extension Dial {
  enum Layout {
    enum Dropdown {
      static let width: CGFloat = 440
      static let height: CGFloat = 440
      static let contentWidth: CGFloat = 410
      static let contentHeight: CGFloat = 410
      static let cornerRadius: CGFloat = 36
      static let panelHorizontalPadding: CGFloat = 10
      static let hudScreenHorizontalPadding: CGFloat = 14
      static let outerTopPadding: CGFloat = 8
      static let hudTopChromeHeight: CGFloat = 37
      static let hudRailScreenGap: CGFloat = 8
      static let hudScreenHeightWithTransport: CGFloat = 246
      static let hudScreenHeightWithoutTransport: CGFloat = 348
      static let hudScreenTransportGap: CGFloat = 12
      static let hudTransportHeight: CGFloat = 74
      static let hudRailContentYOffset: CGFloat = 6
      static let hudBottomPaddingWithTransport: CGFloat = 17
      static let hudBottomPaddingWithoutTransport: CGFloat = 9
      static let fullScreenVerticalPadding: CGFloat = 9
      static let hudContentTopPadding: CGFloat = 24
      static let hudContentBottomPadding: CGFloat = 0
      static let shellSpacing: CGFloat = hudRailScreenGap
      static let outerBottomPadding: CGFloat = hudBottomPaddingWithTransport
    }

    enum Setup {
      static let railTopPadding: CGFloat = 8
      static let contentTopPadding: CGFloat = 14
      static let contentBottomPadding: CGFloat = 8
      static let wordmarkTextGap: CGFloat = 8
      static let textPreviewGap: CGFloat = 10
      static let previewCTAGap: CGFloat = 18
      static let ctaFooterGap: CGFloat = 14
      static let previewWidth: CGFloat = 188
      static let previewHeight: CGFloat = 98
    }

    enum Header {
      static let spacing: CGFloat = 10
      static let topPadding: CGFloat = 8
      static let leadingPadding: CGFloat = 10
      static let bottomPadding: CGFloat = 8
      static let trailingPadding: CGFloat = 14
    }

    enum PetScreen {
      static let contentPadding = EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8)
      static let contentSpacing: CGFloat = 5
      static let companionPanelHeight: CGFloat = 164
      static let roomSceneHeight: CGFloat = 104
      static let weeklyMemoryHeight: CGFloat = 52
      static let memoryShelfHeight: CGFloat = 42
      static let evolutionHeight: CGFloat = 52
      static let shellSafetyInset: CGFloat = 10
    }

    enum StatusRail {
      static let contentWidth: CGFloat = 340
      static let railHeight: CGFloat = 34
      static let spacing: CGFloat = 6
      static let horizontalPadding: CGFloat = 16
      static let verticalPadding: CGFloat = 1
      static let ledSize: CGFloat = 5
      static let iconSize: CGFloat = 12
      static let hitSize: CGFloat = 27
    }

    enum Hero {
      static let spacing: CGFloat = 12
      static let padding = EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
      static let artworkSize: CGFloat = 70
      static let artworkCornerRadius: CGFloat = Dial.Radius.media
      static let textMinHeight: CGFloat = 70
      static let metadataLineSpacing: CGFloat = 2
      static let metadataActionSpacing: CGFloat = 9
      static let badgeSpacing: CGFloat = 6
      static let badgeTrailingMinSpacing: CGFloat = 6
      static let badgeMinHeight: CGFloat = 22
      static let badgeIconBaseSize: CGFloat = 14
      static let badgeCornerRadius: CGFloat = Dial.Radius.printed
      static let badgePaddingBase = EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 8)
      static let petSpriteHeight: CGFloat = 51
      static let petContentSize: CGFloat = 52
      static let petFrameSize: CGFloat = 60
      static let petCornerRadius: CGFloat = Dial.Radius.media
    }

    enum Readouts {
      static let outerHorizontalPadding: CGFloat = 10
      static let outerVerticalPadding: CGFloat = 2
      static let railPadding = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
      static let railCornerRadius: CGFloat = Dial.Radius.control
      static let cellHorizontalPadding: CGFloat = 7
      static let cellLabelValueSpacing: CGFloat = 4
      static let valueDeltaSpacing: CGFloat = 5
      static let valueFontSize: CGFloat = 17
      static let dividerHeight: CGFloat = 40
    }

    enum Spectrum {
      static let padding = EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)
      static let labelGridSpacing: CGFloat = 5
      static let rows = 8
      static let cellGap: CGFloat = 1
      static let cellHeight: CGFloat = 5
      static let hotZoneFraction = 0.30
    }

    enum Transport {
      static let stackSpacing: CGFloat = 6
      static let padding = EdgeInsets(top: 16, leading: 11, bottom: 0, trailing: 11)
      static let scrubberYOffset: CGFloat = 11
      static let buttonRowYOffset: CGFloat = 7
      static let panelHorizontalPadding: CGFloat = 10
      static let edgeButtonInset: CGFloat = 38
      static let clusterSpacing: CGFloat = 14
      static let iconHitSize: CGFloat = 40
      static let scrubberTimeWidth: CGFloat = 38
      static let scrubberSpacing: CGFloat = 8
      static let scrubberHeight: CGFloat = 13
      static let trackHeight: CGFloat = 4
      static let thumbRestingSize: CGFloat = 6
      static let thumbActiveSize: CGFloat = 8
      static let minButtonRowHeight: CGFloat = 32
      static let secondaryPillWidth: CGFloat = 36
      static let secondaryPillHeight: CGFloat = 26
      static let prominentPillWidth: CGFloat = 44
      static let prominentPillHeight: CGFloat = 30
    }

    enum SecondaryScreen {
      static let contentPadding = EdgeInsets(top: 14, leading: 14, bottom: 16, trailing: 14)
      static let petContentPadding = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
      static let sectionSpacing: CGFloat = 13
      static let petSectionSpacing: CGFloat = 12
    }
  }
}
