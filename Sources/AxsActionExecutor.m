#import "AxsActionExecutor.h"
#import "AxsConfig.h"
#import "AxsPrivate.h"
#import <UIKit/UIKit.h>
#import <spawn.h>

extern char **environ;

// =============================================================================
#pragma mark - AxsActionExecutor 实现
// =============================================================================

@implementation AxsActionExecutor

+ (void)executeActionForRegion:(NSInteger)region gesture:(NSInteger)gesture {
    NSString *action = [[AxsConfig sharedConfig] actionForRegion:region gesture:gesture];
    [self executeAction:action];
}

+ (void)executeAction:(NSString *)action {
    if (!action || [action isEqualToString:kAxsActionNone]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([action isEqualToString:kAxsActionScreenshot]) {
            [self performScreenshot];
        } else if ([action isEqualToString:kAxsActionLockScreen]) {
            [self performLockScreen];
        } else if ([action isEqualToString:kAxsActionHomeScreen]) {
            [self performHomeScreen];
        } else if ([action isEqualToString:kAxsActionAppSwitcher]) {
            [self performAppSwitcher];
        } else if ([action isEqualToString:kAxsActionControlCenter]) {
            [self performControlCenter];
        } else if ([action isEqualToString:kAxsActionNotificationCenter]) {
            [self performNotificationCenter];
        } else if ([action isEqualToString:kAxsActionFlashlight]) {
            [self performFlashlight];
        } else if ([action isEqualToString:kAxsActionSilentToggle]) {
            [self performSilentToggle];
        } else if ([action isEqualToString:kAxsActionSiri]) {
            [self performSiri];
        } else if ([action isEqualToString:kAxsActionRotationLock]) {
            [self performRotationLock];
        } else if ([action isEqualToString:kAxsActionRespring]) {
            [self performRespring];
        } else if ([action isEqualToString:kAxsActionSafeMode]) {
            [self performSafeMode];
        } else if ([action isEqualToString:kAxsActionReboot]) {
            [self performReboot];
        } else if ([action isEqualToString:kAxsActionOpenApp]) {
            [self performOpenApp];
        } else if ([action isEqualToString:kAxsActionShortcut]) {
            [self performShortcut];
        } else if ([action isEqualToString:kAxsActionShellCommand]) {
            [self performShellCommand];
        }
    });
}

// =============================================================================
#pragma mark - 系统动作实现
// =============================================================================

+ (void)performScreenshot {
    // 通过 SBScreenshotManager 截图（SpringBoard 进程内部调用）
    Class mgr = NSClassFromString(@"SBScreenshotManager");
    if ([mgr respondsToSelector:@selector(sharedInstance)]) {
        id instance = [mgr performSelector:@selector(sharedInstance)];
        if ([instance respondsToSelector:@selector(saveScreenshots)]) {
            [instance performSelector:@selector(saveScreenshots)];
            return;
        }
    }
    // 兜底：使用后台截图命令
    [self runShellCommand:@"screencapture" args:@[@"-x", @"/tmp/gesturepro_screenshot.png"]];
}

+ (void)performLockScreen {
    // 通过 GraphicsServices 锁屏（SpringBoard 进程内）
    Class gsEvent = NSClassFromString(@"GSEvent");
    if ([gsEvent respondsToSelector:@selector(sendButtonEvent:isDown:)]) {
        // iOS 16 可能不支持此私有 API，尝试 SBLockScreenManager
    }

    // 尝试通过 SBUIController 锁屏
    id uiController = [self sbuicontroller];
    if ([uiController respondsToSelector:@selector(lockInterface)]) {
        [uiController performSelector:@selector(lockInterface)];
        return;
    }

    // 兜底：使用前台 app 的方式触发锁屏
    Class springBoard = NSClassFromString(@"SpringBoard");
    id sb = [springBoard performSelector:@selector(sharedApplication)];
    if ([sb respondsToSelector:@selector(lockButtonDown)]) {
        [sb performSelector:@selector(lockButtonDown)];
    }
}

+ (void)performHomeScreen {
    // 通过 SBUIController 回到主屏幕
    id uiController = [self sbuicontroller];
    if ([uiController respondsToSelector:@selector(presentSpotlightFromEdge:)]) {
        // 非主屏幕，尝试 _goToHomeScreen
    }
    if ([uiController respondsToSelector:@selector(_goToHomeScreen)]) {
        [uiController performSelector:@selector(_goToHomeScreen)];
        return;
    }
    // 尝试通过 UIApplication 回到桌面
    [[UIApplication sharedApplication] performSelector:@selector(suspend)];
}

+ (void)performAppSwitcher {
    // 通过 SBUIController 打开多任务
    id uiController = [self sbuicontroller];
    if ([uiController respondsToSelector:@selector(toggleSwitcherNoninteractively)]) {
        [uiController performSelector:@selector(toggleSwitcherNoninteractively)];
        return;
    }
    if ([uiController respondsToSelector:@selector(_toggleAppSwitcherAnimated:shouldFloat:)]) {
        [uiController performSelector:@selector(_toggleAppSwitcherAnimated:shouldFloat:) withObject:@YES withObject:@NO];
    }
}

+ (void)performControlCenter {
    // 展开控制中心
    id uiController = [self sbuicontroller];
    if ([uiController respondsToSelector:@selector(_showControlCenter)]) {
        [uiController performSelector:@selector(_showControlCenter)];
    }
}

+ (void)performNotificationCenter {
    // 展开通知中心
    id uiController = [self sbuicontroller];
    if ([uiController respondsToSelector:@selector(_showNotificationCenter)]) {
        [uiController performSelector:@selector(_showNotificationCenter)];
    }
}

+ (void)performFlashlight {
    // SBFlashlightController 手电筒（SpringBoard 进程内）
    Class flash = NSClassFromString(@"SBFlashlightController");
    if ([flash respondsToSelector:@selector(sharedInstance)]) {
        id instance = [flash performSelector:@selector(sharedInstance)];
        unsigned long long currentLevel =
            [instance respondsToSelector:@selector(level)] ? [[instance valueForKey:@"level"] unsignedLongLongValue] : 0;
        unsigned long long newLevel = (currentLevel > 0) ? 0 : 1;
        if ([instance respondsToSelector:@selector(setLevel:)]) {
            [instance performSelector:@selector(setLevel:) withObject:@(newLevel)];
            return;
        }
    }
    // 兜底：使用硬件闪光灯（需要 AVFoundation）
    [self toggleTorch];
}

+ (void)performSilentToggle {
    // 通过 SBRingerControl 切换静音
    Class ringer = NSClassFromString(@"SBRingerControl");
    if (ringer) {
        id instance = [[ringer alloc] init];
        BOOL isSilenced = NO;
        if ([instance respondsToSelector:@selector(isRingerSilenced)]) {
            isSilenced = [[instance valueForKey:@"isRingerSilenced"] boolValue];
        }
        if ([instance respondsToSelector:@selector(setRingerSilenced:)]) {
            [instance performSelector:@selector(setRingerSilenced:) withObject:@(!isSilenced)];
            return;
        }
    }
    // AVSystemController 兜底
    BOOL isMuted = [self isMuted];
    [self setMuted:!isMuted];
}

+ (void)performSiri {
    // 通过 SBUIController 激活 Siri
    id uiController = [self sbuicontroller];
    if ([uiController respondsToSelector:@selector(activateSiri)]) {
        [uiController performSelector:@selector(activateSiri)];
    }
}

+ (void)performRotationLock {
    // SBOrientationLockManager 方向锁定
    Class lockMgr = NSClassFromString(@"SBOrientationLockManager");
    if ([lockMgr respondsToSelector:@selector(sharedInstance)]) {
        id instance = [lockMgr performSelector:@selector(sharedInstance)];
        BOOL isLocked = [instance respondsToSelector:@selector(isLocked)] ? [[instance valueForKey:@"isLocked"] boolValue] : NO;
        if (isLocked) {
            if ([instance respondsToSelector:@selector(unlock)]) [instance performSelector:@selector(unlock)];
        } else {
            if ([instance respondsToSelector:@selector(lock)]) [instance performSelector:@selector(lock)];
        }
    }
}

+ (void)performRespring {
    [self runShellCommand:@"killall" args:@[@"-9", @"SpringBoard"]];
}

+ (void)performSafeMode {
    [self runShellCommand:@"killall" args:@[@"-SEGV", @"SpringBoard"]];
}

+ (void)performReboot {
    [self runShellCommand:@"reboot" args:nil];
}

+ (void)performOpenApp {
    AxsConfig *cfg = [AxsConfig sharedConfig];
    NSString *bundleID = cfg.openAppBundleID;
    if (bundleID.length == 0) return;

    // 使用 LSApplicationWorkspace 打开 App
    Class workspace = NSClassFromString(@"LSApplicationWorkspace");
    if ([workspace respondsToSelector:@selector(defaultWorkspace)]) {
        id ws = [workspace performSelector:@selector(defaultWorkspace)];
        [ws performSelector:@selector(openApplicationWithBundleID:) withObject:bundleID];
    }
}

+ (void)performShortcut {
    AxsConfig *cfg = [AxsConfig sharedConfig];
    NSString *shortcutName = cfg.shortcutName;
    if (shortcutName.length == 0) return;

    // 通过 URL scheme 运行快捷指令
    NSString *urlStr = [NSString stringWithFormat:
        @"shortcuts://run-shortcut?name=%@",
        [shortcutName stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlStr]
                                       options:@{}
                             completionHandler:nil];
}

+ (void)performShellCommand {
    AxsConfig *cfg = [AxsConfig sharedConfig];
    NSString *command = cfg.shellCommand;
    if (command.length == 0) return;

    [self runShellCommand:@"/bin/sh" args:@[@"-c", command]];
}

// =============================================================================
#pragma mark - 辅助方法
// =============================================================================

// 获取 SBUIController 实例
+ (id)sbuicontroller {
    Class cls = NSClassFromString(@"SBUIController");
    if ([cls respondsToSelector:@selector(sharedInstance)]) {
        return [cls performSelector:@selector(sharedInstance)];
    }
    return nil;
}

// 执行 Shell 命令（使用 posix_spawn，iOS 无 NSTask）
+ (void)runShellCommand:(NSString *)command args:(NSArray<NSString *> * _Nullable)args {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        pid_t pid;
        NSUInteger argCount = args ? [args count] : 0;
        char **argv = malloc(sizeof(char *) * (argCount + 2));
        argv[0] = (char *)[command UTF8String];
        for (NSUInteger i = 0; i < argCount; i++) {
            argv[i + 1] = (char *)[args[i] UTF8String];
        }
        argv[argCount + 1] = NULL;
        posix_spawn(&pid, argv[0], NULL, NULL, argv, environ);
        free(argv);
    });
}

// 切换手电筒（AVFoundation 兜底）
+ (void)toggleTorch {
    Class device = NSClassFromString(@"AVCaptureDevice");
    if (![device respondsToSelector:@selector(defaultDeviceWithMediaType:)]) return;
    id captureDevice = [device performSelector:@selector(defaultDeviceWithMediaType:) withObject:@"vide"];
    if (!captureDevice) return;
    if (![captureDevice respondsToSelector:@selector(hasTorch)] || ![[captureDevice valueForKey:@"hasTorch"] boolValue]) return;
    if (![captureDevice respondsToSelector:@selector(lockForConfiguration:)]) return;

    BOOL torchOn = [[captureDevice valueForKey:@"torchMode"] integerValue] == 1; // AVCaptureTorchModeOn = 1
    NSError *err = nil;
    // 使用 NSInvocation 代替 performSelector，避免 ARC 下 NSError ** 类型不兼容
    NSMethodSignature *lockSig = [captureDevice methodSignatureForSelector:@selector(lockForConfiguration:)];
    if (lockSig) {
        NSInvocation *lockInv = [NSInvocation invocationWithMethodSignature:lockSig];
        [lockInv setTarget:captureDevice];
        [lockInv setSelector:@selector(lockForConfiguration:)];
        [lockInv setArgument:&err atIndex:2];
        [lockInv invoke];
    }
    if (err) return;
    if ([captureDevice respondsToSelector:@selector(setTorchMode:)]) {
        [captureDevice performSelector:@selector(setTorchMode:) withObject:@(torchOn ? 0 : 1)];
    }
    if ([captureDevice respondsToSelector:@selector(unlockForConfiguration)]) {
        [captureDevice performSelector:@selector(unlockForConfiguration)];
    }
}

// 静音状态（通过 AVSystemController）
+ (BOOL)isMuted {
    Class avc = NSClassFromString(@"AVSystemController");
    if ([avc respondsToSelector:@selector(sharedAVSystemController)]) {
        id controller = [avc performSelector:@selector(sharedAVSystemController)];
        if ([controller respondsToSelector:@selector(getActiveCategoryMuted:)]) {
            BOOL muted = NO;
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
                [controller methodSignatureForSelector:@selector(getActiveCategoryMuted:)]];
            [inv setSelector:@selector(getActiveCategoryMuted:)];
            [inv setTarget:controller];
            [inv setArgument:&muted atIndex:2];
            [inv invoke];
            return muted;
        }
    }
    return NO;
}

+ (void)setMuted:(BOOL)muted {
    Class avc = NSClassFromString(@"AVSystemController");
    if ([avc respondsToSelector:@selector(sharedAVSystemController)]) {
        id controller = [avc performSelector:@selector(sharedAVSystemController)];
        if ([controller respondsToSelector:@selector(setActiveCategoryMuted:)]) {
            [controller performSelector:@selector(setActiveCategoryMuted:) withObject:@(muted)];
        }
    }
}

@end
