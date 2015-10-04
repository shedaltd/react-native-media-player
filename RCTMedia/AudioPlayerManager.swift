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

    func decodeFromBase64() -> String {
        if let data = NSData(base64EncodedString: self as String, options: NSDataBase64DecodingOptions(rawValue: 0)) {
            return NSString(data:data, encoding:NSUTF8StringEncoding) as! String
        }

         return ""
    }
}

extension AVPlayer {
    func isPlaying() -> Bool {
      return self.rate > 0.0
    }
}

struct PlayerMeta {
    let trackId, path:String
    let playerId: Int
    let loop: Bool

    init(trackId: String, path: String, playerId: Int, loop:Bool = false) {
        self.trackId = trackId
        self.path = path
        self.playerId = playerId
        self.loop = loop
    }

    func asDictionary () -> NSDictionary {
        return ["playerId" : playerId, "trackId" : trackId, "path" : path]
    }
}


@objc(AudioPlayerManager)
class AudioPlayerManager: NSObject, AVAudioPlayerDelegate, RCTBridgeModule {

  let (AudioPlayerEventProgress, AudioPlayerEventFinished, AudioPlayerError, AudioPlayerStarted,AudioPlayerLoading, AudioPlayerLoaded, AudioPlayerEventPaused, AudioPlayerFullyStopped) = ("PlayerProgress", "PlayerFinished","PlayerError", "PlayerStarted","PlayerLoading", "PlayerLoaded", "PlayerPaused","AllPlayStopped")
    let _notificationCenter = NSNotificationCenter.defaultCenter()
    let AVPlayerDidPlayToEndNotification = "PlayerDidPlayToEndNotification"
    var _audioPlayerList: [(String,AVPlayer,PlayerMeta)] = []
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
        AudioPlayerLoaded: AudioPlayerLoaded,
        AudioPlayerEventPaused: AudioPlayerEventPaused,
        AudioPlayerFullyStopped: AudioPlayerFullyStopped
        ]
    ]
  }

  /*
   * Player public functions
   */
  @objc func play(path:NSString, loop:Bool = false) {
    playAddedTrack(path,loop: loop)
  }

  @objc func playMultiple(pathArray: NSArray, loop:Bool = false) {

    let castArray = pathArray as! Array<String>
    //stop all tracks if anything is playing
    if self.isPlayingAnyTracks() {
        self.stopMultiple()
    }
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
      //create a new timed observer to dispatach current time over bridge
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
    let found = findPlayerByIdAndAction(trackId) { (id,player,playerMeta) -> () in
        NSLog("Player for path \(path) already exists will use player")
        if player.isPlaying() {
            player.pause()
        }
        player.currentItem.seekToTime(kCMTimeZero)
        player.currentItem.addObserver(self, forKeyPath: "status", options:nil, context: &self.AVPlayerItemContext)
        player.addObserver(self, forKeyPath:"status",options:nil, context: &self.AVPlayerContext)
        
        player.play()
        NSLog("Started playing player for path \(path)")

        self.dispatchEvent(self.AudioPlayerStarted, body: playerMeta.asDictionary())
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
    for (trackId,player, meta) in self._audioPlayerList {
       stopPlaying(player, playerMeta: meta, pause: false)
    }
  }

    @objc func stopRemovedTrack(path: NSString) {

        for (index, (trackId, player, meta)) in enumerate(self._audioPlayerList) {
            if trackId == path.toBase64String() {
                self._audioPlayerList.removeAtIndex(index)
                stopPlaying(player, playerMeta: meta, pause: false)
            }
        }
    }


    @objc func pauseMultiple() {
        for (trackId, player, meta) in self._audioPlayerList {
            stopPlaying(player, playerMeta: meta)
        }
    }

    @objc func pause(path: NSString) {
        let pathAsBase64 = path.toBase64String()

        for (trackId, player, meta) in self._audioPlayerList {
            if trackId == pathAsBase64 {
                //if player wasn't playing pause it
                if !stopPlaying(player, playerMeta: meta) {
                   player.play()
                }
            }
        }
    }

    @objc func stop() {
        self.pauseMultiple()
    }

    @objc func isPlayingAnyTracks() -> Bool {
        return self._audioPlayerList.filter{$0.1.isPlaying() }.count > 0
    }

    /**
     * Player private functions
     */


    func createPlayerWithPath(path: String,loop: Bool) -> (String, AVPlayer, PlayerMeta) {
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
        let playerMeta = PlayerMeta(trackId: trackId, path: path, playerId: playerId, loop: loop)

        if let anError = player.error {
            dispatchAnError(anError, bodyMessage: playerMeta.asDictionary())
        } else {
            //keep alive audio at background
            AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback, error: nil)
            AVAudioSession.sharedInstance().setActive(true, error: nil)

            _notificationCenter.addObserver(self,
                selector: "playerItemDidReachEnd:",
                name: AVPlayerItemDidPlayToEndTimeNotification,
                object: player.currentItem)

           //set a listener for when the player ends
           _notificationCenter.addObserver(self,
             selector: "handlePlayerEnd:",
             name: AVPlayerItemDidPlayToEndTimeNotification,
             object: player.currentItem)

            player.rate = 1.0
            player.volume = 1.0
            player.addObserver(self, forKeyPath:"status",options:nil, context: &AVPlayerContext)

            player.actionAtItemEnd = AVPlayerActionAtItemEnd.None

            self.dispatchEvent(self.AudioPlayerLoading, body: playerMeta.asDictionary())
        }
        return (trackId, player, playerMeta)
    }



    override func observeValueForKeyPath(keyPath: String, ofObject object: AnyObject, change: [NSObject : AnyObject], context: UnsafeMutablePointer<()>) {

        switch (keyPath,context) {
            case ("status", &AVPlayerContext) :
                if let player = object  as? AVPlayer {
                    let playerMeta:NSDictionary = self.getPlayerMetaAsDictionary(player.currentItem.asset)

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
                if let playerItem = object as? AVPlayerItem,
                    let (_,player,playerMeta) = self.getPlayerMeta(playerItem.asset) {

                    switch playerItem.status {
                        case AVPlayerItemStatus.ReadyToPlay:
                            NSLog("AVPlayerItemStatus ReadyToPlay")
                            NSLog("AVPlayerItemStatus tracks \(playerItem.tracks)")
                            self.dispatchEvent(self.AudioPlayerLoaded, body: playerMeta.asDictionary())
                        default:
                            let status = playerItem.status == AVPlayerItemStatus.Unknown ? "unknown" : "failed"
                            NSLog("AVPlayerItemStatus is \(status)")
                            NSLog("AVPlayerItem Access Logs \(playerItem.accessLog())")
                            NSLog("AVPlayerItem Error Logs \(playerItem.errorLog())")
                            self.dispatchEvent(self.AudioPlayerError, body: playerMeta.asDictionary())
                            //NSLog("Removing observer for  player item \(playerItem.asset) \(playerItem.tracks)")
                            playerItem.removeObserver(self, forKeyPath:"status", context: &AVPlayerItemContext)
                            player.removeObserver(self, forKeyPath:"status", context: &AVPlayerContext)
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

                let found = findPlayerByIdAndAction(trackId) { (id,player,_) -> () in
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

  /*!
  @method		stopPlaying:
  @abstract		Stops a player if it's currently playing a track and dispatches an event to
  @param			AVPlayer to stop
  @param			String containing track id to stop
  @param			Boolean to indicate if the call was to pause or stop the player
  @result		A boolean to indicate if the player was actually stopped
  */
  //function to stop a player, takes a boolean to
  func stopPlaying(aPlayer: AVPlayer, playerMeta: PlayerMeta,pause:Bool = true) -> Bool {
    var wasPaused = false
    if aPlayer.isPlaying() {
      aPlayer.pause()
      wasPaused = true

        aPlayer.currentItem.removeObserver(self, forKeyPath:"status", context: &AVPlayerItemContext)
        aPlayer.removeObserver(self, forKeyPath: "status", context: &AVPlayerContext)

        //removed any timedobservers for the player
        removeTimedObserverForPlayer(aPlayer,trackId: playerMeta.trackId)

    }

    //check if there are anymore tracks playting
    let anyTrackPlaying = self.isPlayingAnyTracks()


    //send event over bridge based on if it was a pause or not
    self.dispatchEvent(pause ? AudioPlayerEventPaused: AudioPlayerEventFinished, body: ["trackId" : playerMeta.trackId , "path" : playerMeta.path, "isAnythingPlaying": anyTrackPlaying])

    //if no more tracks are playing fire AudioPlayerFullyStopped event
    if !anyTrackPlaying {
      self.dispatchEvent(AudioPlayerFullyStopped, body: ["isAnythingPlaying": anyTrackPlaying])
    }



    return wasPaused
  }

    func playerItemDidReachEnd(notification: NSNotification) {
        var message:NSDictionary = [:]

        if let asset = (notification.object as? AVPlayerItem)?.asset {
            message = self.getPlayerMetaAsDictionary(asset)
        }

        self.dispatchEvent(self.AudioPlayerEventFinished, body: message)
    }

  func handlePlayerEnd(notification: NSNotification) {
    if let asset = (notification.object as? AVPlayerItem)?.asset,
        let (_,player,meta:PlayerMeta) = self.getPlayerMeta(asset) {

        //determine selector to fire when player reaches end of track
        //restart player from beginning if looping
        if meta.loop {
          self.restartPlayerFromBegining(player.currentItem)
        } else {

          self.stopPlaying(player, playerMeta: meta, pause: false)
        }
      //let selectorToFireOnEnd = loop ? "restartPlayerFromBegining" : "stopTimedObserver"
    }
  }
    func restartPlayerFromBegining(avPlayerItem: AVPlayerItem) {
        avPlayerItem.seekToTime(kCMTimeZero)
        NSLog("\restarting track")
        self.dispatchEvent(self.AudioPlayerStarted, body: self.getPlayerMetaAsDictionary(avPlayerItem.asset))
    }

  func removeTimedObserverForPlayer(player: AVPlayer,trackId: String) {
      if let observer: AnyObject = self.playerObservers[trackId],
        let index = self.playerObservers.indexForKey(trackId) {
        player.removeTimeObserver(observer)
        self.playerObservers.removeAtIndex(index)
      }
  }


    func findPlayerByIdAndAction(trackId: String, closure: (String,AVPlayer,PlayerMeta) -> ()) -> Bool {
        var found = false
        if let playerTuple = (_audioPlayerList.filter{$0.0 == trackId}.first) {
            closure(playerTuple)
            found = true
        }
        return found
    }

    func getPlayerMetaAsDictionary(playerAsset: AVAsset) -> NSDictionary {
        var meta = [:]
        if let playerMeta:PlayerMeta = getPlayerMeta(playerAsset) {
            meta = playerMeta.asDictionary()
        }
        return meta
    }

    func getPlayerMeta(playerAsset: AVAsset) -> PlayerMeta? {
        var meta: PlayerMeta?
        if let (_,_,playerMeta) = getPlayerMeta(playerAsset) {
            meta = playerMeta
        }
        return meta
    }

    func getPlayerMeta(playerAsset: AVAsset) -> (String,AVPlayer,PlayerMeta)? {

        var meta: (String,AVPlayer,PlayerMeta)?

        if let pathUrl = (playerAsset as? AVURLAsset)?.URL {

            let path = pathUrl.absoluteString!
            let trackId = path.toBase64String()

            return getPlayerDetails(trackId)

        }

        return meta
    }

    func getPlayerDetails(trackId:String) -> (String,AVPlayer,PlayerMeta)? {
        return ((_audioPlayerList.filter{$0.0 == trackId}).first)
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

        findPlayerByIdAndAction(trackId) { (id,player,_) -> () in
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
        _notificationCenter.removeObserver(self)

        for (trackId,player, meta) in self._audioPlayerList {
            player.pause()
            player.currentItem.removeObserver(self, forKeyPath:"status", context: &AVPlayerItemContext)
            player.removeObserver(self, forKeyPath: "status", context: &AVPlayerContext)
            removeTimedObserverForPlayer(player,trackId: trackId)
        }
    }
}
