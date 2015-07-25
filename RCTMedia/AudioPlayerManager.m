//
//  AudioPlayerManager.m
//  MediaPlayer
//
//  Created by Mike Ebinum on 3/06/2015.
//  Copyright (c) 2015 SEED Digital. All rights reserved.
//

#import "RCTBridgeModule.h"
#import "RCTConvert.h"
#import "RCTBridge.h"
#import "RCTEventDispatcher.h"
#import "RCTLog.h"

@interface RCT_EXTERN_MODULE(AudioPlayerManager, NSObject)

RCT_EXTERN_METHOD(play:(NSString *)path loop:(BOOL)loop)

RCT_EXTERN_METHOD(playMultiple:(NSArray *)path loop:(BOOL)loop)

RCT_EXTERN_METHOD(playAddedTrack:(NSString *)path loop:(BOOL)loop)

RCT_EXTERN_METHOD(stopMultiple)

RCT_EXTERN_METHOD(stopRemovedTrack:(NSString *)path)

RCT_EXTERN_METHOD(pauseMultiple)

RCT_EXTERN_METHOD(pause:(NSString *)path)

RCT_EXTERN_METHOD(stop)

@end

