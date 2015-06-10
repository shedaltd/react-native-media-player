'use strict';

var React = require('react-native');

var NativeModules  = require('NativeModules');

var AudioPlayerManager = NativeModules.AudioPlayerManager;

var RCTDeviceEventEmitter = require('RCTDeviceEventEmitter');

var AudioPlayer = {
  init: function(subscriptions) {
   this.subscriptions = subscriptions ? subscriptions : [];
   this.createListeners();
  },
  Events: AudioPlayerManager.Events,
  play: function(path) {
    AudioPlayerManager.play(path, false);
  },
  pause: function() {
    AudioPlayerManager.pause();
  },
  stop: function() {
    AudioPlayerManager.stop();
  },
  createListeners: function() {
    var self = this;
    var subscriptions = [];
    var playerEvents = AudioPlayerManager.Events;

    var addListener = function (event) {
        var listener = RCTDeviceEventEmitter.addListener(
          playerEvents[event],
          (eventData) => {
            // event handler defined? call it and pass along any event data
            var eventHandler = self["on"+event];
            eventHandler && eventHandler(eventData);
          }
        );
        subscriptions.push(listener);
    };

    // For each event key in AudioPlayerManager constantsToExport
    // Create listener and call event handler from props
    // e.g.  this.props.onPlayerProgress, this.props.onPlayerFinished
    Object.keys(playerEvents).forEach(addListener);

    // Add listeners to state
    self.subscriptions = subscriptions;
  }
};

module.exports = AudioPlayer;
