@interface SBLockScreenViewControllerBase : NSObject
- (void)startLockScreenFadeInAnimationForSource:(int)arg1;
@end
@interface SBLockScreenManager : NSObject
+ (id)sharedInstance;
@property(readonly, nonatomic) SBLockScreenViewControllerBase *lockScreenViewController;
@end
@interface SBUserAgent : NSObject 
+ (id)sharedUserAgent;
- (void)undimScreen;
@end
@interface SpringBoard : UIApplication
- (BOOL)isLocked;
@end
@interface NSUserDefaults (wave) {
}
- (id)objectForKey:(id)key inDomain:(id)d;
@end
#include <IOKit/hid/IOHIDEventSystemClient.h>
#include <IOKit/hid/IOHIDEventSystem.h>

extern "C" {
	IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
	int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
	CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef, int);
	typedef struct __IOHIDServiceClient * IOHIDServiceClientRef;
	int IOHIDServiceClientSetProperty(IOHIDServiceClientRef, CFStringRef, CFNumberRef);

} 
static BOOL enable(void) {
    NSNumber *enable = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"enable" inDomain:@"com.broganminer.wave"];
    return (enable)? [enable boolValue]:YES;
}
static NSString *sens(void) {
    NSString *sens = (NSString *)[[NSUserDefaults standardUserDefaults] objectForKey:@"sensitivity" inDomain:@"com.broganminer.anchor"];
    return (sens)? sens:@"normal";
}
static BOOL waved;
static NSMutableArray *array = [[NSMutableArray alloc] init];

static IOHIDEventSystemClientRef ALSSystem;
static IOHIDServiceClientRef ALSService;
static CGFloat sensitivity = 0.45;
static void wake(void);
static void handleALS(void* target, void* refcon, IOHIDEventQueueRef queue, IOHIDEventRef event) {
	if (IOHIDEventGetType(event) == kIOHIDEventTypeAmbientLightSensor) { 
		int channel1 = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldAmbientLightSensorLevel); //get lux value
		
		/*average values from the light sensor because they come out weird sometimes*/
		[array addObject:[NSNumber numberWithInt:channel1]];
		while ([array count] > 5) {
			[array removeObjectAtIndex:0];
		}
		int lastBright = 0;
		for (NSNumber *n in array) {
			lastBright += [n intValue];
		}
		lastBright = lastBright/[array count];
		
		if (channel1 < (lastBright-lastBright*sensitivity) && !waved) {
			/*hand moves over sensor*/
			waved = YES;
		}
		else if (channel1 > (lastBright+lastBright*0.1) && waved) {
			waved = NO;
			/*wake screen, when hand leaves*/
			wake();
		}
	}
}

static void runALSListener(void) {
	if ([sens() isEqual:@"low"]) {
		sensitivity = 0.65;
	}
	else if ([sens() isEqual:@"high"]) {
		sensitivity = 0.3;
	}
	else {
		sensitivity = 0.45;
	}
	/*set page and usagepage of apropriate IOKit sensor, information available through ioreg (or most are on the iphonedevwiki)*/
	int page = 0xff00;
	int usage = 4;
	CFStringRef keys[2];
	CFNumberRef nums[2];
	keys[0] = CFStringCreateWithCString(0, "PrimaryUsagePage", 0);
	keys[1] = CFStringCreateWithCString(0, "PrimaryUsage", 0);
	nums[0] = CFNumberCreate(0, kCFNumberSInt32Type, &page);
	nums[1] = CFNumberCreate(0, kCFNumberSInt32Type, &usage);
	CFDictionaryRef dict = CFDictionaryCreate(0, (const void**)keys, (const void**)nums, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	/*create the system, have to use system client, wont return NULL if bundle ID != Springboards */
	ALSSystem = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
	/*Register system*/
	IOHIDEventSystemClientScheduleWithRunLoop(ALSSystem, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	IOHIDEventSystemClientRegisterEventCallback(ALSSystem, handleALS, NULL, NULL);
    IOHIDEventSystemClientSetMatching(ALSSystem,dict);
    CFArrayRef matchingsrvs = IOHIDEventSystemClientCopyServices(ALSSystem,0);
    /*create a service and change the update interval*/
    ALSService = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(matchingsrvs, 0);
 	int ri = 100000; //this is 10 ms
 	CFNumberRef interval = CFNumberCreate(CFAllocatorGetDefault(), kCFNumberIntType, &ri);
    IOHIDServiceClientSetProperty(ALSService,CFSTR("ReportInterval"),interval);
}

static void killALSListener(void) {
	/*change light sensor update interval back to normal*/
	int ri = 5428500;
 	CFNumberRef interval = CFNumberCreate(CFAllocatorGetDefault(), kCFNumberIntType, &ri);
    IOHIDServiceClientSetProperty(ALSService,CFSTR("ReportInterval"),interval);
    /*Unregister the calling of my functions and stop the system from running*/
	IOHIDEventSystemClientUnregisterEventCallback(ALSSystem);
	IOHIDEventSystemClientUnscheduleWithRunLoop(ALSSystem, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	/*release the system*/
	CFRelease(ALSSystem);
	ALSSystem = nil;
}

static void wake(void){
    //Make sure we animate properly
	[((SBLockScreenManager *)[%c(SBLockScreenManager) sharedInstance]).lockScreenViewController startLockScreenFadeInAnimationForSource:1];
	//undim the screen, with respect to the autodim timer
	[[%c(SBUserAgent) sharedUserAgent] undimScreen];


}
static void locked(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo){
	/*start the sesnor again on lock of the device*/
	if(!ALSSystem && enable())runALSListener();
}
%hook SBLockScreenViewController
/*Screen unlocked, stops running the light sensor*/
- (void)_releaseLockScreenView {
	%orig;
	if(![(SpringBoard *)[%c(SpringBoard) sharedApplication] isLocked]) {
		if(ALSSystem)killALSListener();
	}
}
%end

%ctor {
	/*starts light sensor at the springboard restart*/
	if(enable())runALSListener();
	/*register for screen locks*/
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (locked), CFSTR("com.apple.springboard.lockstate"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}