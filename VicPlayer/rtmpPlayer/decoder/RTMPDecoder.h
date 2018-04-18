//
//  RTMPDecoder.h
//  VicPlayer
//
//  Created by Vic on 06/09/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import <UIKit/UIKit.h>

#include "libavformat/avformat.h"

#import "RTMPFrameComponents.h"

typedef NS_ENUM(NSInteger, RTMPDecoderError) {
    RTMPDecoderErrorNone = 0,
    RTMPDecoderErrorOpenFile,
    RTMPDecoderErrorStreamInfoNotFound,
    RTMPDecoderErrorStreamNotFound,
    RTMPDecoderErrorCodecNotFound,
    RTMPDecoderErrorOpenCodec,
    RTMPDecoderErrorAllocateFrame,
    RTMPDecoderErrorSetupScaler,
    RTMPDecoderErrorReSampler,
    RTMPDecoderErrorUnsupported,
};

typedef BOOL (^RTMPDecoderInterruptionCallback) (void);

@interface RTMPDecoder : NSObject

@property (readonly, nonatomic, strong) NSString *path;
@property (readonly, nonatomic) BOOL isEOF;
@property (nonatomic) CGFloat position;
@property (readonly, nonatomic) CGFloat duration;
@property (readonly, nonatomic) CGFloat sampleRate;
@property (readonly, nonatomic) NSUInteger frameWidth;
@property (readonly, nonatomic) NSUInteger frameHeight;
@property (readonly, nonatomic) NSUInteger audioStreamsCount;
@property (nonatomic) NSInteger selectedAudioStream;
@property (readonly, nonatomic) NSUInteger subtitleStreamsCount;
@property (nonatomic) NSInteger selectedSubtitleStream;
@property (readonly, nonatomic) BOOL validVideo;
@property (readonly, nonatomic) BOOL validAudio;
@property (readonly, nonatomic) BOOL validSubtitles;
@property (readonly, nonatomic, strong) NSDictionary *info;
@property (readonly, nonatomic, strong) NSString *videoStreamFormatName;
@property (readonly, nonatomic) BOOL isNetwork;
@property (readonly, nonatomic) CGFloat startTime;

/** 是否加载自网络 */
@property (nonatomic, readonly, getter=isLoadFromWebURL) BOOL loadFromWebURL;

/** 资源文件路径 */
@property (nonatomic, strong, readonly) NSString *rtmpPath;

@property (nonatomic, assign) CGFloat fps;
@property (nonatomic, assign, getter=isDisableDeinterlacing) BOOL disableDeinterlacing;
@property (nonatomic, copy) RTMPDecoderInterruptionCallback interruptionCallback;

- (void)setupDecoderWithContentUrl:(NSString *)path
                             error:(NSError **)error;

- (BOOL)setVideoFrameFormat:(EnumRTMPVideoFrameType)enumVideoFrameType;

- (NSArray *)decodeFramesWithMinDuration:(CGFloat)minDuration;

@end
