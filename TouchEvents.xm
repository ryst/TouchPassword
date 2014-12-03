#define TouchIDFingerDown	1
#define TouchIDFingerUp		0
#define TouchIDFingerHeld	2
#define TouchIDMatched		3
#define TouchIDNotMatched	9

@protocol BiometricKitDelegate <NSObject>
@end

@protocol SBUIBiometricEventMonitorDelegate
@required
-(void)biometricEventMonitor:(id)monitor handleBiometricEvent:(unsigned)event;
@end

@interface SBUIBiometricEventMonitor : NSObject <BiometricKitDelegate>
+(id)sharedInstance;
-(void)removeObserver:(id)arg1;
-(void)addObserver:(id)arg1;
-(void)_setMatchingEnabled:(_Bool)arg1;
-(void)_stopMatching;
-(void)_startMatching;
-(void)setMatchingDisabled:(_Bool)arg1 requester:(id)arg2;
-(_Bool)isMatchingEnabled;
@end

@interface BiometricKit : NSObject <BiometricKitDelegate>
+(id)manager;
@end

@interface TouchPasswordController : NSObject <SBUIBiometricEventMonitorDelegate> {
	BOOL _wasMatching;
	id _monitorDelegate;
	NSArray *_monitorObservers;
	BOOL isMonitoringEvents;
}
@end

static TouchPasswordController* controller;

@implementation TouchPasswordController
-(void)biometricEventMonitor:(id)monitor handleBiometricEvent:(unsigned)event {
	if (event == TouchIDMatched) {
		// positive match!
		[NSObject cancelPreviousPerformRequestsWithTarget:controller
			selector:@selector(monitoringTimeout) object:nil];
		[self stopMonitoringEvents];

		// Send OK to app to save/retrieve password.
		CFNotificationCenterPostNotification(
			CFNotificationCenterGetDarwinNotifyCenter(), // center
			CFSTR("com.ryst.touchpassword.matched"), // event name
			NULL, // object
			NULL, // userInfo,
			false);
	}
}

-(void)startMonitoringEvents
{
	if (isMonitoringEvents) {
		return;
	}
	isMonitoringEvents = YES;

	SBUIBiometricEventMonitor* monitor = [%c(SBUIBiometricEventMonitor) sharedInstance];

	// Save and replace delegate.
	_monitorDelegate = [[%c(BiometricKit) manager] delegate];
	[[%c(BiometricKit) manager] setDelegate:monitor];

	// Save the matching state.
	_wasMatching = [[monitor valueForKey:@"_matchingEnabled"] boolValue];

	// Remember and remove existing observers.
	_monitorObservers = [[monitor valueForKey:@"observers"] copy];
	for (int i = 0; i < _monitorObservers.count; i++) {
		[monitor removeObserver:[[monitor valueForKey:@"observers"] anyObject]];
	}

	// Add ourself as an observer and enable matching.
	[monitor addObserver:self];
	[monitor _setMatchingEnabled:YES];
	[monitor _startMatching];
}

-(void)stopMonitoringEvents {
	if (!isMonitoringEvents) {
		return;
	}

	SBUIBiometricEventMonitor *monitor = [[%c(BiometricKit) manager] delegate];

	// Remove ourself as observer and restore existing observers.
	[monitor removeObserver:self]; 
	for (id observer in _monitorObservers) {
		[monitor addObserver:observer];
	}

	// Restore matching state and delegate.
	[monitor _setMatchingEnabled:_wasMatching];
	[[%c(BiometricKit) manager] setDelegate:_monitorDelegate];

	isMonitoringEvents = NO;
}

-(void)monitoringTimeout {
	[self stopMonitoringEvents];

	CFNotificationCenterPostNotification(
		CFNotificationCenterGetDarwinNotifyCenter(), // center
		CFSTR("com.ryst.touchpassword.matchingTimeout"), // event name
		NULL, // object
		NULL, // userInfo,
		false);
}
@end

%group SpringBoardHooks

void receivedSBNotification(CFNotificationCenterRef center, void* observer, CFStringRef name, const void* object, CFDictionaryRef userInfo) {

	NSString* notificationName = (NSString*)name;

	if ([notificationName isEqualToString:@"com.ryst.touchpassword.startMatching"]) {
		[NSObject cancelPreviousPerformRequestsWithTarget:controller
			selector:@selector(monitoringTimeout) object:nil];
		[controller startMonitoringEvents];
		[controller performSelector:@selector(monitoringTimeout) withObject:nil afterDelay:5.0];
	} else if ([notificationName isEqualToString:@"com.ryst.touchpassword.stopMatching"]) {
		[NSObject cancelPreviousPerformRequestsWithTarget:controller
			selector:@selector(monitoringTimeout) object:nil];
		[controller stopMonitoringEvents];
	}
}

%hook SpringBoard
-(void)applicationDidFinishLaunching:(id)application {
	%orig;

	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), // center
		self, // observer
		receivedSBNotification, // callback
		CFSTR("com.ryst.touchpassword.startMatching"), // event name
		NULL, // object
		CFNotificationSuspensionBehaviorDeliverImmediately);

	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), // center
		self, // observer
		receivedSBNotification, // callback
		CFSTR("com.ryst.touchpassword.stopMatching"), // event name
		NULL, // object
		CFNotificationSuspensionBehaviorDeliverImmediately);
}
%end

%end // group SpringBoardHooks

%ctor {
	if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
		controller = [[TouchPasswordController alloc] init];
		%init(SpringBoardHooks);
	}
}

