#include "STUtils/STUtils.h"

@interface UIKeyboardImpl : UIView;
+(id)activeInstance;
@property(assign, nonatomic) UIResponder<UIKeyInput>* delegate;
-(id)textInputTraits;
@end

@interface DOMNode : NSObject;
-(id)text;
-(void)setText:(id)text;
-(id)uiWebDocumentView;
@end

@interface BrowserController
+(id)sharedBrowserController;
-(id)tabController;
@end

@interface TabDocument
-(NSString*)URLString;
@end

@interface TabController
@property(retain, nonatomic) TabDocument* activeTabDocument;
@end

@interface UIWebDocumentView
-(id)_documentUrl;
@end

@interface WKWebView
-(void)evaluateJavaScript:(id)script completionHandler:(id)handler;
@end

@interface WKContentView
-(BOOL)hasContent;
-(id)_moveToEndOfDocument:(BOOL)arg1 withHistory:(id)arg2;
@end

#define NSEC_IN_SEC 1000000000

static bool skipCallChanged = NO;
static bool addedObservers = NO;
static bool isMatching = NO;
static NSMutableArray* firstPasswords = [NSMutableArray arrayWithCapacity:3];
static NSMutableArray* secondPasswords = [NSMutableArray arrayWithCapacity:3];

NSString* getHostname(id inputField) {
	NSString* hostname;
	if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.mobilesafari"]) {
		BrowserController* browser = [%c(BrowserController) sharedBrowserController];
		TabController* tabs = [browser tabController];
		TabDocument* activeTab = [tabs activeTabDocument];
		hostname = [[NSURL URLWithString:[activeTab URLString]] host];
	} else if (inputField && [inputField isKindOfClass:%c(UIThreadSafeNode)]) {
		DOMNode* node = MSHookIvar<DOMNode*>(inputField, "_node");
		UIWebDocumentView* webView = [node uiWebDocumentView];
		NSURL* url = [webView _documentUrl];
		hostname = [url host];
		if (hostname == nil) {
			hostname = @"";
		}
	} else {
		hostname = @"";
	}

	return hostname;
}

NSString* getPassword(id inputField) {
	NSString* hostname = getHostname(inputField);
	NSString* password = [STKeychain getPasswordForUsername:@"TouchPassword" andServiceName:hostname error:nil];

	return password;
}

void savePassword(NSString* password, id inputField) {
	NSString* hostname = getHostname(inputField);
	[STKeychain storeUsername:@"TouchPassword" andPassword:password forServiceName:hostname updateExisting:YES error:nil];
}

void pastePassword(id inputField, NSString* password) {
	UIPasteboard* pb = [UIPasteboard generalPasteboard];
	NSString* oldPasteText = [pb string];
	[pb setString:password];
	[inputField paste:inputField];
	[pb setString:oldPasteText];
}

id getInputField(bool mustBeSecure) {
	UIKeyboardImpl* keyboard = [UIKeyboardImpl activeInstance];
	if (keyboard == nil) {
		return nil;
	}

	id inputField = keyboard.delegate;
	if (!mustBeSecure) {
		return inputField;
	} else {
		if (inputField && [inputField respondsToSelector:@selector(textInputTraits)]) {
			UITextInputTraits* traits = [inputField textInputTraits];
			if ([traits isSecureTextEntry]) {
				return inputField;
			}
		}
	}

	return nil;
}

void saveWKContentViewPassword(bool firstPass) {
	id inputField = getInputField(YES);
	if (inputField == nil)
		return;

	if (![inputField isKindOfClass:%c(WKContentView)])
		return;

	NSString *passwordJs = @"var passwords=[]; for(var z=document.getElementsByTagName(\"input\"),x=z.length;x--;){if(z[x].type===\"password\")passwords.push(z[x].value);} passwords; ";

	WKWebView* webView = MSHookIvar<WKWebView*>(inputField, "_webView");

	[webView evaluateJavaScript:passwordJs completionHandler:^(NSString* result, NSError* error) {
		if (firstPass) {
			[firstPasswords removeAllObjects];
			[secondPasswords removeAllObjects];

			[firstPasswords addObjectsFromArray:(NSArray*)result];

			[inputField _moveToEndOfDocument:YES withHistory:nil];

			int longest = 0;
			for (NSString* word in firstPasswords) {
				if ([word length] > longest) {
					longest = [word length];
				}
			}

			while (longest-- > 0) {
				[inputField deleteBackward];
			}
		
			saveWKContentViewPassword(NO);
		} else {
			[secondPasswords addObjectsFromArray:(NSArray*)result];

			// Find which password changed
			for (int i = 0; i < [firstPasswords count]; i++) {
				NSString* first = [firstPasswords objectAtIndex:i];
				NSString* second = [secondPasswords objectAtIndex:i];

				if (![first isEqualToString:@""] && [second isEqualToString:@""]) {
					savePassword(first, inputField);
					skipCallChanged = YES;
					[inputField performSelector:@selector(insertText:) withObject:first afterDelay:0.25];

					break;
				}
			}
		}
	}];
}

void receivedNotification(CFNotificationCenterRef center, void* observer, CFStringRef name, const void* object, CFDictionaryRef userInfo) {

    NSString* notificationName = (NSString*)name;

    if ([notificationName isEqualToString:@"com.ryst.touchpassword.matchingTimeout"]) {
		isMatching = NO;

    } else if ([notificationName isEqualToString:@"com.ryst.touchpassword.matched"]) {

		if (!isMatching) {
			return;
		}

		isMatching = NO;

		id inputField = getInputField(YES);
		if (inputField == nil) {
			return;
		}

		NSString* text;

		if ([inputField isKindOfClass:%c(UIThreadSafeNode)]) {
			DOMNode* node = MSHookIvar<DOMNode*>(inputField, "_node");
			text = [node text];
			if ([text isEqualToString:@""]) {
				// retrieve the password
				NSString* password = getPassword(inputField);
				NSUInteger length = [password length];
				if (length > 0) {
					skipCallChanged = YES;
					[node setText:password];
				}
			} else {
				// save the password
				savePassword(text, inputField);
				skipCallChanged = YES;
				[node setText:@""];
				[node performSelector:@selector(setText:) withObject:text afterDelay:0.25];
			}
		} else if ([inputField isKindOfClass:%c(WKContentView)]) {
			if ([inputField hasContent]) {

				saveWKContentViewPassword(YES);

			} else {
				// retrieve the password
				NSString* password = getPassword(inputField);
				NSUInteger length = [password length];
				if (length > 0) {
					skipCallChanged = YES;
					[inputField insertText:password];
				}
			}

		} else {
			// Regular text field
			UITextRange* fullRange = [inputField
				textRangeFromPosition:[inputField beginningOfDocument]
				toPosition:[inputField endOfDocument]];
			text = [inputField textInRange:fullRange];

			if ([text isEqualToString:@""]) {
				// retrieve the password
				NSString* password = getPassword(inputField);
				NSUInteger length = [password length];
				if (length > 0) {
					skipCallChanged = YES;
					pastePassword(inputField, password);
				}
			} else if (text && [text length] > 0) {
				// save the password
				savePassword(text, inputField);
				skipCallChanged = YES;
				[inputField replaceRange:fullRange withText:@""];
				[inputField performSelector:@selector(insertText:) withObject:text afterDelay:0.25];
			}
		}

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_IN_SEC),
			dispatch_get_main_queue(),
			^(void) {
				skipCallChanged = NO;
		});
    }
}

void startMatching() {
	if (!addedObservers) {
		// Add observer
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), // center
			nil, // observer
			receivedNotification, // callback
			CFSTR("com.ryst.touchpassword.matched"), // event name
			NULL, // object
			CFNotificationSuspensionBehaviorDrop);

		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), // center
			nil, // observer
			receivedNotification, // callback
			CFSTR("com.ryst.touchpassword.matchingTimeout"), // event name
			NULL, // object
			CFNotificationSuspensionBehaviorDrop);

		addedObservers = YES;
	}

	// Post notification to start matching
	CFNotificationCenterPostNotification(
		CFNotificationCenterGetDarwinNotifyCenter(), // center
		CFSTR("com.ryst.touchpassword.startMatching"), // event name
		NULL, // object
		NULL, // userInfo,
		false);

	isMatching = YES;
}

void stopMatching() {
	if (!isMatching) {
		return;
	}

	// Post notification to stop matching
	CFNotificationCenterPostNotification(
		CFNotificationCenterGetDarwinNotifyCenter(), // center
		CFSTR("com.ryst.touchpassword.stopMatching"), // event name
		NULL, // object
		NULL, // userInfo,
		false);

	isMatching = NO;
}

%hook UIKeyboardLayoutStar
-(void)showKeyboardWithInputTraits:(id)inputTraits screenTraits:(id)screenTraits splitTraits:(id)splitTraits {
	%orig;

	if ([inputTraits isSecureTextEntry]) {
		startMatching();
	}
}

// This is only necessary because of some app (I think it was ZipCar) where the password text field
// wasn't a secure entry field until *after* the keyboard appeared!
-(void)restoreDefaultsForAllKeys {
	%orig;

	// Set a timeout to check the input field.
	// The restoreDefaultsForAllKeys is called several times whenever the keyboard is shown,
	// so the idea here is to test the input field after the last call.
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(TP_testInputTraits) object:nil];
	[self performSelector:@selector(TP_testInputTraits) withObject:nil afterDelay:0.2];
}

-(void)deactivateActiveKeys {
	%orig;

	stopMatching();
}

%new
-(void)TP_testInputTraits {
	if (skipCallChanged) {
		return;
	}

	id inputField = getInputField(YES);
	if (inputField) {
		startMatching();
	}
}
%end

%hook UIKeyboardImpl
-(void)callChanged {
	%orig;

	if (skipCallChanged) {
		return;
	}

	UITextInputTraits* traits = [self textInputTraits];
	if ([traits isSecureTextEntry]) {
		if (self.delegate && [self.delegate conformsToProtocol:@protocol(UITextInput)]) {
			if ([self.delegate isKindOfClass:[%c(SBUIPasscodeTextField) class]]) {
				return; // Don't support this type!
			}

			// Send a notification to SpringBoard to listen for Touch ID match.
			// Delay by 0.5s in case user is typing fast.
			[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(TP_startMatching) object:nil];
			[self performSelector:@selector(TP_startMatching) withObject:nil afterDelay:0.5];
		}
	}
}

%new
-(void)TP_startMatching {
	startMatching();
}
%end

