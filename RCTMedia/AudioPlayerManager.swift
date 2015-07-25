//
//  AudioPlayerManager.swift
//  MediaPlayer
//
//  Created by Mike Ebinum on 3/06/2015.
//  Copyright (c) 2015 Facebook. All rights reserved.
//

import Foundation
import AVFoundation

class PlayerDelegate: NSObject, AVAudioPlayerDelegate {

}

extension NSString {
    func toBase64String() -> String {
        let plainData = self.dataUsingEncoding(NSUTF8StringEncoding)
        return plainData!.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0))
    }
}

extension AVPlayer {
    func isPlaying() -> Bool {
      return self.rate > 0.0
    }
}


@objc(AudioPlayerManager)
class AudioPlayerManager: NSObject, AVAudioPlayerDelegate, RCTBridgeModule {

  let (AudioPlayerEventProgress, AudioPlayerEventFinished, AudioPlayerError, AudioPlayerStarted,AudioPlayerLoading, AudioPlayerLoaded) = ("PlayerProgress", "PlayerFinished","PlayerError", "PlayerStarted","PlayerLoading", "PlayerLoaded")
    let _notificationCenter = NSNotificationCenter.defaultCenter()
    var _audioPlayerList: [(String,AVPlayer)] = []
  var _currentTime:NSTimeInterval?
  var _progressUpdateTimers: [NSTimer] = []
  var _progressUpdateInterval:Int = 0
  var _prevProgressUpdateTime:NSDate?
  var _audioFileURL:NSURL?
  var bridge:RCTBridge?
    //create typealias for Key Value Observer contexts
    typealias KVOContext = UInt8
    var AVPlayerItemContext = KVOContext()
    var AVPlayerContext = KVOContext()
    var playerObservers: [NSString: AnyObject] = [:]
    
  func constantsToExport() -> [NSObject : AnyObject] {
    return ["Events" :
        [AudioPlayerEventProgress : AudioPlayerEventProgress,
        AudioPlayerEventFinished : AudioPlayerEventFinished,
        AudioPlayerError : AudioPlayerError,
        AudioPlayerStarted: AudioPlayerStarted,
        AudioPlayerLoading: AudioPlayerLoading,
        AudioPlayerLoaded: AudioPlayerLoaded
        ]
    ]
  }
  
  /*
   * Player public functions
   */
  @objc func play(path:NSString, loop:Bool = false) {
    
    let fileURL = getPathUrl(path)
    playWithUrl(fileURL!,loop: loop)
  }
  
  @objc func playMultiple(pathArray: NSArray, loop:Bool = false) {
    
    let castArray = pathArray as! Array<String>
    //stop all tracks
    self.stopMultiple()
    for path in castArray {
        playAddedTrack(path,loop: loop)
    }
  }
    
  @objc func playAddedTrack(path: NSString, loop:Bool = false) {
    let trackId = path.toBase64String()
    
    //used to start a time to update progress for the player
    let startTimer = {(aPlayer:AVPlayer) -> () in
        let playerId = ObjectIdentifier(aPlayer).hashValue
        let playerMeta = ["playerId" : playerId, "trackId" : trackId, "path" : path]
        //check if there is an observer already
        if let observer: AnyObject = self.playerObservers[trackId] {
            aPlayer.removeTimeObserver(observer)
        }
        let timeObserver: AnyObject! = aPlayer.addPeriodicTimeObserverForInterval(CMTimeMakeWithSeconds(Float64(1.0), Int32(NSEC_PER_SEC)),
            queue: dispatch_get_main_queue(), usingBlock: { (CMTime) -> Void in
                var currentTime = 0.0
                if aPlayer.isPlaying() {
                    currentTime = CMTimeGetSeconds(aPlayer.currentTime())
                }
                
                self.dispatchEvent(self.AudioPlayerEventProgress, body: ["currentTime": currentTime as NSNumber, "trackId": trackId as NSString , "path": path as NSString])
        })
        self.playerObservers[trackId] = timeObserver
    }
    
    //if player exists already restart player item
    let found = findPlayerByIdAndAction(trackId) { (id,player) -> () in
        NSLog("Player for path \(path) already exists will use player")
        if player.isPlaying() {
            player.pause()
        }
        player.currentItem.seekToTime(kCMTimeZero)
        player.play()
        NSLog("Started playing player for path \(path)")
        self.dispatchEvent(self.AudioPlayerStarted, body: self.getPlayerMeta(player.currentItem.asset))
        startTimer(player)
    }
    
    //else create new player and add to list
    if !found {
        let playerTuple = self.createPlayerWithPath(path as String,loop: loop)
        self._audioPlayerList.append(playerTuple)
        startTimer(playerTuple.1)
    }
  }
    
  @objc func stopMultiple() {
    for (trackId,player) in self._audioPlayerList {
        if player.isPlaying() {
            player.pause()
            self.dispatchEvent(AudioPlayerEventFinished, body: ["trackId" : trackId])
        }
    }
  }
    
    @objc func stopRemovedTrack(path: NSString) {
   
        for (index, (pathId, player)) in enumerate(self._audioPlayerList) {
            if pathId == path.toBase64String() {
                self._audioPlayerList.removeAtIndex(index)
                if player.isPlaying() {
                    player.pause()
                    self.dispatchEvent(AudioPlayerEventFinished, body: ["trackId" : path.toBase64String(), "path" : path ])
                }
            }
        }
    }
    
    
    @objc func pauseMultiple() {
        for (_,player) in self._audioPlayerList {
            if player.isPlaying() {
                player.pause()
            }
        }
    }
    
    @objc func pause(path: NSString) {
        let pathAsBase64 = path.toBase64String()
        
        for (trackId,player) in self._audioPlayerList {
            if trackId == pathAsBase64 {
                if player.isPlaying() {
                    player.pause()
                } else {
                    player.play()
                }
            }
        }
    }
    
    @objc func stop() {
        self.pauseMultiple()
    }
    
  @objc func playWithUrl(url : NSURL, loop:Bool = false) {
    playAddedTrack(String(contentsOfURL:url)!,loop: loop)
  }
    
    /**
     * Player private functions
     */
    func createPlayerWithPath(path: String,loop: Bool) -> (String, AVPlayer) {
        var error:NSError?
        
        let fileURL = self.getPathUrl(path)
        let trackId = path.toBase64String()
        
        let keys = ["tracks","playable","duration"]
        let creatPlayerItem = { (path:String) -> (AVPlayerItem) in
            let fileURL = self.getPathUrl(path)
            if self.isRemoteLink(path) {
                return  AVPlayerItem(URL:fileURL)
            } else {
                let asset:AVAsset = AVURLAsset.assetWithURL(fileURL) as! AVAsset
                asset.loadValuesAsynchronouslyForKeys(keys, completionHandler: {
                    dispatch_async(dispatch_get_main_queue(), {
                        self.prepareToPlayAsset(asset, keys: keys, assetMeta: ["trackId" : trackId, "path" : path])
                    })
                })
                return AVPlayerItem(asset:asset)
            }
        }
        
        let item = creatPlayerItem(path)
        item.addObserver(self, forKeyPath: "status", options:nil, context: &AVPlayerItemContext)
        let player = AVPlayer(playerItem:item)
        let playerId = ObjectIdentifier(player).hashValue
        let playerMeta = ["playerId" : playerId, "trackId" : trackId, "path" : path]
        
        if let anError = player.error {
            dispatchAnError(anError, bodyMessage:playerMeta)
        } else {
            //keep alive audio at background
            AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback, error: nil)
            AVAudioSession.sharedInstance().setActive(true, error: nil)

            _notificationCenter.addObserver(self,
                selector: "playerItemDidReachEnd:",
                name: AVPlayerItemDidPlayToEndTimeNotification,
                object: player.currentItem)
            
            player.rate = 1.0
            player.volume = 1.0
            player.addObserver(self, forKeyPath:"status",options:nil, context: &AVPlayerContext)
            
            player.actionAtItemEnd = AVPlayerActionAtItemEnd.None
            
            if loop {
                //set a listener for when the player ends
                _notificationCenter.addObserver(self,
                    selector: "restartPlayerFromBegining:",
                    name: AVPlayerItemDidPlayToEndTimeNotification,
                    object: player.currentItem)
            }
            self.dispatchEvent(self.AudioPlayerLoading, body: playerMeta)
        }
        return (trackId, player)
    }
    
    
    
    override func observeValueForKeyPath(keyPath: String, ofObject object: AnyObject, change: [NSObject : AnyObject], context: UnsafeMutablePointer<()>) {
        
        switch (keyPath,context) {
            case ("status", &AVPlayerContext) :
                if let player = object  as? AVPlayer {
                    let playerMeta = getPlayerMeta(player.currentItem.asset)
                    
                    switch player.status {
                    case AVPlayerStatus.ReadyToPlay:
                        NSLog("AVPlayerItemStatus ReadyToPlay")
                        NSLog("AVPlayerItemStatus tracks \(player.currentItem.tracks)")
                        self.dispatchEvent(self.AudioPlayerLoaded, body:playerMeta)
                        player.play()
                        self.dispatchEvent(self.AudioPlayerStarted, body:playerMeta)
                    default:
                        let status = player.status == AVPlayerStatus.Unknown ? "unknown" : "failed"
                        NSLog("AVPlayer is \(status)")
                        NSLog("AVPlayer Access Logs \(player.currentItem.accessLog())")
                        NSLog("AVPlayer Error Logs \(player.currentItem.errorLog())")
                        self.dispatchEvent(self.AudioPlayerError, body: playerMeta)
                        //NSLog("Removing observer for  player item \(player.currentItem.asset) \(player.currentItem.tracks)")
                        player.removeObserver(self, forKeyPath:"status", context: &AVPlayerContext)
                    }
                }
            case ("status", &AVPlayerItemContext) :
                if let playerItem = object as? AVPlayerItem {
                    
                    let playerMeta = getPlayerMeta(playerItem.asset)
                    
                    switch playerItem.status {
                        case AVPlayerItemStatus.ReadyToPlay:
                            NSLog("AVPlayerItemStatus ReadyToPlay")
                            NSLog("AVPlayerItemStatus tracks \(playerItem.tracks)")
                            self.dispatchEvent(self.AudioPlayerLoaded, body:playerMeta)
                        default:
                            let status = playerItem.status == AVPlayerItemStatus.Unknown ? "unknown" : "failed"
                            NSLog("AVPlayerItemStatus is \(status)")
                            NSLog("AVPlayerItem Access Logs \(playerItem.accessLog())")
                            NSLog("AVPlayerItem Error Logs \(playerItem.errorLog())")
                            self.dispatchEvent(self.AudioPlayerError, body: playerMeta)
                            //NSLog("Removing observer for  player item \(playerItem.asset) \(playerItem.tracks)")
                            playerItem.removeObserver(self, forKeyPath:"status", context: &AVPlayerItemContext)
                    }
                }
            default:
                NSLog("No action found for \(keyPath)")
        }
    }
    
    func startProgressTimer (playerMeta: NSDictionary = [:]) {
        self._progressUpdateInterval = 250;
        self._prevProgressUpdateTime = nil;
        
        self.stopProgressTimer()
        let timer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: Selector("sendProgressUpdate:"), userInfo: playerMeta, repeats: true)
        timer.fire()
        self._progressUpdateTimers.append(timer)
    }
    
    func stopProgressTimer () {
        
        for (index, timer) in enumerate(self._progressUpdateTimers){
            timer.invalidate()
            self._progressUpdateTimers.removeAtIndex(index)
        }
    }
    
    func sendProgressUpdate(playerMeta: NSDictionary) {
        //["playerId" : playerId, "trackId" : trackId, "path" : path]
        if let trackId: String = playerMeta["trackId"] as? String,
            let path: String = playerMeta["path"] as? String {
                
                let found = findPlayerByIdAndAction(trackId) { (id,player) -> () in
                    var currentTime = 0.0
                    if player.isPlaying() {
                        currentTime = CMTimeGetSeconds(player.currentTime())
                    }
                    
                    self.dispatchEvent(self.AudioPlayerEventProgress, body: ["currentTime": currentTime as NSNumber, "trackId": trackId as NSString , "path": path as NSString])
                }
                if(!found) {
                    NSLog("player with track Id not found \(trackId)")
                }
        }
    }
    
    func prepareToPlayAsset(asset:AVAsset, keys: Array<String>, assetMeta: NSDictionary = [:]) {
        for key in keys {
            var error:NSError? = nil
            
            switch asset.statusOfValueForKey(key, error: &error) {
            case AVKeyValueStatus.Loading:
                self.dispatchEvent(self.AudioPlayerLoading, body: assetMeta)
            case AVKeyValueStatus.Loaded:
                self.dispatchEvent(self.AudioPlayerLoaded, body: assetMeta)
            default:
                NSLog("error occured loading asset \(asset) with path \((asset as? AVURLAsset)?.URL)")
                dispatchAnError(error!)
            }
        }
    }

    func playerItemDidReachEnd(notification: NSNotification) {
        var message:NSDictionary = [:]
        if let asset = (notification.object as? AVPlayerItem)?.asset {
            message = self.getPlayerMeta(asset)
        }
        self.dispatchEvent(self.AudioPlayerEventFinished, body: message)
    }
    
    func restartPlayerFromBegining(notification: NSNotification) {
        if let avPlayerItem = notification.object as? AVPlayerItem {
            avPlayerItem.seekToTime(kCMTimeZero)
            NSLog("\restarting track")
            self.dispatchEvent(self.AudioPlayerStarted, body: self.getPlayerMeta(avPlayerItem.asset))
        } else {
            NSLog("\(notification.object) not found in notification object")
        }
    }
    

    func findPlayerByIdAndAction(trackId: String, closure: (String,AVPlayer) -> ()) -> Bool {
        var found = false
        if let playerTuple = (_audioPlayerList.filter{$0.0 == trackId}.first) {
            closure(playerTuple)
            found = true
        }
        return found
    }
    
    func getPlayerMeta(playerAsset: AVAsset) -> NSDictionary {
        var meta:[String:AnyObject] = [:]
        if let pathUrl = (playerAsset as? AVURLAsset)?.URL {
            
            let path = pathUrl.absoluteString!
            let trackId = path.toBase64String()
            meta["path"] = path
            meta["trackId"] = trackId
            meta["duration"] = CMTimeGetSeconds(playerAsset.duration)
            
            if let (_,player) = (_audioPlayerList.filter{$0.0 == trackId}).first {
                meta["playerId"] = ObjectIdentifier(player).hashValue
            }
        }
        
        return meta
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
    
    func dispatchProgressUpdate(path: String) {
        let trackId = path.toBase64String()
        
        findPlayerByIdAndAction(trackId) { (id,player) -> () in
            var currentTime = 0.0
            if player.isPlaying() {
                currentTime = CMTimeGetSeconds(player.currentTime())
            }
            
            self.dispatchEvent(self.AudioPlayerEventProgress, body: ["currentTime": currentTime as NSNumber, "trackId": trackId as NSString , "path": path as NSString])
        }
    }

    func dispatchAnError (anError:NSError, bodyMessage: NSDictionary = [:]) {
        let errorMessage = "audio playback loading error: \(anError.localizedDescription)"
        //RCTLogInfo(errorMessage)
        var temp = NSMutableDictionary(dictionary: bodyMessage)
        temp.addEntriesFromDictionary(["errorMessage" : errorMessage])
        self.dispatchEvent(self.AudioPlayerError, body: temp)
    }
    
  func dispatchEvent(eventName:String, body:AnyObject = []) {
    if let bridge = self.bridge {
        NSLog("dispatching event\(eventName) with body \(body) over RCTBridge")
        bridge.eventDispatcher.sendDeviceEventWithName(eventName, body: body)
    } else {
      NSLog("couldn't dispatch event \(eventName) with body \(body) the RCTBridge has not been initalized)")
    }
  }
    
    func isRemoteLink(path:NSString) -> Bool {
        return path.hasPrefix("http") || path.hasPrefix("https")
    }
  
  func getPathUrl(path:NSString) -> NSURL? {
    if isRemoteLink(path) {
        return NSURL(string: path as String)
    }
    //if no http assume loading from asset bundle
    var audioFilePath  = NSBundle.mainBundle().resourcePath?.stringByAppendingPathComponent(path as String);
    return NSURL(fileURLWithPath: audioFilePath!)
  }
  
  func delay(delay:Double, closure:() -> ()) {
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                Int64(delay * Double(NSEC_PER_SEC))
            ),
            dispatch_get_main_queue(), closure)
    }
    
    deinit {

    }
}
