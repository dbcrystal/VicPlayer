//
//  RTMPAudioManager.m
//  VicPlayer
//
//  Created by Vic on 11/09/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import "RTMPAudioManager.h"

#define MAX_FRAME_SIZE 4096
#define MAX_CHAN       2

@interface RTMPAudioManager ()

@property (nonatomic, assign, getter=isAudioSessionActivated) BOOL audioSessionActivate;

@property (nonatomic, assign) AudioUnit audioUnit;

@end

@implementation RTMPAudioManager

+ (RTMPAudioManager *)sharedManager
{
    static RTMPAudioManager *tool = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tool = [[RTMPAudioManager alloc] init];
    });
    return tool;
}


- (id)init
{
    self = [super init];
    if (self) {
        
        _outputData = (float *)calloc(MAX_FRAME_SIZE*MAX_CHAN, sizeof(float));
        _outputVolume = 0.5;
    }
    return self;
}

#pragma mark - activate
- (NSError *)activateAudioSession {
    
    NSError *error;
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                           error:&error];
    
    [[AVAudioSession sharedInstance] setActive:YES
                                   withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                         error:&error];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioManagerHandleInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:[AVAudioSession sharedInstance]];
    
    return error;
}

- (void)setupAudioUnit {
    
    AudioComponentDescription description = {0};
    description.componentType = kAudioUnitType_Output;
    description.componentSubType = kAudioUnitSubType_RemoteIO;
    description.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    AudioComponentInstanceNew(component, &_audioUnit);
    
    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioUnitGetProperty(_audioUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         0,
                         &_outputFormat,
                         &size);
    
    _outputFormat.mSampleRate = _samplingRate;
    AudioUnitSetProperty(_audioUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         0,
                         &_outputFormat,
                         size);
    
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = renderCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)(self);
    
    AudioUnitSetProperty(_audioUnit,
                                        kAudioUnitProperty_SetRenderCallback,
                                        kAudioUnitScope_Input,
                                        0,
                                        &callbackStruct,
                         sizeof(callbackStruct));
    
    AudioUnitInitialize(_audioUnit);
}

#pragma mark - deactivate
- (NSError *)deactivateAudioSession {
    
    [self stop];
    
    AudioUnitUninitialize(_audioUnit);
    AudioComponentInstanceDispose(_audioUnit);
    
    NSError *error;
    [[AVAudioSession sharedInstance] setActive:NO
                                   withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                         error:&error];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioSessionInterruptionNotification
                                                  object:[AVAudioSession sharedInstance]];
    
    return error;
}

#pragma mark - play
- (BOOL)play {
    
    OSStatus error = AudioOutputUnitStart(_audioUnit);
    
    return [self checkError:error];
}

#pragma mark - stop
- (void)stop {
    AudioOutputUnitStop(_audioUnit);
}

#pragma mark - 检查audioSession是否可以播放
- (BOOL)checkIfAudioSessionIsReady {
    if ([[AVAudioSession sharedInstance] isOtherAudioPlaying]) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)renderFrames:(UInt32)numFrames
              ioData:(AudioBufferList *)ioData
{
    for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
        memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);
    }
    
    if (_playing && _outputBlock ) {
        
        // Collect data to render from the callbacks
        _outputBlock(_outputData, numFrames, _numOutputChannels);
        
        // Put the rendered data into the output buffer
        if (_numBytesPerSample == 4) // then we've already got floats
        {
            float zero = 0.0;
            
            for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
                
                int thisNumChannels = ioData->mBuffers[iBuffer].mNumberChannels;
                
                for (int iChannel = 0; iChannel < thisNumChannels; ++iChannel) {
                    vDSP_vsadd(_outputData+iChannel, _numOutputChannels, &zero, (float *)ioData->mBuffers[iBuffer].mData, thisNumChannels, numFrames);
                }
            }
        }
        else if (_numBytesPerSample == 2) // then we need to convert SInt16 -> Float (and also scale)
        {
            //            dumpAudioSamples(@"Audio frames decoded by FFmpeg:\n",
            //                             _outData, @"% 12.4f ", numFrames, _numOutputChannels);
            
            float scale = (float)INT16_MAX;
            vDSP_vsmul(_outputData, 1, &scale, _outputData, 1, numFrames*_numOutputChannels);
            
#ifdef DUMP_AUDIO_DATA
            LoggerAudio(2, @"Buffer %u - Output Channels %u - Samples %u",
                        (uint)ioData->mNumberBuffers, (uint)ioData->mBuffers[0].mNumberChannels, (uint)numFrames);
#endif
            
            for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
                
                int thisNumChannels = ioData->mBuffers[iBuffer].mNumberChannels;
                
                for (int iChannel = 0; iChannel < thisNumChannels; ++iChannel) {
                    vDSP_vfix16(_outputData+iChannel, _numOutputChannels, (SInt16 *)ioData->mBuffers[iBuffer].mData+iChannel, thisNumChannels, numFrames);
                }
#ifdef DUMP_AUDIO_DATA
                dumpAudioSamples(@"Audio frames decoded by FFmpeg and reformatted:\n",
                                 ((SInt16 *)ioData->mBuffers[iBuffer].mData),
                                 @"% 8d ", numFrames, thisNumChannels);
#endif
            }
            
        }        
    }
    
    return noErr;
}

#pragma mark - Notification
- (void)audioManagerHandleInterruption:(NSNotification *)notification {
    ;
}

- (BOOL)checkError:(OSStatus)error {
    
    if (error == noErr)
        return NO;
    
    char str[20] = {0};
    // see if it appears to be a 4-char-code
    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    }
    return YES;
}

static OSStatus renderCallback (void						*inRefCon,
                                AudioUnitRenderActionFlags	* ioActionFlags,
                                const AudioTimeStamp 		* inTimeStamp,
                                UInt32						inOutputBusNumber,
                                UInt32						inNumberFrames,
                                AudioBufferList				* ioData)
{
    RTMPAudioManager *sm = (__bridge RTMPAudioManager *)inRefCon;
    return [sm renderFrames:inNumberFrames ioData:ioData];
}

@end
