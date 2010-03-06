//  trash.m
//
//  Created by Ali Rantakari
//  http://hasseg.org
//

/*
The MIT License

Copyright (c) 2010 Ali Rantakari

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/


#include <AppKit/AppKit.h>
#include <ScriptingBridge/ScriptingBridge.h>
#import <libgen.h>


const int VERSION_MAJOR = 0;
const int VERSION_MINOR = 5;
const int VERSION_BUILD = 0;

BOOL arg_verbose = NO;



// helper methods for printing to stdout and stderr

// other Printf functions call this, and you call them
void RealPrintf(NSString *aStr, va_list args)
{
	NSString *str = [
		[[NSString alloc]
			initWithFormat:aStr
			locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]
			arguments:args
			] autorelease
		];
	
	[str writeToFile:@"/dev/stdout" atomically:NO encoding:NSUTF8StringEncoding error:NULL];
}

void VerbosePrintf(NSString *aStr, ...)
{
	if (!arg_verbose)
		return;
	va_list argList;
	va_start(argList, aStr);
	RealPrintf(aStr, argList);
	va_end(argList);
}

void Printf(NSString *aStr, ...)
{
	va_list argList;
	va_start(argList, aStr);
	RealPrintf(aStr, argList);
	va_end(argList);
}

void PrintfErr(NSString *aStr, ...)
{
	va_list argList;
	va_start(argList, aStr);
	NSString *str = [
		[[NSString alloc]
			initWithFormat:aStr
			locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]
			arguments:argList
			] autorelease
		];
	va_end(argList);
	
	[str writeToFile:@"/dev/stderr" atomically:NO encoding:NSUTF8StringEncoding error:NULL];
}




int emptyTrash(BOOL securely)
{
	SBApplication *finder = [SBApplication applicationWithBundleIdentifier:@"com.apple.Finder"];
	id trash = [finder performSelector:@selector(trash)];
	
	NSUInteger trashItemsCount = [[trash items] count];
	if (trashItemsCount == 0)
	{
		Printf(@"The trash is already empty.\n");
		return 0;
	}
	
	BOOL plural = (trashItemsCount > 1);
	Printf(
		@"There %@ currently %i item%@ in the trash.\nAre you sure you want to permanantly%@ delete %@ item%@?\n",
		plural?@"are":@"is",
		trashItemsCount,
		plural?@"s":@"",
		securely?@" (and securely)":@"",
		plural?@"these":@"this",
		plural?@"s":@""
		);
	
	Printf(@"[y/N]: ");
	char inputChar;
	scanf("%s&*c",&inputChar);
	
	if (inputChar != 'y' && inputChar != 'Y')
		return 1;
	
	[trash setWarnsBeforeEmptying:NO];
	[trash emptySecurity:securely];
	
	return 0;
}

void listTrashContents()
{
	SBApplication *finder = [SBApplication applicationWithBundleIdentifier:@"com.apple.Finder"];
	id trash = [finder performSelector:@selector(trash)];
	
	for (id item in [trash items])
	{
		Printf(@"%@\n", [[NSURL URLWithString:(NSString *)[item URL]] path]);
	}
}



OSStatus moveFileToTrash(NSString *filePath)
{
	// We use FSMoveObjectToTrashSync() directly instead of
	// using NSWorkspace's performFileOperation:... (which
	// uses FSMoveObjectToTrashSync()) because the former
	// returns us an OSStatus describing a possible error
	// and the latter only returns a BOOL describing success
	// or failure.
	// 
	
	if (filePath == nil)
		return bdNamErr;
	
	FSRef fsRef;
	FSPathMakeRefWithOptions(
		(const UInt8 *)[filePath fileSystemRepresentation],
		kFSPathMakeRefDoNotFollowLeafSymlink,
		&fsRef,
		NULL // Boolean *isDirectory
		);
	
	OSStatus ret = FSMoveObjectToTrashSync(&fsRef, NULL, kFSFileOperationDefaultOptions);
	VerbosePrintf(@"%@\n", filePath);
	return ret;
}


NSString *osStatusToErrorString(OSStatus status)
{
	// GetMacOSStatusCommentString() generally shouldn't be used
	// to provide error messages to users but using it is much better
	// than manually writing a long switch statement and typing up
	// the error messages -- the messages returned by this function
	// are 'good enough' for this program's supposed users.
	// 
	return [[NSString stringWithUTF8String:GetMacOSStatusCommentString(status)]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}


NSString* versionNumberStr()
{
	return [NSString stringWithFormat:@"%d.%d.%d", VERSION_MAJOR, VERSION_MINOR, VERSION_BUILD];
}

char *myBasename;
void printUsage()
{
	Printf(@"usage: %s [-vles] <file> [<file> ...]\n", myBasename);
	Printf(@"\n");
	Printf(@"  Move files/folders to the trash.\n");
	Printf(@"\n");
	Printf(@"  Options:\n");
	Printf(@"\n");
	Printf(@"  -v  Be verbose; show files as they are deleted\n");
	Printf(@"  -l  List items currently in trash\n");
	Printf(@"  -e  Empty trash (asks for confirmation)\n");
	Printf(@"  -s  Empty trash securely (asks for confirmation)\n");
	Printf(@"\n");
	Printf(@"Version %@\n", versionNumberStr());
	Printf(@"Copyright (c) 2010 Ali Rantakari, http://hasseg.org/\n");
	Printf(@"\n");
}



int exitValue = 0;
#define EXIT(x)		{ exitValue = x; goto cleanUpAndExit; }

int main(int argc, char *argv[])
{
	NSAutoreleasePool *autoReleasePool = [[NSAutoreleasePool alloc] init];
	
	myBasename = basename(argv[0]);
	
	if (argc == 1)
	{
		printUsage();
		EXIT(0);
	}
	
	BOOL arg_list = NO;
	BOOL arg_empty = NO;
	BOOL arg_emptySecurely = NO;
	
	int opt;
	while ((opt = getopt(argc, argv, "vles")) != EOF)
	{
		switch (opt)
		{
			case 'v':	arg_verbose = YES;
				break;
			case 'l':	arg_list = YES;
				break;
			case 'e':	arg_empty = YES;
				break;
			case 's':	arg_emptySecurely = YES;
				break;
			case '?':
			default:
				printUsage();
				EXIT(1);
		}
	}
	
	
	
	if (arg_list || arg_empty || arg_emptySecurely)
	{
		if (arg_list)
		{
			listTrashContents();
			EXIT(0);
		}
		else if (arg_empty || arg_emptySecurely)
		{
			EXIT(emptyTrash(arg_emptySecurely));
		}
	}
	
	
	BOOL atLeastOneValidPath = NO;
	int i;
	for (i = optind; i < argc; i++)
	{
		// Note: don't standardize the path! we don't want to expand symlinks.
		NSString *path = [[NSString stringWithUTF8String:argv[i]] stringByExpandingTildeInPath];
		if (path == nil)
		{
			PrintfErr(@"Error: invalid path: %s\n", argv[i]);
			continue;
		}
		
		OSStatus status = moveFileToTrash(path);
		if (status == noErr)
			atLeastOneValidPath = YES;
		else
		{
			exitValue = 1;
			PrintfErr(@"Error: can not delete: %@ (%@)\n", path, osStatusToErrorString(status));
		}
	}
	
	if (!atLeastOneValidPath)
		printUsage();
	
	
cleanUpAndExit:
	[autoReleasePool release];
	return exitValue;
}








