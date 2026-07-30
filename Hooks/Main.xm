// GesturePro — 状态栏手势核心 Hook
// Hook SpringBoard 启动流程，注入透明手势覆盖视图到状态栏窗口

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import "AxsPrivate.h"
#import "AxsConfig.h"
#import "AxsGestureRecognizer.h"
#import "AxsActionExecutor.h"

// =============================================================================
#pragma mark - 状态栏覆盖视图管理
// =============================================================================

// 关联对象 key（标记覆盖视图已添加）
static char kAxsOverlayKey;

@interface AxsOverlayManager : NSObject <AxsGestureRecognizerDelegate>
+ (instancetype)sharedManager;
- (void)ensureOverlayInstalled;
- (void)removeOverlayIfNeeded;
@end

@implementation AxsOverlayManager

+ (instancetype)sharedManager {
    static AxsOverlayManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[AxsOverlayManager alloc] init];
    });
    return manager;
}

// 查找 UIStatusBarWindow（iOS 16）
- (UIWindow *)statusBarWindow {
    // 遍历所有窗口，查找 UIStatusBarWindow 类型的窗口
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([window class]) isEqualToString:@"UIStatusBarWindow"] ||
            [NSStringFromClass([window class]) isEqualToString:@"_UIStatusBarWindow"]) {
            return window;
        }
    }
    // 某些 iOS 16 版本通过 UIApplication._statusBarWindow 访问
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(valueForKey:)]) {
        id statusBarWindow = [app valueForKey:@"_statusBarWindow"];
        if ([statusBarWindow isKindOfClass:UIWindow.class]) {
            return (UIWindow *)statusBarWindow;
        }
    }
    return nil;
}

// 添加覆盖视图到状态栏窗口
- (void)ensureOverlayInstalled {
    // 检查是否启用
    if (![AxsConfig sharedConfig].enabled) {
        [self removeOverlayIfNeeded];
        return;
    }

    UIWindow *sbWindow = [self statusBarWindow];
    if (!sbWindow) return;

    // 检查是否已经添加了覆盖视图（通过关联对象）
    AxsGestureRecognizer *existingOverlay = objc_getAssociatedObject(sbWindow, &kAxsOverlayKey);
    if (existingOverlay) return; // 已存在

    // 获取状态栏框架
    CGRect statusBarFrame;
    if ([sbWindow respondsToSelector:@selector(statusBarFrame)]) {
        statusBarFrame = [[sbWindow valueForKey:@"statusBarFrame"] CGRectValue];
    } else {
        statusBarFrame = sbWindow.bounds;
    }

    // 调整：在 iPhone 14 Pro 上状态栏高度为 54pt，确保覆盖整个状态栏区域
    CGFloat height = MAX(statusBarFrame.size.height, kAxsStateBarHeight);
    statusBarFrame.size.height = height;
    statusBarFrame.origin.y = 0;

    // 创建透明覆盖视图
    AxsGestureRecognizer *overlay = [[AxsGestureRecognizer alloc] initWithFrame:statusBarFrame];
    overlay.delegate = self;
    overlay.backgroundColor = [UIColor clearColor]; // 完全透明
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    [sbWindow addSubview:overlay];
    objc_setAssociatedObject(sbWindow, &kAxsOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 监听启用状态变化通知
    [self registerEnableObserver];
}

// 移除覆盖视图
- (void)removeOverlayIfNeeded {
    UIWindow *sbWindow = [self statusBarWindow];
    if (!sbWindow) return;

    AxsGestureRecognizer *overlay = objc_getAssociatedObject(sbWindow, &kAxsOverlayKey);
    if (overlay) {
        [overlay removeFromSuperview];
        objc_setAssociatedObject(sbWindow, &kAxsOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// 监听 notify_post 通知（设置面板切换启用状态时发送）
- (void)registerEnableObserver {
    static BOOL registered = NO;
    if (registered) return;
    registered = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        int token = 0;
        notify_register_dispatch("com.axs.gesturepro.enabled-changed", &token,
            dispatch_get_main_queue(), ^(int t) {
                if ([AxsConfig sharedConfig].enabled) {
                    [[AxsOverlayManager sharedManager] ensureOverlayInstalled];
                } else {
                    [[AxsOverlayManager sharedManager] removeOverlayIfNeeded];
                }
            });
    });
}

// =============================================================================
#pragma mark - AxsGestureRecognizerDelegate
// =============================================================================

- (void)gestureRecognizedInRegion:(NSInteger)region gesture:(NSInteger)gesture {
    [AxsActionExecutor executeActionForRegion:region gesture:gesture];
}

@end

// =============================================================================
#pragma mark - SpringBoard Hooks
// =============================================================================

%hook SpringBoard

// 应用启动完成后，添加状态栏手势覆盖视图
- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;

    // 延迟一点安装覆盖视图，确保 UIStatusBarWindow 已创建
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[AxsOverlayManager sharedManager] ensureOverlayInstalled];

        // 监听应用进入前台，状态栏窗口可能会重新创建
        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"UIApplicationDidBecomeActiveNotification"
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *note) {
                [[AxsOverlayManager sharedManager] ensureOverlayInstalled];
            }];
    });
}

%end

// =============================================================================
#pragma mark - %ctor — 默认值持久化
// =============================================================================

%ctor {
    @autoreleasepool {
        [[AxsConfig sharedConfig] registerDefaults];
    }
}
