//
//  SOSPicker.m
//  SyncOnSet
//
//  Created by Christopher Sullivan on 10/25/13.
//
//

#import "SOSPicker.h"


#import "GMImagePickerController.h"
#import "GMFetchItem.h"

#define CDV_PHOTO_PREFIX @"cdv_photo_"

typedef enum : NSUInteger {
    FILE_URI = 0,
    BASE64_STRING = 1
} SOSPickerOutputType;

@interface SOSPicker () <GMImagePickerControllerDelegate>
@end

@implementation SOSPicker

@synthesize callbackId;

- (void) hasReadPermission:(CDVInvokedUrlCommand *)command {
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:[PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusAuthorized];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) requestReadPermission:(CDVInvokedUrlCommand *)command {
    // [PHPhotoLibrary requestAuthorization:]
    // this method works only when it is a first time, see
    // https://developer.apple.com/library/ios/documentation/Photos/Reference/PHPhotoLibrary_Class/

    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    CDVPluginResult* pluginResult = nil;

    if (status == PHAuthorizationStatusNotDetermined) {
        // Access has not been determined. requestAuthorization: is available
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            CDVPluginResult* pluginResult = nil;
            if (status == PHAuthorizationStatusAuthorized) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            } else {
                [self showProhibitedMessage];
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
        }];
    } else if (status == PHAuthorizationStatusAuthorized) {
        NSLog(@"Access has been granted.");
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else if (status == PHAuthorizationStatusDenied) {
        NSLog(@"Access has been denied. Change your setting > this app > Photo enable");
        [self showProhibitedMessage];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
    } else if (status == PHAuthorizationStatusRestricted) {
        NSLog(@"Access has been restricted. Change your setting > Privacy > Photo enable");
        [self showProhibitedMessage];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
    }

    if (pluginResult != nil) {
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void) getPictures:(CDVInvokedUrlCommand *)command {

    NSDictionary *options = [command.arguments objectAtIndex: 0];

    self.outputType = [[options objectForKey:@"outputType"] integerValue];
    BOOL allow_video = [[options objectForKey:@"allow_video" ] boolValue ];
    NSInteger maximumImagesCount = [[options objectForKey:@"maximumImagesCount"] integerValue];
    NSString * title = [options objectForKey:@"title"];
    NSString * message = [options objectForKey:@"message"];
    BOOL disable_popover = [[options objectForKey:@"disable_popover" ] boolValue];
    if (message == (id)[NSNull null]) {
      message = nil;
    }
    self.width = [[options objectForKey:@"width"] integerValue];
    self.height = [[options objectForKey:@"height"] integerValue];
    self.quality = [[options objectForKey:@"quality"] integerValue];

    self.callbackId = command.callbackId;
    [self launchGMImagePicker:allow_video title:title message:message disable_popover:disable_popover maximumImagesCount:maximumImagesCount];
}

- (void)showProhibitedMessage {
    __weak SOSPicker* weakSelf = self;

    // If iOS 8+, offer a link to the Settings app
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wtautological-pointer-compare"
    NSString* settingsButton = (&UIApplicationOpenSettingsURLString != NULL)
    ? NSLocalizedString(@"Settings", nil)
    : nil;
#pragma clang diagnostic pop

    // Denied; show an alert
    dispatch_async(dispatch_get_main_queue(), ^{

        UIAlertController* alert = [UIAlertController
                                    alertControllerWithTitle:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                                    message:NSLocalizedString(@"Access to the photo album has been prohibited; please enable it in the Settings app to continue.", nil)
                                    preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction
                          actionWithTitle:NSLocalizedString(@"OK", nil)
                          style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {}]];

        if (settingsButton != nil) {
            [alert addAction:[UIAlertAction
                              actionWithTitle:settingsButton
                              style:UIAlertActionStyleDefault
                              handler:^(UIAlertAction * action) {
                                  [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                              }]];
        }

        [self.viewController presentViewController:alert animated:YES completion:nil];
    });
}

- (void)launchGMImagePicker:(bool)allow_video title:(NSString *)title message:(NSString *)message disable_popover:(BOOL)disable_popover maximumImagesCount:(NSInteger)maximumImagesCount
{
    GMImagePickerController *picker = [[GMImagePickerController alloc] init:allow_video];
    picker.delegate = self;
    picker.maximumImagesCount = maximumImagesCount;
    picker.title = title;
    picker.customNavigationBarPrompt = message;
    picker.colsInPortrait = 4;
    picker.colsInLandscape = 6;
    picker.minimumInteritemSpacing = 2.0;

    if(!disable_popover) {
        picker.modalPresentationStyle = UIModalPresentationPopover;

        UIPopoverPresentationController *popPC = picker.popoverPresentationController;
        popPC.permittedArrowDirections = UIPopoverArrowDirectionAny;
        popPC.sourceView = picker.view;
        //popPC.sourceRect = nil;
    }

    [self.viewController showViewController:picker sender:nil];
}


- (UIImage*)imageByScalingNotCroppingForSize:(UIImage*)anImage toSize:(CGSize)frameSize
{
    UIImage* sourceImage = anImage;
    UIImage* newImage = nil;
    CGSize imageSize = sourceImage.size;
    CGFloat width = imageSize.width;
    CGFloat height = imageSize.height;
    CGFloat targetWidth = frameSize.width;
    CGFloat targetHeight = frameSize.height;
    CGFloat scaleFactor = 0.0;
    CGSize scaledSize = frameSize;

    if (CGSizeEqualToSize(imageSize, frameSize) == NO) {
        CGFloat widthFactor = targetWidth / width;
        CGFloat heightFactor = targetHeight / height;

        // opposite comparison to imageByScalingAndCroppingForSize in order to contain the image within the given bounds
        if (widthFactor == 0.0) {
            scaleFactor = heightFactor;
        } else if (heightFactor == 0.0) {
            scaleFactor = widthFactor;
        } else if (widthFactor > heightFactor) {
            scaleFactor = heightFactor; // scale to fit height
        } else {
            scaleFactor = widthFactor; // scale to fit width
        }
        scaledSize = CGSizeMake(floor(width * scaleFactor), floor(height * scaleFactor));
    }

    UIGraphicsBeginImageContext(scaledSize); // this will resize

    [sourceImage drawInRect:CGRectMake(0, 0, scaledSize.width, scaledSize.height)];

    newImage = UIGraphicsGetImageFromCurrentImageContext();
    if (newImage == nil) {
        NSLog(@"could not scale image");
    }

    // pop the context to get back to the default
    UIGraphicsEndImageContext();
    return newImage;
}


#pragma mark - UIImagePickerControllerDelegate


- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    [picker.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    NSLog(@"UIImagePickerController: User finished picking assets");
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    NSLog(@"UIImagePickerController: User pressed cancel button");
}

#pragma mark - GMImagePickerControllerDelegate

- (void)assetsPickerController:(GMImagePickerController *)picker didFinishPickingAssets:(NSArray *)fetchArray
{
    [picker.presentingViewController dismissViewControllerAnimated:YES completion:nil];

    NSLog(@"GMImagePicker: User finished picking assets. Number of selected items is: %lu", (unsigned long)fetchArray.count);

    NSMutableArray * result_all = [[NSMutableArray alloc] init];
    CGSize targetSize = CGSizeMake(self.width, self.height);
    NSFileManager* fileMgr = [[NSFileManager alloc] init];
    NSString* docsPath = [NSTemporaryDirectory()stringByStandardizingPath];

    NSError* err = nil;
    int i = 1;
    NSString* filePath;
    CDVPluginResult* result = nil;

    for (GMFetchItem *item in fetchArray) {

        if ( !item.image_fullsize ) {
            continue;
        }

        do {
            filePath = [NSString stringWithFormat:@"%@/%@%03d.%@", docsPath, CDV_PHOTO_PREFIX, i++, @"jpg"];
        } while ([fileMgr fileExistsAtPath:filePath]);

        NSData* data = nil;
        if (self.width == 0 && self.height == 0) {
            // no scaling required
            if (self.outputType == BASE64_STRING){
                UIImage* image = [UIImage imageNamed:item.image_fullsize];
                [result_all addObject:[UIImageJPEGRepresentation(image, self.quality/100.0f) base64EncodedStringWithOptions:0]];
            } else {
                if (self.quality == 100) {
                    // no scaling, no downsampling, this is the fastest option
                    [result_all addObject:item.image_fullsize];
                } else {
                    // resample first
                    UIImage* image = [UIImage imageNamed:item.image_fullsize];
                    data = UIImageJPEGRepresentation(image, self.quality/100.0f);
                    if (![data writeToFile:filePath options:NSAtomicWrite error:&err]) {
                        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:[err localizedDescription]];
                        break;
                    } else {
                        [result_all addObject:[[NSURL fileURLWithPath:filePath] absoluteString]];
                    }
                }
            }
        } else {
            // scale
            UIImage* image = [UIImage imageNamed:item.image_fullsize];
            UIImage* scaledImage = [self imageByScalingNotCroppingForSize:image toSize:targetSize];
            data = UIImageJPEGRepresentation(scaledImage, self.quality/100.0f);

            if (![data writeToFile:filePath options:NSAtomicWrite error:&err]) {
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:[err localizedDescription]];
                break;
            } else {
                if(self.outputType == BASE64_STRING){
                    [result_all addObject:[data base64EncodedStringWithOptions:0]];
                } else {
                    [result_all addObject:[[NSURL fileURLWithPath:filePath] absoluteString]];
                }
            }
        }
    }

    if (result == nil) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:result_all];
    }

    [self.viewController dismissViewControllerAnimated:YES completion:nil];
    [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];

}

//Optional implementation:
-(void)assetsPickerControllerDidCancel:(GMImagePickerController *)picker
{
    NSLog(@"GMImagePicker: User pressed cancel button");
}


@end
