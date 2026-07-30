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

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) {
        for (UIGestureRecognizer *gr in self.gestureRecognizers) {
            if (gr.enabled) return self;
        }
        return nil;
    }
    return hit;
}

@end

// =============================================================================
#pragma mark - 配置变更回调（C 函数，供 CFNotificationCenter 使用）
// =============================================================================

static void PrefsChangedCallback(CFNotificationCenterRef center,
                                  void *observer,
                                  CFStringRef name,
                                  const void *object,
                                  CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        _AxsLog(@"Prefs changed notification received");
        BOOL enabled = [AxsConfig sharedConfig].isEnabled;
        _AxsLog(@"  enabled = %d", enabled);

        // 通过 AxsGestureHandler 的类方法重新安装
        Class cls = NSClassFromString(@"AxsGestureHandler");
        if (cls) {
            id handler = [cls performSelector:@selector(shared)];
            if (enabled) {
                [handler performSelector:@selector(install)];
            } else {
                [handler performSelector:@selector(uninstall)];
            }
        }
    });
}

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
    _AxsLog(@"====== GesturePro install() called ======");

    BOOL enabled = [AxsConfig sharedConfig].isEnabled;
    _AxsLog(@"Config enabled = %d", enabled);
    if (!enabled) {
        _AxsLog(@"Plugin disabled, abort install");
        return;
    }

    if (self.isSetup && self.gestureWindow) {
        _AxsLog(@"Already installed, updating frame");
        [self updateFrame];
        return;
    }

    @try {
        NSArray *windows = [UIApplication sharedApplication].windows;
        _AxsLog(@"Total windows: %lu", (unsigned long)windows.count);

        UIWindow *refWindow = nil;
        for (UIWindow *w in windows) {
            _AxsLog(@"  Window: %@ key=%d level=%.0f frame=%@",
                    NSStringFromClass([w class]), w.isKeyWindow, w.windowLevel,
                    NSStringFromCGRect(w.frame));
            if (w.isKeyWindow) { refWindow = w; break; }
        }

        if (!refWindow) {
            _AxsLog(@"ERROR: No keyWindow found, retrying in 1s");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{ [[AxsGestureHandler shared] install]; });
            return;
        }

        CGRect sbFrame = [self statusBarFrameFromWindow:refWindow];
        _AxsLog(@"statusBarFrame(raw): %@", NSStringFromCGRect(sbFrame));

        if (CGRectIsEmpty(sbFrame) || sbFrame.size.height <= 0) {
            sbFrame = CGRectMake(0, 0, refWindow.bounds.size.width, kAxsStateBarHeight);
            _AxsLog(@"statusBarFrame fallback: %@", NSStringFromCGRect(sbFrame));
        }
        sbFrame.origin.x = 0;
        sbFrame.origin.y = 0;
        sbFrame.size.width = refWindow.bounds.size.width;

        // 创建窗口
        self.gestureWindow = [[AxsTouchThroughWindow alloc] initWithFrame:sbFrame];
        self.gestureWindow.windowLevel = UIWindowLevelStatusBar + 1;
        self.gestureWindow.backgroundColor = [UIColor clearColor];
        self.gestureWindow.userInteractionEnabled = YES;
        self.gestureWindow.hidden = NO;

        if (@available(iOS 13.0, *)) {
            self.gestureWindow.windowScene = refWindow.windowScene;
        }

        _AxsLog(@"GestureWindow created: frame=%@ level=%.0f",
                NSStringFromCGRect(sbFrame), self.gestureWindow.windowLevel);

        [self setupGestureRecognizers];
        [self registerConfigObserver];

        self.isSetup = YES;

        // 打印当前配置
        _AxsLog(@"--- Gesture Config ---");
        for (NSInteger r = 0; r < 3; r++) {
            NSString *rn = @[@"Left", @"Island", @"Right"][r];
            NSArray *gn = @[@"Tap", @"Double", @"Long", @"SwipeL", @"SwipeR"];
            for (NSInteger g = 0; g < 5; g++) {
                _AxsLog(@"  %@.%@ = %@", rn, gn[g],
                        [[AxsConfig sharedConfig] actionForRegion:r gesture:g]);
            }
        }
        _AxsLog(@"  urlLink = %@", [AxsConfig sharedConfig].urlLink);
        _AxsLog(@"====== Install COMPLETE ======");

    } @catch (NSException *e) {
        _AxsLog(@"EXCEPTION: %@ reason: %@", e.name, e.reason);
    }
}

- (void)uninstall {
    _AxsLog(@"GesturePro uninstall()");
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
    _AxsLog(@"Setting up gesture recognizers...");

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

    _AxsLog(@"GRs added: %lu", (unsigned long)self.gestureWindow.gestureRecognizers.count);
}

// =============================================================================
#pragma mark - UIGestureRecognizerDelegate
// =============================================================================

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    CGPoint pt = [touch locationInView:nil];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat ratio = pt.x / sw;

    if (ratio < kAxsRegionLeftRatio)
        self.currentTouchRegion = AxsStatusBarRegionLeft;
    else if (ratio > kAxsRegionRightRatio)
        self.currentTouchRegion = AxsStatusBarRegionRight;
    else
        self.currentTouchRegion = AxsStatusBarRegionIsland;

    _AxsLog(@"Touch (%.0f, %.0f) ratio=%.3f region=%ld",
            pt.x, pt.y, ratio, (long)self.currentTouchRegion);

    return YES;
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
#pragma mark - CFNotificationCenter 监听（iOS 16 兼容）
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
    _AxsLog(@"CFNotificationCenter observer registered");
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
    _AxsLog(@"====== SpringBoard applicationDidFinishLaunching ======");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[AxsGestureHandler shared] install];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *n) {
                _AxsLog(@"App became active, reinstalling...");
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
        _AxsLog(@"====== GesturePro %%ctor: defaults registered ======");
    }
}
