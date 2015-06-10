//
//  AudioPlayerManager.swift
//  MediaPlayer
//
//  Created by Mike Ebinum on 3/06/2015.
//  Copyright (c) 2015 Facebook. All rights reserved.
//

import Foundation
import AVFoundation

@objc(AudioPlayerManager)
class AudioPlayerManager: NSObject, AVAudioPlayerDelegate, RCTBridgeModule {

  let (AudioPlayerEventProgress, AudioPlayerEventFinished, AudioPlayerError, AudioPlayerStarted) = ("PlayerProgress", "PlayerFinished","PlayerError", "PlayerStarted")
  
  
  var _audioPlayer:AVAudioPlayer?
  var _currentTime:NSTimeInterval?
  var _progressUpdateTimer:AnyObject?
  var _progressUpdateInterval:Int = 0
  var _prevProgressUpdateTime:NSDate?
  var _audioFileURL:NSURL?
  var bridge:RCTBridge?
  
  func constantsToExport() -> [NSObject : AnyObject] {
    return ["Events" :
      [AudioPlayerEventProgress : AudioPlayerEventProgress],
      [AudioPlayerEventFinished : AudioPlayerEventFinished],
      [AudioPlayerError : AudioPlayerError],
      [AudioPlayerStarted:AudioPlayerStarted]
    ]
  }

  
  /*
   * Player functions
   */
  @objc func play(path:NSString, loop:Bool = false) {
    let fileURL = getPathUrl(path)
    playWithUrl(fileURL!,loop: loop)
  }
  
  @objc func playWithUrl(url : NSURL, loop:Bool = false) {
    var error: NSError?
    self._audioPlayer?.delegate = nil
    self._audioPlayer?.stop()
    self._audioPlayer = AVAudioPlayer(contentsOfURL: url, error: &error)
    
    if let player = _audioPlayer {
      player.prepareToPlay()
      player.delegate = self
      if loop {
        player.numberOfLoops = -1
      }
      
      //        player.enableRate = true
      //        player.rate = 1.2 // cool feature
      self.startProgressTimer()
      player.play()
      dispatchEvent(AudioPlayerStarted, body: [])
    } else if let anError = error {
      self.stopProgressTimer()
      let errorMessage = "audio playback loading error: \(anError.localizedDescription)"
      NSLog(errorMessage)
      dispatchEvent(AudioPlayerError, body: ["errorMessage" : errorMessage])
    }
  }
  
  @objc func pause() {
    if let player = self._audioPlayer where player.playing {
      player.pause()
    }
  }
  
  @objc func stop() {
    if let player = self._audioPlayer where player.playing {
      player.stop()
    }
  }
  
  
  @objc func startProgressTimer () {
    self._progressUpdateInterval = 250;
    self._prevProgressUpdateTime = nil;
    
    self.stopProgressTimer()
    
    self._progressUpdateTimer   = CADisplayLink(target: self, selector: "sendProgressUpdate") as CADisplayLink!
    self._progressUpdateTimer!.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
  }
  
  @objc func stopProgressTimer () {
    _progressUpdateTimer?.invalidate();
  }
  
  @objc func sendProgressUpdate() {
    
    if let player = self._audioPlayer,
      previousUpdateTime = self._prevProgressUpdateTime
      where (previousUpdateTime.timeIntervalSinceNow * -1000.0) >= Double(self._progressUpdateInterval) {
        
        if player.playing {
          self._currentTime = player.currentTime
        }
        
        var time = NSString(format: "%f", _currentTime! )
        dispatchEvent(AudioPlayerEventProgress, body: ["currentTime": self._currentTime! as NSNumber])
        self._prevProgressUpdateTime = NSDate()
    }
  }
  
  
  
  // Delegates
  func audioPlayerDidFinishPlaying(player: AVAudioPlayer!, successfully flag: Bool) {
    NSLog(flag ? "FINISHED OK" : "FINISH ERROR");
    dispatchEvent(AudioPlayerEventFinished, body: ["finished": true])
  }
  
  
  func audioPlayerDecodeErrorDidOccur(player: AVAudioPlayer!, error: NSError!) {
    let errorMessage = "audio player decode error occured loading error: \(error.localizedDescription)"
    NSLog(errorMessage)
    dispatchEvent(AudioPlayerError,  body: ["errorMessage" : errorMessage])
  }

  func dispatchEvent(eventName:String, body:AnyObject = []) {
    if let bridge = self.bridge {
      bridge.eventDispatcher.sendDeviceEventWithName(eventName, body: body)
    } else {
      NSLog("couldn't dispatch event \(eventName) with body \(body) the RCTBridge has not been initalized)")
    }
  }
  
  func getPathUrl(path:NSString) -> NSURL? {
    if path.hasPrefix("http") {
        return NSURL(fileURLWithPath: path as String)
    }
    //if no http assume loading from asset bundle
    
    var audioFilePath  = NSBundle.mainBundle().resourcePath?.stringByAppendingPathComponent(path as String);
    return NSURL(fileURLWithPath: audioFilePath!)
  }
}
