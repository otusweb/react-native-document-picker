#import "RNDocumentPicker.h"

#import <MobileCoreServices/MobileCoreServices.h>

#import <React/RCTConvert.h>
#import <React/RCTBridge.h>
#import <React/RCTUtils.h>


static NSString *const E_DOCUMENT_PICKER_CANCELED = @"DOCUMENT_PICKER_CANCELED";
static NSString *const E_INVALID_DATA_RETURNED = @"INVALID_DATA_RETURNED";
static NSString *const E_CANT_COPY_FOLDER = @"CANT_COPY_FOLDER";
static NSString *const E_INVALID_FILEPATH_PARAM = @"MISSING_FILEPATH_PARAM";

static NSString *const OPTION_TYPE = @"type";
static NSString *const OPTION_MULIPLE = @"multiple";

static NSString *const FIELD_URI = @"uri";
static NSString *const FIELD_FILE_COPY_URI = @"fileCopyUri";
static NSString *const FIELD_COPY_ERR = @"copyError";
static NSString *const FIELD_NAME = @"name";
static NSString *const FIELD_TYPE = @"type";
static NSString *const FIELD_SIZE = @"size";

//static NSString *const USERDEFAULTS_BOOKMARKS = @"bookmarkURLs";


@interface RNDocumentPicker () <UIDocumentPickerDelegate>
@end

@implementation RNDocumentPicker {
    NSMutableArray *composeResolvers;
    NSMutableArray *composeRejecters;
    NSString* copyDestination;
    NSURL *baseScopedURL;
}

@synthesize bridge = _bridge;

- (instancetype)init
{
    if ((self = [super init])) {
        composeResolvers = [[NSMutableArray alloc] init];
        composeRejecters = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(pickFolder:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    
    
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (@available(iOS 13, *)) {
        
        UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[(NSString*)kUTTypeFolder]
                                                                                                                inMode:UIDocumentPickerModeOpen];
        
        [composeResolvers addObject:resolve];
        [composeRejecters addObject:reject];
        
        documentPicker.delegate = self;
        documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
        
        documentPicker.allowsMultipleSelection = [RCTConvert BOOL:options[OPTION_MULIPLE]];
        
        UIViewController *rootViewController = RCTPresentedViewController();
        
        [rootViewController presentViewController:documentPicker animated:YES completion:nil];
        
    }
#endif
}

RCT_EXPORT_METHOD(pick:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSArray *allowedUTIs = [RCTConvert NSArray:options[OPTION_TYPE]];
    
    UIDocumentPickerMode mode = UIDocumentPickerModeImport;
    
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (allowedUTIs.count == 1 &&
        [allowedUTIs.firstObject isEqual:  (NSString*)kUTTypeFolder])
    {
        mode = UIDocumentPickerModeOpen;
        
        if (options[@"copyTo"] != nil)
        {
            reject(E_CANT_COPY_FOLDER, @"can't copy a folder", nil);
            return ;
        }
    }
#endif
    
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:(NSArray *)allowedUTIs inMode:mode];
    
    [composeResolvers addObject:resolve];
    [composeRejecters addObject:reject];
    copyDestination = options[@"copyTo"] ? options[@"copyTo"] : nil;
    
    
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
    if (@available(iOS 11, *)) {
        documentPicker.allowsMultipleSelection = [RCTConvert BOOL:options[OPTION_MULIPLE]];
    }
#endif
    
    UIViewController *rootViewController = RCTPresentedViewController();
    
    [rootViewController presentViewController:documentPicker animated:YES completion:nil];
}


RCT_EXPORT_METHOD(copyToTemp:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    __block NSMutableDictionary* result = [NSMutableDictionary dictionary];
    NSString *filePath = options[@"filePath"];
    NSURL *fileURL = [NSURL fileURLWithPath: filePath];
    
    if (!fileURL)
    {
        reject(E_INVALID_FILEPATH_PARAM, @"invalid parameter 'filePath'", nil);
    }
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
    NSError *fileError;
    
    [coordinator coordinateReadingItemAtURL:baseScopedURL
                                    options:NSFileCoordinatorReadingResolvesSymbolicLink
                                      error:&fileError
                                 byAccessor:^(NSURL *newURL) {
        if (!fileError) {
            NSError *copyError;
            NSURL* copyURL = [RNDocumentPicker copyToUniqueDestinationFrom:fileURL
                                                    usingDestinationPreset:nil
                                                                     error:copyError];
            [result setValue:copyURL.lastPathComponent forKey:FIELD_NAME];
            [result setValue: copyURL.absoluteString forKey:FIELD_FILE_COPY_URI];
            NSString *mimeType = [RNDocumentPicker mimeTypeForURL: copyURL];
            if (mimeType)
            {
                [result setValue: mimeType forKey:FIELD_TYPE];
            }
            
            if (copyError) {
                [result setValue:copyError.description forKey:FIELD_COPY_ERR];
            }
        }
    }];
    
    if (fileError) {
        reject(E_INVALID_FILEPATH_PARAM, @"failed to copy file", fileError);
    } else {
        resolve(result);
    }
}

- (NSMutableDictionary *)getMetadataForUrl:(NSURL *)url error:(NSError **)error
{
    __block NSMutableDictionary* result = [NSMutableDictionary dictionary];
    
    [url startAccessingSecurityScopedResource];
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
    NSError *fileError;
    
    [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingResolvesSymbolicLink error:&fileError byAccessor:^(NSURL *newURL) {
        if (!fileError) {
            [result setValue:newURL.absoluteString forKey:FIELD_URI];
            NSError *copyError;
            NSURL* maybeFileCopyPath = copyDestination ? [RNDocumentPicker copyToUniqueDestinationFrom:newURL usingDestinationPreset:copyDestination error:copyError] : newURL;
            [result setValue: maybeFileCopyPath.absoluteString forKey:FIELD_FILE_COPY_URI];
            if (copyError) {
                [result setValue:copyError.description forKey:FIELD_COPY_ERR];
            }
            
            [result setValue:[newURL lastPathComponent] forKey:FIELD_NAME];
            
            NSError *attributesError = nil;
            NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:newURL.path error:&attributesError];
            if(!attributesError) {
                [result setValue:[fileAttributes objectForKey:NSFileSize] forKey:FIELD_SIZE];
            } else {
                NSLog(@"%@", attributesError);
            }
            
            if ( newURL.pathExtension != nil ) {
                CFStringRef extension = (__bridge CFStringRef)[newURL pathExtension];
                CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, extension, NULL);
                CFStringRef mimeType = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType);
                CFRelease(uti);
                
                NSString *mimeTypeString = (__bridge_transfer NSString *)mimeType;
                [result setValue:mimeTypeString forKey:FIELD_TYPE];
            }
        }
    }];
    
    [url stopAccessingSecurityScopedResource];
    
    if (fileError) {
        *error = fileError;
        return nil;
    } else {
        return result;
    }
}

+ (NSString*) mimeTypeForURL:(NSURL*) url
{
    if ( url.pathExtension != nil ) {
        CFStringRef extension = (__bridge CFStringRef)[url pathExtension];
        CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, extension, NULL);
        CFStringRef mimeType = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType);
        CFRelease(uti);
        
        NSString *mimeTypeString = (__bridge_transfer NSString *)mimeType;
        return mimeTypeString;
    }
    return nil;
}

+ (NSURL*)getDirectoryForFileCopy:(NSString*) copyToDirectory {
    if ([@"cachesDirectory" isEqualToString:copyToDirectory]) {
        return [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    } else if ([@"documentDirectory" isEqualToString:copyToDirectory]) {
        return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    }
    // this should not happen as the value is checked in JS, but we fall back to NSTemporaryDirectory()
    return [NSURL fileURLWithPath: NSTemporaryDirectory() isDirectory: YES];
}

+ (NSURL *)copyToUniqueDestinationFrom:(NSURL *) url usingDestinationPreset: (NSString*) copyToDirectory error:(NSError *)error
{
    NSURL* destinationRootDir = [self getDirectoryForFileCopy:copyToDirectory];
    // we don't want to rename the file so we put it into a unique location
    NSString *uniqueSubDirName = [[NSUUID UUID] UUIDString];
    NSURL *destinationDir = [destinationRootDir URLByAppendingPathComponent:[NSString stringWithFormat:@"%@/", uniqueSubDirName]];
    NSURL *destinationUrl = [destinationDir URLByAppendingPathComponent:[NSString stringWithFormat:@"%@", url.lastPathComponent]];
    
    [NSFileManager.defaultManager createDirectoryAtURL:destinationDir withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        return url;
    }
    [NSFileManager.defaultManager copyItemAtURL:url toURL:destinationUrl error:&error];
    if (error) {
        return url;
    } else {
        return destinationUrl;
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url
{
    if (controller.documentPickerMode == UIDocumentPickerModeOpen ||
        controller.documentPickerMode == UIDocumentPickerModeImport) {
        RCTPromiseResolveBlock resolve = [composeResolvers lastObject];
        RCTPromiseRejectBlock reject = [composeRejecters lastObject];
        [composeResolvers removeLastObject];
        [composeRejecters removeLastObject];
        
        NSError *error;
        NSDictionary* result = @{FIELD_URI: url.absoluteString};
        
        if (result) {
            NSArray *results = @[result];
            resolve(results);
        } else {
            reject(E_INVALID_DATA_RETURNED, error.localizedDescription, error);
        }
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSLog(@"urls: %@", urls);
    if (controller.documentPickerMode == UIDocumentPickerModeOpen ||
        controller.documentPickerMode == UIDocumentPickerModeImport) {
        RCTPromiseResolveBlock resolve = [composeResolvers lastObject];
        RCTPromiseRejectBlock reject = [composeRejecters lastObject];
        [composeResolvers removeLastObject];
        [composeRejecters removeLastObject];
        
        
        NSMutableArray *results = [NSMutableArray array];
        for (NSURL* url in urls) {
            
            baseScopedURL = url;
            [url startAccessingSecurityScopedResource];
            
            
            [results addObject: [self photoInfos]];
        }
        
        
        resolve(results);
        
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    if (controller.documentPickerMode == UIDocumentPickerModeOpen ||
        controller.documentPickerMode == UIDocumentPickerModeImport) {
        RCTPromiseRejectBlock reject = [composeRejecters lastObject];
        [composeResolvers removeLastObject];
        [composeRejecters removeLastObject];
        
        reject(E_DOCUMENT_PICKER_CANCELED, @"User canceled document picker", nil);
    }
}

- (NSArray<NSDictionary*>*) photoInfos
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
    __block NSError *fileError;
    __block NSMutableArray *contents = [NSMutableArray new];
    
    [coordinator coordinateReadingItemAtURL:baseScopedURL options:NSFileCoordinatorReadingResolvesSymbolicLink error:&fileError byAccessor:^(NSURL *newURL) {
        NSArray *contentsPath = [fileManager contentsOfDirectoryAtPath:[newURL path] error:&fileError];
        
        for (NSString *path in contentsPath) {
            NSURL *itemURL = [newURL URLByAppendingPathComponent: path];
            NSString *path = [itemURL path];
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:nil];
            
            NSString* fileExtension = [path pathExtension];
            CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef _Nonnull)(fileExtension), NULL);
            
            NSDictionary *exifDict = @{};
            if (UTTypeConformsTo(fileUTI, kUTTypeImage))
            {
                CGImageSourceRef imageSource = CGImageSourceCreateWithURL((CFURLRef)itemURL, nil);
                
                NSDictionary* imageProperties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil));
                exifDict = imageProperties[(NSString*)kCGImagePropertyExifDictionary];
                if (exifDict == nil)
                {
                    exifDict = @{};
                }
                
                CFDictionaryRef options = (__bridge CFDictionaryRef) @{
                    (id) kCGImageSourceCreateThumbnailWithTransform : @YES,
                    (id) kCGImageSourceCreateThumbnailFromImageAlways : @YES,
                    (id) kCGImageSourceThumbnailMaxPixelSize : @(300)
                };
                
                CGImageRef scaledImageRef = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options);
                UIImage *scaled = [UIImage imageWithCGImage:scaledImageRef];
                NSString *thumbPath = [self saveImageToTemp: scaled];
                
                CGImageRelease(scaledImageRef);
                
                CFRelease(imageSource);
                NSLog(@"path: %@", path);
                NSMutableDictionary *objectInfo = @{
                    @"ctime": @([(NSDate *)[attributes objectForKey:NSFileCreationDate] timeIntervalSince1970]),
                    @"mtime": @([(NSDate *)[attributes objectForKey:NSFileModificationDate] timeIntervalSince1970]),
                    @"name": [itemURL lastPathComponent],
                    @"path": path,
                    @"size": [attributes objectForKey:NSFileSize],
                    @"type": [attributes objectForKey:NSFileType],
                    @"thumb": thumbPath,
                    @"exif": exifDict,
                    
                };
                
                [contents addObject: objectInfo];
            }
        }
    }];
    
    return contents;
}

- (NSString*) saveImageToTemp:(UIImage*)image
{
    NSString *tmpDirectory = NSTemporaryDirectory();
    NSString *uuid = [[NSUUID new] UUIDString];
    NSString *tmpFile = [[tmpDirectory stringByAppendingPathComponent:uuid] stringByAppendingPathExtension: @"jpg"];
    NSData * imageData = UIImageJPEGRepresentation(image, 1.0);
    [imageData writeToFile:tmpFile atomically:true];
    
    return tmpFile;
}

@end
