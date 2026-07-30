#import "AxsConfig.h"
#import "AxsPrivate.h"

// =============================================================================
#pragma mark - 常量定义
// =============================================================================

static NSString * const kDomain = kAxsDomain;

static inline NSUserDefaults * AxsPrefs(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:kDomain];
}

static BOOL      BoolVal(id v, BOOL d)      { return [v isKindOfClass:NSNumber.class] ? [v boolValue]    : d; }
static NSString *StrVal(id v, NSString *d)   { return [v isKindOfClass:NSString.class] ? v                : d; }

// 所有区域的 key 名称
static NSArray<NSString *> *kAxsRegionKeys(void) {
    static NSArray *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[ kAxsRegionKeyLeft, kAxsRegionKeyIsland, kAxsRegionKeyRight ];
    });
    return keys;
}

// 每个区域下所有手势的 key 名称
static NSArray<NSString *> *kAxsGestureKeys(void) {
    static NSArray *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[ kAxsGestureKeyTap, kAxsGestureKeyDouble, kAxsGestureKeyLong,
                  kAxsGestureKeySwipeLeft, kAxsGestureKeySwipeRight ];
    });
    return keys;
}

// =============================================================================
#pragma mark - 生成 userdefaults key
// =============================================================================

static NSString * KeyForRegionGesture(NSString *regionKey, NSString *gestureKey) {
    return [NSString stringWithFormat:@"statusbar.%@.%@", regionKey, gestureKey];
}

// =============================================================================
#pragma mark - AxsConfig 实现
// =============================================================================

@implementation AxsConfig

// 单例
static AxsConfig *_shared = nil;

+ (AxsConfig *)sharedConfig {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[AxsConfig alloc] init];
    });
    return _shared;
}

// =============================================================================
#pragma mark - 默认值持久化
// =============================================================================

- (void)registerDefaults {
    NSUserDefaults *d = AxsPrefs();
    BOOL needsSync = NO;

    // 启用开关（默认关闭）
    if (![d objectForKey:@"enabled"]) {
        [d setBool:NO forKey:@"enabled"];
        needsSync = YES;
    }

    // 所有区域 + 手势默认动作为 "none"
    for (NSString *regionKey in kAxsRegionKeys()) {
        for (NSString *gestureKey in kAxsGestureKeys()) {
            NSString *key = KeyForRegionGesture(regionKey, gestureKey);
            if (![d objectForKey:key]) {
                [d setObject:kAxsActionNone forKey:key];
                needsSync = YES;
            }
        }
    }

    // 额外参数默认值
    if (![d objectForKey:@"openAppBundleID"]) { [d setObject:@"" forKey:@"openAppBundleID"]; needsSync = YES; }
    if (![d objectForKey:@"shortcutName"])    { [d setObject:@"" forKey:@"shortcutName"]; needsSync = YES; }
    if (![d objectForKey:@"shellCommand"])    { [d setObject:@"" forKey:@"shellCommand"]; needsSync = YES; }
    if (![d objectForKey:@"urlLink"])         { [d setObject:@"" forKey:@"urlLink"]; needsSync = YES; }

    if (needsSync) [d synchronize];
}

// =============================================================================
#pragma mark - 通用属性
// =============================================================================

- (BOOL)isEnabled {
    return BoolVal([AxsPrefs() objectForKey:@"enabled"], NO);
}

// =============================================================================
#pragma mark - 左区域动作
// =============================================================================

- (NSString *)actionLeftTap          { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyLeft, kAxsGestureKeyTap)],          kAxsActionNone); }
- (NSString *)actionLeftDouble       { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyLeft, kAxsGestureKeyDouble)],       kAxsActionNone); }
- (NSString *)actionLeftLong         { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyLeft, kAxsGestureKeyLong)],         kAxsActionNone); }
- (NSString *)actionLeftSwipeLeft    { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyLeft, kAxsGestureKeySwipeLeft)],    kAxsActionNone); }
- (NSString *)actionLeftSwipeRight   { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyLeft, kAxsGestureKeySwipeRight)],   kAxsActionNone); }

// =============================================================================
#pragma mark - 灵动岛区域动作
// =============================================================================

- (NSString *)actionIslandTap         { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyIsland, kAxsGestureKeyTap)],          kAxsActionNone); }
- (NSString *)actionIslandDouble      { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyIsland, kAxsGestureKeyDouble)],       kAxsActionNone); }
- (NSString *)actionIslandLong        { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyIsland, kAxsGestureKeyLong)],         kAxsActionNone); }
- (NSString *)actionIslandSwipeLeft   { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyIsland, kAxsGestureKeySwipeLeft)],    kAxsActionNone); }
- (NSString *)actionIslandSwipeRight  { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyIsland, kAxsGestureKeySwipeRight)],   kAxsActionNone); }

// =============================================================================
#pragma mark - 右区域动作
// =============================================================================

- (NSString *)actionRightTap         { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyRight, kAxsGestureKeyTap)],          kAxsActionNone); }
- (NSString *)actionRightDouble      { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyRight, kAxsGestureKeyDouble)],       kAxsActionNone); }
- (NSString *)actionRightLong        { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyRight, kAxsGestureKeyLong)],         kAxsActionNone); }
- (NSString *)actionRightSwipeLeft   { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyRight, kAxsGestureKeySwipeLeft)],    kAxsActionNone); }
- (NSString *)actionRightSwipeRight  { return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(kAxsRegionKeyRight, kAxsGestureKeySwipeRight)],   kAxsActionNone); }

// =============================================================================
#pragma mark - 额外参数
// =============================================================================

- (NSString *)openAppBundleID  { return StrVal([AxsPrefs() objectForKey:@"openAppBundleID"], @""); }
- (NSString *)shortcutName     { return StrVal([AxsPrefs() objectForKey:@"shortcutName"], @""); }
- (NSString *)shellCommand     { return StrVal([AxsPrefs() objectForKey:@"shellCommand"], @""); }
- (NSString *)urlLink          { return StrVal([AxsPrefs() objectForKey:@"urlLink"], @""); }

// =============================================================================
#pragma mark - 区域+手势 → 动作映射
// =============================================================================

- (NSString *)actionForRegion:(NSInteger)region gesture:(NSInteger)gesture {
    NSString *regionKey = nil;
    switch (region) {
        case AxsStatusBarRegionLeft:   regionKey = kAxsRegionKeyLeft;   break;
        case AxsStatusBarRegionIsland: regionKey = kAxsRegionKeyIsland; break;
        case AxsStatusBarRegionRight:  regionKey = kAxsRegionKeyRight;  break;
        default: return kAxsActionNone;
    }

    NSString *gestureKey = nil;
    switch (gesture) {
        case AxsGestureTypeTap:        gestureKey = kAxsGestureKeyTap;        break;
        case AxsGestureTypeDoubleTap:  gestureKey = kAxsGestureKeyDouble;     break;
        case AxsGestureTypeLongPress:  gestureKey = kAxsGestureKeyLong;       break;
        case AxsGestureTypeSwipeLeft:  gestureKey = kAxsGestureKeySwipeLeft;  break;
        case AxsGestureTypeSwipeRight: gestureKey = kAxsGestureKeySwipeRight; break;
        default: return kAxsActionNone;
    }

    return StrVal([AxsPrefs() objectForKey:KeyForRegionGesture(regionKey, gestureKey)], kAxsActionNone);
}

// =============================================================================
#pragma mark - 设置面板读写（静态便捷方法）
// =============================================================================

+ (NSString *)stringForKey:(NSString *)key {
    return StrVal([AxsPrefs() objectForKey:key], nil);
}

+ (void)setString:(NSString *)value forKey:(NSString *)key {
    NSUserDefaults *d = AxsPrefs();
    if (value) {
        [d setObject:value forKey:key];
    } else {
        [d removeObjectForKey:key];
    }
    [d synchronize];
}

@end
