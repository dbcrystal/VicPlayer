//
//  RTMPDecoder.m
//  VicPlayer
//
//  Created by Vic on 06/09/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import "RTMPDecoder.h"

#import "RTMPAudioManager.h"
#import "RTMPSubtitleASSParser.h"


#include "libavformat/avformat.h"

#import <libswresample/swresample.h>
#import <libswscale/swscale.h>
#import <libavutil/pixdesc.h>

static int interrupt_callback(void *ctx);

@interface RTMPDecoder ()

@property (nonatomic) EnumRTMPVideoFrameType enumVideoFrameFormat;

@property (nonatomic) AVFormatContext *context;

// Video
@property (nonatomic, assign) NSInteger videoStream;
@property (nonatomic, assign) NSInteger artworkStream;
@property (nonatomic) AVCodecContext *videoCodecContext;
@property (nonatomic) AVCodecParameters *videoCodecParam;
@property (nonatomic, strong) NSArray *arrVideoStreams;
@property (nonatomic) CGFloat videoTimeBase;
@property (nonatomic) AVFrame *videoFrame;

// Audio
@property (nonatomic) AVCodecContext *audioCodecContext;
@property (nonatomic) AVCodecParameters *audioCodecParam;
@property (nonatomic, assign) NSInteger audioStream;
@property (nonatomic, strong) NSArray *arrAudioStreams;
@property (nonatomic) CGFloat audioTimeBase;
@property (nonatomic) AVFrame *audioFrame;

@property (nonatomic) SwrContext *swrContext;
@property (nonatomic) void *swrBuffer;
@property (nonatomic) NSUInteger swrBufferSize;

@property (nonatomic) struct SwsContext *swsContext;

@property (nonatomic, assign) NSInteger subtitleStream;
@property (nonatomic) AVCodecContext *subtitleCodecContext;
@property (nonatomic) AVCodecParameters *subtitleCodecParam;
@property (nonatomic, strong) NSArray *arrSubtitleStreams;
@property (nonatomic) NSInteger subtitleASSEvents;

@property (nonatomic) AVFrame *frame;

@property (nonatomic, assign) BOOL isEOF;

@property (nonatomic, strong) NSString *path;
@property (nonatomic) CGFloat duration;
@property (nonatomic) CGFloat sampleRate;
@property (nonatomic) NSUInteger frameWidth;
@property (nonatomic) NSUInteger frameHeight;
@property (nonatomic) NSUInteger audioStreamsCount;
@property (nonatomic) NSUInteger subtitleStreamsCount;
@property (nonatomic) BOOL validVideo;
@property (nonatomic) BOOL validAudio;
@property (nonatomic) BOOL validSubtitles;
@property (nonatomic, strong) NSDictionary *info;
@property (nonatomic, strong) NSString *videoStreamFormatName;
@property (nonatomic) BOOL isNetwork;
@property (nonatomic) CGFloat startTime;

@property (nonatomic, assign) BOOL pictureValid;

@end

static void FFLog(void* context, int level, const char* format, va_list args);

@implementation RTMPDecoder

+ (void)initialize
{
    av_log_set_callback(FFLog);
    av_register_all();
    avformat_network_init();
}

#pragma mark - open File
- (void)setupDecoderWithContentUrl:(NSString *)path
                             error:(NSError **)error {
    avcodec_register_all();
    av_register_all();
    
    [self openFileWithPath:path
                     error:error];
    
    
}

- (BOOL)setVideoFrameFormat:(EnumRTMPVideoFrameType)enumVideoFrameType {
    
    if (enumVideoFrameType == EnumRTMPVideoFrameTypeYUV &&
        _videoCodecContext &&
        (_videoCodecContext->pix_fmt == AV_PIX_FMT_YUV420P || _videoCodecContext->pix_fmt == AV_PIX_FMT_YUVJ420P)) {
        
        self.enumVideoFrameFormat = EnumRTMPVideoFrameTypeYUV;
        return YES;
    }
    
    self.enumVideoFrameFormat = EnumRTMPVideoFrameTypeRGB;
    return self.enumVideoFrameFormat == enumVideoFrameType;
}

- (BOOL)openFileWithPath:(NSString *)path
                   error:(NSError **)error {
    
    [self closeFile];
    
    if (!path || [path isEqualToString:@""]) {
        return NO;
    }
    
    _loadFromWebURL = [self checkIfIsWebURL:path];
    
    // 初始化网络
    static BOOL needNetworkInit = YES;
    if (needNetworkInit && _loadFromWebURL) {
        
        needNetworkInit = NO;
        avformat_network_init();
    }
    
    _rtmpPath = path;
    
    // 读取文件
    RTMPDecoderError errCode = [self openFile:path];
    
    // 读取成功
    if (errCode == RTMPDecoderErrorNone) {
        
        RTMPDecoderError videoErr = [self openVideoStream];
        RTMPDecoderError audioErr = [self openAudioStream];
        
        _subtitleStream = -1;
        
        if (videoErr != RTMPDecoderErrorNone &&
            audioErr != RTMPDecoderErrorNone) {
            
            errCode = videoErr; // both fails
            
        } else {
            
            _arrSubtitleStreams = [self collectStreamsWithContext:_context andCType:AVMEDIA_TYPE_SUBTITLE];
        }
    }
    
    if (errCode != RTMPDecoderErrorNone) {
        
        [self closeFile];
        
        return NO;
    }
    
    return YES;
}

- (RTMPDecoderError)openFile:(NSString *)path {
    
    AVFormatContext *formatContext = NULL;
    
    if (_interruptionCallback) {
        formatContext = avformat_alloc_context();
        if (!formatContext) {
            return RTMPDecoderErrorOpenFile;
        }
        AVIOInterruptCB cb = {interrupt_callback, (__bridge void *)(self)};
        formatContext->interrupt_callback = cb;
    }
    
    if (avformat_open_input(&formatContext, [path cStringUsingEncoding:NSUTF8StringEncoding], NULL, NULL) != 0) {
        // 路径打开失败
        if (formatContext) {
            avformat_free_context(formatContext);
        }
        return RTMPDecoderErrorOpenFile;
    }
    
    if (avformat_find_stream_info(formatContext, NULL) < 0) {
        // 路径不可读
        avformat_close_input(&formatContext);
        return RTMPDecoderErrorStreamInfoNotFound;
    }
    
    // 读取成功
    av_dump_format(formatContext, 0, [path.lastPathComponent cStringUsingEncoding:NSUTF8StringEncoding], false);
    
    self.context = formatContext;
    return RTMPDecoderErrorNone;
}

#pragma mark - 打开视频流
- (RTMPDecoderError)openVideoStream {
    
    RTMPDecoderError error = RTMPDecoderErrorStreamNotFound;
    
    // 重置视频流信息
    _videoStream = -1;
    _artworkStream = -1;
    
    _arrVideoStreams = [self collectStreamsWithContext:_context andCType:AVMEDIA_TYPE_VIDEO];
    
    for (NSNumber *num in _arrVideoStreams) {
        
        const NSUInteger stream = [num integerValue];
        
        if (0 == (_context->streams[stream]->disposition & AV_DISPOSITION_ATTACHED_PIC)) {
            error = [self openVideoStreamWithStream:stream];
            
            // stream正确读取
            if (error == RTMPDecoderErrorNone) {
                break;
            }
        } else {
            _artworkStream = stream;
        }
    }
    
    return error;
}

- (RTMPDecoderError)openVideoStreamWithStream:(NSInteger)videoStream {
    
    AVCodecParameters *videoCodecParam = _context->streams[videoStream]->codecpar;
    
    // 获取解码器
    AVCodec *videoCodec = avcodec_find_decoder(videoCodecParam->codec_id);
    
    _videoCodecContext = avcodec_alloc_context3(videoCodec);
    avcodec_parameters_to_context(_videoCodecContext, videoCodecParam);
    
    if (!videoCodecParam) {
        return RTMPDecoderErrorCodecNotFound;
    }
    
    if (avcodec_open2(_videoCodecContext, videoCodec, NULL) < 0) {
        return RTMPDecoderErrorOpenCodec;
    }
    
    // 声明视频用AVFrame
    _videoFrame = av_frame_alloc();
    if (!_videoFrame) {
        avcodec_free_context(&_videoCodecContext);
        return RTMPDecoderErrorAllocateFrame;
    }
    
    _videoStream = videoStream;
    _videoCodecParam = videoCodecParam;
    
    // TODO: 设置FPS
//    AVStream *stream = _context->streams[_videoStream];
    
    return RTMPDecoderErrorNone;
}

#pragma mark - 打开音频流
- (RTMPDecoderError)openAudioStream {
    
    RTMPDecoderError error = RTMPDecoderErrorStreamNotFound;
    
    _audioStream = -1;
    _arrAudioStreams = [self collectStreamsWithContext:_context andCType:AVMEDIA_TYPE_AUDIO];
    
    for (NSNumber *num in _arrAudioStreams) {
        
        error = [self openAudioStreamWithStream:num.integerValue];
        if (error == RTMPDecoderErrorNone) {
            break;
        }
    }
    return error;
}

- (RTMPDecoderError)openAudioStreamWithStream:(NSInteger)audioStream {
    
    AVCodecParameters *audioCodecParam = _context->streams[audioStream]->codecpar;
    SwrContext *swrContext = NULL;

    // 获取解码器
    AVCodec *audioCodec = avcodec_find_decoder(audioCodecParam->codec_id);

    _audioCodecContext = avcodec_alloc_context3(audioCodec);
    avcodec_parameters_to_context(_audioCodecContext, audioCodecParam);

    if (!audioCodecParam) {
        return RTMPDecoderErrorCodecNotFound;
    }

    if (avcodec_open2(_audioCodecContext, audioCodec, NULL) < 0) {
        return RTMPDecoderErrorOpenCodec;
    }
    
    if (![self checkIfAudioCodecIsSupported:_audioCodecContext]) {
        
        swrContext = swr_alloc_set_opts(NULL,
                                        av_get_default_channel_layout(audioManager.numOutputChannels),
                                        AV_SAMPLE_FMT_S16,
                                        audioManager.samplingRate,
                                        av_get_default_channel_layout(_audioCodecContext->channels),
                                        _audioCodecContext->sample_fmt,
                                        _audioCodecContext->sample_rate,
                                        0,
                                        NULL);
        
        if (!swrContext || swr_init(swrContext)) {
            
            if (swrContext)
                swr_free(&swrContext);
            avcodec_close(_audioCodecContext);
            
            return RTMPDecoderErrorReSampler;
        }
    }
    
    _audioFrame = av_frame_alloc();
    
    if (!_audioFrame) {
        if (swrContext)
            swr_free(&swrContext);
        avcodec_close(_audioCodecContext);
        return RTMPDecoderErrorAllocateFrame;
    }
    
    _audioStream = audioStream;
    _audioCodecParam = audioCodecParam;
    _swrContext = swrContext;
    
//    AVStream *st = _context->streams[_audioStream];
//    avStreamFPSTimeBase(st, 0.025, 0, &_audioTimeBase);
    
    return RTMPDecoderErrorNone;
}

- (RTMPDecoderError)openSubtitleStream:(NSInteger)subtitleStream {
    
    AVCodecParameters *subtitleCodecParam = _context->streams[subtitleStream]->codecpar;
    
    AVCodec *subtitleCodec = avcodec_find_decoder(subtitleCodecParam->codec_id);
    if(!subtitleCodec)
        return RTMPDecoderErrorCodecNotFound;
    
    const AVCodecDescriptor *codecDesc = avcodec_descriptor_get(subtitleCodecParam->codec_id);
    if (codecDesc && (codecDesc->props & AV_CODEC_PROP_BITMAP_SUB)) {
        // Only text based subtitles supported
        return RTMPDecoderErrorUnsupported;
    }
    
    _subtitleCodecContext = avcodec_alloc_context3(subtitleCodec);
    avcodec_parameters_to_context(_subtitleCodecContext, subtitleCodecParam);
    
    if (avcodec_open2(_subtitleCodecContext, subtitleCodec, NULL) < 0)
        return RTMPDecoderErrorOpenCodec;
    
    _subtitleStream = subtitleStream;
    _subtitleCodecParam = subtitleCodecParam;
    
    return RTMPDecoderErrorNone;
}

- (BOOL)setupScaler {
    
    [self closeScaler];
    
    _frame = av_frame_alloc();
    _frame->format = AV_PIX_FMT_RGB24;
    _frame->width = _videoCodecParam->width;
    _frame->height = _videoCodecParam->height;
    
//    AVCodec *videoCodec = avcodec_find_decoder(_videoCodecParam->codec_id);
    
    _swsContext = sws_getCachedContext(_swsContext,
                                       _videoCodecParam->width,
                                       _videoCodecParam->height,
                                       _videoCodecContext->pix_fmt,
                                       _videoCodecParam->width,
                                       _videoCodecParam->height,
                                       AV_PIX_FMT_RGB24,
                                       SWS_FAST_BILINEAR,
                                       NULL, NULL, NULL);
    
//    avcodec_free_context(&_videoCodecContext);
    
    return _swsContext != NULL;
    
}

#pragma mark - close File
- (void)closeFile {
    
    [self closeVideoStream];
    [self closeAudioStream];
    [self closeSubtitleStream];
    
    _arrVideoStreams = nil;
    _arrAudioStreams = nil;
    _arrSubtitleStreams = nil;
    
    if (_context) {
        
        _context->interrupt_callback.opaque = NULL;
        _context->interrupt_callback.callback = NULL;
        
        avformat_close_input(&_context);
        _context = NULL;
    }
}

#pragma mark - 关闭视频流、音频流、字幕
- (void)closeVideoStream {
    
    _videoStream = -1;
    
    [self closeScaler];
    
    if (_videoFrame) {
        
        av_free(_videoFrame);
        _videoFrame = NULL;
    }
    
    if (_videoCodecParam) {
        
        avcodec_parameters_free(&_videoCodecParam);
        _videoCodecParam = NULL;
    }
}

- (void)closeAudioStream {
    
    _audioStream = -1;
    
    if (_swrBuffer) {
        
        free(_swrBuffer);
        _swrBuffer = NULL;
        _swrBufferSize = 0;
    }
    
    if (_swrContext) {
        
        swr_free(&_swrContext);
        _swrContext = NULL;
    }
    
    if (_audioFrame) {
        
        av_free(_audioFrame);
        _audioFrame = NULL;
    }
    
    if (_audioCodecParam) {
        
        avcodec_parameters_free(&_audioCodecParam);
        _audioCodecParam = NULL;
    }
}

- (void)closeScaler {
    
    if (_swsContext) {
        sws_freeContext(_swsContext);
        _swsContext = NULL;
    }
    
    if (_pictureValid) {
        av_frame_free(&_frame);
        _pictureValid = NO;
    }
}

- (void)closeSubtitleStream {
    
    _subtitleStream = -1;
    
    if (_subtitleCodecContext) {
        
        avcodec_close(_subtitleCodecContext);
        _subtitleCodecContext = NULL;
    }
}

#pragma mark - decode frames
- (NSArray *)decodeFramesWithMinDuration:(CGFloat)minDuration {
    
    // 无视频流及音频流
    if (_videoStream == -1 && _audioStream == -1) {
        return nil;
    }
    
    NSMutableArray *arrFrames = [NSMutableArray array];
    
    // 待解压缩的数据
    AVPacket packet;
    
    BOOL finished = NO;
    CGFloat decodeDuration = 0.f;
    
    while (!finished) {
        
        if (av_read_frame(_context, &packet) < 0) {
            _isEOF = YES;
            break;
        }
        
        if (packet.stream_index == _videoStream) {              // Video
            
            int packetSize = packet.size;
            
            while (packetSize > 0) {
                
                int length = avcodec_send_packet(_videoCodecContext, &packet);
                BOOL gotFrame = avcodec_receive_frame(_videoCodecContext, _videoFrame);
                
                // 解析失败，跳过该packet
                if (length != 0) {
                    break;
                }
                
                if (gotFrame == 0) {
                    
                    if (!self.isDisableDeinterlacing && _videoFrame->interlaced_frame) {
                        ;
                    }
                    
                    RTMPVideoFrame *videoFrame = [self parseVideoFrame];
                    
                    if (videoFrame) {
                        [arrFrames addObject:videoFrame];
                        
                        _position = videoFrame.position;
                        decodeDuration += videoFrame.duration;
                        if (decodeDuration > minDuration) {
                            finished = YES;
                        }
                    }
                    
                    if (0 == length) {
                        break;
                    }
                    
                    packetSize -= length;
                }
            }
        } else if (packet.stream_index == _audioStream) {           // Audio
            
            int packetSize = packet.size;
            
            while (packetSize > 0) {
                
                int length = avcodec_send_packet(_audioCodecContext, &packet);
                int gotFrame = avcodec_receive_frame(_audioCodecContext, _audioFrame);
                
                if (length != 0) {
                    break;
                }
                
                if (gotFrame == 0) {
                    RTMPAudioFrame *audioFrame = [self parseAudioFrame];
                    
                    if (audioFrame) {
                        [arrFrames addObject:audioFrame];
                        
                        // 若没有视频流，即音频数据源
                        if (_videoStream == -1) {
                            _position = audioFrame.position;
                            decodeDuration +=audioFrame.duration;
                            if (decodeDuration > minDuration) {
                                finished = YES;
                            }
                        }
                    }
                }
                
                if (0 == length) {
                    break;
                }
                
                packetSize -= length;
            }
        } else if (packet.stream_index == _artworkStream) {         // Artwork
            
            if (packet.size) {
                RTMPArtworkFrame *frame = [[RTMPArtworkFrame alloc] init];
                frame.picture = [NSData dataWithBytes:packet.data length:packet.size];
                [arrFrames addObject:frame];
            }
        } else if (packet.stream_index == _subtitleStream) {
            
            int packetSize = packet.size;
            
            while (packetSize > 0) {
                
                AVSubtitle subtitle;
                int gotSubtitle = 0;
                
                int length = avcodec_decode_subtitle2(_subtitleCodecContext,
                                                      &subtitle,
                                                      &gotSubtitle,
                                                      &packet);
                
                if (length < 0) {
                    break;
                }
                
                if (gotSubtitle) {
                    RTMPSubtitleFrame *frame = [self parseSubtitleFrame:&subtitle];
                    
                    if (frame) {
                        [arrFrames addObject:frame];
                    }
                    avsubtitle_free(&subtitle);
                }
                
                if (0 == length) {
                    break;
                }
                packetSize -= packet.size;
            }
        }
        
        av_packet_unref(&packet);
    }
    
    return arrFrames;
}

- (RTMPVideoFrame *)parseVideoFrame {
    
    if (!_videoFrame->data[0]) {
        return nil;
    }
    
    RTMPVideoFrame *frame;
    
    if (self.enumVideoFrameFormat == EnumRTMPVideoFrameTypeYUV) {
        
        RTMPVideoFrameYUV *yuvFrame = [[RTMPVideoFrameYUV alloc] init];
        
        yuvFrame.luma = [self copyFrameDataWithSrc:_videoFrame->data[0]
                                          lineSize:_videoFrame->linesize[0]
                                        frameWidth:_videoCodecParam->width
                                       frameHeight:_videoCodecParam->height];
        yuvFrame.chromaB = [self copyFrameDataWithSrc:_videoFrame->data[1]
                                             lineSize:_videoFrame->linesize[1]
                                           frameWidth:_videoCodecParam->width/2
                                          frameHeight:_videoCodecParam->height/2];
        yuvFrame.chromaR = [self copyFrameDataWithSrc:_videoFrame->data[2]
                                             lineSize:_videoFrame->linesize[2]
                                           frameWidth:_videoCodecParam->width/2
                                          frameHeight:_videoCodecParam->height/2];
        
        frame = yuvFrame;
        
    } else if (self.enumVideoFrameFormat == EnumRTMPVideoFrameTypeRGB) {
        
        if (!_swsContext && ![self setupScaler]) {
            return nil;
        }
        
        sws_scale(_swsContext,
                  (const uint8_t **)_videoFrame->data,
                  _videoFrame->linesize,
                  0,
                  _videoCodecParam->height,
                  _frame->data,
                  _frame->linesize);
        
        RTMPVideoFrameRGB *rgbFrame = [[RTMPVideoFrameRGB alloc] init];
        rgbFrame.lineSize = _frame->linesize[0];
        rgbFrame.rgb = [NSData dataWithBytes:_frame->data[0]
                                      length:rgbFrame.lineSize * _videoCodecParam->height];
        
        frame = rgbFrame;
    }
    
    frame.width = _videoCodecParam->width;
    frame.height = _videoCodecParam->height;
    frame.position = av_frame_get_best_effort_timestamp(_videoFrame) * _videoTimeBase;
    
    const int64_t frameDuration = av_frame_get_pkt_duration(_videoFrame);
    if (frameDuration) {
        frame.duration = frameDuration * _videoTimeBase;
        frame.duration += _videoFrame->repeat_pict * _videoTimeBase * 0.5f;
    } else {
        frame.duration = 1.0f/_fps;
    }
    
    return frame;
}

- (RTMPAudioFrame *)parseAudioFrame {
    
    if (!_audioFrame->data[0]) {
        return nil;
    }
    
    const NSUInteger numChannels = audioManager.numOutputChannels;
    NSInteger numFrames;
    
    void *audioData;
    
    if (_swrContext) {
        
        const int ratio = MAX(1, audioManager.samplingRate/_audioCodecParam->sample_rate) *
                                 MAX(1, audioManager.numOutputChannels/_audioCodecParam->channels) * 2;
        const int bufferSize = av_samples_get_buffer_size(NULL,
                                                          audioManager.numOutputChannels,
                                                          _audioFrame->nb_samples * ratio,
                                                          AV_SAMPLE_FMT_S16,
                                                          1);
        if (_swrBuffer || _swrBufferSize < bufferSize) {
            _swrBufferSize = bufferSize;
            _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
        }
        
        Byte *outBuff[2] = {_swrBuffer, 0};
        
        numFrames = swr_convert(_swrContext,
                                outBuff,
                                _audioFrame->nb_samples * ratio,
                                (const uint8_t **)_audioFrame->data,
                                _audioFrame->nb_samples);
        
        if (numFrames < 0) {
            NSLog(@"fail resample audio");
            return nil;
        }
        
        audioData = _swrBuffer;
    } else {
        if (_audioCodecParam->sample_rate != AV_SAMPLE_FMT_S16) {
            NSLog(@"wrong sample rate");
        }
        
        audioData = _audioFrame->data[0];
        numFrames = _audioFrame->nb_samples;
    }
    
    const NSUInteger numElements = numFrames * numChannels;
    NSMutableData *data = [NSMutableData dataWithLength:numElements * sizeof(float)];
    
    float scale = 1.0/(float)INT16_MAX;
    vDSP_vflt16((SInt16 *)audioData, 1, data.mutableBytes, 1, numElements);
    vDSP_vsmul(data.mutableBytes, 1, &scale, data.mutableBytes, 1, numElements);
    
    RTMPAudioFrame *frame = [[RTMPAudioFrame alloc] init];
    frame.position = av_frame_get_best_effort_timestamp(_audioFrame) * _audioTimeBase;
    frame.duration = av_frame_get_pkt_duration(_audioFrame) * _audioTimeBase;
    frame.sample = data;
    
    if (frame.duration == 0) {
        frame.duration = frame.sample.length / (sizeof(float) * numChannels * audioManager.samplingRate);
    }
    
    return frame;
}

- (RTMPSubtitleFrame *)parseSubtitleFrame:(AVSubtitle *)subtitle {
    NSMutableString *strSubTitle = [NSMutableString string];
    
    for (NSInteger index = 0; index < subtitle->num_rects; index++) {
        AVSubtitleRect *rect = subtitle->rects[index];
        
        if (rect) {
         
            if (rect->text) {
                NSString *strText = [NSString stringWithUTF8String:rect->text];
                
                if (strText.length) {
                    [strSubTitle appendString:strText];
                }
            } else if (rect->ass && _subtitleASSEvents != -1) {
                NSString *strText = [NSString stringWithUTF8String:rect->ass];
                
                if (strText.length) {
                    
                    NSArray *fields = [RTMPSubtitleASSParser parseDialogue:strText
                                                                 numFields:_subtitleASSEvents];
                    if (fields.count && [fields.lastObject length]) {
                        
                        strText = [RTMPSubtitleASSParser removeCommandsFromEventText:fields.lastObject];
                        if (strText.length) {
                            [strSubTitle appendString:strText];
                        }
                    }
                }
            }
        }
    }
    
    if (!strSubTitle.length) {
        return nil;
    }
    
    RTMPSubtitleFrame *frame = [[RTMPSubtitleFrame alloc] init];
    frame.text = [strSubTitle copy];
    frame.position = subtitle->pts / AV_TIME_BASE + subtitle->start_display_time;
    frame.duration = (CGFloat)(subtitle->end_display_time - subtitle->start_display_time) / 1000.f;
    
    return frame;
}

#pragma mark - TOOLS
- (BOOL)checkIfIsWebURL:(NSString *)path {
    
    NSRange range = [path rangeOfString:@":"];
    
    if (range.location == NSNotFound) {
        return NO;
    }
    
    NSString *scheme = [path substringToIndex:range.length];
    
    if ([scheme isEqualToString:@"file"]) {
        return NO;
    }
    
    return YES;
}

- (BOOL)interruptDecoder {
    if (_interruptionCallback)
        return _interruptionCallback();
    return NO;
}

- (BOOL)checkIfAudioCodecIsSupported:(AVCodecContext *)audioCodecContext {
    
    if (audioCodecContext->sample_fmt == AV_SAMPLE_FMT_S16) {
        return YES;
    } else {
        return NO;
    }
}

//- (void)avStreamFPSTimeBaseWithStream:(AVStream *)st
//                      defaultTimeBase:(CGFloat)defaultTimeBase
//                                  fps:(CGFloat *)pFPS
//                             timeBase:(CGFloat *)pTimeBase {
//    CGFloat fps, timebase;
//    
//    if (st->time_base.den && st->time_base.num)
//        timebase = av_q2d(st->time_base);
//    else if(st->time_base.den && st->time_base.num)
//        timebase = av_q2d(st->time_base);
//    else
//        timebase = defaultTimeBase;
//    
//    if (st->codec->ticks_per_frame != 1) {
//        timebase *= st->codec->ticks_per_frame;
//    }
//    
//    if (st->avg_frame_rate.den && st->avg_frame_rate.num)
//        fps = av_q2d(st->avg_frame_rate);
//    else if (st->r_frame_rate.den && st->r_frame_rate.num)
//        fps = av_q2d(st->r_frame_rate);
//    else
//        fps = 1.0 / timebase;
//    
//    if (pFPS)
//        *pFPS = fps;
//    if (pTimeBase)
//        *pTimeBase = timebase;
//}

#pragma mark - streaming
- (NSArray *)collectStreamsWithContext:(AVFormatContext *)formatContext andCType:(enum AVMediaType)codecType {
    NSMutableArray *arr = [NSMutableArray array];
    for (NSInteger i = 0; i < formatContext->nb_streams; ++i)
        if (codecType == formatContext->streams[i]->codecpar->codec_type)
            [arr addObject: [NSNumber numberWithInteger: i]];
    return [arr copy];
}

#pragma mark - tools
- (NSData *)copyFrameDataWithSrc:(UInt8 *)src lineSize:(int)lineSize frameWidth:(int)width frameHeight:(int)height {
    
    width = MIN(lineSize, width);
    
    NSMutableData *data = [NSMutableData dataWithLength:width * height];
    Byte *dest = data.mutableBytes;
    
    for (NSUInteger i = 0; i < height; i++) {
        memcpy(dest, src, width);
        dest += width;
        src += lineSize;
    }
    return data;
}

#pragma mark - getter
- (NSUInteger)frameWidth {
    return _videoCodecContext ? _videoCodecContext->width : 0;
}

- (NSUInteger)frameHeight {
    return _videoCodecContext ? _videoCodecContext->height : 0;
}

- (CGFloat)duration {
    if (!_context)
        return 0;
    if (_context->duration == AV_NOPTS_VALUE)
        return MAXFLOAT;
    return (CGFloat)_context->duration / AV_TIME_BASE;
}

- (void)setPosition:(CGFloat)seconds {
    _position = seconds;
    _isEOF = NO;
    
    if (_videoStream != -1) {
        int64_t ts = (int64_t)(seconds / _videoTimeBase);
        avformat_seek_file(_context, (int)_videoStream, ts, ts, ts, AVSEEK_FLAG_FRAME);
        avcodec_flush_buffers(_videoCodecContext);
    }
    
    if (_audioStream != -1) {
        int64_t ts = (int64_t)(seconds / _audioTimeBase);
        avformat_seek_file(_context, (int)_audioStream, ts, ts, ts, AVSEEK_FLAG_FRAME);
        avcodec_flush_buffers(_audioCodecContext);
    }
}

//- (CGFloat)position
//{
//    return _position;
//}

- (CGFloat)sampleRate
{
    return _audioCodecContext ? _audioCodecContext->sample_rate : 0;
}

- (NSUInteger)audioStreamsCount
{
    return [_arrAudioStreams count];
}

- (NSUInteger)subtitleStreamsCount
{
    return [_arrSubtitleStreams count];
}

- (NSInteger)selectedAudioStream
{
    if (_audioStream == -1)
        return -1;
    NSNumber *n = [NSNumber numberWithInteger:_audioStream];
    return [_arrAudioStreams indexOfObject:n];
}

- (void)setSelectedAudioStream:(NSInteger)selectedAudioStream
{
    NSInteger audioStream = [_arrAudioStreams[selectedAudioStream] integerValue];
    [self closeAudioStream];
    RTMPDecoderError errCode = [self openAudioStreamWithStream:audioStream];
    if (RTMPDecoderErrorNone == errCode) {
        NSLog(@"error code : %ld", (long)errCode);
    }
}

- (NSInteger)selectedSubtitleStream
{
    if (_subtitleStream == -1)
        return -1;
    return [_arrSubtitleStreams indexOfObject:@(_subtitleStream)];
}

- (void)setSelectedSubtitleStream:(NSInteger)selected
{
    [self closeSubtitleStream];
    
    if (selected == -1) {
        
        _subtitleStream = -1;
        
    } else {
        
        NSInteger subtitleStream = [_arrSubtitleStreams[selected] integerValue];
        RTMPDecoderError errCode = [self openSubtitleStream:subtitleStream];
        if (RTMPDecoderErrorNone == errCode) {
            NSLog(@"error code : %ld", (long)errCode);
        }
    }
}

- (BOOL)validAudio
{
    return _audioStream != -1;
}

- (BOOL)validVideo
{
    return _videoStream != -1;
}

- (BOOL)validSubtitles
{
    return _subtitleStream != -1;
}

- (NSDictionary *)info
{
    if (!_info) {
        
        NSMutableDictionary *md = [NSMutableDictionary dictionary];
        
        if (_context) {
            
            const char *formatName = _context->iformat->name;
            [md setValue: [NSString stringWithCString:formatName encoding:NSUTF8StringEncoding]
                  forKey: @"format"];
            
            if (_context->bit_rate) {
                
                [md setValue: [NSNumber numberWithInteger:_context->bit_rate]
                      forKey: @"bitrate"];
            }
            
            if (_context->metadata) {
                
                NSMutableDictionary *md1 = [NSMutableDictionary dictionary];
                
                AVDictionaryEntry *tag = NULL;
                while((tag = av_dict_get(_context->metadata, "", tag, AV_DICT_IGNORE_SUFFIX))) {
                    
                    [md1 setValue: [NSString stringWithCString:tag->value encoding:NSUTF8StringEncoding]
                           forKey: [NSString stringWithCString:tag->key encoding:NSUTF8StringEncoding]];
                }
                
                [md setValue: [md1 copy] forKey: @"metadata"];
            }
            
            char buf[256];
            
            if (_arrVideoStreams.count) {
                NSMutableArray *ma = [NSMutableArray array];
                for (NSNumber *n in _arrVideoStreams) {
                    AVStream *st = _context->streams[n.integerValue];
                    avcodec_string(buf, sizeof(buf), st->codec, 1);
                    NSString *s = [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
                    if ([s hasPrefix:@"Video: "])
                        s = [s substringFromIndex:@"Video: ".length];
                    [ma addObject:s];
                }
                md[@"video"] = ma.copy;
            }
            
            if (_arrAudioStreams.count) {
                NSMutableArray *ma = [NSMutableArray array];
                for (NSNumber *n in _arrAudioStreams) {
                    AVStream *st = _context->streams[n.integerValue];
                    
                    NSMutableString *ms = [NSMutableString string];
                    AVDictionaryEntry *lang = av_dict_get(st->metadata, "language", NULL, 0);
                    if (lang && lang->value) {
                        [ms appendFormat:@"%s ", lang->value];
                    }
                    
                    avcodec_string(buf, sizeof(buf), st->codec, 1);
                    NSString *s = [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
                    if ([s hasPrefix:@"Audio: "])
                        s = [s substringFromIndex:@"Audio: ".length];
                    [ms appendString:s];
                    
                    [ma addObject:ms.copy];
                }
                md[@"audio"] = ma.copy;
            }
            
            if (_arrSubtitleStreams.count) {
                NSMutableArray *ma = [NSMutableArray array];
                for (NSNumber *n in _arrSubtitleStreams) {
                    AVStream *st = _context->streams[n.integerValue];
                    
                    NSMutableString *ms = [NSMutableString string];
                    AVDictionaryEntry *lang = av_dict_get(st->metadata, "language", NULL, 0);
                    if (lang && lang->value) {
                        [ms appendFormat:@"%s ", lang->value];
                    }
                    
                    avcodec_string(buf, sizeof(buf), st->codec, 1);
                    NSString *s = [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
                    if ([s hasPrefix:@"Subtitle: "])
                        s = [s substringFromIndex:@"Subtitle: ".length];
                    [ms appendString:s];
                    
                    [ma addObject:ms.copy];
                }
                md[@"subtitles"] = ma.copy;
            }
            
        }
        
        _info = [md copy];
    }
    
    return _info;
}

- (NSString *)videoStreamFormatName
{
    if (!_videoCodecContext)
        return nil;
    
    if (_videoCodecContext->pix_fmt == AV_PIX_FMT_NONE)
        return @"";
    
    const char *name = av_get_pix_fmt_name(_videoCodecContext->pix_fmt);
    return name ? [NSString stringWithCString:name encoding:NSUTF8StringEncoding] : @"?";
}

- (CGFloat)startTime
{
    if (_videoStream != -1) {
        
        AVStream *st = _context->streams[_videoStream];
        if (AV_NOPTS_VALUE != st->start_time)
            return st->start_time * _videoTimeBase;
        return 0;
    }
    
    if (_audioStream != -1) {
        
        AVStream *st = _context->streams[_audioStream];
        if (AV_NOPTS_VALUE != st->start_time)
            return st->start_time * _audioTimeBase;
        return 0;
    }
    
    return 0;
}


@end

static int interrupt_callback(void *ctx) {
    if (!ctx)
        return 0;
    __unsafe_unretained RTMPDecoder *pointer = (__bridge RTMPDecoder *)ctx;
    
    const BOOL r = [pointer interruptDecoder];
    if (r) {
        return r;
    } else {
        return 0;
    }
}

static void FFLog(void* context, int level, const char* format, va_list args) {
    @autoreleasepool {
        //Trim time at the beginning and new line at the end
        NSString* message = [[NSString alloc] initWithFormat: [NSString stringWithUTF8String: format] arguments: args];
        NSLog(@"%@", [message stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
    }
}

