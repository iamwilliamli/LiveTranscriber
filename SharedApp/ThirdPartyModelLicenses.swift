import Foundation
import SwiftUI

enum PinnedModelReleases {
    struct Release: Sendable {
        let repository: String
        let revision: String

        func downloadURL(for fileName: String) -> URL {
            let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
            return URL(
                string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(encodedFileName)"
            )!
        }

        var sourceURL: URL {
            URL(string: "https://huggingface.co/\(repository)/tree/\(revision)")!
        }
    }

    static let whisper = Release(
        repository: "ggerganov/whisper.cpp",
        revision: "5359861c739e955e79d9a303bcbc70fb988958b1"
    )

    static let qwenSummary = Release(
        repository: "Qwen/Qwen3-1.7B-GGUF",
        revision: "90862c4b9d2787eaed51d12237eafdfe7c5f6077"
    )
    static let qwenSummaryFileName = "Qwen3-1.7B-Q8_0.gguf"
    static let qwenSummaryByteCount: Int64 = 1_834_426_016
    static let qwenSummarySHA256 = "061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a"

    static let qwenASR = Release(
        repository: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit",
        revision: "bc441bd1e4295c1f42d9879f056049a925b6e013"
    )
    static let qwenASRWeightSHA256 = "70c7e67e588062adce4f10796e47ad42ead51c6671eda61a0987eae38ca95ddf"

    static let sileroVAD = Release(
        repository: "aufklarer/Silero-VAD-v6.2.1-MLX",
        revision: "0046cea48b26401909b24292b688fbc9b6322bc5"
    )
    static let sileroVADWeightSHA256 = "8367dac03e6c9ae0e20b71886655e9b9cdc459eac66625e8afd770573e43bc0b"

    static let moss = Release(
        repository: "vanch007/mlx-MOSS-Transcribe-Diarize-4bit",
        revision: "d42a296ee807e933ddd7588e2041dbbc84aff85d"
    )
    static let mossWeightSHA256 = "0483be31b7adaa81ff6f94da3eb4c61a993e29b2fe2c3ba07827fbd00494a3c4"
    static let mossTokenizerSHA256 = "bcf03774334462d6e34b5005cb11120a62275f146ee2953e68731ecdbce84fbb"
}

struct ThirdPartyLicenseDocument: Identifiable {
    enum Category: String, CaseIterable {
        case models
        case runtimes

        var title: LocalizedStringResource {
            switch self {
            case .models:
                L10n.Settings.thirdPartyModelLicenses
            case .runtimes:
                L10n.Settings.thirdPartyRuntimeLicenses
            }
        }
    }

    let id: String
    let category: Category
    let name: String
    let purpose: String
    let licenseName: String
    let sourceURL: URL
    let revision: String?
    let artifactSHA256: String?
    let notice: String
    let licenseText: String
}

enum ThirdPartyLicenseCatalog {
    static let documents: [ThirdPartyLicenseDocument] = [
        ThirdPartyLicenseDocument(
            id: "whisper-models",
            category: .models,
            name: "Whisper model weights and GGML/Core ML conversions",
            purpose: "On-device transcription",
            licenseName: "MIT License",
            sourceURL: PinnedModelReleases.whisper.sourceURL,
            revision: PinnedModelReleases.whisper.revision,
            artifactSHA256: nil,
            notice: """
            Whisper code and model weights are Copyright © 2022 OpenAI.
            Live Transcriber downloads GGML model weights and optional Core ML encoder conversions from the ggerganov/whisper.cpp Hugging Face repository at the pinned revision shown above.
            """,
            licenseText: mitLicense(copyright: "Copyright (c) 2022 OpenAI")
        ),
        ThirdPartyLicenseDocument(
            id: "qwen-summary",
            category: .models,
            name: "Qwen3-1.7B-GGUF",
            purpose: "On-device summaries, titles, tags, and recording chat",
            licenseName: "Apache License 2.0",
            sourceURL: PinnedModelReleases.qwenSummary.sourceURL,
            revision: PinnedModelReleases.qwenSummary.revision,
            artifactSHA256: PinnedModelReleases.qwenSummarySHA256,
            notice: """
            Copyright 2025 Alibaba Cloud.
            Live Transcriber downloads the official Qwen3-1.7B Q8_0 GGUF artifact from the Qwen organization.
            """,
            licenseText: apacheLicense
        ),
        ThirdPartyLicenseDocument(
            id: "qwen-asr",
            category: .models,
            name: "Qwen3-ASR-0.6B-MLX-4bit",
            purpose: "On-device post-recording transcription",
            licenseName: "Apache License 2.0",
            sourceURL: PinnedModelReleases.qwenASR.sourceURL,
            revision: PinnedModelReleases.qwenASR.revision,
            artifactSHA256: PinnedModelReleases.qwenASRWeightSHA256,
            notice: """
            This MLX 4-bit conversion by aufklarer is based on Qwen/Qwen3-ASR-0.6B. Both the conversion repository and the upstream Qwen model declare the Apache License 2.0.
            """,
            licenseText: apacheLicense
        ),
        ThirdPartyLicenseDocument(
            id: "silero-vad",
            category: .models,
            name: "Silero VAD v6.2.1 MLX",
            purpose: "Voice activity detection for Qwen3-ASR",
            licenseName: "MIT License",
            sourceURL: PinnedModelReleases.sileroVAD.sourceURL,
            revision: PinnedModelReleases.sileroVAD.revision,
            artifactSHA256: PinnedModelReleases.sileroVADWeightSHA256,
            notice: """
            Copyright (c) 2020-present Silero Team.
            This MLX conversion by aufklarer is based on snakers4/silero-vad v6.2.1.
            """,
            licenseText: mitLicense(copyright: "Copyright (c) 2020-present Silero Team")
        ),
        ThirdPartyLicenseDocument(
            id: "moss",
            category: .models,
            name: "MOSS-Transcribe-Diarize 4-bit MLX",
            purpose: "On-device transcription with timestamps and speaker diarization",
            licenseName: "Apache License 2.0",
            sourceURL: PinnedModelReleases.moss.sourceURL,
            revision: PinnedModelReleases.moss.revision,
            artifactSHA256: PinnedModelReleases.mossWeightSHA256,
            notice: """
            The 4-bit MLX artifact by vanch007 is derived from OpenMOSS-Team/MOSS-Transcribe-Diarize, which is released under the Apache License 2.0.

            Technical report:
            MOSI.AI, “MOSS Transcribe Diarize: Accurate Transcription with Speaker Diarization,” arXiv:2601.01554 (2026).
            """,
            licenseText: apacheLicense
        ),
        ThirdPartyLicenseDocument(
            id: "whisper-runtime",
            category: .runtimes,
            name: "whisper.cpp",
            purpose: "Local Whisper inference runtime",
            licenseName: "MIT License",
            sourceURL: URL(string: "https://github.com/ggml-org/whisper.cpp")!,
            revision: nil,
            artifactSHA256: nil,
            notice: "Copyright (c) 2023-2026 The ggml authors.",
            licenseText: mitLicense(copyright: "Copyright (c) 2023-2026 The ggml authors")
        ),
        ThirdPartyLicenseDocument(
            id: "llama-runtime",
            category: .runtimes,
            name: "llama.cpp",
            purpose: "Local GGUF language-model inference runtime",
            licenseName: "MIT License",
            sourceURL: URL(string: "https://github.com/ggml-org/llama.cpp")!,
            revision: nil,
            artifactSHA256: nil,
            notice: "Copyright (c) 2023-2026 The ggml authors.",
            licenseText: mitLicense(copyright: "Copyright (c) 2023-2026 The ggml authors")
        ),
        ThirdPartyLicenseDocument(
            id: "qwen3-speech-runtime",
            category: .runtimes,
            name: "Qwen3Speech Swift runtime",
            purpose: "Local Qwen3-ASR and VAD inference",
            licenseName: "Apache License 2.0",
            sourceURL: URL(string: "https://github.com/soniqo/speech-swift")!,
            revision: nil,
            artifactSHA256: nil,
            notice: "Copyright 2025 Ivan Digital.",
            licenseText: apacheLicense
        ),
        ThirdPartyLicenseDocument(
            id: "mlx-audio-runtime",
            category: .runtimes,
            name: "MLXAudio MOSS runtime",
            purpose: "Local MOSS inference",
            licenseName: "MIT License",
            sourceURL: URL(string: "https://github.com/soniqo/mlx-audio-swift")!,
            revision: "6ea59e549294151256b98b1cdbb346ba946d12d0",
            artifactSHA256: nil,
            notice: "Copyright (c) 2025 Prince Canuma.",
            licenseText: mitLicense(copyright: "Copyright (c) 2025 Prince Canuma")
        ),
    ]

    private static func mitLicense(copyright: String) -> String {
        """
        MIT License

        \(copyright)

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    }

    private static let apacheLicense = """
    Apache License
    Version 2.0, January 2004
    http://www.apache.org/licenses/

    TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

    1. Definitions.

    "License" shall mean the terms and conditions for use, reproduction,
    and distribution as defined by Sections 1 through 9 of this document.

    "Licensor" shall mean the copyright owner or entity authorized by
    the copyright owner that is granting the License.

    "Legal Entity" shall mean the union of the acting entity and all
    other entities that control, are controlled by, or are under common
    control with that entity. For the purposes of this definition,
    "control" means (i) the power, direct or indirect, to cause the
    direction or management of such entity, whether by contract or
    otherwise, or (ii) ownership of fifty percent (50%) or more of the
    outstanding shares, or (iii) beneficial ownership of such entity.

    "You" (or "Your") shall mean an individual or Legal Entity
    exercising permissions granted by this License.

    "Source" form shall mean the preferred form for making modifications,
    including but not limited to software source code, documentation
    source, and configuration files.

    "Object" form shall mean any form resulting from mechanical
    transformation or translation of a Source form, including but
    not limited to compiled object code, generated documentation,
    and conversions to other media types.

    "Work" shall mean the work of authorship, whether in Source or
    Object form, made available under the License, as indicated by a
    copyright notice that is included in or attached to the work
    (an example is provided in the Appendix below).

    "Derivative Works" shall mean any work, whether in Source or Object
    form, that is based on (or derived from) the Work and for which the
    editorial revisions, annotations, elaborations, or other modifications
    represent, as a whole, an original work of authorship. For the purposes
    of this License, Derivative Works shall not include works that remain
    separable from, or merely link (or bind by name) to the interfaces of,
    the Work and Derivative Works thereof.

    "Contribution" shall mean any work of authorship, including
    the original version of the Work and any modifications or additions
    to that Work or Derivative Works thereof, that is intentionally
    submitted to Licensor for inclusion in the Work by the copyright owner
    or by an individual or Legal Entity authorized to submit on behalf of
    the copyright owner. For the purposes of this definition, "submitted"
    means any form of electronic, verbal, or written communication sent
    to the Licensor or its representatives, including but not limited to
    communication on electronic mailing lists, source code control systems,
    and issue tracking systems that are managed by, or on behalf of, the
    Licensor for the purpose of discussing and improving the Work, but
    excluding communication that is conspicuously marked or otherwise
    designated in writing by the copyright owner as "Not a Contribution."

    "Contributor" shall mean Licensor and any individual or Legal Entity
    on behalf of whom a Contribution has been received by Licensor and
    subsequently incorporated within the Work.

    2. Grant of Copyright License. Subject to the terms and conditions of
    this License, each Contributor hereby grants to You a perpetual,
    worldwide, non-exclusive, no-charge, royalty-free, irrevocable
    copyright license to reproduce, prepare Derivative Works of,
    publicly display, publicly perform, sublicense, and distribute the
    Work and such Derivative Works in Source or Object form.

    3. Grant of Patent License. Subject to the terms and conditions of
    this License, each Contributor hereby grants to You a perpetual,
    worldwide, non-exclusive, no-charge, royalty-free, irrevocable
    (except as stated in this section) patent license to make, have made,
    use, offer to sell, sell, import, and otherwise transfer the Work,
    where such license applies only to those patent claims licensable
    by such Contributor that are necessarily infringed by their
    Contribution(s) alone or by combination of their Contribution(s)
    with the Work to which such Contribution(s) was submitted. If You
    institute patent litigation against any entity (including a
    cross-claim or counterclaim in a lawsuit) alleging that the Work
    or a Contribution incorporated within the Work constitutes direct
    or contributory patent infringement, then any patent licenses
    granted to You under this License for that Work shall terminate
    as of the date such litigation is filed.

    4. Redistribution. You may reproduce and distribute copies of the
    Work or Derivative Works thereof in any medium, with or without
    modifications, and in Source or Object form, provided that You
    meet the following conditions:

    (a) You must give any other recipients of the Work or
        Derivative Works a copy of this License; and

    (b) You must cause any modified files to carry prominent notices
        stating that You changed the files; and

    (c) You must retain, in the Source form of any Derivative Works
        that You distribute, all copyright, patent, trademark, and
        attribution notices from the Source form of the Work,
        excluding those notices that do not pertain to any part of
        the Derivative Works; and

    (d) If the Work includes a "NOTICE" text file as part of its
        distribution, then any Derivative Works that You distribute must
        include a readable copy of the attribution notices contained
        within such NOTICE file, excluding those notices that do not
        pertain to any part of the Derivative Works, in at least one
        of the following places: within a NOTICE text file distributed
        as part of the Derivative Works; within the Source form or
        documentation, if provided along with the Derivative Works; or,
        within a display generated by the Derivative Works, if and
        wherever such third-party notices normally appear. The contents
        of the NOTICE file are for informational purposes only and
        do not modify the License. You may add Your own attribution
        notices within Derivative Works that You distribute, alongside
        or as an addendum to the NOTICE text from the Work, provided
        that such additional attribution notices cannot be construed
        as modifying the License.

    You may add Your own copyright statement to Your modifications and
    may provide additional or different license terms and conditions
    for use, reproduction, or distribution of Your modifications, or
    for any such Derivative Works as a whole, provided Your use,
    reproduction, and distribution of the Work otherwise complies with
    the conditions stated in this License.

    5. Submission of Contributions. Unless You explicitly state otherwise,
    any Contribution intentionally submitted for inclusion in the Work
    by You to the Licensor shall be under the terms and conditions of
    this License, without any additional terms or conditions.
    Notwithstanding the above, nothing herein shall supersede or modify
    the terms of any separate license agreement you may have executed
    with Licensor regarding such Contributions.

    6. Trademarks. This License does not grant permission to use the trade
    names, trademarks, service marks, or product names of the Licensor,
    except as required for reasonable and customary use in describing the
    origin of the Work and reproducing the content of the NOTICE file.

    7. Disclaimer of Warranty. Unless required by applicable law or
    agreed to in writing, Licensor provides the Work (and each
    Contributor provides its Contributions) on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
    implied, including, without limitation, any warranties or conditions
    of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
    PARTICULAR PURPOSE. You are solely responsible for determining the
    appropriateness of using or redistributing the Work and assume any
    risks associated with Your exercise of permissions under this License.

    8. Limitation of Liability. In no event and under no legal theory,
    whether in tort (including negligence), contract, or otherwise,
    unless required by applicable law (such as deliberate and grossly
    negligent acts) or agreed to in writing, shall any Contributor be
    liable to You for damages, including any direct, indirect, special,
    incidental, or consequential damages of any character arising as a
    result of this License or out of the use or inability to use the
    Work (including but not limited to damages for loss of goodwill,
    work stoppage, computer failure or malfunction, or any and all
    other commercial damages or losses), even if such Contributor
    has been advised of the possibility of such damages.

    9. Accepting Warranty or Additional Liability. While redistributing
    the Work or Derivative Works thereof, You may choose to offer,
    and charge a fee for, acceptance of support, warranty, indemnity,
    or other liability obligations and/or rights consistent with this
    License. However, in accepting such obligations, You may act only
    on Your own behalf and on Your sole responsibility, not on behalf
    of any other Contributor, and only if You agree to indemnify,
    defend, and hold each Contributor harmless for any liability
    incurred by, or claims asserted against, such Contributor by reason
    of your accepting any such warranty or additional liability.

    END OF TERMS AND CONDITIONS

    APPENDIX: How to apply the Apache License to your work.

    To apply the Apache License to your work, attach the following
    boilerplate notice, with the fields enclosed by brackets "[]"
    replaced with your own identifying information. (Don't include
    the brackets!) The text should be enclosed in the appropriate
    comment syntax for the file format. We also recommend that a
    file or class name and description of purpose be included on the
    same "printed page" as the copyright notice for easier
    identification within third-party archives.

    Copyright [yyyy] [name of copyright owner]

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    """
}

struct ThirdPartyModelLicensesView: View {
    var body: some View {
        List {
            Section {
                Text(L10n.Settings.thirdPartyLicensesDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(ThirdPartyLicenseDocument.Category.allCases, id: \.rawValue) { category in
                Section {
                    ForEach(ThirdPartyLicenseCatalog.documents.filter { $0.category == category }) { document in
                        NavigationLink {
                            ThirdPartyLicenseDetailView(document: document)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: document.name)
                                    .font(.headline)
                                Text(verbatim: document.purpose)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(verbatim: document.licenseName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.info)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } header: {
                    Text(category.title)
                }
            }
        }
        .navigationTitle(String(localized: L10n.Settings.thirdPartyLicenses))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct ThirdPartyLicenseDetailView: View {
    let document: ThirdPartyLicenseDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                metadata

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.thirdPartyNotice)
                        .font(.headline)
                    Text(verbatim: document.notice)
                        .font(.callout)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: document.licenseName)
                        .font(.headline)
                    Text(verbatim: document.licenseText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding()
        }
        .navigationTitle(document.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(String(localized: L10n.Settings.thirdPartyPurpose)) {
                Text(verbatim: document.purpose)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(String(localized: L10n.Settings.thirdPartyLicense)) {
                Text(verbatim: document.licenseName)
            }
            Link(destination: document.sourceURL) {
                LabeledContent(String(localized: L10n.Settings.thirdPartySource)) {
                    Image(systemName: "arrow.up.right.square")
                }
            }
            if let revision = document.revision {
                LabeledContent(String(localized: L10n.Settings.thirdPartyPinnedRevision)) {
                    Text(verbatim: revision)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
            if let artifactSHA256 = document.artifactSHA256 {
                LabeledContent(String(localized: L10n.Settings.thirdPartyArtifactSHA256)) {
                    Text(verbatim: artifactSHA256)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }
        }
    }
}
