//
//  HYChatMessage.h
//  HYChatProject
//
//  Created by erpapa on 16/4/28.
//  Copyright © 2016年 erpapa. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, HYChatMessageType) {
    HYChatMessageTypeText,  // 文字text
    HYChatMessageTypeImage, // 图片image
    HYChatMessageTypeVoice, // 声音voice
    HYChatMessageTypeVideo // 视频video
};
@class YYTextLayout;
@interface HYChatMessage : NSObject
@property (nonatomic, assign) HYChatMessageType type; // 消息类型
@property (nonatomic, copy) NSString *body; // 内容，可以是文字内容，也可以是url
@property (nonatomic, strong) YYTextLayout *textLayout; // 布局信息
@property (nonatomic, assign) float width; // 高度
@property (nonatomic, assign) float height; // 宽度
@property (nonatomic, assign) float size; // 文件大小
@property (nonatomic, assign) float duraction; // 音频时间

@property (nonatomic, strong) XMPPJID *jid;        // jid
@property (nonatomic, assign) BOOL isOutgoing;     // 发出
@property (nonatomic, assign) BOOL isComposing;    //
@property (nonatomic, assign) BOOL isHidenTime;    // 隐藏时间
@property (nonatomic, copy) NSString *timeString;  // 时间

- (instancetype)initWithJsonString:(NSString *)jsonString;
- (NSString *)jsonString; // 将模型转jsonString
@end
