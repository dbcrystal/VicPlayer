//
//  RTMPCommonFrame.h
//  VicPlayer
//
//  Created by Vic on 30/09/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, EnumRTMPFrameType) {
    EnumRTMPFrameTypeVideo = 0,
    EnumRTMPFrameTypeAudio,
    EnumRTMPFrameTypeArtwork,
    EnumRTMPFrameTypeSubtitle,
};

@interface RTMPCommonFrame : NSObject

@property (nonatomic, assign, readonly) EnumRTMPFrameType enumFrameType;

@property (nonatomic, assign) CGFloat position;
@property (nonatomic, assign) CGFloat duration;

@end
