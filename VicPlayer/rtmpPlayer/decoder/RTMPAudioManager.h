//
//  RTMPAudioManager.h
//  VicPlayer
//
//  Created by Vic on 11/09/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>

#define audioManager [RTMPAudioManager sharedManager]

typedef void (^KxAudioManagerOutputBlock)(float *data, UInt32 numFrames, UInt32 numChannels);


@interface RTMPAudioManager : NSObject{
    
    float                       *_outputData;
    AudioUnit                   _audioUnit;
    AudioStreamBasicDescription _outputFormat;
}

@property (readonly) unsigned int numOutputChannels;
@property (readonly) double samplingRate;
@property (readonly) unsigned int numBytesPerSample;
@property (readonly) float outputVolume;
@property (readonly) BOOL playing;
@property (readonly, strong) NSString *audioRoute;

@property (readwrite, copy) KxAudioManagerOutputBlock outputBlock;

- (NSError *)activateAudioSession;
- (NSError *)deactivateAudioSession;
- (BOOL)play;
- (void)stop;
- (BOOL)renderFrames:(UInt32)numFrames
              ioData:(AudioBufferList *)ioData;

+ (RTMPAudioManager *)sharedManager;

@end
