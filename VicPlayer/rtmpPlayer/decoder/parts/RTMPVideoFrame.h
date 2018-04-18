//
//  RTMPVideoFrame.h
//  VicPlayer
//
//  Created by Vic on 30/09/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "RTMPCommonFrame.h"

typedef NS_ENUM(NSInteger, EnumRTMPVideoFrameType) {
    EnumRTMPVideoFrameTypeRGB = 0,
    EnumRTMPVideoFrameTypeYUV,
};

@interface RTMPVideoFrame : RTMPCommonFrame

@property (nonatomic, assign) EnumRTMPVideoFrameType enumVideoFrameType;
@property (nonatomic, assign) NSUInteger width;
@property (nonatomic, assign) NSUInteger height;

@end

@interface RTMPVideoFrameYUV : RTMPVideoFrame

@property (nonatomic, strong) NSData *luma;
@property (nonatomic, strong) NSData *chromaB;
@property (nonatomic, strong) NSData *chromaR;

@end

@interface RTMPVideoFrameRGB : RTMPVideoFrame

@property (nonatomic) NSUInteger lineSize;
@property (nonatomic, strong) NSData *rgb;

- (UIImage *)asImage;

@end
