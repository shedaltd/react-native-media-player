/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 */
'use strict';

var React = require('react-native');
var AudioPlayer = require('react-native-media-player');
var {
  AppRegistry,
  StyleSheet,
  Text,
  View,
  TextInput,
  TouchableHighlight,
  SwitchIOS
} = React;

var MediaPlayerExample = React.createClass({
  getInitialState() {
    return {
      currentTime: 0.0,
      stoppedPlaying: false,
      playing: false,
      textInputValue : null
    }
  },
  componentDidMount() {

    AudioPlayer.onPlayerError = (error) => {
        console.log('error occurred while playing');
        console.log(error);
      };

    AudioPlayer.onPlayerLoading = (data) => {
      console.log('I\'m loading yeah ' + JSON.stringify(data));
    };

    AudioPlayer.onPlayerLoaded = (data) => {
      console.log('I\'ve finished loading cool bro ' + JSON.stringify(data));
    };

    AudioPlayer.onPlayerStarted = () => {console.log('started playing yeah'); };

    AudioPlayer.onPlayerProgress = (data) => {
    //  console.log('progress current time ' + data.currentTime)
      this.setState({
        currentTime : data.currentTime
      });
    };

    AudioPlayer.onPlayerFinished = (data) => {
      console.log('finsished? ' + JSON.stringify(data));
    };

    AudioPlayer.onAllPlayStopped = (data) => {
      console.log('finshed playing all tracks ' + JSON.stringify(data));
    };
    AudioPlayer.init();
  },

  _renderButton: function(title, onPress, active) {
    var style = (active) ? styles.activeButtonText : styles.buttonText

    return (<TouchableHighlight style={styles.button} onPress={onPress}>
      <Text style={style}>
        {title}
      </Text>
    </TouchableHighlight>);
  },

  _pause: function() {
    if (this.state.playing) {
      AudioPlayer.pause();
    }
  },

  _stop: function() {
    if (this.state.playing) {
      AudioPlayer.stop();
      this.setState({playing: false, stoppedPlaying: true,currentTime:0.0});
    }
  },


 _play: function() {
   var fileName     = this.state.textInputValue;
   console.log(AudioPlayer.Events);
   AudioPlayer.play(fileName);
    this.setState({playing: true});
  },
//http://free-loops.com/data/mp3/9e/b6/c469a7858626b1a3e73b936aacb7.mp3
  // Handler for the TextInput onChange event -- changed a bit to setState
  _onTextInputChange : function(event) {
       this.setState({
           textInputValue : event.nativeEvent.text
       });
   },
   _handlePlayerEvents: function () {

   },
  render: function() {

    return (
      <View style={styles.container}>
        <View style={styles.controls}>
          {/*  Container for input field */}
          <View style={styles.labelContainer}>
              <Text style={styles.labelText}>
                  Media File :
              </Text>
              <TextInput
                  style={styles.textInput}
                  ref="textInput"
                  onChange={this._onTextInputChange}
              />

          </View>
          {this._renderButton("STOP", () => {this._stop()} )}
          {this._renderButton("PAUSE", () => {this._pause()} )}
          {this._renderButton("PLAY", () => {this._play()}, this.state.playing )}
          {/* <SwitchIOS*/}
          <Text style={styles.progressText}>{this.state.currentTime}s</Text>
        </View>
      </View>
    );
  }
});

var styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#2b608a",
  },
  controls: {
    justifyContent: 'center',
    alignItems: 'center',
    flex: 1,
  },
  progressText: {
    paddingTop: 50,
    fontSize: 50,
    color: "#fff"
  },
  button: {
    padding: 20
  },
  disabledButtonText: {
    color: '#eee'
  },
  buttonText: {
    fontSize: 20,
    color: "#fff"
  },
  activeButtonText: {
    fontSize: 20,
    color: "#B81F00"
  },
  labelContainer : {
        flexDirection  : 'row',
        width          : 300
    },

    labelText : {
        paddingRight : 10,
        fontSize     : 18
    },

    textInput : {
        height      : 26,
        borderWidth : 0.5,
        borderColor : '#ffffff',
        padding     : 4,
        flex        : 1,
        fontSize    : 13,
    }

});

AppRegistry.registerComponent('MediaPlayerExample', () => MediaPlayerExample);
