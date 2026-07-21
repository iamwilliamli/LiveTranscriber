import SwiftUI

/// Animated "unboxing" splash shown once per cold launch, after onboarding is complete.
/// The opening frame matches the static launch screen (ambient gradient only) and the
/// closing tableau recreates the app icon — condenser mic, robot, transcript pills —
/// before the overlay crossfades into the main UI. Tapping anywhere skips it.
struct LaunchSplashView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var boxVisible = false
    @State private var boxExited = false
    @State private var micRaised = false
    @State private var groundVisible = false
    @State private var robotVisible = false
    @State private var antennaAngle: Double = 0
    @State private var eyeSquint: CGFloat = 1
    @State private var ticksVisible = false
    @State private var ringScale: CGFloat = 0.55
    @State private var ringOpacity: Double = 0
    @State private var pillsVisible: [Bool] = [false, false, false]
    @State private var titleVisible = false
    @State private var timeline: Task<Void, Never>?
    @State private var hasFinished = false

    var body: some View {
        GeometryReader { proxy in
            let fitScale = min(1, proxy.size.width / Stage.width, proxy.size.height / Stage.height)

            ZStack {
                background
                stage
                    .frame(width: Stage.width, height: Stage.height)
                    .scaleEffect(fitScale)
                    .offset(y: Stage.verticalBias * fitScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            finish()
        }
        .onAppear {
            startTimeline()
        }
        .onDisappear {
            timeline?.cancel()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Live Transcriber"))
        .accessibilityValue(Text(L10n.Splash.tagline))
    }

    // Mirrors TranscriptionView's standby ambient background so the crossfade
    // into the main UI never shifts the backdrop.
    private var background: some View {
        ZStack {
            AppTheme.groupedBackground
            LinearGradient(
                stops: [
                    .init(color: AppTheme.warning.opacity(colorScheme == .dark ? 0.20 : 0.52), location: 0),
                    .init(color: AppTheme.warning.opacity(colorScheme == .dark ? 0.12 : 0.25), location: 0.20),
                    .init(color: AppTheme.warning.opacity(colorScheme == .dark ? 0.04 : 0.08), location: 0.42),
                    .init(color: .clear, location: 0.64)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var stage: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .stroke(SplashPalette.micRed.opacity(0.5), lineWidth: 2)
                .frame(width: Stage.ringSize, height: Stage.ringSize)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
                .position(Stage.capCenter)

            Ellipse()
                .fill(groundColor)
                .frame(width: 90, height: 13)
                .blur(radius: 3)
                .opacity(groundVisible ? 1 : 0)
                .position(x: Stage.micCenterX, y: 508)

            micLayer

            boxView

            RobotHeadView(
                width: 102,
                structureInk: structureInk,
                antennaAngle: antennaAngle,
                eyeSquint: eyeSquint
            )
            .scaleEffect(robotVisible ? 1 : 0.3)
            .opacity(robotVisible ? 1 : 0)
            .offset(y: robotVisible ? 0 : 16)
            .position(x: 273, y: 201)

            tick(width: 4.5, height: 16.5, rotation: 26)
                .position(x: 330, y: 146)
            tick(width: 4.5, height: 12, rotation: 54)
                .position(x: 347, y: 166)

            pills

            titleBlock
        }
    }

    private var micLayer: some View {
        SplashMicView(structureInk: structureInk)
            .frame(width: Stage.micSize.width, height: Stage.micSize.height)
            .offset(y: micRaised ? 0 : Stage.micDropOffset)
            .position(x: Stage.micCenterX, y: Stage.micRestCenterY)
            .frame(width: Stage.width, height: Stage.height, alignment: .topLeading)
            .mask(alignment: .top) {
                // The box mouth: the mic only exists above this line while rising.
                Rectangle()
                    .frame(height: Stage.mouthY)
            }
    }

    private var boxView: some View {
        let scale: CGFloat = boxVisible ? (boxExited ? 0.94 : 1) : 0.85
        let yOffset: CGFloat = boxVisible ? (boxExited ? 50 : 0) : 40
        let opacity: Double = boxVisible && !boxExited ? 1 : 0

        return SplashBoxView()
            .frame(width: 210, height: 144)
            .scaleEffect(scale)
            .offset(y: yOffset)
            .opacity(opacity)
            .position(x: Stage.width / 2, y: 632)
    }

    private var pills: some View {
        ForEach(0..<3, id: \.self) { index in
            let spec = Self.pillSpecs[index]
            Capsule()
                .fill(spec.isRose ? SplashPalette.rose : SplashPalette.periwinkle)
                .frame(width: spec.width, height: 26)
                .overlay(Capsule().strokeBorder(SplashPalette.ink, lineWidth: 4))
                .opacity(pillsVisible[index] ? 1 : 0)
                .offset(x: pillsVisible[index] ? 0 : 40)
                .position(x: spec.x, y: spec.y)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 10) {
            Text(verbatim: "Live Transcriber")
                .font(.redditSans(size: 31, weight: .bold))
                .foregroundStyle(titleColor)
            Text(L10n.Splash.tagline)
                .font(.redditSans(size: 15, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(SplashPalette.tagline)
        }
        .opacity(titleVisible ? 1 : 0)
        .offset(y: titleVisible ? 0 : 14)
        .position(x: Stage.width / 2, y: 630)
    }

    private func tick(width: CGFloat, height: CGFloat, rotation: Double) -> some View {
        Capsule()
            .fill(SplashPalette.tickBlue)
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(ticksVisible ? 1 : 0.4)
            .opacity(ticksVisible ? 1 : 0)
    }

    private var structureInk: Color {
        colorScheme == .dark ? Color(red: 0.92, green: 0.90, blue: 0.88) : SplashPalette.ink
    }

    private var titleColor: Color {
        colorScheme == .dark
            ? Color(red: 0.953, green: 0.929, blue: 0.913)
            : Color(red: 0.137, green: 0.114, blue: 0.102)
    }

    private var groundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : SplashPalette.ink.opacity(0.12)
    }

    private func startTimeline() {
        guard timeline == nil else {
            return
        }

        guard !reduceMotion else {
            showFinalTableau()
            timeline = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.9))
                guard !Task.isCancelled else {
                    return
                }
                finish()
            }
            return
        }

        timeline = Task { @MainActor in
            let clock = ContinuousClock()
            let start = clock.now

            @MainActor
            func waitUntil(_ seconds: Double) async -> Bool {
                try? await clock.sleep(until: start.advanced(by: .seconds(seconds)))
                return !Task.isCancelled
            }

            guard await waitUntil(0.02) else { return }
            withAnimation(.spring(duration: 0.55, bounce: 0.28)) { boxVisible = true }

            guard await waitUntil(0.75) else { return }
            withAnimation(.spring(duration: 0.85, bounce: 0.30)) { micRaised = true }

            guard await waitUntil(1.40) else { return }
            withAnimation(.spring(duration: 0.60, bounce: 0.35)) { robotVisible = true }

            guard await waitUntil(1.45) else { return }
            withAnimation(.easeIn(duration: 0.50)) { boxExited = true }

            guard await waitUntil(1.50) else { return }
#if os(iOS)
            HapticFeedback.softImpact(intensity: 0.55)
#endif

            guard await waitUntil(1.55) else { return }
            ringOpacity = 0.7
            ringScale = 0.55
            withAnimation(.easeOut(duration: 0.85)) {
                ringScale = 1.4
                ringOpacity = 0
            }

            guard await waitUntil(1.60) else { return }
            withAnimation(.easeOut(duration: 0.40)) { groundVisible = true }
            withAnimation(.easeOut(duration: 0.15)) { ticksVisible = true }

            guard await waitUntil(1.75) else { return }
            withAnimation(.easeInOut(duration: 0.15)) { antennaAngle = 10 }
#if os(iOS)
            HapticFeedback.softImpact(intensity: 0.40)
#endif

            guard await waitUntil(1.80) else { return }
            withAnimation(.spring(duration: 0.50, bounce: 0.22)) { pillsVisible[0] = true }

            guard await waitUntil(1.90) else { return }
            withAnimation(.easeInOut(duration: 0.15)) { antennaAngle = -8 }

            guard await waitUntil(1.93) else { return }
            withAnimation(.spring(duration: 0.50, bounce: 0.22)) { pillsVisible[1] = true }

            guard await waitUntil(1.95) else { return }
            withAnimation(.easeOut(duration: 0.25)) { ticksVisible = false }

            guard await waitUntil(2.05) else { return }
            withAnimation(.easeInOut(duration: 0.15)) { antennaAngle = 0 }
            withAnimation(.easeIn(duration: 0.10)) { eyeSquint = 0.15 }

            guard await waitUntil(2.06) else { return }
            withAnimation(.spring(duration: 0.50, bounce: 0.22)) { pillsVisible[2] = true }

            guard await waitUntil(2.17) else { return }
            withAnimation(.easeOut(duration: 0.12)) { eyeSquint = 1 }

            guard await waitUntil(2.20) else { return }
            withAnimation(.easeOut(duration: 0.55)) { titleVisible = true }

            guard await waitUntil(2.95) else { return }
            finish()
        }
    }

    private func showFinalTableau() {
        boxVisible = true
        boxExited = true
        micRaised = true
        groundVisible = true
        robotVisible = true
        pillsVisible = [true, true, true]
        titleVisible = true
    }

    private func finish() {
        guard !hasFinished else {
            return
        }
        hasFinished = true
        timeline?.cancel()
        onFinished()
    }

    private static let pillSpecs: [(width: CGFloat, x: CGFloat, y: CGFloat, isRose: Bool)] = [
        (100, 299, 470, false),
        (82, 290, 509, false),
        (61, 279.5, 547, true)
    ]
}

// MARK: - Stage geometry

/// Fixed design canvas; scaled down uniformly on smaller screens.
private enum Stage {
    static let width: CGFloat = 390
    static let height: CGFloat = 720
    static let verticalBias: CGFloat = -44
    static let mouthY: CGFloat = 560
    static let micSize = CGSize(width: 228, height: 258)
    static let micCenterX: CGFloat = 157
    static let micRestCenterY: CGFloat = 379
    static let micDropOffset: CGFloat = 330
    static let capCenter = CGPoint(x: 157, y: 341.5)
    static let ringSize: CGFloat = 210
}

// MARK: - Icon palette

/// Colors sampled from the app icon artwork; intentionally fixed across appearances
/// except for freestanding ink strokes, which lighten in dark mode for contrast.
private enum SplashPalette {
    static let ink = Color(red: 0.149, green: 0.125, blue: 0.098)
    static let micRed = Color(red: 0.941, green: 0.294, blue: 0.267)
    static let periwinkle = Color(red: 0.651, green: 0.678, blue: 0.937)
    static let rose = Color(red: 0.961, green: 0.565, blue: 0.545)
    static let tickBlue = Color(red: 0.357, green: 0.475, blue: 0.910)
    static let boxBorder = Color(red: 0.949, green: 0.894, blue: 0.867)
    static let boxLabel = Color(red: 0.804, green: 0.725, blue: 0.686)
    static let tagline = Color(red: 0.627, green: 0.561, blue: 0.533)
}

// MARK: - Mic

private struct SplashMicView: View {
    let structureInk: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 84,
                bottomTrailingRadius: 84,
                topTrailingRadius: 0,
                style: .circular
            )
            .stroke(structureInk, lineWidth: 5)
            .frame(width: 168, height: 159)
            .mask(Rectangle().padding(.top, 3))
            .position(x: 114, y: 130.5)

            capsuleBody
                .position(x: 114, y: 91.5)

            Capsule()
                .fill(structureInk)
                .frame(width: 10, height: 36)
                .position(x: 113, y: 228)

            Capsule()
                .fill(structureInk)
                .frame(width: 108, height: 10)
                .position(x: 114, y: 249)
        }
    }

    private var capsuleBody: some View {
        ZStack(alignment: .topLeading) {
            Capsule(style: .circular)
                .fill(Color.white)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(SplashPalette.micRed)
                    .frame(width: 58)
                Color.clear
            }
            .clipShape(Capsule(style: .circular))

            RoundedRectangle(cornerRadius: 4.5)
                .fill(SplashPalette.ink)
                .frame(width: 36, height: 9)
                .position(x: 37.5, y: 42)

            RoundedRectangle(cornerRadius: 3.5)
                .fill(SplashPalette.ink)
                .frame(width: 7, height: 7.5)
                .position(x: 91, y: 40)

            RoundedRectangle(cornerRadius: 3.5)
                .fill(SplashPalette.ink)
                .frame(width: 7, height: 7.5)
                .position(x: 104.5, y: 40)

            RoundedRectangle(cornerRadius: 3.5)
                .fill(SplashPalette.ink)
                .frame(width: 7, height: 69)
                .position(x: 97, y: 97.5)

            Capsule(style: .circular)
                .stroke(SplashPalette.ink, lineWidth: 5)
        }
        .frame(width: 126, height: 183)
        .shadow(color: SplashPalette.ink.opacity(0.10), radius: 9, y: 7)
    }
}

// MARK: - Robot

private struct RobotHeadView: View {
    let width: CGFloat
    let structureInk: Color
    let antennaAngle: Double
    let eyeSquint: CGFloat

    var body: some View {
        let k = width / 110

        ZStack(alignment: .topLeading) {
            ZStack(alignment: .top) {
                Circle()
                    .fill(SplashPalette.micRed)
                    .frame(width: 13 * k, height: 13 * k)
                    .overlay(Circle().stroke(SplashPalette.ink, lineWidth: 3 * k))
                Capsule()
                    .fill(structureInk)
                    .frame(width: 3.5 * k, height: 19 * k)
                    .offset(y: 11 * k)
            }
            .frame(width: 13 * k, height: 30 * k, alignment: .top)
            .rotationEffect(.degrees(antennaAngle), anchor: .bottom)
            .position(x: 55 * k, y: 15 * k)

            RoundedRectangle(cornerRadius: 6 * k)
                .fill(SplashPalette.micRed)
                .frame(width: 11 * k, height: 24 * k)
                .overlay(RoundedRectangle(cornerRadius: 6 * k).stroke(SplashPalette.ink, lineWidth: 3 * k))
                .position(x: 5.5 * k, y: 66 * k)

            RoundedRectangle(cornerRadius: 6 * k)
                .fill(SplashPalette.micRed)
                .frame(width: 11 * k, height: 24 * k)
                .overlay(RoundedRectangle(cornerRadius: 6 * k).stroke(SplashPalette.ink, lineWidth: 3 * k))
                .position(x: 104.5 * k, y: 66 * k)

            RoundedRectangle(cornerRadius: 30 * k)
                .fill(Color.white)
                .frame(width: 94 * k, height: 76 * k)
                .overlay(RoundedRectangle(cornerRadius: 30 * k).stroke(SplashPalette.ink, lineWidth: 3 * k))
                .shadow(color: SplashPalette.ink.opacity(0.07), radius: 0, y: 5 * k)
                .position(x: 55 * k, y: 66 * k)

            RoundedRectangle(cornerRadius: 16 * k)
                .fill(SplashPalette.ink)
                .frame(width: 66 * k, height: 40 * k)
                .position(x: 55 * k, y: 62 * k)

            HappyEyeShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))
                .frame(width: 14 * k, height: 7 * k)
                .scaleEffect(x: 1, y: eyeSquint, anchor: .bottom)
                .position(x: 40 * k, y: 59.5 * k)

            HappyEyeShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))
                .frame(width: 14 * k, height: 7 * k)
                .scaleEffect(x: 1, y: eyeSquint, anchor: .bottom)
                .position(x: 70 * k, y: 59.5 * k)
        }
        .frame(width: width, height: 106 * k, alignment: .topLeading)
    }
}

/// Upward arc — the robot's happy closed eye.
private struct HappyEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: true
        )
        return path
    }
}

// MARK: - Box

private struct SplashBoxView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(SplashPalette.boxBorder, lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 17, y: 9)

            Circle()
                .fill(SplashPalette.micRed)
                .frame(width: 13.5, height: 13.5)
                .offset(y: -26)

            Text(verbatim: "LIVETRANSCRIBER")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2.7)
                .foregroundStyle(SplashPalette.boxLabel)
                .offset(y: 2)
        }
    }
}

#if DEBUG
#Preview("Launch Splash") {
    LaunchSplashView {}
}

#Preview("Launch Splash · Dark") {
    LaunchSplashView {}
        .preferredColorScheme(.dark)
}
#endif
