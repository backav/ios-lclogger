//
//  LELog.m
//  lelib
//
//  Created by Petr on 25/11/13.
//  Copyright (c) 2013,2014 Logentries. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "LCLog.h"
#import "LCBackgroundThread.h"
#import "LogFiles.h"
#import "LCLogger.h"


extern LCBackgroundThread* backgroundThread;

extern dispatch_queue_t le_write_queue;
extern char* le_token;

@interface LCLogger(){
    NSString *logOpen;// YES for True
}
@end

@implementation LCLogger

- (id)init
{
    self = [super init];
    if (le_init()) return nil;
    
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(notificationReceived:) name:UIApplicationWillEnterForegroundNotification object:nil];

    le_poke();

    return self;
}

- (void)dealloc
{
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)log:(NSObject*)object
{
    
   
    
    NSString* text = nil;
    
    if ([object respondsToSelector:@selector(leDescription)]) {
        id<LELoggableObject> leLoggableObject = (id<LELoggableObject>)object;
        text = [leLoggableObject leDescription];
    } else if ([object isKindOfClass:[NSString class]]) {
        text = (NSString*)object;
    } else {
        text = [object description];
    }
    
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"\u2028"];

    LE_DEBUG(@"%@", text);
    
    le_write_string(text);
    
    if ([self log_allowed]) {
        le_poke();
    }
}

-(bool)log_allowed
{
    if (self.switchURL) {
        if ([@"NO" isEqualToString:logOpen]) {
            return NO;
        }
        if ([@"CHECKING" isEqualToString:logOpen]) {
            return NO;
        }
        
        if (!logOpen) {
            
            __weak LCLogger *weakSelf=self;
            NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.switchURL]];
            [req setValue:[NSString stringWithCString:le_get_token() encoding:NSUTF8StringEncoding] forHTTPHeaderField:@"X-LOGCENTRAL-TOKEN"];
            [NSURLConnection sendAsynchronousRequest:req queue:[[NSOperationQueue alloc] init] completionHandler:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
                __strong LCLogger *strongSelf=weakSelf;
                if (!connectionError) {
                    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
                    if (httpResponse.statusCode==200) {
                        strongSelf->logOpen=@"YES";
                        return;
                    }
                }
                strongSelf->logOpen=@"NO";
                
            }];
            logOpen=@"CHECKING";
            return NO;
        }
    }
    
    return YES;
}

+ (void)log:(NSObject *)object{
    
    [[self sharedInstance] log:object];
}
+ (LCLogger*)sharedInstance
{
    static dispatch_once_t once;
    static LCLogger* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [LCLogger new];
    });
    return sharedInstance;
}
+(LCLogger*)sessionWithToken:(NSString*)token endpoint:(NSString *)endpoint{
    
    le_set_endpoint(endpoint);
    LCLogger * leLog = [self sharedInstance];
    [leLog setToken:token];
    return leLog;
}
- (void)setToken:(NSString *)token
{
    le_set_token([token cStringUsingEncoding:NSUTF8StringEncoding]);
}

- (void)setDebugLogs:(BOOL)debugLogs
{
    le_set_debug_logs(debugLogs);
}

- (NSString*)token
{
    __block NSString* r = nil;
    dispatch_sync(le_write_queue, ^{
        
        if (!le_token || le_token[0]) {
            r = nil;
        } else {
            r = [NSString stringWithUTF8String:le_token];
        }
    });
    
    return r;
}

- (void)notificationReceived:(NSNotification*)notification
{
    if ([notification.name isEqualToString:UIApplicationWillEnterForegroundNotification]) {
        
        if (self.logApplicationLifecycleNotifications) {
            [self log:notification.name];
        }
        
        le_poke();
        
        return;
    }
    
    if ([notification.name isEqualToString:UIApplicationDidBecomeActiveNotification]) {
        [self log:notification.name];
        return;
    }
    
    if ([notification.name isEqualToString:UIApplicationWillResignActiveNotification]) {
        [self log:notification.name];
        return;
    }
    
    if ([notification.name isEqualToString:UIApplicationDidFinishLaunchingNotification]) {
        [self log:notification.name];
        return;
    }

    if ([notification.name isEqualToString:UIApplicationWillTerminateNotification]) {
        [self log:notification.name];
        return;
    }

    if ([notification.name isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
        [self log:notification.name];
        return;
    }
    
    if ([notification.name isEqualToString:UIApplicationDidReceiveMemoryWarningNotification]) {
        [self log:notification.name];
        return;
    }
}

- (void)registerForNotifications
{
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    
    [center addObserver:self selector:@selector(notificationReceived:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(notificationReceived:) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(notificationReceived:) name:UIApplicationDidFinishLaunchingNotification object:nil];
    [center addObserver:self selector:@selector(notificationReceived:) name:UIApplicationWillTerminateNotification object:nil];
    [center addObserver:self selector:@selector(notificationReceived:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(notificationReceived:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

- (void)unregisterFromNotifications
{
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [center removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [center removeObserver:self name:UIApplicationDidFinishLaunchingNotification object:nil];
    [center removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
    [center removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

- (void)setLogApplicationLifecycleNotifications:(BOOL)logApplicationLifecycleNotifications
{
    @synchronized(self) {

        if (logApplicationLifecycleNotifications == _logApplicationLifecycleNotifications) return;
        
        _logApplicationLifecycleNotifications = logApplicationLifecycleNotifications;
        
        if (logApplicationLifecycleNotifications) {
            [self registerForNotifications];
        } else {
            [self unregisterFromNotifications];
        }
    }
}


@end
