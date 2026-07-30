#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 配置读取层：统一管理 15 个状态栏手势的动作绑定
@interface AxsConfig : NSObject

@property (class, nonatomic, readonly) AxsConfig *sharedConfig;

// --- 通用 ---
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;

// --- 状态栏左区手势动作 ---
@property (nonatomic, readonly, copy) NSString *actionLeftTap;
@property (nonatomic, readonly, copy) NSString *actionLeftDouble;
@property (nonatomic, readonly, copy) NSString *actionLeftLong;
@property (nonatomic, readonly, copy) NSString *actionLeftSwipeLeft;
@property (nonatomic, readonly, copy) NSString *actionLeftSwipeRight;

// --- 灵动岛区手势动作 ---
@property (nonatomic, readonly, copy) NSString *actionIslandTap;
@property (nonatomic, readonly, copy) NSString *actionIslandDouble;
@property (nonatomic, readonly, copy) NSString *actionIslandLong;
@property (nonatomic, readonly, copy) NSString *actionIslandSwipeLeft;
@property (nonatomic, readonly, copy) NSString *actionIslandSwipeRight;

// --- 状态栏右区手势动作 ---
@property (nonatomic, readonly, copy) NSString *actionRightTap;
@property (nonatomic, readonly, copy) NSString *actionRightDouble;
@property (nonatomic, readonly, copy) NSString *actionRightLong;
@property (nonatomic, readonly, copy) NSString *actionRightSwipeLeft;
@property (nonatomic, readonly, copy) NSString *actionRightSwipeRight;

// 快捷方式/额外参数
@property (nonatomic, readonly, copy) NSString *openAppBundleID;    // 打开App：Bundle ID
@property (nonatomic, readonly, copy) NSString *shortcutName;       // 快捷指令：名称
@property (nonatomic, readonly, copy) NSString *shellCommand;       // Shell：命令文本
@property (nonatomic, readonly, copy) NSString *urlLink;            // 打开URL：链接字符串（支持 Prefs: / http:// / scheme://）

// 首次安装持久化默认值（不覆盖已有值）
- (void)registerDefaults;

// 根据区域和手势获取绑定的动作标识符
- (NSString *)actionForRegion:(NSInteger)region gesture:(NSInteger)gesture;

// 设置面板写入（通过 key 读写）
+ (nullable NSString *)stringForKey:(NSString *)key;
+ (void)setString:(nullable NSString *)value forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
