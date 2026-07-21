import Foundation
import SwiftUI
import TranscriberCore
import TranscriberDomain

/// Drives download and lifecycle of the local MOSS multi-speaker model on macOS.
@MainActor
final class MacMOSSModelController: ObservableObject {
    @Published private(set) var status = MOSSLocalModelManager.currentStatus()
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    @Published var errorTitle: String?
    @Published var errorMessage: String?

    func refresh() {
        status = MOSSLocalModelManager.currentStatus()
    }

    func download() {
        guard !isDownloading else {
            return
        }
        isDownloading = true
        downloadProgress = 0

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let downloadedStatus = try await MOSSLocalModelManager.download { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = progress
                    }
                }
                status = downloadedStatus
            } catch {
                errorTitle = String(localized: L10n.MOSSLocal.downloadFailed)
                errorMessage = error.localizedDescription
                refresh()
            }
            isDownloading = false
        }
    }

    func deleteModel() {
        do {
            status = try MOSSLocalModelManager.deleteDownloadedModel()
        } catch {
            errorTitle = String(localized: L10n.MOSSLocal.deleteFailed)
            errorMessage = error.localizedDescription
        }
    }
}
