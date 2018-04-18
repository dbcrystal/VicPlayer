//
//  RTMPGLView.h
//  VicPlayer
//
//  Created by Vic on 02/04/2018.
//  Copyright © 2018 cn.6. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RTMPVideoFrame;
@class RTMPDecoder;

@interface RTMPGLView : UIView

- (id)initWithFrame:(CGRect)frame decoder:(RTMPDecoder *)decoder;

- (void)render:(RTMPVideoFrame *)frame;

@end
