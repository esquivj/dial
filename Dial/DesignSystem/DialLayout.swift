import SwiftUI

extension Dial {
  enum Layout {
    enum Dropdown {
      static let width: CGFloat = 360
      static let height: CGFloat = 360
      static let cornerRadius: CGFloat = Dial.Radius.device
      static let shellSpacing: CGFloat = 4
      static let panelHorizontalPadding: CGFloat = 10
      static let outerTopPadding: CGFloat = 8
      static let outerBottomPadding: CGFloat = 10
      static let hudContentTopPadding: CGFloat = 4
      static let hudContentBottomPadding: CGFloat = 4
    }

    enum Header {
      static let spacing: CGFloat = 10
      static let topPadding: CGFloat = 8
      static let leadingPadding: CGFloat = 10
      static let bottomPadding: CGFloat = 8
      static let trailingPadding: CGFloat = 14
    }

    enum StatusRail {
      static let spacing: CGFloat = 8
      static let horizontalPadding: CGFloat = 24
      static let verticalPadding: CGFloat = 1
      static let ledSize: CGFloat = 5
      static let iconSize: CGFloat = 12
      static let hitSize: CGFloat = 30
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
      static let padding = EdgeInsets(top: 7, leading: 11, bottom: 8, trailing: 11)
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
