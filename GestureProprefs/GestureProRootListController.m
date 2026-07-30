#import "GestureProRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <notify.h>

static NSString * const kDomain = @"com.axs.gesturepro";

// 动作列表（标识符 → 中文名称）
static NSDictionary *kActionMap(void) {
    static NSDictionary *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"none":                @"无",
            @"screenshot":          @"截图",
            @"lockscreen":          @"锁屏",
            @"homescreen":          @"主屏幕",
            @"appswitcher":         @"多任务切换",
            @"controlcenter":       @"控制中心",
            @"notificationcenter":  @"通知中心",
            @"flashlight":          @"手电筒",
            @"silenttoggle":        @"静音切换",
            @"siri":                @"Siri",
            @"rotationlock":        @"旋转锁定",
            @"respring":            @"注销 (Respring)",
            @"safemode":            @"安全模式",
            @"reboot":              @"重启",
            @"openapp":             @"打开 App",
            @"shortcut":            @"快捷指令",
            @"shellcommand":        @"Shell 命令"
        };
    });
    return map;
}

// 动作对应 validValues / validTitles 数组（按字典序）
static NSArray *kActionValues(void) {
    return @[ @"appswitcher", @"controlcenter", @"flashlight", @"homescreen",
              @"lockscreen", @"none", @"notificationcenter", @"openapp",
              @"reboot", @"respring", @"rotationlock", @"safemode",
              @"screenshot", @"shellcommand", @"shortcut", @"silenttoggle", @"siri" ];
}

static NSArray *kActionTitles(void) {
    NSMutableArray *titles = [NSMutableArray array];
    for (NSString *val in kActionValues()) {
        [titles addObject:kActionMap()[val] ?: val];
    }
    return [titles copy];
}

// =============================================================================
#pragma mark - GestureProRootListController
// =============================================================================

@implementation GestureProRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];

        // 关于我们（固定，所有插件相同）
        [specs addObject:[PSSpecifier preferenceSpecifierNamed:@"关于我们"
                                                        target:self
                                                           set:nil
                                                           get:nil
                                                        detail:nil
                                                          cell:PSGroupCell
                                                          edit:nil]];
        [self btn:@"Sileo 越狱源" act:@selector(openSileoRepo:)      to:specs];
        [self btn:@"TG分享频道"   act:@selector(openTelegramChannel:) to:specs];
        [self btn:@"QQ交流群组"   act:@selector(openQQGroup:)         to:specs];

        _specifiers = [specs copy];
    }
    return _specifiers;
}

// =============================================================================
#pragma mark - 通用 helper
// =============================================================================

- (void)btn:(NSString *)t act:(SEL)a to:(NSMutableArray *)arr {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:t
                                                    target:self
                                                       set:nil
                                                       get:nil
                                                    detail:nil
                                                      cell:PSButtonCell
                                                      edit:nil];
    s.buttonAction = a;
    [arr addObject:s];
}

// =============================================================================
#pragma mark - 读写
// =============================================================================

- (id)readPreferenceValue:(PSSpecifier *)spec {
    NSString *k = [spec propertyForKey:@"key"];
    if (!k) return nil;
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kDomain];
    id v = [d objectForKey:k];
    return v ?: [spec propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)val specifier:(PSSpecifier *)spec {
    NSString *k = [spec propertyForKey:@"key"];
    if (!k) return;
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kDomain];

    if ([val isKindOfClass:[NSNumber class]]) {
        NSNumber *n = (NSNumber *)val;
        if (strcmp([n objCType], @encode(BOOL)) == 0 || strcmp([n objCType], @encode(char)) == 0) {
            [d setBool:[n boolValue] forKey:k];
        } else {
            [d setDouble:[n doubleValue] forKey:k];
        }
    } else {
        [d setObject:val forKey:k];
    }
    [d synchronize];

    // 如果切换了启用开关，发送通知让 SpringBoard 端感知
    if ([k isEqualToString:@"enabled"]) {
        notify_post("com.axs.gesturepro.enabled-changed");
    }
}

// =============================================================================
#pragma mark - 关于我们（固定：scheme 优先 + 网页兜底）
// =============================================================================

- (void)openURL:(NSURL *)primary fallback:(NSURL *)fallback {
    UIApplication *app = [UIApplication sharedApplication];
    if (primary) {
        [app openURL:primary options:@{} completionHandler:^(BOOL s) {
            if (!s && fallback) [app openURL:fallback options:@{} completionHandler:nil];
        }];
    } else if (fallback) {
        [app openURL:fallback options:@{} completionHandler:nil];
    }
}

- (void)openSileoRepo {
    NSString *src = @"https://axs66.github.io/pro";
    NSString *enc = [src stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"sileo://source/%@", enc]];
    if (!u) u = [NSURL URLWithString:[NSString stringWithFormat:@"sileo://add-source?source=%@", enc ?: src]];
    [self openURL:u fallback:[NSURL URLWithString:src]];
}
- (void)openSileoRepo:(id)_ { [self openSileoRepo]; }

- (void)openTelegramChannel {
    [self openURL:[NSURL URLWithString:@"tg://resolve?domain=wxfx8"]
         fallback:[NSURL URLWithString:@"https://t.me/wxfx8"]];
}
- (void)openTelegramChannel:(id)_ { [self openTelegramChannel]; }

- (void)openQQGroup {
    [self openURL:[NSURL URLWithString:@"http://qm.qq.com/cgi-bin/qm/qr?_wv=1027&k=b9yIV3X8xKi3ZZUC7YXIr1YasKOzjYnm&authKey=ReN7wx79FV6Y4EIowsWSljNRUTSaGfgwWlmRzuvpWpBxl%2BCEKz%2BMNP3JePx1mMQ8&noverify=0&group_code=1001525693"]
         fallback:nil];
}
- (void)openQQGroup:(id)_ { [self openQQGroup]; }

@end
