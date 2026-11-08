#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static char kATDPIAlphabeticKeyboardKey;

#pragma mark - DPI field identification

static NSString *ATDPIFoldedText(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return @"";
    NSString *folded = [text stringByFoldingWithOptions:NSDiacriticInsensitiveSearch
                                                  locale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
    return folded.lowercaseString;
}

static BOOL ATDPIIsDPITextField(UITextField *field) {
    if (!field) return NO;

    NSString *placeholder = ATDPIFoldedText(field.placeholder);
    NSString *accessibility = ATDPIFoldedText(field.accessibilityLabel);
    NSString *identifier = ATDPIFoldedText(field.accessibilityIdentifier);
    NSString *context = [NSString stringWithFormat:@"%@ %@ %@", placeholder, accessibility, identifier];

    /* Matches the actual AppTools 2.9.0 prompt shown in the user's screenshot:
       "Nhập tỷ lệ thu phóng (mặc định là 1)". */
    return [context containsString:@"dpi"] ||
           [context containsString:@"thu phong"] ||
           [context containsString:@"ty le thu phong"] ||
           [context containsString:@"zoom ratio"] ||
           [context containsString:@"scale factor"];
}

static void ATDPIForceAlphabeticKeyboard(UITextField *field) {
    if (!field) return;

    objc_setAssociatedObject(field,
                             &kATDPIAlphabeticKeyboardKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (field.keyboardType != UIKeyboardTypeDefault) {
        field.keyboardType = UIKeyboardTypeDefault;
    }

    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;

    if (field.isFirstResponder) {
        [field reloadInputViews];
    }
}

#pragma mark - SpringBoard-only hooks

%group ATDPIAlphabeticKeyboard

/*
 * The DPI prompt is an alert text field, not ATEditingControlsView's slider
 * field. Hooking setPlaceholder catches it irrespective of who created it.
 */
%hook UITextField

- (void)setPlaceholder:(NSString *)placeholder {
    %orig(placeholder);

    if (ATDPIIsDPITextField(self)) {
        ATDPIForceAlphabeticKeyboard(self);
    }
}

- (void)setKeyboardType:(UIKeyboardType)keyboardType {
    if (objc_getAssociatedObject(self, &kATDPIAlphabeticKeyboardKey)) {
        %orig(UIKeyboardTypeDefault);
        return;
    }

    %orig(keyboardType);
}

- (BOOL)becomeFirstResponder {
    if (objc_getAssociatedObject(self, &kATDPIAlphabeticKeyboardKey) &&
        self.keyboardType != UIKeyboardTypeDefault) {
        self.keyboardType = UIKeyboardTypeDefault;
    }
    return %orig;
}

%end

/*
 * Additional coverage for AppTools' UIAlertController-based DPI dialog.
 * Run AppTools' original field configuration first, then override its type.
 */
%hook UIAlertController

- (void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *))configurationHandler {
    __weak UIAlertController *weakAlert = self;

    void (^wrappedHandler)(UITextField *) = ^(UITextField *field) {
        if (configurationHandler) {
            configurationHandler(field);
        }

        UIAlertController *alert = weakAlert;
        NSString *alertText = [NSString stringWithFormat:@"%@ %@",
                               ATDPIFoldedText(alert.title),
                               ATDPIFoldedText(alert.message)];

        BOOL isDPIAlert = [alertText containsString:@"dpi"] ||
                          [alertText containsString:@"thu phong"] ||
                          ATDPIIsDPITextField(field);

        if (isDPIAlert) {
            ATDPIForceAlphabeticKeyboard(field);
            NSLog(@"[AppToolsRatio] Switched DPI input to the alphabetic keyboard.");
        }
    };

    %orig(wrappedHandler);
}

%end
%end

__attribute__((constructor))
static void ATDPIAlphabeticKeyboardInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (![bundleID isEqualToString:@"com.apple.springboard"]) return;

        if (objc_getClass("UITextField") && objc_getClass("UIAlertController")) {
            %init(ATDPIAlphabeticKeyboard);
            NSLog(@"[AppToolsRatio] DPI keyboard hooks installed in SpringBoard.");
        }
    }
}
