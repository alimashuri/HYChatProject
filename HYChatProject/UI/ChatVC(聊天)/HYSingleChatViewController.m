//
//  HYSingleChatViewController.m
//  HYChatProject
//
//  Created by erpapa on 16/3/20.
//  Copyright © 2016年 erpapa. All rights reserved.
//

#import "HYSingleChatViewController.h"
#import "HYInputViewController.h"
#import "HYChatMessageFrame.h"
#import "HYXMPPManager.h"
#import "HYDatabaseHandler+HY.h"
#import "YYImageCache.h"
#import "YYImageCoder.h"
#import "HYUtils.h"
#import "HYAudioPlayer.h"
#import "AFNetworking.h"
#import "HYNetworkManager.h"

#import "ODRefreshControl.h"
#import "HYVideoCaptureController.h"
#import "HYVideoPlayController.h"
#import "HYPhotoBrowserController.h"
#import "HYUservCardViewController.h"

#import "HYBaseChatViewCell.h"
#import "HYTextChatViewCell.h"
#import "HYImageChatViewCell.h"
#import "HYAudioChatViewCell.h"
#import "HYVideoChatViewCell.h"

static NSString *kTextChatViewCellIdentifier = @"kTextChatViewCellIdentifier";
static NSString *kImageChatViewCellIdentifier = @"kImageChatViewCellIdentifier";
static NSString *kAudioChatViewCellIdentifier = @"kAudioChatViewCellIdentifier";
static NSString *kVideoChatViewCellIdentifier = @"kVideoChatViewCellIdentifier";
@interface HYSingleChatViewController ()<UITableViewDataSource, UITableViewDelegate,NSFetchedResultsControllerDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate, HYInputViewControllerDelegate, HYBaseChatViewCellDelegate,HYVideoCaptureControllerDelegate,HYAudioPlayerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) HYInputViewController *inputVC;
@property (nonatomic, strong) NSFetchedResultsController *resultController;//查询结果集合
@property (nonatomic, strong) ODRefreshControl *refreshControl;

@property (nonatomic, strong) HYAudioPlayer *audioPlayer;
@property (nonatomic, strong) NSString *playingMessageID;// 当前播放的消息
@property (nonatomic, assign) BOOL isShowMultimedia;
@end

@implementation HYSingleChatViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor whiteColor];
    self.automaticallyAdjustsScrollViewInsets = NO;
    // 1.tableView
    [self.tableView registerClass:[HYTextChatViewCell class] forCellReuseIdentifier:kTextChatViewCellIdentifier];
    [self.tableView registerClass:[HYImageChatViewCell class] forCellReuseIdentifier:kImageChatViewCellIdentifier];
    [self.tableView registerClass:[HYAudioChatViewCell class] forCellReuseIdentifier:kAudioChatViewCellIdentifier];
    [self.tableView registerClass:[HYVideoChatViewCell class] forCellReuseIdentifier:kVideoChatViewCellIdentifier];
    
    [self.view addSubview:self.tableView];
    
    // 2.下拉刷新
    self.refreshControl = [[ODRefreshControl alloc] initInScrollView:self.tableView];
    self.refreshControl.tintColor = [UIColor colorWithRed:241/255.0 green:241/255.0 blue:241/255.0 alpha:1.0];
    [self.refreshControl addTarget:self action:@selector(loadMoreChatMessage) forControlEvents:UIControlEventValueChanged];
    
    // 3.聊天工具条
    self.inputVC = [[HYInputViewController alloc] init];
    self.inputVC.delegate = self;
    self.inputVC.view.frame = CGRectMake(0, CGRectGetHeight(self.view.bounds) - kInputBarHeight, CGRectGetWidth(self.view.bounds), kInputBarHeight);
    [self.view addSubview:self.inputVC.view];
    
    // 4.设置当前聊天对象
    [HYXMPPManager sharedInstance].chatJID = self.chatJid;
    
    // 5.获取聊天数据
     [self getChatHistory];
    
    // 6.监听网络状态改变
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        if (status == AFNetworkReachabilityStatusNotReachable) { // 网络不可用
            [HYUtils alertWithErrorMsg:@"网络不可用！"];
        }
    }];
    
    // 7.音频
    self.audioPlayer = [[HYAudioPlayer alloc] init];
    self.audioPlayer.delegate = self;
    
    // 8.注册通知
    [HYNotification addObserver:self selector:@selector(receiveSingleMessage:) name:HYChatDidReceiveSingleMessage object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.isShowMultimedia) {
        self.isShowMultimedia = NO;
        return;
    }
    // 自动滚动表格到最后一行
    if (self.dataSource.count) {
        NSIndexPath *lastPath = [NSIndexPath indexPathForRow:self.dataSource.count - 1 inSection:0];
        [self.tableView scrollToRowAtIndexPath:lastPath atScrollPosition:UITableViewScrollPositionNone animated:NO];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self settingKeyboard];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [self.audioPlayer stop];
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.dataSource.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    HYBaseChatViewCell *cell = nil;
    HYChatMessageFrame *messageFrame = [self.dataSource objectAtIndex:indexPath.row];
    HYChatMessage *message = messageFrame.chatMessage;
    switch (message.type) {
        case HYChatMessageTypeText:{
            cell = [tableView dequeueReusableCellWithIdentifier:kTextChatViewCellIdentifier];
            break;
        }
        case HYChatMessageTypeImage:{
            cell = [tableView dequeueReusableCellWithIdentifier:kImageChatViewCellIdentifier];
            break;
        }
        case HYChatMessageTypeAudio:{
            cell = [tableView dequeueReusableCellWithIdentifier:kAudioChatViewCellIdentifier];
            break;
        }
        case HYChatMessageTypeVideo:{
            cell = [tableView dequeueReusableCellWithIdentifier:kVideoChatViewCellIdentifier];
            break;
        }
        default:
            break;
    }
    cell.messageFrame = messageFrame;
    cell.delegate = self;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    HYChatMessageFrame *messageFrame = [self.dataSource objectAtIndex:indexPath.row];
    return messageFrame.cellHeight;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    UIMenuController *popMenu = [UIMenuController sharedMenuController];
    if (popMenu.isMenuVisible) {
        [popMenu setMenuVisible:NO animated:YES];
    }
    if (self.inputVC.isFirstResponder) {
        [self.inputVC resignFirstResponder]; // 输入框取消第一响应者
        [self settingKeyboard];
    }
    
}

#pragma mark - 获取聊天数据

- (void)getChatHistory
{
    NSMutableArray *chatMessages = [NSMutableArray array];
    [[HYDatabaseHandler sharedInstance] recentChatMessages:chatMessages fromChatJID:self.chatJid];
    // 处理数据
    [chatMessages enumerateObjectsUsingBlock:^(HYChatMessage *message, NSUInteger idx, BOOL * _Nonnull stop) {
        // 判断是否显示时间
        message.timeString = [HYUtils timeStringSince1970:message.time];
        HYChatMessageFrame *lastMessageFrame = [self.dataSource lastObject];
        message.isHidenTime = [lastMessageFrame.chatMessage.timeString isEqualToString:message.timeString];
        HYChatMessageFrame *messageFrame = [[HYChatMessageFrame alloc] init];
        messageFrame.chatMessage = message;
        [self.dataSource addObject:messageFrame];
        [self downlodMultimediaMessage:message]; // 下载
    }];
}

// 获取更多数据
- (void)loadMoreChatMessage
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSMutableArray *chatMessages = [NSMutableArray array];
        HYChatMessageFrame *firstMessageFrame = [self.dataSource firstObject];
        [[HYDatabaseHandler sharedInstance] moreChatMessages:chatMessages fromChatJID:self.chatJid beforeTime:firstMessageFrame.chatMessage.time];
        // 处理数据
        [self.refreshControl endRefreshing];
        if (chatMessages.count == 0) {
            return;
        }
        
        NSMutableArray *tempArray = [NSMutableArray array];
        [chatMessages enumerateObjectsUsingBlock:^(HYChatMessage *message, NSUInteger idx, BOOL * _Nonnull stop) {
            // 判断是否显示时间
            message.timeString = [HYUtils timeStringSince1970:message.time];
            HYChatMessageFrame *lastMessageFrame = [tempArray lastObject];
            message.isHidenTime = [lastMessageFrame.chatMessage.timeString isEqualToString:message.timeString];
            HYChatMessageFrame *messageFrame = [[HYChatMessageFrame alloc] init];
            messageFrame.chatMessage = message;
            [tempArray addObject:messageFrame];
            [self downlodMultimediaMessage:message]; // 下载
        }];
        [tempArray addObjectsFromArray:self.dataSource];
        self.dataSource = tempArray;
        [self.tableView reloadData];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:chatMessages.count - 1 inSection:0];
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionTop animated:NO];
    });
}

#pragma mark - 键盘inputViewControllerDelegate
// 发送照片/视频/文件
- (void)inputViewController:(HYInputViewController *)inputViewController clickExpandType:(HYExpandType)type
{
    self.isShowMultimedia = YES;
    switch (type) {
        case HYExpandTypePicture:{ // 照片
            UIImagePickerController *pickerController = [[UIImagePickerController alloc] init];
            pickerController.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            pickerController.delegate = self;
            [self presentViewController:pickerController animated:YES completion:nil];
            break;
        }
        case HYExpandTypeCamera:{ // 拍照
            UIImagePickerController *pickerController = [[UIImagePickerController alloc] init];
            pickerController.sourceType = UIImagePickerControllerSourceTypeCamera;
            pickerController.delegate = self;
            [self presentViewController:pickerController animated:YES completion:nil];
            break;
        }
        case HYExpandTypeVideo:{ // 视频
            HYVideoCaptureController *videoVapture = [[HYVideoCaptureController alloc] init];
            videoVapture.modalPresentationStyle = UIModalPresentationOverCurrentContext;// 半透明
            videoVapture.delegate = self;
            [self presentViewController:videoVapture animated:NO completion:nil];
            break;
        }
        case HYExpandTypeFolder:{ // 文件
            
            break;
        }
            
        default:
            break;
    }
}

#pragma mark UIImagePickerControllerDelegate

/**
 *  发送图片
 */
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{
    [picker dismissViewControllerAnimated:YES completion:^{
        
        //获取照片的原图
        UIImage *original = [info objectForKey:UIImagePickerControllerOriginalImage];
        //发送消息
        HYChatMessage *message = [[HYChatMessage alloc] init];
        NSString *imageName = [NSString stringWithFormat:@"%@.webP",message.messageID];
        message.imageUrl = QN_FullURL(imageName);
        [self sendSingleMessage:message withObject:original];
        BACK(^{
            CGFloat quality = 0.9;
            NSData *data = UIImageJPEGRepresentation(original, quality);
            if (data.length >= 768 * 1024) quality = 0.7;
            NSData *imageData = [YYImageEncoder encodeImage:original type:YYImageTypeWebP quality:quality];
            [[YYImageCache sharedCache] setImage:nil imageData:imageData forKey:QN_FullURL(imageName) withType:YYImageCacheTypeAll]; // 设置缓存，重要！！！！
            __weak typeof(self) weakSelf = self;
            [[HYNetworkManager sharedInstance] uploadImage:imageData imageName:imageName successBlock:^(BOOL success) {
                if(success){ // 上传照片成功
                    BOOL sendSuccess = [[HYXMPPManager sharedInstance] sendText:[message jsonString] toJid:weakSelf.chatJid];
                    if (sendSuccess) {
                        message.sendStatus = HYChatSendMessageStatusSuccess;
                    } else {
                        message.sendStatus = HYChatSendMessageStatusFaild;
                    }
                } else {
                    message.sendStatus = HYChatSendMessageStatusFaild;
                }
                [weakSelf refreshMessage:message];
            }];
        });
        
    }]; // dismiss
    
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - HYVideoCaptureControllerDelegate

// 上传视频
- (void)videoCaptureController:(HYVideoCaptureController *)videoCaptureController captureVideo:(NSString *)filePath screenShot:(UIImage *)screenShot
{
    //发送消息
    HYChatMessage *message = [[HYChatMessage alloc] init];
    
    NSString *imageName = [NSString stringWithFormat:@"%@.webP",message.messageID];
    NSString *videoName = [filePath lastPathComponent];
    HYVideoModel *videoModel = [[HYVideoModel alloc] init];
    videoModel.videoThumbImageUrl = QN_FullURL(imageName);
    videoModel.videoUrl = QN_FullURL(videoName);
    videoModel.videoSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil] fileSize]; // 视频大小
    NSData *imageData = [YYImageEncoder encodeImage:screenShot type:YYImageTypeWebP quality:0.9];
    [[YYImageCache sharedCache] setImage:nil imageData:imageData forKey:QN_FullURL(imageName) withType:YYImageCacheTypeAll]; // 设置缓存，重要！！！！
    [self sendSingleMessage:message withObject:videoModel];
    // 上传到七牛云
    
    __weak typeof(self) weakSelf = self;
    [[HYNetworkManager sharedInstance] uploadImage:imageData imageName:imageName successBlock:^(BOOL success) { // 上传封面
        if (success) {
            [[HYNetworkManager sharedInstance] uploadFilePath:filePath fileName:videoName successBlock:^(BOOL success) { // 上传视频
                if (success) {
                    BOOL sendSuccess = [[HYXMPPManager sharedInstance] sendText:[message jsonString] toJid:weakSelf.chatJid];
                    if (sendSuccess) {
                        message.sendStatus = HYChatSendMessageStatusSuccess;
                    } else {
                        message.sendStatus = HYChatSendMessageStatusFaild;
                    }
                } else {
                    message.sendStatus = HYChatSendMessageStatusFaild;
                }
                [self refreshMessage:message];
            }];
            
        } else {
            message.sendStatus = HYChatSendMessageStatusFaild;
            [self refreshMessage:message];
        }
    }];
}


// 发送文本/表情消息
- (void)inputViewController:(HYInputViewController *)inputViewController sendText:(NSString *)text
{
    //发送消息
    HYChatMessage *message = [[HYChatMessage alloc] init];
    message.type = HYChatMessageTypeText;
    message.textMessage = text;
    BOOL sendSuccess = [[HYXMPPManager sharedInstance] sendText:[message jsonString] toJid:self.chatJid];
    if (sendSuccess) {
        message.sendStatus = HYChatSendMessageStatusSuccess;
        [self sendSingleMessage:message withObject:text];
    } else {
        message.sendStatus = HYChatSendMessageStatusFaild;
        [self sendSingleMessage:message withObject:text];
    }
    
}

// 发送语音消息
- (void)inputViewController:(HYInputViewController *)inputViewController sendAudioModel:(HYAudioModel *)audioModel
{
    HYChatMessage *message = [[HYChatMessage alloc] init];
    [self sendSingleMessage:message withObject:audioModel];
    __weak typeof(self) weakSelf = self;
    [[HYNetworkManager sharedInstance] uploadFilePath:audioModel.tempEncodeFilePath fileName:[audioModel.tempEncodeFilePath lastPathComponent] successBlock:^(BOOL success) {
        if(success){ // 上传音频文件成功
            BOOL sendSuccess = [[HYXMPPManager sharedInstance] sendText:[message jsonString] toJid:weakSelf.chatJid];
            if (sendSuccess) {
                message.sendStatus = HYChatSendMessageStatusSuccess;
            } else {
                message.sendStatus = HYChatSendMessageStatusFaild;
            }
        } else {
            message.sendStatus = HYChatSendMessageStatusFaild;
        }
        [weakSelf refreshMessage:message];
    }];
}

// 调整高度
- (void)inputViewController:(HYInputViewController *)inputViewController newHeight:(CGFloat)height
{
    self.tableView.contentInset = UIEdgeInsetsMake(64, 0, height, 0);
    if (self.dataSource.count) {
        NSIndexPath *lastIndexPath = [NSIndexPath indexPathForRow:self.dataSource.count - 1 inSection:0];
        if ([[self.tableView indexPathsForVisibleRows] containsObject:lastIndexPath]) { // 最后一个row可见
            [self.tableView scrollToRowAtIndexPath:lastIndexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
        }
    }
}


#pragma mark - HYBaseChatViewCellDelegate
// 点击音频
- (void)chatViewCellClickAudio:(HYBaseChatViewCell *)chatViewCell
{
    NSIndexPath *indexPath = [self.tableView indexPathForCell:chatViewCell];
    HYChatMessageFrame *messageFrame = [self.dataSource objectAtIndex:indexPath.row];
    HYChatMessage *message = messageFrame.chatMessage;
    if ([self.playingMessageID isEqualToString:message.messageID]) { // 当前播放
        [self.audioPlayer stop];// 停止播放
        message.isRead = YES;
        message.isPlayingAudio = NO;
    } else {
        [self.audioPlayer stop];// 停止播放
        [self.audioPlayer playAudioFile:message.audioModel]; // 播放
        message.isRead = YES;
        message.isPlayingAudio = YES;
        self.playingMessageID = message.messageID;
    }
    [[HYDatabaseHandler sharedInstance] updateChatMessage:message];// 更新数据库操作
    [self.dataSource replaceObjectAtIndex:indexPath.row withObject:messageFrame];
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - HYAudioPlayerDelegate 停止播放

- (void)audioPlayer:(HYAudioPlayer *)audioPlay didFinishPlayAudio:(HYAudioModel *)audioFile
{
    NSInteger count = self.dataSource.count;
    for (NSInteger index = 0; index < count; index++) {
        HYChatMessageFrame *messageFrame = [self.dataSource objectAtIndex:index];
        HYChatMessage *message = messageFrame.chatMessage;
        if ([message.messageID isEqualToString:self.playingMessageID]) {
            message.isPlayingAudio = NO;
            self.playingMessageID = nil;
            MAIN(^{
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            });
            return;
        }
    }
}

// 点击头像
- (void)chatViewCell:(HYBaseChatViewCell *)chatViewCell didClickHeaderWithJid:(XMPPJID *)jid
{
    HYUservCardViewController *userVC = [[HYUservCardViewController alloc] init];
    userVC.userJid = jid;
    [self.navigationController pushViewController:userVC animated:YES];
}

// 点击图片
- (void)chatViewCellClickImage:(HYBaseChatViewCell *)chatViewCell
{
    NSMutableArray *photos = [NSMutableArray array];
    [self.dataSource enumerateObjectsUsingBlock:^(HYChatMessageFrame *messageFrame, NSUInteger idx, BOOL * _Nonnull stop) {
        HYChatMessage *message = messageFrame.chatMessage;
        if (message.imageUrl.length) {
            [photos addObject:message.imageUrl];
        }
    }];
    NSInteger currentImageIndex = photos.count - 1;;
    for (NSInteger index = 0; index < photos.count; index++) {
        NSString *imageUrl = [photos objectAtIndex:index];
        if ([imageUrl isEqualToString:chatViewCell.messageFrame.chatMessage.imageUrl]) {
            currentImageIndex = index;
            break;
        }
    }
    self.isShowMultimedia = YES;
    HYPhotoBrowserController *photoBrowser = [[HYPhotoBrowserController alloc] init];
    photoBrowser.currentImageIndex = currentImageIndex;
    photoBrowser.dataSource = photos;
    [self presentViewController:photoBrowser animated:YES completion:nil];
}

// 点击视频
- (void)chatViewCellClickVideo:(HYBaseChatViewCell *)chatViewCell
{
    self.isShowMultimedia = YES;
    HYChatMessageFrame *messsageFrame = chatViewCell.messageFrame;
    HYVideoModel *videoModel = messsageFrame.chatMessage.videoModel;
    HYVideoPlayController *playController = [[HYVideoPlayController alloc] initWithPath:videoModel.videoLocalPath];
    [self presentViewController:playController animated:YES completion:nil];
}

// 删除消息
- (void)chatViewCellDelete:(HYBaseChatViewCell *)chatViewCell
{
    NSIndexPath *indexPath = [self.tableView indexPathForCell:chatViewCell];
    [[HYDatabaseHandler sharedInstance] deleteChatMessage:chatViewCell.messageFrame.chatMessage];
    [self.dataSource removeObjectAtIndex:indexPath.row];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

// 转发
- (void)chatViewCellForward:(HYBaseChatViewCell *)chatViewCell
{
    
}

// 重发
- (void)chatViewCellReSend:(HYBaseChatViewCell *)chatViewCell
{
    HYChatMessageFrame *messsageFrame = chatViewCell.messageFrame;
    HYChatMessage *message = messsageFrame.chatMessage;
    switch (message.type) {
        case HYChatMessageTypeText:{ // 文本
            BOOL sendSuccess = [[HYXMPPManager sharedInstance] sendText:[message jsonString] toJid:self.chatJid];
            if (sendSuccess) {
                message.sendStatus = HYChatSendMessageStatusSuccess;
            } else {
                message.sendStatus = HYChatSendMessageStatusFaild;
            }
            [self refreshMessage:message];
            break;
        }
        case HYChatMessageTypeImage:{ // 图片
            NSString *imageName = [NSString stringWithFormat:@"%@.webP",message.messageID];
            NSData *imageData = [[YYImageCache sharedCache] getImageDataForKey:QN_FullURL(imageName)]; // 从缓存读取图片
            message.sendStatus = HYChatSendMessageStatusSending;
            [self refreshMessage:message]; // 刷新
            __weak typeof(self) weakSelf = self;
            [[HYNetworkManager sharedInstance] uploadImage:imageData imageName:imageName successBlock:^(BOOL success) {
                if(success){ // 上传照片成功
                    BOOL sendSuccess = [[HYXMPPManager sharedInstance] sendText:[message jsonString] toJid:weakSelf.chatJid];
                    if (sendSuccess) {
                        message.sendStatus = HYChatSendMessageStatusSuccess;
                    } else {
                        message.sendStatus = HYChatSendMessageStatusFaild;
                    }
                } else {
                    message.sendStatus = HYChatSendMessageStatusFaild;
                }
                [weakSelf refreshMessage:message];
            }];
            break;
        }
        case HYChatMessageTypeAudio:{ // 音频
            message.sendStatus = HYChatSendMessageStatusSending;
            [self refreshMessage:message]; // 刷新
            __weak typeof(self) weakSelf = self;
            [[HYNetworkManager sharedInstance] uploadFilePath:message.audioModel.tempEncodeFilePath fileName:[message.audioModel.tempEncodeFilePath lastPathComponent] successBlock:^(BOOL success) {
                if(success){ // 上传音频文件成功
                    BOOL sendSuccess = [[HYXMPPManager sharedInstance] sendText:[message jsonString] toJid:weakSelf.chatJid];
                    if (sendSuccess) {
                        message.sendStatus = HYChatSendMessageStatusSuccess;
                    } else {
                        message.sendStatus = HYChatSendMessageStatusFaild;
                    }
                } else {
                    message.sendStatus = HYChatSendMessageStatusFaild;
                }
                [weakSelf refreshMessage:message];
            }];
            break;
        }
        
        case HYChatMessageTypeVideo:{ // 视频
            NSString *imageName = [NSString stringWithFormat:@"%@.webP",message.messageID];
            NSData *imageData = [[YYImageCache sharedCache] getImageDataForKey:QN_FullURL(imageName)]; // 从缓存读取图片
            NSString *filePath = message.videoModel.videoLocalPath;
            NSString *videoName = [filePath lastPathComponent];
            message.sendStatus = HYChatSendMessageStatusSending;
            [self refreshMessage:message]; // 刷新
            // 上传到七牛云
            __weak typeof(self) weakSelf = self;
            [[HYNetworkManager sharedInstance] uploadImage:imageData imageName:imageName successBlock:^(BOOL success) { // 上传封面
                if (success) {
                    [[HYNetworkManager sharedInstance] uploadFilePath:filePath fileName:videoName successBlock:^(BOOL success) { // 上传视频
                        if (success) {
                            BOOL sendSuccess = [[HYXMPPManager sharedInstance] sendText:[message jsonString] toJid:weakSelf.chatJid];
                            if (sendSuccess) {
                                message.sendStatus = HYChatSendMessageStatusSuccess;
                            } else {
                                message.sendStatus = HYChatSendMessageStatusFaild;
                            }
                        } else {
                            message.sendStatus = HYChatSendMessageStatusFaild;
                        }
                        [self refreshMessage:message];
                    }];
                    
                } else {
                    message.sendStatus = HYChatSendMessageStatusFaild;
                    [self refreshMessage:message];
                }
            }];
            break;
        }
            
        default:
            break;
    }
}

/**
 *  控制keyboard显示
 */
- (void)settingKeyboard
{
    CGRect section = [self.tableView rectForSection:0];
    CGFloat h = CGRectGetHeight(self.view.bounds) - 64 - section.size.height;
    if (h > kPanelHeight) {
        self.inputVC.onlyMoveKeyboard = YES;// 数据太少就不整体向上移动
    } else {
        self.inputVC.onlyMoveKeyboard = NO;// 整体向上移动
    }
}

#pragma mark - 发送消息

- (void)sendSingleMessage:(HYChatMessage *)chatMessage withObject:(id)obj
{
    if ([obj isKindOfClass:[NSString class]]) {
        chatMessage.type = HYChatMessageTypeText;
        chatMessage.textMessage = obj;
    }else if ([obj isKindOfClass:[HYAudioModel class]]) { // 语音
        chatMessage.type = HYChatMessageTypeAudio;
        chatMessage.audioModel = obj;
        chatMessage.sendStatus = HYChatSendMessageStatusSending;
    } else if ([obj isKindOfClass:[UIImage class]]) { // 图片
        UIImage *image = (UIImage *)obj;
        chatMessage.type = HYChatMessageTypeImage;
        chatMessage.image = image;
        chatMessage.imageWidth = image.size.width;
        chatMessage.imageHeight = image.size.height;
        chatMessage.sendStatus = HYChatSendMessageStatusSending;
    } else if ([obj isKindOfClass:[HYVideoModel class]]) { // 视频
        chatMessage.type = HYChatMessageTypeVideo;
        chatMessage.videoModel = obj;
        chatMessage.sendStatus = HYChatSendMessageStatusSending;
    }
    chatMessage.jid = self.chatJid;
    chatMessage.time = [[NSDate date] timeIntervalSince1970];
    chatMessage.isRead = YES;
    chatMessage.isOutgoing = YES;
    chatMessage.isGroup = NO;
    // 判断是否显示时间
    chatMessage.timeString = [HYUtils timeStringSince1970:chatMessage.time];
    HYChatMessageFrame *lastMessageFrame = [self.dataSource lastObject];
    chatMessage.isHidenTime = [lastMessageFrame.chatMessage.timeString isEqualToString:chatMessage.timeString];
    HYChatMessageFrame *messageFrame = [[HYChatMessageFrame alloc] init];
    messageFrame.chatMessage = chatMessage;
    [self.dataSource addObject:messageFrame];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.dataSource.count - 1 inSection:0];
    MAIN(^{
        [[HYDatabaseHandler sharedInstance] addChatMessage:chatMessage]; // 储存
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
    });
    
}


#pragma mark - 接收消息通知

- (void)receiveSingleMessage:(NSNotification *)noti
{
    HYChatMessage *message = noti.object;
    if (![message.jid.bare isEqualToString:self.chatJid.bare]) {
        return;
    }
    // 判断是否显示时间
    message.timeString = [HYUtils timeStringSince1970:message.time];
    HYChatMessageFrame *lastMessageFrame = [self.dataSource lastObject];
    message.isHidenTime = [lastMessageFrame.chatMessage.timeString isEqualToString:message.timeString];
    HYChatMessageFrame *messageFrame = [[HYChatMessageFrame alloc] init];
    messageFrame.chatMessage = message;
    [self.dataSource addObject:messageFrame];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.dataSource.count - 1 inSection:0];
    MAIN(^{
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
    });
    [self downlodMultimediaMessage:message]; // 下载
}

/**
 *  下载音频、视频
 */

- (void)downlodMultimediaMessage:(HYChatMessage *)message
{
    __weak typeof(self) weakSelf = self;
    if (message.type == HYChatMessageTypeAudio) {// 下载audio
        [[HYNetworkManager sharedInstance] downloadAudioModel:message.audioModel successBlock:^(BOOL success) {
            if (success) {
                message.receiveStatus = HYChatReceiveMessageStatusSuccess;
            } else {
                message.receiveStatus = HYChatReceiveMessageStatusFaild;
            }
            [weakSelf refreshMessage:message];
        }];
    } else if (message.type == HYChatMessageTypeVideo) {// 下载视频
        [[HYNetworkManager sharedInstance] downloadVideoUrl:message.videoModel.videoUrl successBlock:^(BOOL success) {
            if (success) {
                message.receiveStatus = HYChatReceiveMessageStatusSuccess;
            } else {
                message.receiveStatus = HYChatReceiveMessageStatusFaild;
            }
            [weakSelf refreshMessage:message];
        }];
    }
}


#pragma mark - 更新消息

- (void)refreshMessage:(HYChatMessage *)message
{
    NSInteger count = self.dataSource.count;
    for (NSInteger index = 0; index < count; index++) {
        HYChatMessageFrame *messageFrame = [self.dataSource objectAtIndex:index];
        HYChatMessage *chatMessage = messageFrame.chatMessage;
        if ([chatMessage.messageID isEqualToString:message.messageID]) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            MAIN(^{
                [[HYDatabaseHandler sharedInstance] updateChatMessage:chatMessage];// 更新数据库
                if ([[self.tableView indexPathsForVisibleRows] containsObject:indexPath]) { // row可见才需要刷新
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                }
                
            });
            return;
        }
    }
}

#pragma mark - 懒加载
- (UITableView *)tableView
{
    if (_tableView == nil) {
        _tableView = [[UITableView alloc] initWithFrame:self.view.bounds];
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.showsHorizontalScrollIndicator = NO;
        _tableView.showsVerticalScrollIndicator = NO;
        _tableView.dataSource = self;
        _tableView.delegate = self;
    }
    return _tableView;
}

// 懒加载
- (NSMutableArray *)dataSource
{
    if (_dataSource == nil) {
        _dataSource = [NSMutableArray array];
    }
    return _dataSource;
}

- (void)dealloc
{
    self.dataSource = nil;
    self.inputVC = nil;
    [HYXMPPManager sharedInstance].chatJID = nil;
    [HYNotification removeObserver:self];
    HYLog(@"%@-dealloc",self);
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
 - (void)getChatHistory
 {
 // 1.上下文
 NSManagedObjectContext *context = [[HYXMPPManager sharedInstance] managedObjectContext_messageArchiving];
 if (context == nil) { // 防止xmppStream没有连接会崩溃
 return;
 }
 // 2.Fetch请求
 NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"XMPPMessageArchiving_Message_CoreDataObject"];
 // 3.过滤
 NSPredicate *predicate = [NSPredicate predicateWithFormat:@"bareJidStr == %@ AND streamBareJidStr == %@",self.chatJid.bare, [HYXMPPManager sharedInstance].myJID.bare];
 [fetchRequest setPredicate:predicate];
 // 4.排序(降序)
 NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:YES];
 [fetchRequest setSortDescriptors:@[sortDescriptor]];
 //    [fetchRequest setFetchLimit:20]; // 分页
 //    [fetchRequest setFetchOffset:0];
 
 // 5.执行查询获取数据
 _resultController = [[NSFetchedResultsController alloc]initWithFetchRequest:fetchRequest managedObjectContext:context sectionNameKeyPath:nil cacheName:nil];
 _resultController.delegate=self;
 // 6.执行
 NSError *error=nil;
 if(![_resultController performFetch:&error]){
 HYLog(@"%s---%@",__func__,error);
 } else {
 [self.dataSource removeAllObjects];
 [_resultController.fetchedObjects enumerateObjectsUsingBlock:^(XMPPMessageArchiving_Message_CoreDataObject *object, NSUInteger idx, BOOL * _Nonnull stop) {
 HYChatMessageFrame *messageFrame = [self chatmessageFrameFromObject:object];
 [self.dataSource addObject:messageFrame]; // 添加到数据源
 }];
 }
 }
 
 #pragma mark - NSFetchedResultsControllerDelegate
 // 数据更新
 - (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(nullable NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(nullable NSIndexPath *)newIndexPath
 {
 XMPPMessageArchiving_Message_CoreDataObject *object = anObject;
 if (object.body.length == 0) return; // 如果body为空，返回
 HYChatMessageFrame *messageFrame = [self chatmessageFrameFromObject:object];
 switch (type) {
 case NSFetchedResultsChangeInsert:{ // 插入
 [self.dataSource addObject:messageFrame];
 [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:self.dataSource.count - 1 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
 [self scrollToBottom];
 break;
 }
 case NSFetchedResultsChangeDelete:{ // 删除
 [self.dataSource removeObjectAtIndex:indexPath.row];
 [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
 break;
 }
 case NSFetchedResultsChangeMove:{ // 移动
 break;
 }
 case NSFetchedResultsChangeUpdate:{ // 更新
 [self.dataSource replaceObjectAtIndex:indexPath.row withObject:messageFrame];
 [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
 break;
 }
 default:
 break;
 }
 }
 
 #pragma mark - 转换模型
 
 - (HYChatMessageFrame *)chatmessageFrameFromObject:(XMPPMessageArchiving_Message_CoreDataObject *)object
 {
 HYChatMessage *message = [[HYChatMessage alloc] initWithJsonString:object.body];
 XMPPJID *jid = nil;
 if (object.isOutgoing) { // 发送
 jid = [HYXMPPManager sharedInstance].myJID;
 } else { // 接收
 jid = self.chatJid;
 }
 message.jid = jid;
 message.isOutgoing = object.isOutgoing;
 message.timeString = [HYUtils timeStringFromDate:object.timestamp];
 // 判断是否显示时间
 HYChatMessageFrame *lastMessageFrame = [self.dataSource lastObject];
 message.isHidenTime = [lastMessageFrame.chatMessage.timeString isEqualToString:message.timeString];
 // 计算message的Frame
 HYChatMessageFrame *messageFrame = [[HYChatMessageFrame alloc] init];
 messageFrame.chatMessage = message;
 return messageFrame;
 }
 */

@end
