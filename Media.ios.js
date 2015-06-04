'use strict';

var React = require('react-native');

var AudioPlayerManager = require('NativeModules').AudioPlayerManager;

var RCTDeviceEventEmitter = require('RCTDeviceEventEmitter');

var AudioPlayer = {
  play: function(path) {
    AudioPlayerManager.play(path,false);
  },
  pause: function() {
    AudioPlayerManager.pause();    
  },
  stop: function() {
    AudioPlayerManager.stop();
    if (this.subscription) {
      this.subscription.remove();
    }
  }
};

module.exports = {AudioPlayer};