#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 动作执行器：根据动作标识符执行对应系统操作
@interface AxsActionExecutor : NSObject

// 执行指定动作标识符
+ (void)executeAction:(NSString *)action;

// 执行指定区域 + 手势绑定的动作（自动从配置读取）
+ (void)executeActionForRegion:(NSInteger)region gesture:(NSInteger)gesture;

@end

NS_ASSUME_NONNULL_END
