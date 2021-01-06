//
//  AudioVisualization.swift
//  AudioEngineLoopbackLatencyTest
//
//  Created by John Nastos on 1/6/21.
//

import SwiftUI
import Accelerate

let kSamplesPerPixel : UInt32 = 50

struct AudioVisualization: View {
    var graphData: [Float]
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let pointWidth = geometry.size.width / CGFloat(graphData.count)
                let halfHeight = geometry.size.height / 2
                for pointIndex in 0..<graphData.count {
                    let pointValue = graphData[pointIndex]
                    let xPos = CGFloat(pointIndex) * pointWidth
                    let yLength = halfHeight * CGFloat(pointValue)
                    path.move(to: CGPoint(x: xPos,
                                          y: halfHeight - yLength))
                    path.addLine(to: CGPoint(x: xPos, y: halfHeight + yLength))
                }
            }.stroke()
        }
    }
}

func convertAudioFileToVisualData(fileUrl: URL) -> ([Float],[Float]) {
    guard let buffer = loadAudioFile(fileUrl) else {
        fatalError("Couldn't load buffer")
    }
    
    let samplesPerPixel = kSamplesPerPixel
    
    let pixelCount = Int(buffer.frameLength / samplesPerPixel)
    let filter = [Float](repeating: 10.0 / Float(samplesPerPixel), count: Int(samplesPerPixel))

    
    // downsample and average
    var downSampledDataL = [Float](repeating: 0.0, count: pixelCount)
    var downSampledDataR = [Float](repeating: 0.0, count: pixelCount)
        
    vDSP_desamp(buffer.floatChannelData![0],
                    vDSP_Stride(samplesPerPixel),
                    filter, &downSampledDataL,
                    vDSP_Length(pixelCount),
                    vDSP_Length(samplesPerPixel))
    
    vDSP_desamp(buffer.floatChannelData![1],
                    vDSP_Stride(samplesPerPixel),
                    filter, &downSampledDataR,
                    vDSP_Length(pixelCount),
                    vDSP_Length(samplesPerPixel))
    
    return (downSampledDataL,downSampledDataR)
}
