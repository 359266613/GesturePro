// GesturePro — 状态栏手势核心 Hook
// 完全复刻 SquidGesturePro 架构：SBFTouchPassThroughWindow + Std Gesture Recognizers

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import "AxsPrivate.h"
#import "AxsConfig.h"
#import "AxsActionExecutor.h"

// =============================================================================
#pragma mark - 手势代理（处理区域判定 + 动作执行）
// =============================================================================

@interface AxsGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, assign) NSInteger region; // 当前手势绑定的区域
@end

@implementation AxsGestureDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    // 根据触摸 X 坐标判定所属区域
    CGPoint point = [touch locationInView:nil]; // 屏幕坐标
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    self.region = [self regionForTouchX:point.x screenWidth:screenW];
    return YES;
}

- (NSInteger)regionForTouchX:(CGFloat)x screenWidth:(CGFloat)screenWidth {
    CGFloat ratio = x / screenWidth;
    if (ratio < kAxsRegionLeftRatio)  return AxsStatusBarRegionLeft;
    if (ratio > kAxsRegionRightRatio) return AxsStatusBarRegionRight;
    return AxsStatusBarRegionIsland;
}

@end

// =============================================================================
#pragma mark - 手势窗口管理器
// =============================================================================

@interface AxsGestureWindowManager : NSObject

@property (nonatomic, strong) UIWindow *gestureWindow;
@property (nonatomic, strong) AxsGestureDelegate *gestureDelegate;
@property (nonatomic, strong) UITapGestureRecognizer *singleTapGR;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGR;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGR;
@property (nonatomic, strong) UISwipeGestureRecognizer *swipeLeftGR;
@property (nonatomic, strong) UISwipeGestureRecognizer *swipeRightGR;
@property (nonatomic, assign) BOOL configObserverRegistered;

+ (instancetype)sharedManager;
- (void)setupGestureWindow;
- (void)teardownGestureWindow;
- (void)updateGestureWindowFrame;

@end

@implementation AxsGestureWindowManager

+ (instancetype)sharedManager {
    static AxsGestureWindowManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[AxsGestureWindowManager alloc] init];
    });
    return manager;
}

// =============================================================================
#pragma mark - 创建手势窗口（核心逻辑，完美复刻 SquidGesturePro）
// =============================================================================

- (void)setupGestureWindow {
    // 只在 SpringBoard 已启动且启用时创建
    if (![AxsConfig sharedConfig].isEnabled) return;
    if (self.gestureWindow) return; // 已存在

    @try {
        // 1. 查找 keyWindow 获取状态栏 frame
        UIWindow *keyWindow = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        if (!keyWindow) return;

        CGRect statusBarFrame;
        if ([keyWindow respondsToSelector:@selector(statusBarFrame)]) {
            statusBarFrame = [[keyWindow valueForKey:@"statusBarFrame"] CGRectValue];
        } else {
            // 兜底：尝试通过 windowScene 获取
            statusBarFrame = [self statusBarFrameFromScene:keyWindow];
        }

        if (CGRectIsEmpty(statusBarFrame)) {
            statusBarFrame = CGRectMake(0, 0, keyWindow.bounds.size.width, kAxsStateBarHeight);
        }

        // 2. 创建 TouchPassThroughWindow（触摸穿透窗口）
        //    SBFTouchPassThroughWindow 的 hitTest: 返回 nil，让底层视图正常接收触摸
        //    但其子视图（手势识别器）仍能接收触摸
        Class passThroughClass = NSClassFromString(@"SBFTouchPassThroughWindow");
        if (!passThroughClass) {
            passThroughClass = [UIWindow class];
        }

        self.gestureWindow = [[passThroughClass alloc] initWithFrame:statusBarFrame];
        self.gestureWindow.windowLevel = UIWindowLevelStatusBar + 1; // 浮在状态栏上方
        self.gestureWindow.backgroundColor = [UIColor clearColor];
        self.gestureWindow.userInteractionEnabled = YES;
        self.gestureWindow.hidden = NO;

        // iOS 13+ 需要设置 windowScene
        if (@available(iOS 13.0, *)) {
            self.gestureWindow.windowScene = keyWindow.windowScene;
        }

        [self.gestureWindow makeKeyAndVisible];
        // makeKeyAndVisible 会让它成为 keyWindow，需要恢复原 keyWindow
        [keyWindow makeKeyWindow];

        // 3. 添加手势识别器
        [self setupGestureRecognizers];

        // 4. 注册配置变更监听
        [self registerConfigObserver];

    } @catch (NSException *e) {
        self.gestureWindow = nil;
    }
}

- (void)teardownGestureWindow {
    if (self.gestureWindow) {
        self.gestureWindow.hidden = YES;
        self.gestureWindow = nil;
    }
    self.gestureDelegate = nil;
}

- (void)updateGestureWindowFrame {
    if (!self.gestureWindow) return;
    UIWindow *keyWindow = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { keyWindow = w; break; }
    }
    if (!keyWindow) return;

    CGRect frame;
    if ([keyWindow respondsToSelector:@selector(statusBarFrame)]) {
        frame = [[keyWindow valueForKey:@"statusBarFrame"] CGRectValue];
    } else {
        frame = CGRectMake(0, 0, keyWindow.bounds.size.width, kAxsStateBarHeight);
    }
    if (CGRectIsEmpty(frame)) {
        frame = CGRectMake(0, 0, keyWindow.bounds.size.width, kAxsStateBarHeight);
    }
    self.gestureWindow.frame = frame;
}

// =============================================================================
#pragma mark - 手势识别器（完全复刻 SquidGesturePro）
// =============================================================================

- (void)setupGestureRecognizers {
    self.gestureDelegate = [[AxsGestureDelegate alloc] init];

    // 单击
    self.singleTapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    self.singleTapGR.numberOfTapsRequired = 1;
    self.singleTapGR.delegate = self.gestureDelegate;
    [self.gestureWindow addGestureRecognizer:self.singleTapGR];

    // 双击
    self.doubleTapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    self.doubleTapGR.numberOfTapsRequired = 2;
    self.doubleTapGR.delegate = self.gestureDelegate;
    [self.gestureWindow addGestureRecognizer:self.doubleTapGR];

    // 单击等待双击失败后才触发（关键！）
    [self.singleTapGR requireGestureRecognizerToFail:self.doubleTapGR];

    // 长按
    self.longPressGR = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    self.longPressGR.minimumPressDuration = kAxsLongPressMinDuration;
    self.longPressGR.delegate = self.gestureDelegate;
    [self.gestureWindow addGestureRecognizer:self.longPressGR];

    // 左滑
    self.swipeLeftGR = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeLeft:)];
    self.swipeLeftGR.direction = UISwipeGestureRecognizerDirectionLeft;
    self.swipeLeftGR.delegate = self.gestureDelegate;
    [self.gestureWindow addGestureRecognizer:self.swipeLeftGR];

    // 右滑
    self.swipeRightGR = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeRight:)];
    self.swipeRightGR.direction = UISwipeGestureRecognizerDirectionRight;
    self.swipeRightGR.delegate = self.gestureDelegate;
    [self.gestureWindow addGestureRecognizer:self.swipeRightGR];
}

// =============================================================================
#pragma mark - 手势回调
// =============================================================================

- (void)handleSingleTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    [AxsActionExecutor executeActionForRegion:self.gestureDelegate.region gesture:AxsGestureTypeTap];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    [AxsActionExecutor executeActionForRegion:self.gestureDelegate.region gesture:AxsGestureTypeDoubleTap];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    [AxsActionExecutor executeActionForRegion:self.gestureDelegate.region gesture:AxsGestureTypeLongPress];
}

- (void)handleSwipeLeft:(UISwipeGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    [AxsActionExecutor executeActionForRegion:self.gestureDelegate.region gesture:AxsGestureTypeSwipeLeft];
}

- (void)handleSwipeRight:(UISwipeGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    [AxsActionExecutor executeActionForRegion:self.gestureDelegate.region gesture:AxsGestureTypeSwipeRight];
}

// =============================================================================
#pragma mark - 配置变更监听
// =============================================================================

- (void)registerConfigObserver {
    if (self.configObserverRegistered) return;
    self.configObserverRegistered = YES;

    // 使用 CFNotificationCenter Darwin 通知（跨进程可靠，与 SquidGesturePro 一致）
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        configChangedCallback,
        CFSTR("com.axs.gesturepro.prefs-changed"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

static void configChangedCallback(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AxsGestureWindowManager *mgr = [AxsGestureWindowManager sharedManager];
        if ([AxsConfig sharedConfig].isEnabled) {
            if (!mgr.gestureWindow) {
                [mgr setupGestureWindow];
            }
        } else {
            [mgr teardownGestureWindow];
        }
    });
}

// =============================================================================
#pragma mark - 辅助
// =============================================================================

- (CGRect)statusBarFrameFromScene:(UIWindow *)window {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = window.windowScene;
        if (scene && [scene respondsToSelector:@selector(statusBarManager)]) {
            id manager = [scene valueForKey:@"statusBarManager"];
            if (manager && [manager respondsToSelector:@selector(statusBarFrame)]) {
                NSValue *val = [manager valueForKey:@"statusBarFrame"];
                return [val CGRectValue];
            }
        }
    }
    return CGRectZero;
}

@end

// =============================================================================
#pragma mark - SpringBoard Hook
// =============================================================================

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;

    // 延迟创建手势窗口（确保 SpringBoard 完全初始化）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[AxsGestureWindowManager sharedManager] setupGestureWindow];

        // 前台/后台切换时重建
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    AxsGestureWindowManager *mgr = [AxsGestureWindowManager sharedManager];
                    if ([AxsConfig sharedConfig].isEnabled) {
                        if (!mgr.gestureWindow) {
                            [mgr setupGestureWindow];
                        } else {
                            [mgr updateGestureWindowFrame];
                        }
                    }
                });
            }];
    });
}

%end

// =============================================================================
#pragma mark - %ctor
// =============================================================================

%ctor {
    @autoreleasepool {
        [[AxsConfig sharedConfig] registerDefaults];
    }
}
