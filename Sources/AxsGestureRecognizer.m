#import "AxsGestureRecognizer.h"
#import "AxsPrivate.h"

// =============================================================================
#pragma mark - 手势识别状态机实现
// =============================================================================

@implementation AxsGestureRecognizer {
    // 触摸追踪
    CGPoint _touchBeganPoint;        // 首次触摸坐标
    NSTimeInterval _touchBeganTime;  // 首次触摸时间戳
    NSInteger _touchBeganRegion;     // 首次触摸所在区域

    // 双击检测
    NSTimeInterval _lastTapTime;     // 上次单击结束时间
    CGPoint _lastTapPoint;           // 上次单击位置
    NSInteger _lastTapRegion;        // 上次单击区域
    BOOL _waitingForDoubleTap;       // 是否正在等待双击

    // 长按
    BOOL _longPressFired;            // 长按已触发

    // 滑动
    BOOL _isSwiping;                 // 是否正在滑动
}

// =============================================================================
#pragma mark - 区域判定
// =============================================================================

+ (NSInteger)regionForTouchX:(CGFloat)x screenWidth:(CGFloat)screenWidth {
    CGFloat ratio = x / screenWidth;
    if (ratio < kAxsRegionLeftRatio)  return AxsStatusBarRegionLeft;
    if (ratio > kAxsRegionRightRatio) return AxsStatusBarRegionRight;
    return AxsStatusBarRegionIsland;
}

// =============================================================================
#pragma mark - 触摸事件
// =============================================================================

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (!touch) return;

    CGPoint point = [touch locationInView:self];
    _touchBeganPoint  = point;
    _touchBeganTime   = touch.timestamp;
    _touchBeganRegion = [AxsGestureRecognizer regionForTouchX:point.x screenWidth:self.bounds.size.width];
    _isSwiping        = NO;
    _longPressFired   = NO;

    // 长按定时器：超过 kAxsLongPressMinDuration 后触发
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAxsLongPressMinDuration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        // 如果已经识别为其他手势则不再触发长按
        if (self->_longPressFired || self->_isSwiping) return;
        self->_longPressFired = YES;
        [self fireGesture:self->_touchBeganRegion type:AxsGestureTypeLongPress];
    });
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (!touch) return;

    CGPoint currentPoint = [touch locationInView:self];
    CGFloat dx = currentPoint.x - _touchBeganPoint.x;

    // 水平移动超过阈值 → 识别为滑动
    if (fabs(dx) >= kAxsSwipeMinDistance && !_longPressFired) {
        _isSwiping = YES;
        NSInteger gestureType = (dx > 0) ? AxsGestureTypeSwipeRight : AxsGestureTypeSwipeLeft;
        [self fireGesture:_touchBeganRegion type:gestureType];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (!touch) return;

    // 滑动和长按已处理，直接结束
    if (_isSwiping || _longPressFired) return;

    NSTimeInterval duration = touch.timestamp - _touchBeganTime;

    // 单击/双击判断
    if (duration < kAxsTapMaxDuration) {
        // 检查是否在双击时间窗口内
        NSTimeInterval sinceLastTap = touch.timestamp - _lastTapTime;
        CGFloat tapDistance = hypotf(_touchBeganPoint.x - _lastTapPoint.x,
                                     _touchBeganPoint.y - _lastTapPoint.y);

        if (_waitingForDoubleTap &&
            sinceLastTap < kAxsDoubleTapMaxInterval &&
            tapDistance < 20.0 &&
            _lastTapRegion == _touchBeganRegion) {
            // 双击
            [self fireGesture:_touchBeganRegion type:AxsGestureTypeDoubleTap];
            _waitingForDoubleTap = NO;
            _lastTapTime = 0;
        } else {
            // 可能是单击，先等待双击窗口确认
            _lastTapPoint = _touchBeganPoint;
            _lastTapTime  = touch.timestamp;
            _lastTapRegion = _touchBeganRegion;
            _waitingForDoubleTap = YES;

            __weak typeof(self) weakSelf = self;
            NSInteger region = _touchBeganRegion;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAxsDoubleTapMaxInterval * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || !self->_waitingForDoubleTap) return;
                self->_waitingForDoubleTap = NO;

                // 双击窗口内没有第二次点击 → 确认为单击
                [self fireGesture:region type:AxsGestureTypeTap];
            });
        }
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _isSwiping      = NO;
    _longPressFired = NO;
}

// =============================================================================
#pragma mark - 触发手势回调
// =============================================================================

- (void)fireGesture:(NSInteger)region type:(NSInteger)gesture {
    if ([self.delegate respondsToSelector:@selector(gestureRecognizedInRegion:gesture:)]) {
        [self.delegate gestureRecognizedInRegion:region gesture:gesture];
    }
}

@end
