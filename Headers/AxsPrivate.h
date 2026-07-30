// 私有类 / 协议 / 方法前向声明（仅声明，无需实现，供 Hooks/、Sources/ 引用）
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// =============================================================================
#pragma mark - 手势与区域枚举
// =============================================================================

// 手势类型
typedef NS_ENUM(NSInteger, AxsGestureType) {
    AxsGestureTypeTap = 0,
    AxsGestureTypeDoubleTap,
    AxsGestureTypeLongPress,
    AxsGestureTypeSwipeLeft,
    AxsGestureTypeSwipeRight
};

// 状态栏区域
typedef NS_ENUM(NSInteger, AxsStatusBarRegion) {
    AxsStatusBarRegionLeft = 0,
    AxsStatusBarRegionIsland,
    AxsStatusBarRegionRight
};

// =============================================================================
#pragma mark - 全局常量
// =============================================================================

// 配置域 = control 的 Package
#define kAxsDomain @"com.axs.gesturepro"

// 状态栏区域名称（供配置 key 使用）
#define kAxsRegionKeyLeft    @"left"
#define kAxsRegionKeyIsland  @"island"
#define kAxsRegionKeyRight   @"right"

// 手势名称（供配置 key 使用）
#define kAxsGestureKeyTap         @"tap"
#define kAxsGestureKeyDouble      @"double"
#define kAxsGestureKeyLong        @"long"
#define kAxsGestureKeySwipeLeft   @"swipeLeft"
#define kAxsGestureKeySwipeRight  @"swipeRight"

// 动作标识符
#define kAxsActionNone             @"none"
#define kAxsActionScreenshot       @"screenshot"
#define kAxsActionLockScreen       @"lockscreen"
#define kAxsActionHomeScreen       @"homescreen"
#define kAxsActionAppSwitcher      @"appswitcher"
#define kAxsActionControlCenter    @"controlcenter"
#define kAxsActionNotificationCenter @"notificationcenter"
#define kAxsActionFlashlight       @"flashlight"
#define kAxsActionSilentToggle     @"silenttoggle"
#define kAxsActionSiri             @"siri"
#define kAxsActionRotationLock     @"rotationlock"
#define kAxsActionRespring         @"respring"
#define kAxsActionSafeMode         @"safemode"
#define kAxsActionReboot           @"reboot"
#define kAxsActionOpenApp          @"openapp"
#define kAxsActionShortcut         @"shortcut"
#define kAxsActionShellCommand     @"shellcommand"

// 状态栏区域宽度比例
#define kAxsRegionLeftRatio     0.333
#define kAxsRegionRightRatio    0.667

// 手势识别阈值
#define kAxsTapMaxDuration      0.30   // 单击最大持续时间（秒）
#define kAxsDoubleTapMaxInterval 0.35  // 双击最大间隔（秒）
#define kAxsLongPressMinDuration 0.50  // 长按最小持续时间（秒）
#define kAxsSwipeMinDistance    30.0   // 滑动最小距离（点）
#define kAxsStateBarHeight      54.0   // iPhone 14 Pro 状态栏高度

// =============================================================================
#pragma mark - iOS 16 私有类声明
// =============================================================================

// 状态栏窗口（iOS 16）
@interface UIStatusBarWindow : UIWindow
@end

// SpringBoard 方向锁定管理
@interface SBOrientationLockManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isLocked;
- (void)lock;
- (void)unlock;
@end

// SpringBoard 手电筒管理
@interface SBFlashlightController : NSObject
+ (instancetype)sharedInstance;
- (void)setLevel:(unsigned long long)level;
- (unsigned long long)level;
@end

// SpringBoard 铃声音量控制（静音状态）
@interface SBRingerControl : NSObject
- (BOOL)isRingerSilenced;
- (void)setRingerSilenced:(BOOL)silenced;
@end

// SpringBoard 媒体控制
@interface SBMediaController : NSObject
+ (instancetype)sharedInstance;
@end

// 截图服务（SpringBoard 进程内截图）
@interface SBScreenshotManager : NSObject
+ (instancetype)sharedInstance;
- (void)saveScreenshots;
@end

// 应用切换器
@interface SBAppSwitcherController : UIViewController
@end

@interface SBMainSwitcherViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
