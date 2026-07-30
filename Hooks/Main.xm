// GesturePro — 完全复刻 SquidGesturePro 架构
// TouchThroughWindow + UIGestureRecognizer — hitTest 按区域/手势配置精确穿透

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
        if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    }
}

// =============================================================================
#pragma mark - 区域判定 + 配置查询（静态工具函数）
// =============================================================================

static NSInteger _AxRegionForX(CGFloat x, CGFloat screenW) {
    CGFloat r = x / screenW;
    if (r < kAxsRegionLeftRatio)  return AxsStatusBarRegionLeft;
    if (r > kAxsRegionRightRatio) return AxsStatusBarRegionRight;
    return AxsStatusBarRegionIsland;
}

// 检查该区域是否有任何手势配置了非 none 动作
static BOOL _AxRegionHasAnyAction(NSInteger region) {
    for (NSInteger g = AxsGestureTypeTap; g <= AxsGestureTypeSwipeRight; g++) {
        NSString *a = [[AxsConfig sharedConfig] actionForRegion:region gesture:g];
        if (a && ![a isEqualToString:kAxsActionNone]) return YES;
    }
    return NO;
}

// =============================================================================
#pragma mark - AxsTouchThroughWindow（精确触摸穿透）
// =============================================================================

@interface AxsTouchThroughWindow : UIWindow
@end

@implementation AxsTouchThroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // 判定触摸所在状态栏区域
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    NSInteger region = _AxRegionForX(point.x, sw);

    // 该区域无任何已配置手势 → 穿透触摸到 SpringBoard
    if (!_AxRegionHasAnyAction(region)) {
        return nil;
    }

    // 该区域有配置手势 → 返回 self 让手势识别器处理
    return [super hitTest:point withEvent:event];
}

@end

// =============================================================================
#pragma mark - 配置变更回调（带防抖）
// =============================================================================

static void PrefsChangedCallback(CFNotificationCenterRef center,
                                  void *observer, CFStringRef name,
                                  const void *object, CFDictionaryRef userInfo) {
    static NSTimeInterval lastCall = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastCall < 0.3) return;
    lastCall = now;

    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = NSClassFromString(@"AxsGestureHandler");
        if (cls) {
            id h = [cls performSelector:@selector(shared)];
            BOOL en = [AxsConfig sharedConfig].isEnabled;
            if (en) [h performSelector:@selector(install)];
            else    [h performSelector:@selector(uninstall)];
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
    if (![AxsConfig sharedConfig].isEnabled) {
        [self uninstall];
        return;
    }
    if (self.isSetup && self.gestureWindow) { [self updateFrame]; return; }

    @try {
        // 找真正的 SpringBoard 窗口（不用 floatingView 等第三方窗口）
        NSArray *windows = [UIApplication sharedApplication].windows;
        UIWindow *refWindow = nil;
        for (UIWindow *w in windows) {
            NSString *cn = NSStringFromClass([w class]);
            if ([cn hasPrefix:@"SB"] && w.isKeyWindow) { refWindow = w; break; }
        }
        if (!refWindow) {
            for (UIWindow *w in windows) {
                NSString *cn = NSStringFromClass([w class]);
                if ([cn hasPrefix:@"SB"]) { refWindow = w; break; }
            }
        }
        if (!refWindow) {
            for (UIWindow *w in windows) { if (w.isKeyWindow) { refWindow = w; break; } }
        }
        if (!refWindow) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{ [self install]; });
            return;
        }

        _AxsLog(@"install: refWindow=%@ level=%.0f", NSStringFromClass([refWindow class]), refWindow.windowLevel);

        CGRect sbFrame = [self statusBarFrameFromWindow:refWindow];
        if (CGRectIsEmpty(sbFrame) || sbFrame.size.height <= 0)
            sbFrame = CGRectMake(0, 0, refWindow.bounds.size.width, kAxsStateBarHeight);
        sbFrame.origin = CGPointZero;
        sbFrame.size.width = refWindow.bounds.size.width;

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

        _AxsLog(@"Install OK. frame=%@ regions:", NSStringFromCGRect(sbFrame));
        for (NSInteger r = 0; r < 3; r++) {
            NSMutableString *acts = [NSMutableString string];
            NSArray *gn = @[@"Tap", @"Dbl", @"Long", @"SwL", @"SwR"];
            for (NSInteger g = 0; g < 5; g++) {
                NSString *a = [[AxsConfig sharedConfig] actionForRegion:r gesture:g];
                if (a && ![a isEqualToString:kAxsActionNone])
                    [acts appendFormat:@"%@=%@ ", gn[g], a];
            }
            if (acts.length > 0)
                _AxsLog(@"  %@: %@", @[@"Left", @"Island", @"Right"][r], acts);
        }

    } @catch (NSException *e) {
        _AxsLog(@"EXCEPTION: %@", e);
    }
}

- (void)uninstall {
    if (self.gestureWindow) { self.gestureWindow.hidden = YES; self.gestureWindow = nil; }
    self.isSetup = NO;
}

- (void)updateFrame {
    UIWindow *ref = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows)
        if (w.isKeyWindow) { ref = w; break; }
    if (!ref) return;
    CGRect f = [self statusBarFrameFromWindow:ref];
    if (CGRectIsEmpty(f) || f.size.height <= 0)
        f = CGRectMake(0, 0, ref.bounds.size.width, kAxsStateBarHeight);
    f.origin = CGPointZero; f.size.width = ref.bounds.size.width;
    self.gestureWindow.frame = f;
}

// =============================================================================
#pragma mark - 手势识别器
// =============================================================================

- (void)setupGestureRecognizers {
    // 清除旧的手势
    for (UIGestureRecognizer *gr in self.gestureWindow.gestureRecognizers)
        [self.gestureWindow removeGestureRecognizer:gr];

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
#pragma mark - UIGestureRecognizerDelegate：只接受已配置手势类型
// =============================================================================

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    CGPoint pt = [touch locationInView:nil];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    NSInteger region = _AxRegionForX(pt.x, sw);

    // 确定手势类型
    NSInteger gtype;
    if (gr == self.doubleTapGR)      gtype = AxsGestureTypeDoubleTap;
    else if (gr == self.longPressGR)  gtype = AxsGestureTypeLongPress;
    else if (gr == self.swipeLeftGR)  gtype = AxsGestureTypeSwipeLeft;
    else if (gr == self.swipeRightGR) gtype = AxsGestureTypeSwipeRight;
    else                              gtype = AxsGestureTypeTap;

    NSString *action = [[AxsConfig sharedConfig] actionForRegion:region gesture:gtype];
    BOOL ok = action && ![action isEqualToString:kAxsActionNone];
    if (ok) {
        // 用 associated object 把 region+gesture 绑定到这个 GR 实例，回调时读取
        objc_setAssociatedObject(gr, "region", @(region), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gr, "gtype", @(gtype), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        _AxsLog(@"GR ok: %@.%@ = %@", @[@"L",@"I",@"R"][region], @[@"Tap",@"Dbl",@"Long",@"SwL",@"SwR"][gtype], action);
    }
    return ok;
}

// =============================================================================
#pragma mark - 手势回调
// =============================================================================

- (void)handleGesture:(UIGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded && gr.state != UIGestureRecognizerStateBegan) return;

    NSNumber *rNum = objc_getAssociatedObject(gr, "region");
    NSNumber *gNum = objc_getAssociatedObject(gr, "gtype");
    if (!rNum || !gNum) return;

    // 对于长按，只在 Began 状态触发
    if (gNum.integerValue == AxsGestureTypeLongPress && gr.state != UIGestureRecognizerStateBegan) return;
    // 对于非长按，只在 Ended 状态触发
    if (gNum.integerValue != AxsGestureTypeLongPress && gr.state != UIGestureRecognizerStateEnded) return;

    NSInteger region = rNum.integerValue;
    NSInteger gtype = gNum.integerValue;
    NSString *action = [[AxsConfig sharedConfig] actionForRegion:region gesture:gtype];

    _AxsLog(@">>> %@ region=%@ action=%@",
            @[@"Tap",@"DblTap",@"Long",@"SwL",@"SwR"][gtype],
            @[@"L",@"I",@"R"][region], action);

    [AxsActionExecutor executeActionForRegion:region gesture:gtype];
}

- (void)handleSingleTap:(UITapGestureRecognizer *)gr   { [self handleGesture:gr]; }
- (void)handleDoubleTap:(UITapGestureRecognizer *)gr   { [self handleGesture:gr]; }
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr { [self handleGesture:gr]; }
- (void)handleSwipeLeft:(UISwipeGestureRecognizer *)gr { [self handleGesture:gr]; }
- (void)handleSwipeRight:(UISwipeGestureRecognizer *)gr { [self handleGesture:gr]; }

// =============================================================================
#pragma mark - CFNotificationCenter
// =============================================================================

- (void)registerConfigObserver {
    static BOOL done = NO;
    if (done) return; done = YES;
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self, PrefsChangedCallback,
        CFSTR("com.axs.gesturepro.prefs-changed"),
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately
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
                               dispatch_get_main_queue(), ^{ [[AxsGestureHandler shared] install]; });
            }];
    });
}

%end

%ctor {
    @autoreleasepool { [[AxsConfig sharedConfig] registerDefaults]; }
}
