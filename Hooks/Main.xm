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

// 查找状态栏窗口（iOS 16 兼容多种类名）
// 不使用 _statusBarWindow KVC（启动早期会抛 NSException 导致 crash）
- (UIWindow *)statusBarWindow {
    @try {
        NSArray *windows = [UIApplication sharedApplication].windows;
        // 第一轮：匹配已知的状态栏窗口类名
        for (UIWindow *window in windows) {
            NSString *className = NSStringFromClass([window class]);
            if ([className isEqualToString:@"UIStatusBarWindow"] ||
                [className isEqualToString:@"_UIStatusBarWindow"] ||
                [className isEqualToString:@"UIApplicationStatusBarWindow"]) {
                return window;
            }
        }
        // 第二轮回退：找 keyWindow（部分设备状态栏渲染在 keyWindow 上）
        for (UIWindow *window in windows) {
            if (window.isKeyWindow && window.windowLevel >= UIWindowLevelNormal) {
                return window;
            }
        }
    } @catch (NSException *e) {
        // SpringBoard 尚未完全初始化时 .windows 可能抛异常，安全忽略
    }
    return nil;
}

// 添加覆盖视图到状态栏窗口
- (void)ensureOverlayInstalled {
    @try {
        // 检查是否启用
        if (![AxsConfig sharedConfig].enabled) {
            [self removeOverlayIfNeeded];
            return;
        }

        UIWindow *sbWindow = [self statusBarWindow];
        if (!sbWindow) {
            // 状态栏窗口尚未创建，延迟 0.5s 重试
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [[AxsOverlayManager sharedManager] ensureOverlayInstalled];
            });
            return;
        }

        // 检查是否已经添加了覆盖视图（通过关联对象）
        AxsGestureRecognizer *existingOverlay = objc_getAssociatedObject(sbWindow, &kAxsOverlayKey);
        if (existingOverlay) {
            // 视图已存在，确保在窗口最上层可接收触摸
            if (existingOverlay.superview != sbWindow) {
                [sbWindow addSubview:existingOverlay];
            }
            [sbWindow bringSubviewToFront:existingOverlay];
            return;
        }

        // 获取状态栏框架
        CGRect statusBarFrame = sbWindow.bounds;
        @try {
            if ([sbWindow respondsToSelector:@selector(statusBarFrame)]) {
                statusBarFrame = [[sbWindow valueForKey:@"statusBarFrame"] CGRectValue];
            }
        } @catch (NSException *e) {
            statusBarFrame = sbWindow.bounds;
        }

        // 调整：在 iPhone 14 Pro 上状态栏高度为 54pt，确保覆盖整个状态栏区域
        CGFloat height = MAX(statusBarFrame.size.height, kAxsStateBarHeight);
        statusBarFrame.size.height = height;
        statusBarFrame.origin.y = 0;
        statusBarFrame.origin.x = 0;
        statusBarFrame.size.width = sbWindow.bounds.size.width;

        // 创建透明覆盖视图
        AxsGestureRecognizer *overlay = [[AxsGestureRecognizer alloc] initWithFrame:statusBarFrame];
        overlay.delegate = self;
        overlay.backgroundColor = [UIColor clearColor];
        overlay.userInteractionEnabled = YES;
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        [sbWindow addSubview:overlay];
        // 关键：将覆盖视图置于窗口最顶层，确保触摸事件不被其他视图遮挡
        [sbWindow bringSubviewToFront:overlay];
        objc_setAssociatedObject(sbWindow, &kAxsOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // 监听设置变更通知
        [self registerConfigObserver];
    } @catch (NSException *e) {
        // 整体异常保护，避免 SpringBoard crash
    }
}

// 移除覆盖视图
- (void)removeOverlayIfNeeded {
    @try {
        UIWindow *sbWindow = [self statusBarWindow];
        if (!sbWindow) return;

        AxsGestureRecognizer *overlay = objc_getAssociatedObject(sbWindow, &kAxsOverlayKey);
        if (overlay) {
            [overlay removeFromSuperview];
            objc_setAssociatedObject(sbWindow, &kAxsOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (NSException *e) {
        // 整体异常保护
    }
}

// 监听 notify_post 通知（设置面板变更时重新加载配置）
- (void)registerConfigObserver {
    static BOOL registered = NO;
    if (registered) return;
    registered = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        int token = 0;
        notify_register_dispatch("com.axs.gesturepro.prefs-changed", &token,
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

- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;

    // 延迟安装覆盖视图，确保 UIStatusBarWindow 已创建
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[AxsOverlayManager sharedManager] ensureOverlayInstalled];

        // 监听应用进入前台，状态栏窗口可能会重新创建
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [[AxsOverlayManager sharedManager] ensureOverlayInstalled];
                });
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
