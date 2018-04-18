//
//  RTMPPlayer.m
//  VicPlayer
//
//  Created by Vic on 26/10/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import "RTMPPlayer.h"

#import "RTMPGLView.h"
#import "RTMPDecoder.h"
#import "RTMPAudioManager.h"

#define LOCAL_MIN_BUFFERED_DURATION   0.2
#define LOCAL_MAX_BUFFERED_DURATION   0.4
#define NETWORK_MIN_BUFFERED_DURATION 2.0
#define NETWORK_MAX_BUFFERED_DURATION 4.0

NSString * const KxMovieParameterMinBufferedDuration = @"KxMovieParameterMinBufferedDuration";
NSString * const KxMovieParameterMaxBufferedDuration = @"KxMovieParameterMaxBufferedDuration";
NSString * const KxMovieParameterDisableDeinterlacing = @"KxMovieParameterDisableDeinterlacing";

@interface RTMPPlayer ()
{
    
    dispatch_queue_t    _dispatchQueue;
    NSMutableArray      *_videoFrames;
    NSMutableArray      *_audioFrames;
    NSMutableArray      *_subtitles;
    NSData              *_currentAudioFrame;
    NSUInteger          _currentAudioFramePos;
    CGFloat             _moviePosition;
    BOOL                _disableUpdateHUD;
    NSTimeInterval      _tickCorrectionTime;
    NSTimeInterval      _tickCorrectionPosition;
    NSUInteger          _tickCounter;
    BOOL                _fullscreen;
    BOOL                _hiddenHUD;
    BOOL                _fitMode;
    BOOL                _infoMode;
    BOOL                _restoreIdleTimer;
    BOOL                _interrupted;
    
    RTMPGLView         *_glView;
    UIImageView         *_imageView;
    UIView              *_topHUD;
    
    
    
    CGFloat             _bufferedDuration;
    CGFloat             _minBufferedDuration;
    CGFloat             _maxBufferedDuration;
    BOOL                _buffered;
    
    NSDictionary        *_parameters;
}

@property (nonatomic, strong) RTMPDecoder *decoder;
@property (nonatomic, strong) RTMPArtworkFrame *artworkFrame;

@property (nonatomic, assign, getter=isDecoding) BOOL decoding;
@property (nonatomic, assign, getter=isPlaying) BOOL playing;

@end

@implementation RTMPPlayer

- (id)initWithFrame:(CGRect)frame andParam:(NSDictionary *)param
{
    self = [super initWithFrame:frame];
    if (self) {
        
        _moviePosition = 0;
        
        _parameters = param;
        
    }
    return self;
}

#pragma mark - public method
- (void)setupAddress:(NSString *)address {
    
    RTMPDecoder *decoder = [[RTMPDecoder alloc] init];
    
    decoder.interruptionCallback = ^BOOL(){
        
        __weak RTMPPlayer *weakSelf = self;
        return weakSelf ? [weakSelf ifInterrupted] : YES;
    };
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        NSError *error = nil;
        [decoder setupDecoderWithContentUrl:address error:&error];
        
        if (self) {
            
            dispatch_sync(dispatch_get_main_queue(), ^{
                
                [self setMovieDecoder:decoder withError:error];
                
                if (self.decoder) {
                    [self setupPresentView];
                    
                }
                
                [self startPlayback];
            });
        }
    });
}

- (void)setupPresentView
{
    
    if (_decoder.validVideo) {
        _glView =  [[RTMPGLView alloc] initWithFrame:self.bounds decoder:_decoder];
    }
    
    if (!_glView) {
        
        [_decoder setVideoFrameFormat:EnumRTMPVideoFrameTypeRGB];
        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.backgroundColor = [UIColor blackColor];
    }
    
    UIView *frameView = _glView ? _glView : _imageView;
    frameView.contentMode = UIViewContentModeScaleAspectFit;
    frameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    
    [self insertSubview:frameView atIndex:0];
}

- (void)startPlayback {
    if (self.isPlaying) {
        return;
    }
    
    self.playing = YES;
    
    [self asyncDecodeFrames];
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self tick];
    });
    
    if (_decoder.validAudio)
        [self enableAudio:YES];
}

- (void)stopPlayback {
    if (!self.isPlaying)
        return;
    
    self.playing = NO;
    [self enableAudio:NO];
}

#pragma mark - private
- (BOOL)ifInterrupted {
    return _interrupted;
}

- (void)setMovieDecoder:(RTMPDecoder *)decoder
              withError:(NSError *)error
{
    if (!error && decoder) {
        
        _decoder        = decoder;
        _dispatchQueue  = dispatch_queue_create("KxMovie", DISPATCH_QUEUE_SERIAL);
        _videoFrames    = [NSMutableArray array];
        _audioFrames    = [NSMutableArray array];
        
        if (_decoder.subtitleStreamsCount) {
            _subtitles = [NSMutableArray array];
        }
        
        if (_decoder.isNetwork) {
            
            _minBufferedDuration = NETWORK_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = NETWORK_MAX_BUFFERED_DURATION;
            
        } else {
            
            _minBufferedDuration = LOCAL_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = LOCAL_MAX_BUFFERED_DURATION;
        }
        
        if (!_decoder.validVideo)
            _minBufferedDuration *= 10.0; // increase for audio
        
        // allow to tweak some parameters at runtime
        if (_parameters.count) {
            
            id val;
            
            val = [_parameters valueForKey: KxMovieParameterMinBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _minBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: KxMovieParameterMaxBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _maxBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: KxMovieParameterDisableDeinterlacing];
            if ([val isKindOfClass:[NSNumber class]])
                _decoder.disableDeinterlacing = [val boolValue];
            
            if (_maxBufferedDuration < _minBufferedDuration)
                _maxBufferedDuration = _minBufferedDuration * 2;
        }
        
        
    } else {
    }
}

- (void)asyncDecodeFrames
{
    if (self.isDecoding)
        return;
    
    __weak RTMPDecoder *weakDecoder = _decoder;
    
    const CGFloat duration = _decoder.isNetwork ? .0f : 0.1f;
    
    self.decoding = YES;
    dispatch_async(_dispatchQueue, ^{
        
        BOOL good = YES;
        while (good) {
            
            good = NO;
            
            @autoreleasepool {
                
                __strong RTMPDecoder *decoder = weakDecoder;
                
                if (decoder && (decoder.validVideo || decoder.validAudio)) {
                    
                    NSArray *frames = [decoder decodeFramesWithMinDuration:duration];
                    if (frames.count && self) {
                        
                        good = [self addFrames:frames];
                    }
                }
            }
        }
            
        if (self) {
            self.decoding = NO;
        }
        
    });
}

- (BOOL)addFrames:(NSArray *)frames
{
    if (_decoder.validVideo) {
        
        @synchronized(_videoFrames) {
            
            for (RTMPCommonFrame *frame in frames)
                if (frame.enumFrameType == EnumRTMPFrameTypeVideo) {
                    [_videoFrames addObject:frame];
                    _bufferedDuration += frame.duration;
                }
        }
    }
    
    if (_decoder.validAudio) {
        
        @synchronized(_audioFrames) {
            
            for (RTMPCommonFrame *frame in frames)
                if (frame.enumFrameType == EnumRTMPFrameTypeAudio) {
                    [_audioFrames addObject:frame];
                    if (!_decoder.validVideo)
                        _bufferedDuration += frame.duration;
                }
        }
        
        if (!_decoder.validVideo) {
            
            for (RTMPCommonFrame *frame in frames)
                if (frame.enumFrameType == EnumRTMPFrameTypeArtwork)
                    self.artworkFrame = (RTMPArtworkFrame *)frame;
        }
    }
    
    if (_decoder.validSubtitles) {
        
        @synchronized(_subtitles) {
            
            for (RTMPCommonFrame *frame in frames)
                if (frame.enumFrameType == EnumRTMPFrameTypeSubtitle) {
                    [_subtitles addObject:frame];
                }
        }
    }
    
    return _bufferedDuration < _maxBufferedDuration;
}

#pragma mark - tick
- (void)tick
{
    if (_buffered && ((_bufferedDuration > _minBufferedDuration) || _decoder.isEOF)) {
        
        _tickCorrectionTime = 0;
        _buffered = NO;
    }
    
    CGFloat interval = 0;
    if (!_buffered)
        interval = [self presentFrame];
    
    if (self.isPlaying) {
        
        const NSUInteger leftFrames =
        (_decoder.validVideo ? _videoFrames.count : 0) +
        (_decoder.validAudio ? _audioFrames.count : 0);
        
        if (0 == leftFrames) {
            
            if (_decoder.isEOF) {
                
                [self stopPlayback];
                return;
            }
            
            if (_minBufferedDuration > 0 && !_buffered) {
                
                _buffered = YES;
            }
        }
        
        if (!leftFrames ||
            !(_bufferedDuration > _minBufferedDuration)) {
            
            [self asyncDecodeFrames];
        }
        
        const NSTimeInterval correction = [self tickCorrection];
        const NSTimeInterval time = MAX(interval + correction, 0.01);
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self tick];
        });
    }
}

- (CGFloat)tickCorrection
{
    if (_buffered)
        return 0;
    
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (!_tickCorrectionTime) {
        
        _tickCorrectionTime = now;
        _tickCorrectionPosition = _moviePosition;
        return 0;
    }
    
    NSTimeInterval dPosition = _moviePosition - _tickCorrectionPosition;
    NSTimeInterval dTime = now - _tickCorrectionTime;
    NSTimeInterval correction = dPosition - dTime;
    
    if (correction > 1.f || correction < -1.f) {
        
        correction = 0;
        _tickCorrectionTime = 0;
    }
    
    return correction;
}

#pragma mark - Video
- (CGFloat)presentFrame
{
    CGFloat interval = 0;
    
    if (_decoder.validVideo) {
        
        RTMPVideoFrame *frame;
        
        @synchronized(_videoFrames) {
            
            if (_videoFrames.count > 0) {
                
                frame = _videoFrames[0];
                [_videoFrames removeObjectAtIndex:0];
                _bufferedDuration -= frame.duration;
            }
        }
        
        if (frame)
            interval = [self presentVideoFrame:frame];
        
    } else if (_decoder.validAudio) {
        
        if (self.artworkFrame) {
            
            _imageView.image = [self.artworkFrame asImage];
            self.artworkFrame = nil;
        }
    }
    
    if (_decoder.validSubtitles)
        [self presentSubtitles];
    
    return interval;
}

- (CGFloat)presentVideoFrame:(RTMPVideoFrame *)frame
{
    if (_glView) {
        
        [_glView render:frame];
        
    } else {
        
        RTMPVideoFrameRGB *rgbFrame = (RTMPVideoFrameRGB *)frame;
        _imageView.image = [rgbFrame asImage];
    }
    
    _moviePosition = frame.position;
    
    return frame.duration;
}

- (void)presentSubtitles
{
//    NSArray *actual, *outdated;
//
//    if ([self subtitleForPosition:_moviePosition
//                           actual:&actual
//                         outdated:&outdated]){
//
//        if (outdated.count) {
//            @synchronized(_subtitles) {
//                [_subtitles removeObjectsInArray:outdated];
//            }
//        }
//
//        if (actual.count) {
//
//            NSMutableString *ms = [NSMutableString string];
//            for (KxSubtitleFrame *subtitle in actual.reverseObjectEnumerator) {
//                if (ms.length) [ms appendString:@"\n"];
//                [ms appendString:subtitle.text];
//            }
//
//            if (![_subtitlesLabel.text isEqualToString:ms]) {
//
//                CGSize viewSize = self.view.bounds.size;
//                CGSize size = [ms sizeWithFont:_subtitlesLabel.font
//                             constrainedToSize:CGSizeMake(viewSize.width, viewSize.height * 0.5)
//                                 lineBreakMode:NSLineBreakByTruncatingTail];
//                _subtitlesLabel.text = ms;
//                _subtitlesLabel.frame = CGRectMake(0, viewSize.height - size.height - 10,
//                                                   viewSize.width, size.height);
//                _subtitlesLabel.hidden = NO;
//            }
//
//        } else {
//
//            _subtitlesLabel.text = nil;
//            _subtitlesLabel.hidden = YES;
//        }
//    }
}

#pragma mark - Audio
- (void)enableAudio:(BOOL)on
{
    if (on && _decoder.validAudio) {
        
        audioManager.outputBlock = ^(float *outData, UInt32 numFrames, UInt32 numChannels) {
            
            [self audioCallbackFillData: outData numFrames:numFrames numChannels:numChannels];
        };
        
        [audioManager play];
        
        NSLog(@"audio device smr: %d fmt: %d chn: %d",
              (int)audioManager.samplingRate,
              (int)audioManager.numBytesPerSample,
              (int)audioManager.numOutputChannels);
        
    } else {
        
        [audioManager stop];
        audioManager.outputBlock = nil;
    }
}

- (void)audioCallbackFillData:(float *)outData
                    numFrames:(UInt32)numFrames
                  numChannels:(UInt32)numChannels
{
    
    if (_buffered) {
        memset(outData, 0, numFrames * numChannels * sizeof(float));
        return;
    }
    
    @autoreleasepool {
        
        while (numFrames > 0) {
            
            if (!_currentAudioFrame) {
                
                @synchronized(_audioFrames) {
                    
                    NSUInteger count = _audioFrames.count;
                    
                    if (count > 0) {
                        
                        RTMPAudioFrame *frame = _audioFrames[0];
                        if (_decoder.validVideo) {
                            
                            const CGFloat delta = _moviePosition - frame.position;
                            
                            if (delta < -0.1) {
                                
                                memset(outData, 0, numFrames * numChannels * sizeof(float));
                                break; // silence and exit
                            }
                            
                            [_audioFrames removeObjectAtIndex:0];
                            
                            if (delta > 0.1 && count > 1) {
                                continue;
                            }
                            
                        } else {
                            
                            [_audioFrames removeObjectAtIndex:0];
                            _moviePosition = frame.position;
                            _bufferedDuration -= frame.duration;
                        }
                        
                        _currentAudioFramePos = 0;
                        _currentAudioFrame = frame.sample;
                    }
                }
            }
            
            if (_currentAudioFrame) {
                
                const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels * sizeof(float);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                
                if (bytesToCopy < bytesLeft)
                    _currentAudioFramePos += bytesToCopy;
                else
                    _currentAudioFrame = nil;
                
            } else {
                
                memset(outData, 0, numFrames * numChannels * sizeof(float));
                break;
            }
        }
    }
}

@end
