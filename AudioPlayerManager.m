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

@interface RCT_EXTERN_MODULE(AudioPlayerManger, NSObject)

RCT_EXTERN_METHOD(play:(NSString *)path loop:(BOOL)loop)

RCT_EXTERN_METHOD(pause)

RCT_EXTERN_METHOD(stop)

@end

