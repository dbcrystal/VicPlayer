//
//  RTMPVideoFrame.m
//  VicPlayer
//
//  Created by Vic on 30/09/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import "RTMPVideoFrame.h"

@implementation RTMPVideoFrame

- (EnumRTMPFrameType)enumFrameType {
    return EnumRTMPFrameTypeVideo;
}

@end

@implementation RTMPVideoFrameYUV

- (EnumRTMPVideoFrameType)enumVideoFrameType {
    return EnumRTMPVideoFrameTypeYUV;
}

@end 

@implementation RTMPVideoFrameRGB

- (EnumRTMPVideoFrameType)enumVideoFrameType {
    return EnumRTMPVideoFrameTypeRGB;
}

- (UIImage *)asImage {
    UIImage *img;
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)(_rgb));
    
    if (provider) {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        
        if (colorSpace) {
            CGImageRef imgRef = CGImageCreate(self.width,
                                              self.height,
                                              8,
                                              24,
                                              self.lineSize,
                                              colorSpace,
                                              kCGBitmapByteOrderDefault,
                                              provider,
                                              NULL,
                                              YES,
                                              kCGRenderingIntentDefault);
            
            if (imgRef) {
                img = [UIImage imageWithCGImage:imgRef];
                CGImageRelease(imgRef);
            }
            CGColorSpaceRelease(colorSpace);
        }
        CGDataProviderRelease(provider);
    }
    
    return img;
}

@end
