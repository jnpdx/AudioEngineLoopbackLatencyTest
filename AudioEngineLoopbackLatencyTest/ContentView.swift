//
//  ContentView.swift
//  AudioEngineLoopbackLatencyTest
//
//  Created by John Nastos on 1/6/21.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var audioManager = AudioManager()
    
    var body: some View {
        VStack(spacing: 20) {
            if !audioManager.isRunning {
                Button(action: {
                    audioManager.start()
                }) {
                    Text("Start")
                }
            } else {
                Button(action: {
                    audioManager.stop()
                }) {
                    Text("Stop")
                }
            }
            
            Button(action: {
                audioManager.playResult()
            }) {
                Text("Play result")
            }.disabled(!audioManager.hasResultFileToPlay)
            
            Divider()
            
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    AudioVisualization(graphData: audioManager.floatDataToDisplay.0)
                        .frame(width: CGFloat(audioManager.floatDataToDisplay.0.count),
                               height: geometry.size.height / 2)
                    AudioVisualization(graphData: audioManager.floatDataToDisplay.1)
                        .frame(width: CGFloat(audioManager.floatDataToDisplay.1.count),
                               height: geometry.size.height / 2)
                }
                .frame(height: geometry.size.height)
            }
            
            if audioManager.floatDataToDisplay.0.count > 0 {
                Text("Scale: 1pt = \(kSamplesPerPixel) samples / Grid shows 100 sample increments")
                Text("Top graph: original audio / Bottom graph: recorded input audio")
            }
        }
        .padding()
        .onAppear {
            #if os(iOS)
            AVAudioSession.sharedInstance().requestRecordPermission { _ in
                
            }
            #endif
        }
    }
}
