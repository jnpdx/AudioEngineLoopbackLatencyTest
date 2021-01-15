//
//  AudioVisualization.swift
//  AudioEngineLoopbackLatencyTest
//
//  Created by John Nastos on 1/6/21.
//

import SwiftUI
import Accelerate

let kSamplesPerPixel : UInt32 = 10

struct AudioVisualization: View {
    var graphData: [Float]
    
    @Environment(\.colorScheme) var colorScheme
    
    var gridColor : Color {
        colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)
    }
    
    var body: some View {
        GeometryReader { geometry in
            
            //draw a grid every 1000 samples
            Path { path in
                let gridColumnWidth = CGFloat(100) / CGFloat(kSamplesPerPixel)
                for gridColumnIndex in 0..<Int(geometry.size.width/gridColumnWidth) {
                    path.move(to: CGPoint(x: CGFloat(gridColumnIndex) * gridColumnWidth, y: 0))
                    path.addLine(to: CGPoint(x: CGFloat(gridColumnIndex) * gridColumnWidth, y: geometry.size.height))
                }
            }
            .stroke(gridColor)
            
            //the waveform
            Path { path in
                let pointWidth = geometry.size.width / CGFloat(graphData.count)
                let halfHeight = geometry.size.height / 2
                for pointIndex in 0..<graphData.count {
                    let pointValue = graphData[pointIndex]
                    let xPos = CGFloat(pointIndex) * pointWidth
                    let yLength = max(0.5,halfHeight * CGFloat(pointValue))
                    path.move(to: CGPoint(x: xPos,
                                          y: halfHeight - yLength))
                    path.addLine(to: CGPoint(x: xPos, y: halfHeight + yLength))
                }
            }
            .stroke()
        }
    }
}

func convertAudioFileToVisualData(fileUrl: URL) -> ([Float],[Float]) {
    guard let buffer = loadAudioFile(fileUrl) else {
        fatalError("Couldn't load buffer")
    }
    
    let samplesPerPixel = kSamplesPerPixel
    
    let pixelCount = Int(buffer.frameLength / samplesPerPixel)
    let filter = [Float](repeating: 1.0/Float(samplesPerPixel), count: Int(samplesPerPixel))

    let bufferLength = vDSP_Length(buffer.frameLength)
    
    var processingBufferL = [Float](repeating: 0.0, count: Int(bufferLength))
    var processingBufferR = [Float](repeating: 0.0, count: Int(bufferLength))
    
    //get absolute values to show magnitude
    vDSP_vabs(buffer.floatChannelData![0], 1, &processingBufferL, 1, bufferLength)
    vDSP_vabs(buffer.floatChannelData![1], 1, &processingBufferR, 1, bufferLength)
    
    //clip to range
    var high:Float = 1.0
    var low:Float = 0.0
    vDSP_vclip(processingBufferL, 1, &low, &high, &processingBufferL, 1, bufferLength);
    vDSP_vclip(processingBufferR, 1, &low, &high, &processingBufferR, 1, bufferLength);
    
    // downsample and average
    var downSampledDataL = [Float](repeating: 0.0, count: pixelCount)
    var downSampledDataR = [Float](repeating: 0.0, count: pixelCount)
        
    vDSP_desamp(processingBufferL,
                    vDSP_Stride(samplesPerPixel),
                    filter, &downSampledDataL,
                    vDSP_Length(pixelCount),
                    vDSP_Length(samplesPerPixel))
    
    vDSP_desamp(processingBufferR,
                    vDSP_Stride(samplesPerPixel),
                    filter, &downSampledDataR,
                    vDSP_Length(pixelCount),
                    vDSP_Length(samplesPerPixel))
    
    return (downSampledDataL,downSampledDataR)
}
