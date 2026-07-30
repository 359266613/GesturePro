// GesturePro — 完全复刻 SquidGesturePro 架构
// TouchThroughWindow + UIGestureRecognizer + manual touch fallback

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "AxsPrivate.h"
#import "AxsConfig.h"
#import "AxsActionExecutor.h"

// =============================================================================
#pragma mark - AxsTouchThroughWindow（核心：触摸穿透窗口）
// =============================================================================

@interface AxsTouchThroughWindow : UIWindow
@property (nonatomic, weak) id gestureTarget;
@end

@implementation AxsTouchThroughWindow

// 关键：让不命中手势识别器的触摸穿透到底层窗口
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // 只有当触摸点命中手势识别器所在的 view（即 self 上添加了 GR）时才返回
    // 否则返回 nil 让触摸穿透
    if (hit == self) {
        // 检查是否有手势识别器可能响应
        for (UIGestureRecognizer *gr in self.gestureRecognizers) {
            if (gr.enabled) {
                return self; // 有启用的手势识别器，保留触摸
            }
        }
        return nil; // 无手势识别器，穿透
    }
    return hit;
}

@end

// =============================================================================
#pragma mark - 手势处理器
// =============================================================================

@interface AxsGestureHandler : NSObject <UIGestureRecognizerDelegate>

@property (nonatomic, strong) AxsTouchThroughWindow *gestureWindow;
@property (nonatomic, strong) UITapGestureRecognizer *singleTapGR;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGR;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGR;
@property (nonatomic, strong) UISwipeGestureRecognizer *swipeLeftGR;
@property (nonatomic, strong) UISwipeGestureRecognizer *swipeRightGR;

@property (nonatomic, assign) NSInteger currentTouchRegion;
@property (nonatomic, assign) BOOL isSetup;
@property (nonatomic, assign) int notifyToken;

+ (instancetype)shared;
- (void)install;
- (void)uninstall;
- (void)updateFrame;

@end

@implementation AxsGestureHandler

+ (instancetype)shared {
    static AxsGestureHandler *h = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [[AxsGestureHandler alloc] init]; });
    return h;
}

// =============================================================================
#pragma mark - 安装手势窗口
// =============================================================================

- (void)install {
    if (![AxsConfig sharedConfig].isEnabled) return;
    if (self.isSetup && self.gestureWindow) {
        [self updateFrame];
        return;
    }

    @try {
        // 1. 获取状态栏 frame（从任意 keyWindow）
        UIWindow *refWindow = nil;
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *w in windows) {
            if (w.isKeyWindow) { refWindow = w; break; }
        }
        if (!refWindow) {
            // 没有 keyWindow，延迟重试
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                [[AxsGestureHandler shared] install];
            });
            return;
        }

        CGRect sbFrame = [self statusBarFrameFromWindow:refWindow];
        if (CGRectIsEmpty(sbFrame) || sbFrame.size.height <= 0) {
            sbFrame = CGRectMake(0, 0, refWindow.bounds.size.width, kAxsStateBarHeight);
        }
        sbFrame.origin.x = 0;
        sbFrame.origin.y = 0;
        sbFrame.size.width = refWindow.bounds.size.width;

        // 2. 创建 TouchThroughWindow
        self.gestureWindow = [[AxsTouchThroughWindow alloc] initWithFrame:sbFrame];
        self.gestureWindow.windowLevel = UIWindowLevelStatusBar + 1;
        self.gestureWindow.backgroundColor = [UIColor clearColor];
        self.gestureWindow.userInteractionEnabled = YES;
        self.gestureWindow.hidden = NO;
        self.gestureWindow.gestureTarget = self;

        if (@available(iOS 13.0, *)) {
            self.gestureWindow.windowScene = refWindow.windowScene;
        }

        // 3. 添加手势识别器
        [self setupGestureRecognizers];

        // 4. 注册通知
        [self registerNotify];

        self.isSetup = YES;

        NSLog(@"[GesturePro] Window installed: frame=%@ level=%.0f",
              NSStringFromCGRect(sbFrame), self.gestureWindow.windowLevel);

    } @catch (NSException *e) {
        NSLog(@"[GesturePro] install error: %@", e);
    }
}

- (void)uninstall {
    if (self.gestureWindow) {
        self.gestureWindow.hidden = YES;
        self.gestureWindow = nil;
    }
    self.isSetup = NO;
    if (self.notifyToken != 0) {
        notify_cancel(self.notifyToken);
        self.notifyToken = 0;
    }
}

- (void)updateFrame {
    if (!self.gestureWindow) return;
    UIWindow *refWindow = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { refWindow = w; break; }
    }
    if (!refWindow) return;
    CGRect f = [self statusBarFrameFromWindow:refWindow];
    if (CGRectIsEmpty(f) || f.size.height <= 0) {
        f = CGRectMake(0, 0, refWindow.bounds.size.width, kAxsStateBarHeight);
    }
    f.origin = CGPointZero;
    f.size.width = refWindow.bounds.size.width;
    self.gestureWindow.frame = f;
}

// =============================================================================
#pragma mark - 手势识别器（完全复刻 SquidGesturePro）
// =============================================================================

- (void)setupGestureRecognizers {
    // 单击
    self.singleTapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    self.singleTapGR.numberOfTapsRequired = 1;
    self.singleTapGR.delegate = self;
    [self.gestureWindow addGestureRecognizer:self.singleTapGR];

    // 双击
    self.doubleTapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    self.doubleTapGR.numberOfTapsRequired = 2;
    self.doubleTapGR.delegate = self;
    [self.gestureWindow addGestureRecognizer:self.doubleTapGR];

    // 单击等待双击确认（关键！）
    [self.singleTapGR requireGestureRecognizerToFail:self.doubleTapGR];

    // 长按
    self.longPressGR = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    self.longPressGR.minimumPressDuration = kAxsLongPressMinDuration;
    self.longPressGR.delegate = self;
    [self.gestureWindow addGestureRecognizer:self.longPressGR];

    // 左滑
    self.swipeLeftGR = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeLeft:)];
    self.swipeLeftGR.direction = UISwipeGestureRecognizerDirectionLeft;
    self.swipeLeftGR.delegate = self;
    [self.gestureWindow addGestureRecognizer:self.swipeLeftGR];

    // 右滑
    self.swipeRightGR = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeRight:)];
    self.swipeRightGR.direction = UISwipeGestureRecognizerDirectionRight;
    self.swipeRightGR.delegate = self;
    [self.gestureWindow addGestureRecognizer:self.swipeRightGR];
}

// =============================================================================
#pragma mark - UIGestureRecognizerDelegate
// =============================================================================

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    CGPoint pt = [touch locationInView:nil];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat ratio = pt.x / sw;
    if (ratio < kAxsRegionLeftRatio)       self.currentTouchRegion = AxsStatusBarRegionLeft;
    else if (ratio > kAxsRegionRightRatio) self.currentTouchRegion = AxsStatusBarRegionRight;
    else                                   self.currentTouchRegion = AxsStatusBarRegionIsland;

    // 检查该区域手势是否启用
    return [AxsConfig sharedConfig].isEnabled;
}

// =============================================================================
#pragma mark - 手势回调 → 执行动作
// =============================================================================

- (void)handleSingleTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    NSLog(@"[GesturePro] SingleTap region=%ld", (long)self.currentTouchRegion);
    [AxsActionExecutor executeActionForRegion:self.currentTouchRegion gesture:AxsGestureTypeTap];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    NSLog(@"[GesturePro] DoubleTap region=%ld", (long)self.currentTouchRegion);
    [AxsActionExecutor executeActionForRegion:self.currentTouchRegion gesture:AxsGestureTypeDoubleTap];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    NSLog(@"[GesturePro] LongPress region=%ld", (long)self.currentTouchRegion);
    [AxsActionExecutor executeActionForRegion:self.currentTouchRegion gesture:AxsGestureTypeLongPress];
}

- (void)handleSwipeLeft:(UISwipeGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    NSLog(@"[GesturePro] SwipeLeft region=%ld", (long)self.currentTouchRegion);
    [AxsActionExecutor executeActionForRegion:self.currentTouchRegion gesture:AxsGestureTypeSwipeLeft];
}

- (void)handleSwipeRight:(UISwipeGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    NSLog(@"[GesturePro] SwipeRight region=%ld", (long)self.currentTouchRegion);
    [AxsActionExecutor executeActionForRegion:self.currentTouchRegion gesture:AxsGestureTypeSwipeRight];
}

// =============================================================================
#pragma mark - 通知监听
// =============================================================================

- (void)registerNotify {
    __weak typeof(self) weakSelf = self;
    self.notifyToken = 0;
    notify_register_dispatch("com.axs.gesturepro.prefs-changed", &_notifyToken,
        dispatch_get_main_queue(), ^(int t) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if ([AxsConfig sharedConfig].isEnabled) {
                if (!self.gestureWindow) {
                    [self install];
                }
            } else {
                [self uninstall];
            }
        });
}

// =============================================================================
#pragma mark - Helper
// =============================================================================

- (CGRect)statusBarFrameFromWindow:(UIWindow *)window {
    // 方式1: UIWindow statusBarFrame
    if ([window respondsToSelector:@selector(statusBarFrame)]) {
        NSValue *v = [window valueForKey:@"statusBarFrame"];
        if (v) return [v CGRectValue];
    }
    // 方式2: UIWindowScene.statusBarManager
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = window.windowScene;
        if (scene) {
            id mgr = [scene valueForKey:@"statusBarManager"];
            if (mgr) {
                NSValue *v = [mgr valueForKey:@"statusBarFrame"];
                if (v) return [v CGRectValue];
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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[AxsGestureHandler shared] install];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *n) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [[AxsGestureHandler shared] install];
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
