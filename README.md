# AudioEngineLoopbackLatencyTest

This project demonstrates an attempt to reconcile audio input/output timestamps on macOS/iOS/macCatalyst by doing a loopback experiment.  

The desired result is an algorithm that is able accurately sync an input recording with an original audio source after the fact.  In practice, it ends up between 500 and 1500 samples off, depending on machine.

**I would expect that I'd have to compensate for input/output latency somewhere, but I haven't figured out a reliable way to do this across platforms**.  For example, `AVAudioSession`'s latency properties (eg. `inputLatency`, `outputLatency`, and `ioBufferDuration`) are only available on iOS. How would these be calculated on macOS?
Even on iOS, how do these properties get used correctly and reliably to sync audio?

## High-level summary
- A pre-recorded metronome audio file is scheduled and played via an `AVAudioPlayerNode`
- Audio input data is recorded via a tap on `AVAudioEngine`'s `inputNode` (*Note: make sure speakers are turned on (no headphones) so that the mic picks up the original audio)*
- An output file is generated (and displayed visually on-screen) that attempts to sync the audio signals. Ideally, after syncing, the result file should play the original audio and the new input audio totally in sync.
- `AudioEngineLoopbackLatencyTest` target can be run as a MacCatalyst or iOS app.  `AudioEngineLoopbackLatencyTest-MacNative` runs the same codebase, but as a native macOS app (eg no Catalyst wrapper).

## Sync strategy details
- Using `sampleTime` is not a reliable timing strategy -- the input node and output node may report dramatically different timestamps.  However, theoretically, the `hostTime` property gives an accurate timestamp that can be compared across nodes.
- The original audio (recorded metronome clicks) are scheduled at a certain host time
- The input audio is recorded and a `hostTime` is stored from when the first input buffers come in
- Upon sync, the original audio scheduled time is compared to the first input buffer time to determine a `hostTime` offset
- `hostTime` offset is converted to samples and the input audio is shifted by that number of samples in an attempt to sync the two sources
- Note: The `outputNode` of `AVAudioEngine` is also tapped and it's first buffers store an inital timestamp as well. In practice, this always syncs perfectly with the original audio.

## Code layout
Almost everything sync-related happens in [`AudioManager`](AudioEngineLoopbackLatencyTest/AudioManager.swift) in the `createResultFile()` function.  Search the file for "DETERMINE SYNC" to jump right to the calculations.
Initial timestamps are set in `scheduleAndPlayAudioBuffers()` and `installTapOnInputNode()`
