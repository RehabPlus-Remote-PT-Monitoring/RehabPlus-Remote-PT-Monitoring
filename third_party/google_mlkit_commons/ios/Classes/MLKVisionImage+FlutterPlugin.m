#import "GoogleMlKitCommonsPlugin.h"
#import <MLKitVision/MLKitVision.h>

@implementation MLKVisionImage(FlutterPlugin)

+ (MLKVisionImage *)visionImageFromData:(NSDictionary *)imageData {
    NSString *imageType = imageData[@"type"];
    if ([@"file" isEqualToString:imageType]) {
        return [self filePathToVisionImage:imageData[@"path"]];
    } else if ([@"bytes" isEqualToString:imageType]) {
        return [self bytesToVisionImage:imageData];
    } else if ([@"bitmap" isEqualToString:imageType]) {
        return [self bitmapToVisionImage:imageData];
    } else {
        NSString *errorReason = [NSString stringWithFormat:@"No image type for: %@", imageType];
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:errorReason
                                     userInfo:nil];
    }
}

+ (MLKVisionImage *)filePathToVisionImage:(NSString *)filePath {
    UIImage *image = [UIImage imageWithContentsOfFile:filePath];
    MLKVisionImage *visionImage = [[MLKVisionImage alloc] initWithImage:image];
    visionImage.orientation = image.imageOrientation;
    return visionImage;
}

+ (MLKVisionImage *)bytesToVisionImage:(NSDictionary *)imageData {
    FlutterStandardTypedData *byteData = imageData[@"bytes"];
    NSData *imageBytes = byteData.data;
    NSDictionary *metadata = imageData[@"metadata"];
    NSNumber *width = metadata[@"width"];
    NSNumber *height = metadata[@"height"];
    NSNumber *rawFormat = metadata[@"image_format"];
    NSNumber *bytesPerRow = metadata[@"bytes_per_row"];
    CVPixelBufferRef pxBuffer = [self bytesToPixelBuffer:width.unsignedLongValue
                                                  height:height.unsignedLongValue
                                                  format:FOUR_CHAR_CODE(rawFormat.unsignedIntValue)
                                             baseAddress:(void *)imageBytes.bytes
                                             bytesPerRow:bytesPerRow.unsignedLongValue];
    return [self pixelBufferToVisionImage:pxBuffer];
}

+ (CVPixelBufferRef)bytesToPixelBuffer:(size_t)width
                                height:(size_t)height
                                format:(FourCharCode)format
                           baseAddress:(void *)baseAddress
                           bytesPerRow:(size_t)bytesPerRow {
    CVPixelBufferRef pxBuffer = NULL;
    CVPixelBufferCreateWithBytes(kCFAllocatorDefault, width, height, format, baseAddress, bytesPerRow,
                                 NULL, NULL, NULL, &pxBuffer);
    return pxBuffer;
}

// RehabPlus patch (see third_party/README.md): upstream created a NEW
// CIContext for every camera frame. A CIContext sets up a GPU render
// pipeline, so creating one per frame cost far more than the conversion
// itself and slowed every pose result on iPhone. One context is created
// once and reused (CIContext is thread-safe). Colour management is turned
// off: ML Kit doesn't need colour-matched pixels and it saves a pass.
+ (CIContext *)sharedContext {
    static CIContext *context = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        context = [CIContext contextWithOptions:@{
            kCIContextWorkingColorSpace : [NSNull null],
            kCIContextCacheIntermediates : @NO,
        }];
    });
    return context;
}

// RehabPlus patch: the iPhone camera stream delivers 32BGRA. Those bytes
// can become a CGImage directly (one memcpy of ~400 KB at 352x288) without
// a GPU round trip through Core Image. Returns nil for any other format or
// on failure, and the caller then falls back to the Core Image path.
+ (MLKVisionImage *)bgraPixelBufferToVisionImage:(CVPixelBufferRef)pixelBufferRef {
    if (pixelBufferRef == NULL ||
        CVPixelBufferGetPixelFormatType(pixelBufferRef) != kCVPixelFormatType_32BGRA) {
        return nil;
    }
    CVPixelBufferLockBaseAddress(pixelBufferRef, kCVPixelBufferLock_ReadOnly);
    void *base = CVPixelBufferGetBaseAddress(pixelBufferRef);
    size_t width = CVPixelBufferGetWidth(pixelBufferRef);
    size_t height = CVPixelBufferGetHeight(pixelBufferRef);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBufferRef);

    CGImageRef cgImage = NULL;
    if (base != NULL) {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap = CGBitmapContextCreate(
            base, width, height, 8, bytesPerRow, colorSpace,
            kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        if (bitmap != NULL) {
            // Copies the pixels, so the image outlives the Dart-owned bytes.
            cgImage = CGBitmapContextCreateImage(bitmap);
            CGContextRelease(bitmap);
        }
        CGColorSpaceRelease(colorSpace);
    }
    CVPixelBufferUnlockBaseAddress(pixelBufferRef, kCVPixelBufferLock_ReadOnly);
    if (cgImage == NULL) return nil;

    UIImage *uiImage = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return [[MLKVisionImage alloc] initWithImage:uiImage];
}

+ (MLKVisionImage *)pixelBufferToVisionImage:(CVPixelBufferRef)pixelBufferRef {
    MLKVisionImage *fast = [self bgraPixelBufferToVisionImage:pixelBufferRef];
    if (fast != nil) {
        CVPixelBufferRelease(pixelBufferRef);
        return fast;
    }

    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBufferRef];
    
    CIContext *temporaryContext = [self sharedContext];
    CGImageRef videoImage =
    [temporaryContext createCGImage:ciImage
                           fromRect:CGRectMake(0, 0, CVPixelBufferGetWidth(pixelBufferRef),
                                               CVPixelBufferGetHeight(pixelBufferRef))];
    
    UIImage *uiImage = [UIImage imageWithCGImage:videoImage];
    CVPixelBufferRelease(pixelBufferRef);
    CGImageRelease(videoImage);
    return [[MLKVisionImage alloc] initWithImage:uiImage];
}

+ (MLKVisionImage *)bitmapToVisionImage:(NSDictionary *)imageDict {
    // Get the bitmap data
    FlutterStandardTypedData *bitmapData = imageDict[@"bitmapData"];
    
    if (bitmapData == nil) {
        NSString *errorReason = @"Bitmap data is nil";
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:errorReason
                                     userInfo:nil];
    }
    
    // Try to get metadata if available
    NSDictionary *metadata = imageDict[@"metadata"];
    if (metadata != nil) {
        NSNumber *width = metadata[@"width"];
        NSNumber *height = metadata[@"height"];
        
        if (width != nil && height != nil) {
            // Create bitmap context from raw RGBA data
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            uint8_t *rawData = (uint8_t*)[bitmapData.data bytes];
            size_t bytesPerPixel = 4;
            size_t bytesPerRow = bytesPerPixel * width.intValue;
            size_t bitsPerComponent = 8;
            
            CGContextRef context = CGBitmapContextCreate(rawData, width.intValue, height.intValue,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
            
            if (context) {
                CGImageRef imageRef = CGBitmapContextCreateImage(context);
                UIImage *image = [UIImage imageWithCGImage:imageRef];
                
                CGImageRelease(imageRef);
                CGContextRelease(context);
                CGColorSpaceRelease(colorSpace);
                
                if (image) {
                    MLKVisionImage *visionImage = [[MLKVisionImage alloc] initWithImage:image];
                    visionImage.orientation = image.imageOrientation;
                    return visionImage;
                }
            }
            
            CGColorSpaceRelease(colorSpace);
        }
    }
    
    // Fallback: try to create UIImage directly from data
    UIImage *image = [UIImage imageWithData:bitmapData.data];
    
    if (image == nil) {
        NSString *errorReason = @"Failed to create UIImage from bitmap data";
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:errorReason
                                     userInfo:nil];
    }
    
    MLKVisionImage *visionImage = [[MLKVisionImage alloc] initWithImage:image];
    visionImage.orientation = image.imageOrientation;
    return visionImage;
}

@end
