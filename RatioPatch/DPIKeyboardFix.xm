#import <UIKit/UIKit.h>
#import <objc/runtime.h>

/*
 * AppTools 2.9.0 DPI editor keyboard fix.
 *
 * Binary inspection of the supplied AppTool.dylib found:
 *   ATEditingControlsView
 *     _currentValueTextEntry : UITextField
 *     _targetSetting         : NSString
 *   ATEditingMainView
 *     _currentSetting        : NSString
 *     _currentSettingLabel   : UILabel
 *
 * The hook is installed only inside SpringBoard, where AppTools builds its
 * per-app control panel. It switches only the text field belonging to a DPI
 * editor to the normal alphabetic keyboard (UIKeyboardTypeDefault).
 */

@interface ATEditingControlsView : UIView
@end

static char kATDPITextFieldMarker;

#pragma mark - Safe private-ivar access

static id ATDPIObjectIvar(id object, const char *ivarName) {
    if (!object || !ivarName) return nil;

    Class cls = object_getClass(object);
    Ivar ivar = class_getInstanceVariable(cls, ivarName);
    if (!ivar) return nil;

    return object_getIvar(object, ivar);
}

static void ATDPIAppendText(NSMutableString *destination, id value) {
    if (![value isKindOfClass:[NSString class]]) return;
    NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return;
    [destination appendFormat:@" %@", text];
}

static BOOL ATDPIStringIdentifiesDPI(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return NO;

    NSString *value = [text lowercaseString];
    NSArray<NSString *> *markers = @[
        @"dpi",
        @"density",
        @"pixel density",
        @"pixelsperinch",
        @"dotsperinch",
        @"độ phân giải",
        @"mật độ điểm ảnh"
    ];

    for (NSString *marker in markers) {
        if ([value containsString:marker]) return YES;
    }
    return NO;
}

static BOOL ATDPIIsDPIEditor(ATEditingControlsView *controls,
                             UITextField *textField) {
    if (!controls || !textField) return NO;

    NSMutableString *context = [NSMutableString string];

    /* Exact setting key stored by AppTools' ATEditingControlsView. */
    ATDPIAppendText(context, ATDPIObjectIvar(controls, "_targetSetting"));

    /* The editor's parent stores the visible setting title and label. */
    UIView *ancestor = controls.superview;
    NSUInteger depth = 0;
    while (ancestor && depth++ < 12) {
        NSString *className = NSStringFromClass(ancestor.class);
        if ([className isEqualToString:@"ATEditingMainView"]) {
            ATDPIAppendText(context, ATDPIObjectIvar(ancestor, "_currentSetting"));

            UILabel *settingLabel = ATDPIObjectIvar(ancestor, "_currentSettingLabel");
            ATDPIAppendText(context, settingLabel.text);
            break;
        }
        ancestor = ancestor.superview;
    }

    /* Fallback to the field's own visible metadata. */
    ATDPIAppendText(context, textField.placeholder);
    ATDPIAppendText(context, textField.accessibilityLabel);

    return ATDPIStringIdentifiesDPI(context);
}

static void ATDPIUseAlphabeticKeyboard(UITextField *textField) {
    if (!textField) return;

    objc_setAssociatedObject(textField,
                             &kATDPITextFieldMarker,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    /* Default gives the full QWERTY keyboard with letters and number access. */
    if (textField.keyboardType != UIKeyboardTypeDefault) {
        textField.keyboardType = UIKeyboardTypeDefault;
    }

    /* Refresh the currently displayed keyboard if the field is already active. */
    if (textField.isFirstResponder) {
        [textField reloadInputViews];
    }
}

#pragma mark - Logos hooks, SpringBoard only

%group ATDPIKeyboardFix

%hook ATEditingControlsView

- (void)setCurrentValueTextEntry:(UITextField *)textField {
    %orig(textField);

    if ([textField isKindOfClass:[UITextField class]] &&
        ATDPIIsDPIEditor((ATEditingControlsView *)self, textField)) {
        ATDPIUseAlphabeticKeyboard(textField);
    }
}

%end

%hook UITextField

- (void)setKeyboardType:(UIKeyboardType)keyboardType {
    if (objc_getAssociatedObject(self, &kATDPITextFieldMarker)) {
        %orig(UIKeyboardTypeDefault);
        return;
    }

    %orig(keyboardType);
}

%end

%end

__attribute__((constructor))
static void ATDPIKeyboardFixInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (![bundleID isEqualToString:@"com.apple.springboard"]) return;

        if (objc_getClass("ATEditingControlsView")) {
            %init(ATDPIKeyboardFix);
        }
    }
}
