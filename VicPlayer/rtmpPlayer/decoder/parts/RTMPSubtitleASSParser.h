//
//  RTMPSubtitleASSParser.h
//  VicPlayer
//
//  Created by Vic on 12/10/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RTMPSubtitleASSParser : NSObject

+ (NSArray *)parseEvents:(NSString *)events;
+ (NSArray *)parseDialogue:(NSString *)dialogue
                  numFields:(NSUInteger)numFields;
+ (NSString *)removeCommandsFromEventText:(NSString *)text;

@end
