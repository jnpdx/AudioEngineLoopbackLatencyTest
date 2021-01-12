//
//  AudioManager.swift
//  AudioEngineLoopbackLatencyTest
//
//  Created by John Nastos on 1/6/21.
//

import Foundation
import AVFoundation
import AudioToolbox
import Accelerate
import CoreAudio

struct AudioManagerState {
    var secondsToTicks : Double = calculateSecondsToTicks()
    
    //time markers (all in host time)
    var audioBuffersScheduledAtHost : UInt64 = 0 //when does the original audio get played
    var inputNodeTapBeganAtHost : UInt64 = 0 //the first call to the input node tap
    var outputNodeTapBeganAtHost : UInt64 = 0 //first call to the output node tap
    
    var outputLatency : UInt64 = 0
    var inputLatency : UInt64 = 0
}

class AudioManager : ObservableObject {
    @Published var isRunning = false
    @Published var hasResultFileToPlay = false
    @Published var floatDataToDisplay : ([Float],[Float]) = ([],[])
    
    public var state = AudioManagerState()
    
    private var audioEngine = AVAudioEngine()
    
    //this node/buffer will play back our pre-recorded metronome audio file
    private var playerNode = AVAudioPlayerNode()
    private var metronomeFileBuffer : AVAudioPCMBuffer?
    
    //these files will get written to from the input taps
    private var inputRecordingFile : AVAudioFile?
    private var outputRecordingFile : AVAudioFile?
    
    //once the sync is done, this player can be used to play the resulting file
    private var resultAudioPlayer : AVAudioPlayer?
}

/* START AND STOP FUNCTIONS */
extension AudioManager {
    func start() {
        setupAudio()
        createRecordingAudioFiles()
        
        self.isRunning = true
        do {
            try audioEngine.start()
            print("Audio engine running")
        } catch {
            fatalError("Couldn't start engine: \(error)")
        }
        
        scheduleAndPlayAudioBuffers()
    }
    
    func stop() {
        DispatchQueue.main.async {
            self.audioEngine.stop()
            self.isRunning = false
            print("Audio engine stopped")
            self.createResultFile()
        }
    }
}

/* AUDIO ENGINE SETUP
 
    Set up the AVAudioEngine (connect nodes, input taps, etc)
    Reset state to get ready to capture timing values
 */
extension AudioManager {
    func setupAudio() {
        audioEngine.stop()
        playerNode.stop()
        playerNode.reset()
        
        state = AudioManagerState()
        loadAudioBuffers()
        
        setupAudioSession()
        audioEngine = AVAudioEngine()
        
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to:audioEngine.mainMixerNode, format: audioEngine.mainMixerNode.inputFormat(forBus: 0))
        
        installTapOnInputNode()
        installTapOnOutputNode()
        
        audioEngine.prepare()
        self.printLowLevelAudioProperties()

    }
    
    func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true)
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker])
            print("Set audio session...")
            
            print("IO Buffer: \(AVAudioSession.sharedInstance().ioBufferDuration) -- \(AVAudioSession.sharedInstance().ioBufferDuration * audioEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate)")
            print("Input latency: \(AVAudioSession.sharedInstance().inputLatency * audioEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate)")
            print("Output latency: \(AVAudioSession.sharedInstance().outputLatency * audioEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate)")
            //useful for iOS?
            //storedLatencyFrames = (AVAudioSession.sharedInstance().inputLatency + AVAudioSession.sharedInstance().outputLatency) * audioEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        } catch {
            assertionFailure("Error setting session active: \(error.localizedDescription)")
        }
        #endif
    }
    
    func printLowLevelAudioProperties() {
        #if os(macOS)
        var status: OSStatus = noErr
        
        //TODO: get device ID on Catalyst
        
        //maybe try to get the safety offset?
        let outputNodeID = audioEngine.outputNode.auAudioUnit.deviceID
        var pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyLatency,
                                            mScope: kAudioObjectPropertyScopeOutput,
                                            mElement: kAudioObjectPropertyElementMaster)
        var answerSize = UInt32(MemoryLayout<UInt32>.size)
        var answer : UInt32 = 0
        status = AudioObjectGetPropertyData(outputNodeID, &pa, 0, nil, &answerSize, &answer)
        if status != noErr {
            fatalError("Error: \(status)")
        }
        print("kAudioDevicePropertyLatency (output - output scope): \(answer)")
        let outputLatency = answer
        
//        pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyLatency,
//                                            mScope: kAudioObjectPropertyScopeInput,
//                                            mElement: kAudioObjectPropertyElementMaster)
//        answerSize = UInt32(MemoryLayout<UInt32>.size)
//        answer = 0
//        status = AudioObjectGetPropertyData(outputNodeID, &pa, 0, nil, &answerSize, &answer)
//        if status != noErr {
//            fatalError("Error: \(status)")
//        }
//        print("kAudioDevicePropertyLatency (output - input scope): \(answer)")
        
        let inputNodeID = audioEngine.inputNode.auAudioUnit.deviceID
        pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyLatency,
                                            mScope: kAudioObjectPropertyScopeInput,
                                            mElement: kAudioObjectPropertyElementMaster)
        answerSize = UInt32(MemoryLayout<UInt32>.size)
        answer = 0
        status = AudioObjectGetPropertyData(inputNodeID, &pa, 0, nil, &answerSize, &answer)
        if status != noErr {
            fatalError("Error: \(status)")
        }
        print("kAudioDevicePropertyLatency (input -- input scope): \(answer)")
        let inputLatency = answer
        
//        pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyLatency,
//                                            mScope: kAudioObjectPropertyScopeOutput,
//                                            mElement: kAudioObjectPropertyElementMaster)
//        answerSize = UInt32(MemoryLayout<UInt32>.size)
//        answer = 0
//        status = AudioObjectGetPropertyData(inputNodeID, &pa, 0, nil, &answerSize, &answer)
//        if status != noErr {
//            fatalError("Error: \(status)")
//        }
//        print("kAudioDevicePropertyLatency (input -- output scope): \(answer)")
        
        pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertySafetyOffset,
                                            mScope: kAudioObjectPropertyScopeOutput,
                                            mElement: kAudioObjectPropertyElementMaster)
        answerSize = UInt32(MemoryLayout<UInt32>.size)
        answer = 0
        status = AudioObjectGetPropertyData(outputNodeID, &pa, 0, nil, &answerSize, &answer)
        if status != noErr {
            fatalError("Error: \(status)")
        }
        print("kAudioDevicePropertySafetyOffset (output -- output scope): \(answer)")
        let outputSafety = answer
        
//        pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertySafetyOffset,
//                                            mScope: kAudioObjectPropertyScopeInput,
//                                            mElement: kAudioObjectPropertyElementMaster)
//        answerSize = UInt32(MemoryLayout<UInt32>.size)
//        answer = 0
//        status = AudioObjectGetPropertyData(outputNodeID, &pa, 0, nil, &answerSize, &answer)
//        if status != noErr {
//            fatalError("Error: \(status)")
//        }
//        print("kAudioDevicePropertySafetyOffset (output -- input scope): \(answer)")
        
        pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertySafetyOffset,
                                            mScope: kAudioObjectPropertyScopeInput,
                                            mElement: kAudioObjectPropertyElementMaster)
        answerSize = UInt32(MemoryLayout<UInt32>.size)
        answer = 0
        status = AudioObjectGetPropertyData(inputNodeID, &pa, 0, nil, &answerSize, &answer)
        if status != noErr {
            fatalError("Error: \(status)")
        }
        print("kAudioDevicePropertySafetyOffset (input -- input scope): \(answer)")
        let inputSafety = answer
        
//        pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertySafetyOffset,
//                                            mScope: kAudioObjectPropertyScopeOutput,
//                                            mElement: kAudioObjectPropertyElementMaster)
//        answerSize = UInt32(MemoryLayout<UInt32>.size)
//        answer = 0
//        status = AudioObjectGetPropertyData(inputNodeID, &pa, 0, nil, &answerSize, &answer)
//        if status != noErr {
//            fatalError("Error: \(status)")
//        }
//        print("kAudioDevicePropertySafetyOffset (input -- output scope): \(answer)")
        
        pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferSize,
                                            mScope: kAudioObjectPropertyScopeOutput,
                                            mElement: kAudioObjectPropertyElementMaster)
        answerSize = UInt32(MemoryLayout<UInt32>.size)
        answer = 0
        status = AudioObjectGetPropertyData(outputNodeID, &pa, 0, nil, &answerSize, &answer)
        if status != noErr {
            fatalError("Error: \(status)")
        }
        print("kAudioDevicePropertyBufferSize (output -- output scope): \(answer) *bytes*")
        
        pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferSize,
                                            mScope: kAudioObjectPropertyScopeInput,
                                            mElement: kAudioObjectPropertyElementMaster)
        answerSize = UInt32(MemoryLayout<UInt32>.size)
        answer = 0
        status = AudioObjectGetPropertyData(inputNodeID, &pa, 0, nil, &answerSize, &answer)
        if status != noErr {
            fatalError("Error: \(status)")
        }
        print("kAudioDevicePropertyBufferSize (input -- input scope): \(answer) *bytes*")
        
        var streamLatency : UInt32 = 0
        var numStreams : UInt32 = 0
        
        pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMaster)
        status = AudioObjectGetPropertyDataSize(outputNodeID, &pa, 0, nil, &numStreams)
        guard  status == noErr else {
            fatalError("Status: \(status)")
        }
        var streams = [AudioStreamID](repeating: 0, count: Int(numStreams))
        var streamsSize = UInt32(MemoryLayout<AudioStreamID>.size) * numStreams
        status = AudioObjectGetPropertyData(outputNodeID, &pa, 0, nil, &streamsSize, &streams)
        print("Streams: ")
        print(streams)
        guard  status == noErr else {
            fatalError("Status: \(status)")
        }
        pa.mSelector = kAudioDevicePropertyLatency
        answerSize = UInt32(MemoryLayout<UInt32>.size)
        answer = 0
        status = AudioObjectGetPropertyData(streams[0], &pa, 0, nil, &answerSize, &streamLatency)
        guard  status == noErr else {
            fatalError("Status: \(status)")
        }
        print("Stream latency (output): \(streamLatency)")
        let outputStreamLatency = streamLatency
        
        pa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMaster)
        status = AudioObjectGetPropertyDataSize(outputNodeID, &pa, 0, nil, &numStreams)
        guard  status == noErr else {
            fatalError("Status: \(status)")
        }
        streams = [AudioStreamID](repeating: 0, count: Int(numStreams))
        streamsSize = UInt32(MemoryLayout<AudioStreamID>.size) * numStreams
        status = AudioObjectGetPropertyData(inputNodeID, &pa, 0, nil, &streamsSize, &streams)
        print("Streams: ")
        print(streams)
        guard  status == noErr else {
            fatalError("Status: \(status)")
        }
        pa.mSelector = kAudioDevicePropertyLatency
        answerSize = UInt32(MemoryLayout<UInt32>.size)
        answer = 0
        status = AudioObjectGetPropertyData(streams[0], &pa, 0, nil, &answerSize, &streamLatency)
        guard  status == noErr else {
            fatalError("Status: \(status)")
        }
        print("Stream latency (input): \(streamLatency)")
        let inputStreamLatency = streamLatency
        
        //jn's mac : need to get to about ~720 samples
        //mn's mac : need to get to about ~1200 samples
        /*
         
         JN numbers:
         
         kAudioDevicePropertyLatency (output - output scope): 399
         kAudioDevicePropertyLatency (output - input scope): 0
         kAudioDevicePropertyLatency (input -- input scope): 0
         kAudioDevicePropertyLatency (input -- output scope): 399
         kAudioDevicePropertySafetyOffset (output -- output scope): 93
         kAudioDevicePropertySafetyOffset (output -- input scope): 66
         kAudioDevicePropertySafetyOffset (input -- input scope): 66
         kAudioDevicePropertySafetyOffset (input -- output scope): 93
         kAudioDevicePropertyBufferSize (output -- output scope): 4096 *bytes*
         kAudioDevicePropertyBufferSize (input -- input scope): 4096 *bytes*
         Streams:
         [67, 0, 0, 0]
         Stream latency (output): 0
         Streams:
         [68, 0, 0, 0]
         Stream latency (output): 0
         
         */
        
        /*
         
         Input frame offset in samples: -14629.798077300002
         Output frame offset in samples: -13446.7981137
         
         Zeroed out:
         
         Input: -1183
         Output: 0
         
         */
        
        /*
         
         JN formulae:
         outputLatency * 2 (800) - inputSafety (66) = 734
         
         */
        
        /*
         
         MN numbers:
         
         kAudioDevicePropertyLatency (output - output scope): 34
         kAudioDevicePropertyLatency (output - input scope): 0
         kAudioDevicePropertyLatency (input -- input scope): 0
         kAudioDevicePropertyLatency (input -- output scope): 34
         kAudioDevicePropertySafetyOffset (output -- output scope): 117
         kAudioDevicePropertySafetyOffset (output -- input scope): 150
         kAudioDevicePropertySafetyOffset (input -- input scope): 150
         kAudioDevicePropertySafetyOffset (input -- output scope): 117
         kAudioDevicePropertyBufferSize (input -- input scope): 4096 *bytes*
         kAudioDevicePropertyBufferSize (input -- input scope): 2048 *bytes*
         Streams:
         [88, 0, 0, 0]
         Stream latency (output): 933
         Streams:
         [89, 0, 0, 0]
         Stream latency (output): 1444
         
         */
        
        //mn's mac : need to get to about ~1200 samples
        /*
         
         Input frame offset in samples: -5221.879412400001
         Output frame offset in samples: -3930.8793867
         
         Zeroed out:
         
         Input: -1291
         Output: 0
         
         This means the input buffer *reports* starting that many samples earlier than the output buffer
         
         
         1084 (output added up)
         1594 (input added up)
         
         */
        
        /*
         
         MN formulae:
         outputLatency * 2 (68) - inputSafety (150) =  -18 + outputStreamLatency (1444) = 1426
         
         */
        
        //TODO: Dynamic sample rate!
        let inputLatencyInFramesTotal = Double(inputLatency  + inputSafety)
        state.inputLatency = UInt64(inputLatencyInFramesTotal / 44100.0 * state.secondsToTicks)
        print("Input latency: \(state.inputLatency) frames: \(inputLatencyInFramesTotal)")
        let outputLatencyInFramesTotal = Double(outputLatency  + outputSafety)
        state.outputLatency = UInt64(outputLatencyInFramesTotal / 44100.0 * state.secondsToTicks)
        print("Output latency: \(state.outputLatency) frames: \(outputLatencyInFramesTotal)")
        
        #endif
    }
}

/* SCHEDULING OF BUFFERS DURING INITIAL PLAYBACK */
extension AudioManager {
    func scheduleAndPlayAudioBuffers() {
        guard let metronomeFileBuffer = self.metronomeFileBuffer else {
            fatalError("No buffer")
        }
        
        //delay the playback of the initial buffer so that we're not trying to play immediately when the engine starts
        let delay = 0.33 * state.secondsToTicks
        let audioTime = AVAudioTime(hostTime: mach_absolute_time() + UInt64(delay))
        state.audioBuffersScheduledAtHost = audioTime.hostTime
        
        playerNode.play()
        playerNode.scheduleBuffer(metronomeFileBuffer, at: audioTime, options:[], completionHandler: {
            print("Played original buffer")
            self.stop()
        })
    }
}

/* AUDIO FILE SETUP FOR RECORDING INPUT TAPS */
extension AudioManager {
    var inputNodeFileURL : URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("input_recorded.caf")
    }
    
    var outputNodeFileURL : URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("output_recorded.caf")
    }
    
    func createRecordingAudioFiles() {
        try? FileManager.default.removeItem(at: inputNodeFileURL)
        try? FileManager.default.removeItem(at: outputNodeFileURL)
        
        do {
            inputRecordingFile = try AVAudioFile(forWriting: inputNodeFileURL,
                                                 settings: audioEngine.inputNode.outputFormat(forBus: 0).settings)
            outputRecordingFile = try AVAudioFile(forWriting: outputNodeFileURL,
                                                  settings: audioEngine.mainMixerNode.outputFormat(forBus: 0).settings)
        } catch {
            fatalError("Couldn't make files: \(error)")
        }
    }
}

/* CREATE THE RESULT FILE
    
    createResultFile() is where the sync logic is implemented
 */
extension AudioManager {
    var resultFileURL : URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.caf")
    }
    
    func createResultFile() {
        let renderingEngine = AVAudioEngine()
        
        guard let metronomeFileBuffer = self.metronomeFileBuffer else {
            fatalError("No buffer")
        }
        
        guard let inputFileForReading = try? AVAudioFile(forReading: inputNodeFileURL),
              let outputFileForReading = try? AVAudioFile(forReading: outputNodeFileURL)
                else {
            fatalError("No input/output files for reading")
        }
    
        guard let inputFileBuffer = audioFileToBuffer(inputFileForReading),
              let outputFileBuffer = audioFileToBuffer(outputFileForReading)
                else {
            fatalError("No input/output file buffers")
        }
        
        let originalAudioPlayerNode = AVAudioPlayerNode()
        let recordedInputNodePlayer = AVAudioPlayerNode()
        let recordedOutputNodePlayer = AVAudioPlayerNode()
        
        renderingEngine.attach(originalAudioPlayerNode)
        renderingEngine.attach(recordedInputNodePlayer)
        renderingEngine.attach(recordedOutputNodePlayer)
        
        renderingEngine.connect(originalAudioPlayerNode,
                                to:renderingEngine.mainMixerNode,
                                format: renderingEngine.mainMixerNode.inputFormat(forBus: 0))
        
        renderingEngine.connect(recordedInputNodePlayer,
                                to:renderingEngine.mainMixerNode,
                                format: inputFileBuffer.format)
        renderingEngine.connect(recordedOutputNodePlayer,
                                to:renderingEngine.mainMixerNode,
                                format: outputFileBuffer.format)
        
        try? FileManager.default.removeItem(at: resultFileURL)
        
        let resultFormat = renderingEngine.outputNode.outputFormat(forBus: 0)
        
        guard let resultFile = try? AVAudioFile(forWriting: resultFileURL, settings: resultFormat.settings) else {
            fatalError("Couldn't make result file")
        }
        
        do {
            try renderingEngine.enableManualRenderingMode(.offline,
                                                          format: resultFormat,
                                                          maximumFrameCount: 4096)
            try renderingEngine.start()
        } catch {
            fatalError("Couldn't make result file: \(error)")
        }
        
        /* ---------------------------------------------- DETERMINE SYNC -------------------------------------- */
        print("Original buffers were scheduled at: \(state.audioBuffersScheduledAtHost)")
        print("Input node started at: \(state.inputNodeTapBeganAtHost)")
        print("Output node started at: \(state.outputNodeTapBeganAtHost)")
        
        //Try to move the input/output files so that they are synced to the timing of the original audio buffer
        let timestampToSyncTo = state.audioBuffersScheduledAtHost
        
        //Find the difference between the first call of the input/output node taps and the time to sync to
        //For example, if the original audio was scheduled at 1_000_000_000 and the input node tap started at 900_000_000,
        //the input audio file should be shifted left by 100_000_000 in order to line up
        let inputNodeHostTimeDiff = Int64(state.inputNodeTapBeganAtHost) - Int64(timestampToSyncTo)
        let outputNodeHostTimeDiff = Int64(state.outputNodeTapBeganAtHost) - Int64(timestampToSyncTo)
        
        //Since we're going to schedule the audio files in an offline render, conver these host time shifts to sample times
        let inputNodeDiffInSamples = Double(inputNodeHostTimeDiff) / state.secondsToTicks * inputFileBuffer.format.sampleRate
            //- storedLatencyFrames //For iOS?
        print("Input frame offset in samples: \(inputNodeDiffInSamples)")
        
        let outputNodeDiffInSamples = Double(outputNodeHostTimeDiff) / state.secondsToTicks * outputFileBuffer.format.sampleRate
        print("Output frame offset in samples: \(outputNodeDiffInSamples)")
        
        /*
         Note:
         I've attempted to use various latency values here as well to compensate (ie AVAudioSession's inputLatency, outputLatency, ioBufferDuration),
         but they yield wildly different results on different systems.  On my mac, using ioBufferDuration alone gets close to lining things up.
         On my iPhone, ioBufferDuration pushes it further out of sync.
         
         And, the AVAudioSession APIs aren't available on macOS, making me thing perhaps there's a way to do this with AVAudioEngine.
         However, in Catalyst, all AVAudioNode latency values (latency, presentationLatency, etc) seem to report 0.0
         */
        
        //pan the nodes so that the result file is visually easy to see the sync on by comparing the waveforms of the channels
        originalAudioPlayerNode.pan = -1.0
        recordedOutputNodePlayer.pan = -1.0
        recordedInputNodePlayer.pan = 1.0
        
        
        originalAudioPlayerNode.play()
        recordedInputNodePlayer.play()
        recordedOutputNodePlayer.play()
        
        //play the original metronome audio at sample position 0 and try to sync everything else up to it
        let originalAudioTime = AVAudioTime(sampleTime: 0, atRate: renderingEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
//        originalAudioPlayerNode.scheduleBuffer(metronomeFileBuffer, at: originalAudioTime, options: []) {
//            print("Played original audio")
//        }
        
        //play the tap of the output node at its determined sync time -- note that this seems to line up in the result file
        let outputAudioTime = AVAudioTime(sampleTime: AVAudioFramePosition(outputNodeDiffInSamples),
                                          atRate: renderingEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        recordedOutputNodePlayer.scheduleBuffer(outputFileBuffer, at: outputAudioTime, options: []) {
            print("Output buffer played")
        }
        
        //play the tap of the input node at its determined sync time -- this _does not_ appear to line up in the result file
        let inputAudioTime = AVAudioTime(sampleTime: AVAudioFramePosition(inputNodeDiffInSamples),
                                         atRate: renderingEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        recordedInputNodePlayer.scheduleBuffer(inputFileBuffer, at: inputAudioTime, options: []) {
            print("Input buffer played")
        }
        
        /* ---------------------------------------------- END DETERMINE SYNC -------------------------------------- */
        //The rest of the function just renders the result to a file -- no more sync calcluation
        
        let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: renderingEngine.manualRenderingFormat,
            frameCapacity: renderingEngine.manualRenderingMaximumFrameCount)!
        
        do {
            while true {
                let framesToRender = renderBuffer.frameCapacity
                let status = try renderingEngine.renderOffline(framesToRender, to: renderBuffer)
                
                switch status {
                case .success:
                    try resultFile.write(from: renderBuffer)
                default:
                    break
                }
                
                if (renderingEngine.outputNode.lastRenderTime?.sampleTime ?? 0) > inputFileBuffer.frameLength {
                    break
                }
            }
        } catch {
            fatalError("Rendering error: \(error)")
        }
        
        renderingEngine.stop()
        
        print("Created result file at: \(resultFileURL.deletingLastPathComponent())")
        print("Terminal command:")
        print("open \(resultFileURL.deletingLastPathComponent().path)")
        self.hasResultFileToPlay = true
        self.floatDataToDisplay = convertAudioFileToVisualData(fileUrl: resultFileURL)
    }
    
    func playResult() {
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true)
            #endif
            resultAudioPlayer = try AVAudioPlayer(contentsOf: resultFileURL, fileTypeHint: AVFileType.caf.rawValue)
            resultAudioPlayer?.prepareToPlay()
            resultAudioPlayer?.play()
        } catch {
            fatalError("Error making audio player")
        }
    }
}

/* INSTALL TAPS
    
 Also stores the host times for the first input buffers that come in
 Writes tap data to files
 */
extension AudioManager {
    func installTapOnInputNode() {
        audioEngine.inputNode.removeTap(onBus: 0)
        let recordingFormat = audioEngine.inputNode.inputFormat(forBus: 0)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (pcmBuffer, timestamp) in
            if self.state.inputNodeTapBeganAtHost == 0 {
                self.state.inputNodeTapBeganAtHost = timestamp.hostTime - self.state.inputLatency
                print("Input node presentation latency: \(self.audioEngine.inputNode.presentationLatency) samples: \(self.audioEngine.inputNode.presentationLatency * recordingFormat.sampleRate) regular latency: \(self.audioEngine.inputNode.latency)")
            }
            
            do {
                try self.inputRecordingFile?.write(from: pcmBuffer)
            } catch {
                fatalError("Couldn't write audio file")
            }
        }
    }
    
    func installTapOnOutputNode() {
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        let recordingFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (pcmBuffer, timestamp) in
            if self.state.outputNodeTapBeganAtHost == 0 {
                self.state.outputNodeTapBeganAtHost = timestamp.hostTime + self.state.outputLatency
                print("Output node presentation latency: \(self.audioEngine.outputNode.presentationLatency) samples: \(self.audioEngine.outputNode.presentationLatency * recordingFormat.sampleRate) regular latency: \(self.audioEngine.outputNode.latency) \(self.state.outputLatency)")
                
                print("Mixer node latency: \(self.audioEngine.mainMixerNode.outputPresentationLatency * recordingFormat.sampleRate) \(self.audioEngine.mainMixerNode.latency)")
                
                print("Audio unit latency: \(self.audioEngine.outputNode.auAudioUnit.latency)")
            }
            do {
                try self.outputRecordingFile?.write(from: pcmBuffer)
            } catch {
                fatalError("Couldn't write audio file")
            }
        }
    }
}

//loading existing audio files
extension AudioManager {
    func loadAudioBuffers() {
        guard let audioBuffer1 = loadAudioFile("OriginalAudio") else {
            fatalError("Couldn't load audio buffer")
        }
        self.metronomeFileBuffer = audioBuffer1
    }
}
