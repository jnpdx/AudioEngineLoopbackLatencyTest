//
//  UtilityFunctions.swift
//  AudioEngineLoopbackLatencyTest
//
//  Created by John Nastos on 1/6/21.
//

import Foundation
import AVFoundation

func calculateSecondsToTicks() -> Double {
    var tinfo = mach_timebase_info()
    mach_timebase_info(&tinfo)
    let timecon = Double(tinfo.denom) / Double(tinfo.numer)
    return timecon * 1_000_000_000
}

func loadAudioFile(_ url: URL) -> AVAudioPCMBuffer? {
    guard let audioFile = try? AVAudioFile(forReading: url) else {
        fatalError("Couldn't load file")
    }
    return audioFileToBuffer(audioFile)
}

func loadAudioFile(_ filename: String) -> AVAudioPCMBuffer? {
    guard let fileURL = Bundle.main.url(forResource: filename, withExtension: "m4a"),
          let audioFile = try? AVAudioFile(forReading: fileURL) else {
        fatalError("Couldn't load file")
    }
    
    return audioFileToBuffer(audioFile)
}

func audioFileToBuffer(_ audioFile: AVAudioFile) -> AVAudioPCMBuffer? {
    let audioFormat = audioFile.processingFormat
    let audioFrameCount = UInt32(audioFile.length)
    guard let audioFileBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: audioFrameCount) else {
        fatalError("Couldn't make buffer")
    }
    print("Audio file format is: \(audioFormat) for \(audioFile.url.lastPathComponent)")
    do{
        try audioFile.read(into: audioFileBuffer)
    } catch{
        fatalError("Error reading into buffer: \(error)")
    }
    return audioFileBuffer
}
