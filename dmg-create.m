#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "BaseProperties.h"

void printUsage();
void exitWithError( NSString * str, int nErr );
void exitWithErrorUsage( NSString * str, int nErr, BOOL bPrintUsage );

//-----------------------------------------------------------------------------
int main ( int argc, const char * argv[] )
{
    @autoreleasepool
    {
        if ( argc < 2 )
        {
            //	print usage
            printUsage();
            return 0;
        }
        
        NSString *	sSourceFolder = nil;
        NSString *	sFolderName = nil;
        NSString *	sVolumeName = nil;
        NSString *	sDMGFile = nil;
        
        NSMutableDictionary *	dictLanguages = [NSMutableDictionary dictionary];
        NSCharacterSet *		dashSet = [NSCharacterSet characterSetWithCharactersInString:@"-"];
        NSDictionary *			dictLangIDs = nil;
        
        //	language names & IDs
        dictLangIDs = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"5001", @"german",
                       @"5002", @"english",
                       @"5003", @"spanish",
                       @"5004", @"french",
                       @"5005", @"italian",
                       @"5006", @"japanese",
                       @"5007", @"dutch",
                       @"5008", @"swedish",
                       @"5009", @"brazilianportuguese",
                       @"5012", @"danish",
                       @"5013", @"finnish",
                       @"5014", @"frenchcanadian",
                       @"5015", @"korean",
                       @"5016", @"norwegian", nil];
        
        sSourceFolder = [NSString stringWithCString:argv[1] encoding:[NSString defaultCStringEncoding]];
        sFolderName = [sSourceFolder lastPathComponent];
        
        for ( int i = 2; i < argc; )
        {
            NSString * s = [NSString stringWithCString:argv[i] encoding:[NSString defaultCStringEncoding]];
            
            //	eat the '-' and process the option
            if ( [s hasPrefix:@"-"] )
            {
                s = [[s stringByTrimmingCharactersInSet:dashSet] lowercaseString];
                
                //	check for a language option
                if ( [dictLangIDs valueForKey:s] != nil )
                {
                    id	key = [dictLangIDs valueForKey:s];
                    
                    i++;
                    
                    if ( i < argc )
                    {
                        s = [NSString stringWithCString:argv[i] encoding:[NSString defaultCStringEncoding]];
                        [dictLanguages setValue:s forKey:key];
                    }
                    else
                        exitWithErrorUsage( @"Too few arguments, missing license file.", -1, YES );

                }
                else if ( [s caseInsensitiveCompare:@"volname"] == NSOrderedSame )
                {
                    i++;
                    
                    //	volume name
                    if ( i < argc )
                    {
                        sVolumeName = [NSString stringWithCString:argv[i] encoding:[NSString defaultCStringEncoding]];
                    }
                    else
                        exitWithErrorUsage( @"Too few arguments, missing volume name.", -1, YES );
                }
                else
                {
                    exitWithErrorUsage( [NSString stringWithFormat:@"Unrecognized option: %@", s], -1, YES );
                }

            }
            
            i++;
        }
        
        //  Check if the source folder is actually a DMG file. In that case we skip the DMG creation & just add
        //  the license file(s).
        NSString * extension = [sSourceFolder pathExtension];
        
        if ( [extension length] != 0 )
        {
            CFStringRef uti = UTTypeCreatePreferredIdentifierForTag( kUTTagClassFilenameExtension, (__bridge CFStringRef)extension, NULL );
            
            if ( UTTypeConformsTo( uti, kUTTypeDiskImage ) )
            {
                //  The source file is a disk image
                sDMGFile = sSourceFolder;
            }
            
            CFRelease( uti );
        }
        
        if ( sDMGFile == nil )
        {
        
            if ( sVolumeName == nil )
                sVolumeName = sFolderName;
            
            sDMGFile = [NSString stringWithFormat:@"%@.dmg", sVolumeName];

            //	create the disk image
            NSArray *	args;
            int			nStatus = 0;
            
            //	hdiutil create -fs HFS+ -srcfolder <srcFolder> -volname <sFolderName> -format UDBZ <sFolderName>.dmg
            args = [NSArray arrayWithObjects:@"hdiutil", @"create", @"-fs", @"HFS+", @"-srcfolder", sSourceFolder, @"-volname", sVolumeName,
                                             @"-format", @"UDBZ", /*@"UDRO",*/ sDMGFile, nil];
            
            NSTask *	dmgTask = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/env" arguments:args];
            
            [dmgTask waitUntilExit];
            nStatus = [dmgTask terminationStatus];

            if ( nStatus != 0 )
            {
                NSLog( @"Error creating disk image: %d", nStatus );
                return nStatus;
            }

            //	it worked!
        }
        
        //	Only need to do this stuff if there are license files to add...
        if ( [dictLanguages count] > 0 )
        {
            NSArray *	args;
            NSTask *	dmgTask;
            int			nStatus = 0;

            //	Now we need to get the XML properties of the DMG we just created
            //	hdiutil udifderez -xml <sDMGFile>
            NSPipe *		dmgPipe = [NSPipe pipe];
            NSFileHandle *	readHandle = [dmgPipe fileHandleForReading];
            NSData *		xmlPropData = nil;
            NSString *		str = nil;
            
            args = [NSArray arrayWithObjects:@"hdiutil", @"udifderez", @"-xml", sDMGFile, nil];
            dmgTask = [[NSTask alloc] init];
            
            [dmgTask setLaunchPath:@"/usr/bin/env"];
            [dmgTask setArguments:args];
            [dmgTask setStandardOutput:dmgPipe];
            [dmgTask launch];
            
            //	read the data from hdiutil, else we might stall
            xmlPropData = [readHandle readDataToEndOfFile];
            [dmgTask waitUntilExit];
            nStatus = [dmgTask terminationStatus];
            [dmgTask release];
            
            if ( nStatus != 0 )
            {
                NSLog( @"Error reading XML properties: %d", nStatus );
                return nStatus;
            }
            
            NSDictionary *	dmgDict = nil;
            NSMutableDictionary * mergedDict = nil;
            
            //	serialize the xml data to a property list (Dictionary)
    //		This is 10.6-only >:-(
    //		dmgDict = [NSPropertyListSerialization propertyListWithData:xmlPropData
    //															options:0
    //															 format:nil
    //															  error:&error];
            
            dmgDict = [NSPropertyListSerialization propertyListFromData:xmlPropData
                                                       mutabilityOption:0
                                                                 format:nil
                                                       errorDescription:&str];
            if ( dmgDict == nil )
            {
                NSLog( @"Error: %@", str );
                [str release];
                return -1;
            }
            
            //	load the base property list
            NSString * sBaseProps = BASE_PROPS_STR;
            NSData * propsData = nil;
            
            propsData = [NSPropertyListSerialization propertyListFromData:[sBaseProps dataUsingEncoding:NSUTF8StringEncoding]
                                                         mutabilityOption:0
                                                                   format:nil
                                                         errorDescription:&str];
            
            if ( propsData == nil )
                exitWithError( str, -1 );
            
            mergedDict = [NSPropertyListSerialization propertyListFromData:propsData
                                                          mutabilityOption:0
                                                                    format:nil
                                                          errorDescription:&str];

            if ( mergedDict == nil )
                exitWithError( str, -1 );
            
            //	make sure we have a mutable dictionary
            mergedDict = [NSMutableDictionary dictionaryWithDictionary:mergedDict];
            
            //	merge the dmgDict with the mergedDict
            NSEnumerator *	enumerator = [dmgDict keyEnumerator];
            id key;
            
            while ( ( key = [enumerator nextObject] ) )
            {
                id	object;
                
                object = [dmgDict objectForKey:key];
                [mergedDict setObject:object forKey:key];
            }
            
            //	create the array of Language dictionaries
            NSMutableArray *	langArray = [NSMutableArray array];
            
            enumerator = [dictLanguages keyEnumerator];
            
            while ( ( key = [enumerator nextObject] ) )
            {
                NSAttributedString *	strLicense = nil;
                NSString *	strLicensePath = nil;
                NSDictionary *	dict = nil;
                
                strLicensePath = [dictLanguages objectForKey:key];
                strLicense = [[[NSAttributedString alloc] initWithPath:strLicensePath documentAttributes:nil] autorelease];
                
                if ( strLicense == nil )
                {
                    NSLog( @"Error reading license for language ID: %@", key );
                    continue;
                }
                
                //	Convert NSAttributedString into RTF NSData
                NSData *data = [strLicense RTFFromRange:NSMakeRange(0, [strLicense length]) documentAttributes:nil];
                
                if ( data == nil )
                {
                    NSLog( @"Error converting RTF to NSData for language ID: %@", key );
                    continue;
                }
                
                //	set up the dictionary
                dict = [NSDictionary dictionaryWithObjectsAndKeys:
                        @"0x0000", @"Attributes",
                        @"", @"Name",
                        key, @"ID",
                        data, @"Data", nil];
                
                [langArray addObject:dict];
            }
            
            //	Add the language array to the merged Property dict with the key 'RTF '
            [mergedDict setValue:langArray forKey:@"RTF "];
            
            //	Now create an XML plist from the merged dictionary
            NSData *	data = nil;
            
    //		This is 10.6-only >:-(
    //		data = [NSPropertyListSerialization dataWithPropertyList:mergedDict
    //														  format:NSPropertyListXMLFormat_v1_0
    //														 options:0
    //														   error:&error];
            
            data = [NSPropertyListSerialization dataFromPropertyList:mergedDict
                                                              format:NSPropertyListXMLFormat_v1_0
                                                    errorDescription:&str];
            
            
            if ( data == nil )
            {
    //			NSLog( @"Error serializing merged property dictionary: %@", [error localizedDescription] );
                NSLog( @"Error serializing merged property dictionary: %@", str );
                [str release];
                return -1;
            }
            
            //	write the plist out
            [data writeToFile:@"dmgProperties.plist" atomically:YES];
            
            //	now embed the properties into the generated DMG
            //	hdiutil udifrez <sDMGFile> -xml dmgProperties.plist
            args = [NSArray arrayWithObjects:@"hdiutil", @"udifrez", sDMGFile, @"-xml", @"dmgProperties.plist", nil];
            
            dmgTask = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/env" arguments:args];
            [dmgTask waitUntilExit];
            nStatus = [dmgTask terminationStatus];
            
            if ( nStatus != 0 )
            {
                NSLog( @"Error embedding XML properties: %d", nStatus );
                return nStatus;
            }
            
            //	lastly, internet-enable the DMG
            //	hdiutil internet-enable -yes <sDMGFile>
            args = [NSArray arrayWithObjects:@"hdiutil", @"internet-enable", @"-yes", sDMGFile, nil];
            
            dmgTask = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/env" arguments:args];
            [dmgTask waitUntilExit];
            nStatus = [dmgTask terminationStatus];
            
            if ( nStatus != 0 )
            {
                NSLog( @"Error making the DMG internet-enabled: %d", nStatus );
                return nStatus;
            }
            
            //  remove the "dmgProperties.plist" file that we created above
            NSFileManager * manager = [NSFileManager defaultManager];
            
            [manager removeItemAtPath:@"dmgProperties.plist" error:nil];
        }	
    }
    
    return 0;
}

//-----------------------------------------------------------------------------
void printUsage()
{
	printf( "\nUsage: dmg-create <Source> [-volname <Volume Name>] [-<Language> <license.txt>]\n\n" );
    printf( "   <Source>                  :  Either an existing DMG or a folder to be copied. If <Source> is a DMG\n" );
    printf( "                             :  it will have the given license files attached. If <Source> is a folder\n" );
    printf( "                             :  then all contents will be copied to the DMG.\n" );
	printf( "   -volname <Volume Name>    :  Optional Name of the resulting DMG - default is the name of the source folder.\n");
    printf( "                             :  Note that this option only applies when <Source> is a folder.\n" );
	printf( "   -<Language> <license.txt> :  Optional language & license file.  The following languages are supported:\n" );
	printf( "                             :  English, German, Spanish, French, Italian, Japanese, Dutch, Swedish,\n" );
	printf( "                             :  BrazilianPortuguese, Danish, Finnish, FrenchCanadian, Korean, Norwegian.\n\n\n" );
}

//-----------------------------------------------------------------------------
void exitWithError( NSString * str, int nErr )
{
	exitWithErrorUsage( str, nErr, NO );
}

//-----------------------------------------------------------------------------
void exitWithErrorUsage( NSString * str, int nErr, BOOL bPrintUsage )
{
//	NSLog( @"Error: %@", str );
	printf( "\nError: %s\n", [str cStringUsingEncoding:[NSString defaultCStringEncoding]] );
	
	if ( bPrintUsage )
		printUsage();
	
	exit( nErr );
}


//-----------------------------------------------------------------------------
