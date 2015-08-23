'use strict';

var React = require('react-native');

var NativeModules  = require('NativeModules');

var AudioPlayerManager = NativeModules.AudioPlayerManager;

var RCTDeviceEventEmitter = require('RCTDeviceEventEmitter');

var warning = require('warning');

var AudioPlayer = {
  init: function(subscriptions) {
    if (!this.initalized) {
      this.subscriptions = subscriptions ? subscriptions : [];
      this.createListeners();
      this.initalized = true;
    }
  },
  Events: AudioPlayerManager.Events,
  play: function(path,loop) {
    this.init();
    AudioPlayerManager.play(path, loop);
  },
  playMultiple: function(pathArray,loop) {
    this.init();
    AudioPlayerManager.playMultiple(pathArray, loop);
  },
  playAddedTrack: function(path,loop) {
    this.init();
    AudioPlayerManager.playAddedTrack(path, loop);
  },
  pause: function(path) {
    AudioPlayerManager.pause(path);
  },
  pauseMultiple: function() {
    AudioPlayerManager.pauseMultiple();
  },
  stop: function() {
    AudioPlayerManager.stop();
  },
  stopMultiple: function() {
    AudioPlayerManager.stopMultiple();
  },
  stopRemovedTrack: function(path) {
    AudioPlayerManager.stopRemovedTrack(path);
  },
  addListener: function (eventName:string, {path,eventHandler}) {
    var self = this;
    var playerEvents = AudioPlayerManager.Events;
    var event = playerEvents[eventName];
    if (!event) {
      warning(true, eventName + ' is not a supported AudioPlayerManager event. Available events ' + JSON.stringify(playerEvents));
      return;
    }

    var listener = RCTDeviceEventEmitter.addListener(event,(eventData) => {
      //self["on"+event] = eventHandler;
      eventHandler && eventHandler(eventData);
    });

    if (!self.subscriptions) {
      self.subscriptions = [];
    }
    self.subscriptions.push(listener);
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
            var eventHandler = self['on'+event];
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
