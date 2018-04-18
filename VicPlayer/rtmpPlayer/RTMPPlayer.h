//
//  RTMPPlayer.h
//  VicPlayer
//
//  Created by Vic on 26/10/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import <UIKit/UIKit.h>

UIKIT_EXTERN NSString * const KxMovieParameterMinBufferedDuration;
UIKIT_EXTERN NSString * const KxMovieParameterMaxBufferedDuration;
UIKIT_EXTERN NSString * const KxMovieParameterDisableDeinterlacing;

@interface RTMPPlayer : UIView

- (id)initWithFrame:(CGRect)frame andParam:(NSDictionary *)param;

- (void)setupAddress:(NSString *)address;

- (void)startPlayback;
- (void)stopPlayback;

@end
