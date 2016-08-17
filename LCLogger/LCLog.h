//
//  LELog.h
//  lelib
//
//  Created by Petr on 25/11/13.
//  Copyright (c) 2013,2014 Logentries. All rights reserved.
//

#import <Foundation/Foundation.h>

/* Obj-C API */

@protocol LELoggableObject <NSObject>

@optional

- (NSString*)leDescription;

@end

@interface LCLogger : NSObject

+ (LCLogger*)sharedInstance;

+ (LCLogger*)sessionWithToken:(NSString*)token endpoint:(NSString*)endpoint;
/*
 Display all messages on TTY for debug purposes
 */
@property (nonatomic) BOOL debugLogs;

/*
 Appends space separated token to each log message.
 */
@property (atomic, copy) NSString* token;
@property (atomic, copy) NSString* switchURL;

/*
 When object implements LELoggableObject interface, it logs return value of
 leDescription method. Otherwise, tries to log return value of standard
 description method.
 */
- (void)log:(NSObject*)object;

+ (void)log:(NSObject*)object;

/*
 Log UIApplicationDidFinishLaunchingNotification, UIApplicationDidBecomeActiveNotification,
 UIApplicationWillEnterForegroundNotification, UIApplicationWillResignActiveNotification,
 UIApplicationWillTerminateNotification.
 */
@property (nonatomic, assign) BOOL logApplicationLifecycleNotifications;

@end



