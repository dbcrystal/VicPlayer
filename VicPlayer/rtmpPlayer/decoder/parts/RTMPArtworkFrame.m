//
//  RTMPArtworkFrame.m
//  VicPlayer
//
//  Created by Vic on 12/10/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import "RTMPArtworkFrame.h"

@implementation RTMPArtworkFrame

- (EnumRTMPFrameType)type {
    return EnumRTMPFrameTypeArtwork;
}

- (UIImage *)asImage {
    UIImage *img;
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)(_picture));
    if (provider) {
        CGImageRef imgRef = CGImageCreateWithJPEGDataProvider(provider,
                                                              NULL,
                                                              YES,
                                                              kCGRenderingIntentDefault);
        
        if (imgRef) {
            img = [UIImage imageWithCGImage:imgRef];
            CGImageRelease(imgRef);
        }
        CGDataProviderRelease(provider);
    }
    
    return img;
}

@end
