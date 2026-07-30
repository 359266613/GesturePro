#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 手势识别结果回调协议
@protocol AxsGestureRecognizerDelegate <NSObject>
// 手势被识别时回调：region=区域枚举值，gesture=手势类型枚举值
- (void)gestureRecognizedInRegion:(NSInteger)region gesture:(NSInteger)gesture;
@end

// 手势识别器：在透明覆盖视图上捕获触摸，运行状态机判断手势类型与区域
@interface AxsGestureRecognizer : UIView

@property (nonatomic, weak, nullable) id<AxsGestureRecognizerDelegate> delegate;

// 根据触摸起始 X 坐标判定所属区域
+ (NSInteger)regionForTouchX:(CGFloat)x screenWidth:(CGFloat)screenWidth;

@end

NS_ASSUME_NONNULL_END
