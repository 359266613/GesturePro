// GesturePro — 完全复刻 SquidGesturePro 架构
// TouchThroughWindow + UIGestureRecognizer + CFNotificationCenter

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>
#import "AxsPrivate.h"
#import "AxsConfig.h"
#import "AxsActionExecutor.h"

// =============================================================================
#pragma mark - 文件日志
// =============================================================================

#define AXS_LOG_PATH @"/var/mobile/Documents/gesturepro.log"

static void _AxsLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString *ts = [df stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:AXS_LOG_PATH]) {
        [line writeToFile:AXS_LOG_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:AXS_LOG_PATH];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    }
}

// =============================================================================
#pragma mark - AxsTouchThroughWindow
// =============================================================================

@interface AxsTouchThroughWindow : UIWindow
@end

@implementation AxsTouchThroughWindow

// 不重写 hitTest — 交给 UIGestureRecognizer 的 delegate 来控制穿透
// 当 shouldReceiveTouch: 对所有 GR 返回 NO 时，系统不会消费触摸，触摸自然穿透

@end

// =============================================================================
#pragma mark - 配置变更回调
// =============================================================================

static void PrefsChangedCallback(CFNotificationCenterRef center,
                                  void *observer,
                                  CFStringRef name,
                                  const void *object,
                                  CFDictionaryRef userInfo) {
    // 用 debounce 防止重复回调
    static NSTimeInterval lastCallTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastCallTime < 0.3) return; // 300ms 防抖
    lastCallTime = now;

    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = NSClassFromString(@"AxsGestureHandler");
        if (cls) {
            id handler = [cls performSelector:@selector(shared)];
            BOOL enabled = [AxsConfig sharedConfig].isEnabled;
            if (enabled) {
                [handler performSelector:@selector(install)];
            } else {
                [handler performSelector:@selector(uninstall)];
            }
        }
    });
}

// =============================================================================
#pragma mark - AxsGestureHandler
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

+ (instancetype)shared;
- (void)install;
- (void)uninstall;

@end

@implementation AxsGestureHandler

+ (instancetype)shared {
    static AxsGestureHandler *h = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [[AxsGestureHandler alloc] init]; });
    return h;
}

// =============================================================================
#pragma mark - 安装
// =============================================================================

- (void)install {
    BOOL enabled = [AxsConfig sharedConfig].isEnabled;
    if (!enabled) {
        [self uninstall];
        return;
    }

    if (self.isSetup && self.gestureWindow) {
        [self updateFrame];
        return;
    }

    @try {
        NSArray *windows = [UIApplication sharedApplication].windows;
        _AxsLog(@"install: %lu windows", (unsigned long)windows.count);

        // 找 SpringBoard 的真实 keyWindow（跳过 floatingView 等其他 tweak 的窗口）
        UIWindow *refWindow = nil;
        for (UIWindow *w in windows) {
            NSString *cn = NSStringFromClass([w class]);
            // 优先用 SBWindow / SBRootSceneWindow
            if ([cn isEqualToString:@"SBRootSceneWindow"] ||
                [cn isEqualToString:@"SBWindow"] ||
                [cn isEqualToString:@"SBHomeScreenWindow"]) {
                if (w.isKeyWindow) { refWindow = w; break; }
            }
        }
        // 兜底：任何 keyWindow
        if (!refWindow) {
            for (UIWindow *w in windows) {
                if (w.isKeyWindow) { refWindow = w; break; }
            }
        }

        if (!refWindow) {
            _AxsLog(@"No refWindow, retry in 1s");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{ [self install]; });
            return;
        }

        _AxsLog(@"refWindow: %@ level=%.0f", NSStringFromClass([refWindow class]), refWindow.windowLevel);

        // 获取状态栏 frame
        CGRect sbFrame = [self statusBarFrameFromWindow:refWindow];
        if (CGRectIsEmpty(sbFrame) || sbFrame.size.height <= 0) {
            sbFrame = CGRectMake(0, 0, refWindow.bounds.size.width, kAxsStateBarHeight);
        }
        sbFrame.origin = CGPointZero;
        sbFrame.size.width = refWindow.bounds.size.width;

        _AxsLog(@"statusBarFrame: %@", NSStringFromCGRect(sbFrame));

        // 创建窗口
        self.gestureWindow = [[AxsTouchThroughWindow alloc] initWithFrame:sbFrame];
        self.gestureWindow.windowLevel = UIWindowLevelStatusBar + 1;
        self.gestureWindow.backgroundColor = [UIColor clearColor];
        self.gestureWindow.userInteractionEnabled = YES;
        self.gestureWindow.hidden = NO;

        if (@available(iOS 13.0, *)) {
            self.gestureWindow.windowScene = refWindow.windowScene;
        }

        [self setupGestureRecognizers];
        [self registerConfigObserver];

        self.isSetup = YES;

        _AxsLog(@"Install COMPLETE. Config: L.Tap=%@ R.Tap=%@ R.SwipeR=%@ urlLink=%@",
                [[AxsConfig sharedConfig] actionLeftTap],
                [[AxsConfig sharedConfig] actionRightTap],
                [[AxsConfig sharedConfig] actionRightSwipeRight],
                [AxsConfig sharedConfig].urlLink);

    } @catch (NSException *e) {
        _AxsLog(@"EXCEPTION: %@", e);
    }
}

- (void)uninstall {
    if (self.gestureWindow) {
        self.gestureWindow.hidden = YES;
        self.gestureWindow = nil;
    }
    self.isSetup = NO;
}

- (void)updateFrame {
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
#pragma mark - 手势识别器
// =============================================================================

- (void)setupGestureRecognizers {
    self.singleTapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    self.singleTapGR.numberOfTapsRequired = 1;
    self.singleTapGR.delegate = self;
    [self.gestureWindow addGestureRecognizer:self.singleTapGR];

    self.doubleTapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    self.doubleTapGR.numberOfTapsRequired = 2;
    self.doubleTapGR.delegate = self;
    [self.gestureWindow addGestureRecognizer:self.doubleTapGR];

    [self.singleTapGR requireGestureRecognizerToFail:self.doubleTapGR];

    self.longPressGR = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    self.longPressGR.minimumPressDuration = kAxsLongPressMinDuration;
    self.longPressGR.delegate = self;
    [self.gestureWindow addGestureRecognizer:self.longPressGR];

    self.swipeLeftGR = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeLeft:)];
    self.swipeLeftGR.direction = UISwipeGestureRecognizerDirectionLeft;
    self.swipeLeftGR.delegate = self;
    [self.gestureWindow addGestureRecognizer:self.swipeLeftGR];

    self.swipeRightGR = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeRight:)];
    self.swipeRightGR.direction = UISwipeGestureRecognizerDirectionRight;
    self.swipeRightGR.delegate = self;
    [self.gestureWindow addGestureRecognizer:self.swipeRightGR];
}

// =============================================================================
#pragma mark - UIGestureRecognizerDelegate（核心：控制手势穿透）
// =============================================================================

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    CGPoint pt = [touch locationInView:nil];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat ratio = pt.x / sw;

    // 区域判定
    if (ratio < kAxsRegionLeftRatio)
        self.currentTouchRegion = AxsStatusBarRegionLeft;
    else if (ratio > kAxsRegionRightRatio)
        self.currentTouchRegion = AxsStatusBarRegionRight;
    else
        self.currentTouchRegion = AxsStatusBarRegionIsland;

    // 根据手势类型，检查该区域是否配置了有效动作
    NSInteger gestureType = [self gestureTypeForRecognizer:gr];
    NSString *action = [[AxsConfig sharedConfig] actionForRegion:self.currentTouchRegion gesture:gestureType];

    BOOL hasAction = action && ![action isEqualToString:kAxsActionNone];
    if (!hasAction) {
        // 该区域此手势未配置动作 → 拒绝接收触摸，让触摸穿透到 SpringBoard
        return NO;
    }

    _AxsLog(@"GR accept: type=%ld region=%ld action=%@", (long)gestureType, (long)self.currentTouchRegion, action);
    return YES;
}

- (NSInteger)gestureTypeForRecognizer:(UIGestureRecognizer *)gr {
    if (gr == self.doubleTapGR)     return AxsGestureTypeDoubleTap;
    if (gr == self.longPressGR)     return AxsGestureTypeLongPress;
    if (gr == self.swipeLeftGR)     return AxsGestureTypeSwipeLeft;
    if (gr == self.swipeRightGR)    return AxsGestureTypeSwipeRight;
    return AxsGestureTypeTap;       // singleTapGR
}

// =============================================================================
#pragma mark - 手势回调
// =============================================================================

- (void)handleSingleTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    NSString *a = [[AxsConfig sharedConfig] actionForRegion:self.currentTouchRegion gesture:AxsGestureTypeTap];
    _AxsLog(@">>> SingleTap region=%ld action=%@", (long)self.currentTouchRegion, a);
    [AxsActionExecutor executeActionForRegion:self.currentTouchRegion gesture:AxsGestureTypeTap];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    NSString *a = [[AxsConfig sharedConfig] actionForRegion:self.currentTouchRegion gesture:AxsGestureTypeDoubleTap];
    _AxsLog(@">>> DoubleTap region=%ld action=%@", (long)self.currentTouchRegion, a);
    [AxsActionExecutor executeActionForRegion:self.currentTouchRegion gesture:AxsGestureTypeDoubleTap];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    NSString *a = [[AxsConfig sharedConfig] actionForRegion:self.currentTouchRegion gesture:AxsGestureTypeLongPress];
    _AxsLog(@">>> LongPress region=%ld action=%@", (long)self.currentTouchRegion, a);
    [AxsActionExecutor executeActionForRegion:self.currentTouchRegion gesture:AxsGestureTypeLongPress];
}

- (void)handleSwipeLeft:(UISwipeGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    NSString *a = [[AxsConfig sharedConfig] actionForRegion:self.currentTouchRegion gesture:AxsGestureTypeSwipeLeft];
    _AxsLog(@">>> SwipeLeft region=%ld action=%@", (long)self.currentTouchRegion, a);
    [AxsActionExecutor executeActionForRegion:self.currentTouchRegion gesture:AxsGestureTypeSwipeLeft];
}

- (void)handleSwipeRight:(UISwipeGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    NSString *a = [[AxsConfig sharedConfig] actionForRegion:self.currentTouchRegion gesture:AxsGestureTypeSwipeRight];
    _AxsLog(@">>> SwipeRight region=%ld action=%@", (long)self.currentTouchRegion, a);
    [AxsActionExecutor executeActionForRegion:self.currentTouchRegion gesture:AxsGestureTypeSwipeRight];
}

// =============================================================================
#pragma mark - CFNotificationCenter 监听
// =============================================================================

- (void)registerConfigObserver {
    static BOOL registered = NO;
    if (registered) return;
    registered = YES;

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        PrefsChangedCallback,
        CFSTR("com.axs.gesturepro.prefs-changed"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

// =============================================================================
#pragma mark - Helper
// =============================================================================

- (CGRect)statusBarFrameFromWindow:(UIWindow *)window {
    if ([window respondsToSelector:@selector(statusBarFrame)]) {
        NSValue *v = [window valueForKey:@"statusBarFrame"];
        if (v) return [v CGRectValue];
    }
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
