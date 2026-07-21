# TranscriberDomain

`TranscriberDomain` contains platform-independent recording and transcript value types shared by the iOS and macOS applications. `TranscriberCore` defines the service boundaries for transcription, recording-library persistence, and metadata synchronization.

These targets may import Foundation, but must not import UIKit, AppKit, SwiftUI, AVFoundation, CloudKit, or persistence frameworks. Platform implementations conform to the Core protocols as adapters.
