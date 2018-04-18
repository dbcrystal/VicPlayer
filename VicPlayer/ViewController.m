//
//  ViewController.m
//  VicPlayer
//
//  Created by Vic on 26/07/2017.
//  Copyright © 2017 cn.6. All rights reserved.
//

#import "ViewController.h"

//#import <AVFoundation/AVFoundation.h>

#import "RTMPPlayer.h"

@interface ViewController ()

//@property (nonatomic, strong) AVPlayer *player;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    
//    AVPlayerItem *playerItem = [[AVPlayerItem alloc]initWithURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"0" ofType:@"mp4"]]];
//
//    [self.player replaceCurrentItemWithPlayerItem:playerItem];
//    [self p_currentItemAddObserver];
    NSURL *resourceURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"0" ofType:@"mp4"]];
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    
    
    // increase buffering for .wmv, it solves problem with delaying audio frames
//    if ([path.pathExtension isEqualToString:@"wmv"])
//        parameters[KxMovieParameterMinBufferedDuration] = @(5.0);
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
        parameters[KxMovieParameterDisableDeinterlacing] = @(YES);
    
    RTMPPlayer *player = [[RTMPPlayer alloc] initWithFrame:self.view.bounds andParam:parameters];
    player.backgroundColor = [UIColor blackColor];
    [self.view addSubview:player];
    
    [player setupAddress:[resourceURL absoluteString]];
//    [player startPlayback];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

//- (AVPlayer *)player {
//    if (_player == nil) {
//        _player = [[AVPlayer alloc] init];
//        _player.volume = 1.0; // 默认最大音量
//    }
//    return _player;
//}
//
//- (void)p_currentItemAddObserver {
//
//    //监控状态属性，注意AVPlayer也有一个status属性，通过监控它的status也可以获得播放状态
//    [self.player.currentItem addObserver:self forKeyPath:@"status" options:(NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew) context:nil];
//
//    //监控缓冲加载情况属性
//    [self.player.currentItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew context:nil];
//
//    //监控播放完成通知
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackFinished:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
//}
//
//#pragma mark - KVO
//
//- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
//
////    AVPlayerItem *playerItem = object;
////    if ([keyPath isEqualToString:@"status"]) {
////        AVPlayerItemStatus status = [change[@"new"] integerValue];
////        switch (status) {
////            case AVPlayerItemStatusReadyToPlay:
////            {
////                [self.player play];
////            }
////                break;
////            case AVPlayerItemStatusFailed:
////            {
////                NSLog(@"加载失败");
////            }
////                break;
////            case AVPlayerItemStatusUnknown:
////            {
////                NSLog(@"未知资源");
////            }
////                break;
////            default:
////                break;
////        }
////    }
//}
//
//- (void)playbackFinished:(NSNotification *)notifi {
//    NSLog(@"播放完成");
//}

@end
