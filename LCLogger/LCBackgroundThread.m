//
//  LEBackgroundThread.m
//  lelib
//
//  Created by Petr on 25/11/13.
//  Copyright (c) 2013,2014 Logentries. All rights reserved.
//

#import "LCBackgroundThread.h"
#import "LCLogger.h"
#import "LogFiles.h"
#import "LCLog.h"
#import "LeNetworkStatus.h"

#define LOGENTRIES_HOST         @"data.logentries.com"
#define LOGENTRIES_USE_TLS      1
#if LOGENTRIES_USE_TLS
#define LOGENTRIES_PORT         443
#else
#define LOGENTRIES_PORT         80
#endif

#define RETRY_TIMEOUT           60.0
#define KEEPALIVE_INTERVAL      3600.0


@interface LCBackgroundThread()<NSStreamDelegate, LeNetworkStatusDelegete> {
    
    uint8_t output_buffer[MAXIMUM_LOGENTRY_SIZE];
    size_t output_buffer_position;
    size_t output_buffer_length;
    long file_position;
}

@property (nonatomic, assign) FILE* inputFile;
@property (nonatomic, strong) NSTimer* retryTimer;
@property (nonatomic, strong) LeNetworkStatus* networkStatus;

@property (nonatomic, strong) LogFile* currentLogFile;

// when different from currentLogFile.orderNumber, try to finish sending of current log entry and move to the file
@property (nonatomic, assign) NSInteger lastLogFileNumber;

// TRUE when last written character was '\n'
@property (nonatomic, assign) BOOL logentryCompleted;

@end

@implementation LCBackgroundThread

- (void)initNetworkCommunication
{
    
}

- (void)checkConnection
{
    if (self.retryTimer) {
        [self.retryTimer invalidate];
        self.retryTimer = nil;
    }

    if (self.networkStatus) {
        self.networkStatus.delegate = nil;
        self.networkStatus = nil;
    }
    
    [self check];
}

- (void)networkStatusDidChange:(LeNetworkStatus *)networkStatus
{
    if ([networkStatus connected]) {
        LE_DEBUG(@"Network status available");
        [self checkConnection];
    }
}

- (void)retryTimerFired:(NSTimer* __attribute__((unused)))timer
{
    LE_DEBUG(@"Retry timer fired");
    [self checkConnection];
}

- (void)stream:(NSStream * __attribute__((unused)))aStream handleEvent:(NSStreamEvent)eventCode
{
    if (eventCode & NSStreamEventOpenCompleted) {
        LE_DEBUG(@"Socket event NSStreamEventOpenCompleted");
        eventCode = (NSStreamEvent)(eventCode & ~NSStreamEventOpenCompleted);
        self.logentryCompleted = YES;
    }
    
    if (eventCode & NSStreamEventErrorOccurred) {
        LE_DEBUG(@"Socket event NSStreamEventErrorOccurred, scheduling retry timer");
        
        self.networkStatus = [LeNetworkStatus new];
        self.networkStatus.delegate = self;

        self.retryTimer = [NSTimer scheduledTimerWithTimeInterval:RETRY_TIMEOUT target:self selector:@selector(retryTimerFired:) userInfo:nil repeats:NO];
    }
    
    if (eventCode & NSStreamEventHasSpaceAvailable) {
        
        LE_DEBUG(@"Socket event NSStreamEventHasSpaceAvailable");
        eventCode = (NSStreamEvent)(eventCode & ~NSStreamEventHasSpaceAvailable);
        
        [self check];
    }

    if (eventCode) LE_DEBUG(@"Received event %x", (unsigned int)eventCode);
}

- (void)readNextData
{
    output_buffer_position = 0;

    if (feof(self.inputFile)) clearerr(self.inputFile); // clears EOF indicator
    size_t read = fread(output_buffer, 1, MAXIMUM_LOGENTRY_SIZE, self.inputFile);
    if (!read) {
        if (ferror(self.inputFile)) {
            LE_DEBUG(@"Error reading logfile");
        }
        return;
    }
    
    output_buffer_length = read;
}

// do we need to ove to another file, are we late?
- (BOOL)shouldSkipToAnotherFile
{
    NSInteger oldestInterrestingFileNumber = self.lastLogFileNumber - MAXIMUM_FILE_COUNT + 1;
    return (self.currentLogFile.orderNumber < oldestInterrestingFileNumber);
}

- (BOOL)openLogFile:(LogFile*)logFile
{
    LE_DEBUG(@"Will open file %ld", (long)logFile.orderNumber);
    NSString* path = [logFile logPath];
    self.inputFile = fopen([path cStringUsingEncoding:NSUTF8StringEncoding], "r");
    if (!self.inputFile) {
        LE_DEBUG(@"Failed to open log file.");
        self.currentLogFile = nil;
        return FALSE;
    }
    
    file_position = logFile.bytesProcessed;
    int r = fseek(self.inputFile, file_position, SEEK_SET);
    if (r) {
        LE_DEBUG(@"File seek error.");
        file_position = 0;
    } else {
        LE_DEBUG(@"Seeked to position %ld", file_position);
    }
    
    self.currentLogFile = logFile;
    return TRUE;
}

/* 
 Remove current file and move to another one given by self.lastFileLogNumber and self.currentLogFile
 */
- (BOOL)skip
{
    LE_DEBUG(@"Will skip, current file number is %ld", (long)self.currentLogFile.orderNumber);
    output_buffer_length = 0;
    output_buffer_position = 0;
    fclose(self.inputFile);
    [self.currentLogFile remove];
    
    NSInteger next = self.currentLogFile.orderNumber + 1;
    
    // remove skipped files
    while (next + MAXIMUM_FILE_COUNT <= self.lastLogFileNumber) {
        
        LogFile* logFileToDelete = [[LogFile alloc] initWithNumber:next];
        LE_DEBUG(@"Removing skipped file %ld", (long)logFileToDelete.orderNumber);
        [logFileToDelete remove];
        next++;
    }

    LogFile* logFile = [[LogFile alloc] initWithNumber:next];
    BOOL opened = [self openLogFile:logFile];
    
    if (!opened) {
        return FALSE;
    }
    
    LE_DEBUG(@"Did skip, current file number is %ld", (long)self.currentLogFile.orderNumber);
    return TRUE;
}

- (void)check
{
    LE_DEBUG(@"Checking status");
    if (!self.currentLogFile) {
        LE_DEBUG(@"Trying to open a log file");
        BOOL fixed = [self initializeInput];
        if (!fixed) {
            LE_DEBUG(@"Can't open input file");
            return;
        }
    }
    
    if (self.logentryCompleted && [self shouldSkipToAnotherFile]) {
        LE_DEBUG(@"Logentry completed and should skip to another file");
        BOOL skipped = [self skip];
        if (!skipped) {
            LE_DEBUG(@"Can't skip to next input file");
            return;
        }
    }
    
    // check if there is something to send out
    if (output_buffer_position >= output_buffer_length) {
        
        LE_DEBUG(@"Buffer empty, will read data");
        [self readNextData];
        LE_DEBUG(@"Read %ld bytes", (long)output_buffer_length);
        
        if (!output_buffer_length) {
            
            if (self.currentLogFile.orderNumber == self.lastLogFileNumber) {
                LE_DEBUG(@"Nothing to do, finished");
                LE_DEBUG(@"|");
                return;
            }
                
            LE_DEBUG(@"Skip to another file");
            [self skip];
            [self readNextData];
            if (!output_buffer_length) {
                LE_DEBUG(@"Failed to read data from just opened file");
                return;
            }
        }
    }


    NSUInteger maxLength = output_buffer_length - output_buffer_position;
    
    // truncate maxLength if we need to move to another file
    if ([self shouldSkipToAnotherFile]) {
        
        NSUInteger i = 0;
        while (i < maxLength) {
            if (output_buffer[output_buffer_position + i] == '\n') {
                maxLength = i + 1;
                break;
            }
            i++;
        }
    }
    
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.endpoint]];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithCString:le_get_token() encoding:NSUTF8StringEncoding] forHTTPHeaderField:@"X-LOGCENTRAL-TOKEN"];
    [req setHTTPBody:[NSData dataWithBytes:output_buffer length:output_buffer_length]];
    
    NSURLResponse *res;
    NSError *err;
    [NSURLConnection sendSynchronousRequest:req returningResponse:&res error:&err];
    
    NSInteger written = 0;
    if (!err) {
        written=(NSInteger)output_buffer_length;
    }else{
        LE_DEBUG(@"Upload Fail:%@,%@",err,res);
    }
    
    /*
    for (int i = 0; i < written; i++) {
        char c = output_buffer[output_buffer_position + i];
        LE_DEBUG(@"written '%c' (%02x)", c, c);
    }
 */
    
    if (written > 0) {
        self.logentryCompleted = output_buffer[output_buffer_position + (NSUInteger)written - 1] == '\n';
    };
    
    if (self.logentryCompleted && [self shouldSkipToAnotherFile]) {
        [self skip];
        return;
    }
    
    // search for checkpoints
    NSInteger searchIndex = written - 1;
    while (searchIndex >= 0) {
        uint8_t c = output_buffer[output_buffer_position + (NSUInteger)searchIndex];
        if (c == '\n') {
            [self.currentLogFile markPosition:file_position + searchIndex + 1];
            break;
        }
        searchIndex--;
    }
    
    file_position += written;
    
    output_buffer_position += (NSUInteger)written;
    if (output_buffer_position >= output_buffer_length) {
        output_buffer_length = 0;
        output_buffer_position = 0;
        
        // check for another data to send out
        LE_DEBUG(@"Buffer written, will check for another data");
        [self check];
    }
}

- (void)keepaliveTimer:(NSTimer* __attribute__((unused)))timer
{
    // does nothing, just keeps runloop running
}

- (BOOL)initializeInput
{
    if (self.inputFile) return YES;
    
    LE_DEBUG(@"Opening input file");
    LogFiles* logFiles = [LogFiles new];
    
    LogFile* logFile = [logFiles fileToRead];
    BOOL opened = [self openLogFile:logFile];
    return opened;
}

- (void)initialize:(NSTimer* __attribute__((unused)))timer
{
    [self.initialized lock];
    [self.initialized broadcast];
    [self.initialized unlock];
    self.initialized = nil;
}

- (void)poke:(NSNumber*)fileOrderNumber
{
    self.lastLogFileNumber = [fileOrderNumber integerValue];
    [self check];
}

- (void)main
{
    @autoreleasepool {
        NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
        
        // this timer will fire after runloop is ready
        [NSTimer scheduledTimerWithTimeInterval:0.0 target:self selector:@selector(initialize:) userInfo:nil repeats:NO];
        
        // the runloop needs an input source to keep it running, we will provide dummy timer
        [NSTimer scheduledTimerWithTimeInterval:KEEPALIVE_INTERVAL target:self selector:@selector(keepaliveTimer:) userInfo:nil repeats:YES];

        [runLoop run];
    }
}


@end
