# TranscriberDomain

`TranscriberDomain` contains platform-independent recording and transcript value types shared by the iOS and macOS applications.

The target may import Foundation, but must not import UIKit, AppKit, SwiftUI, AVFoundation, CloudKit, or persistence frameworks. Platform services consume these public values through adapter and repository protocols defined in later packages.
