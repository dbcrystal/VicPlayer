//
//  RTMPAudioFrame.h
//  VicPlayer
//
//  Created by Vic on 12/10/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import "RTMPCommonFrame.h"

@interface RTMPAudioFrame : RTMPCommonFrame

@property (nonatomic, strong) NSData *sample;

@end
