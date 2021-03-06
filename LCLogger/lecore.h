//
//  lecore.h
//  lelib
//
//  Created by Petr on 06.01.14.
//  Copyright (c) 2014 Logentries. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef lelib_lecore_h
#define lelib_lecore_h

#define TOKEN_LENGTH                    36
#define MAXIMUM_LOGENTRY_SIZE           8192

#define MAXIMUM_FILE_COUNT              3
#define MAXIMUM_LOGFILE_SIZE            (1024 * 1024)

extern void LE_DEBUG(NSString *format, ...);

/* Pure C API */

int le_init();
void le_handle_crashes(void);
void le_poke();
void le_log(const char* message);
void le_write_string(NSString* string);
void le_set_token(const char* token);
void le_set_endpoint(NSString* endpoint);
void le_set_debug_logs(bool verbose);
char* le_get_token();
#endif
