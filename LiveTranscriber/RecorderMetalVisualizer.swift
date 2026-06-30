import MetalKit
import QuartzCore
import SwiftUI
import UIKit

struct RecorderMetalVisualizer: UIViewRepresentable {
    var isActive: Bool
    var level: Float

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        view.isOpaque = false
        view.isPaused = false
        view.preferredFramesPerSecond = isActive ? 30 : 12
        view.delegate = context.coordinator
        context.coordinator.configure(with: view.device, colorPixelFormat: view.colorPixelFormat)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        view.preferredFramesPerSecond = isActive ? 30 : 12
        context.coordinator.update(isActive: isActive, level: level)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?
        private var startTime = CACurrentMediaTime()
        private var isActive = false
        private var targetLevel: Float = 0
        private var displayedLevel: Float = 0

        func configure(with device: MTLDevice?, colorPixelFormat: MTLPixelFormat) {
            guard let device,
                  commandQueue == nil,
                  let library = device.makeDefaultLibrary(),
                  let vertexFunction = library.makeFunction(name: "recorderVisualizerVertex"),
                  let fragmentFunction = library.makeFunction(name: "recorderVisualizerFragment") else {
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
            commandQueue = device.makeCommandQueue()
        }

        func update(isActive: Bool, level: Float) {
            self.isActive = isActive
            targetLevel = min(max(level, 0), 1)
        }

        func draw(in view: MTKView) {
            guard let pipelineState,
                  let commandQueue,
                  let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }

            let rise: Float = isActive ? 0.34 : 0.08
            let fall: Float = isActive ? 0.12 : 0.20
            let smoothing = targetLevel > displayedLevel ? rise : fall
            displayedLevel += (targetLevel - displayedLevel) * smoothing

            var uniforms = RecorderVisualizerUniforms(
                time: Float(CACurrentMediaTime() - startTime),
                level: displayedLevel,
                active: isActive ? 1 : 0,
                size: SIMD2<Float>(
                    Float(max(view.drawableSize.width, 1)),
                    Float(max(view.drawableSize.height, 1))
                ),
                tint: SIMD4<Float>(0.96, 0.22, 0.10, 1.0)
            )

            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RecorderVisualizerUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    }
}

private struct RecorderVisualizerUniforms {
    var time: Float
    var level: Float
    var active: Float
    var size: SIMD2<Float>
    var tint: SIMD4<Float>
}
