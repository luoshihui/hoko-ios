//
//  HKObserver.m
//  Hoko
//
//  Created by Hoko, S.A. on 23/07/14.
//  Copyright (c) 2015 Hoko, S.A. All rights reserved.
//

#import "HKSwizzling.h"

#import <objc/runtime.h>

#import "Hoko.h"
#import "HKError.h"

@implementation HKSwizzling

#pragma mark - AppDelegate ClassName
/**
 *  Searches for the app delegate class name. Will not work if more than one class
 *  implements the UIApplicationDelegate protocol. If this does not detect the class,
 *  the developer needs to implement and delegate all the push notification and deeplinking
 *  methods to the corresponding modules.
 *
 *  @return The AppDelegate class name.
 */
+ (NSString *)appDelegateClassName
{
  NSMutableArray *appDelegates = [@[] mutableCopy];
  int numClasses;
  Class *classes = NULL;
  numClasses = objc_getClassList(NULL, 0);
  if (numClasses > 0 )
  {
    classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);
    for (int i = 0; i < numClasses; i++) {
      Class class = classes[i];
      // Avoiding StoreKit inner classes
      if (class_conformsToProtocol(class, @protocol(UIApplicationDelegate)) && [class isSubclassOfClass:[UIResponder class]] && ![class isSubclassOfClass:[UIApplication class]]) {
          [appDelegates addObject:NSStringFromClass(classes[i])];
      }
      
    }
    free(classes);
  }
  if (appDelegates.count == 1)
    return appDelegates[0];
  return nil;
}

#pragma mark - Generic Swizzling
/**
 *  Swizzles a class' selector with another selector.
 *
 *  @param classname        The class' name.
 *  @param originalSelector The original selector.
 *  @param swizzledSelector The new selector, which should call the original.
 */
+ (void)swizzleClassname:(NSString *)classname
        originalSelector:(SEL)originalSelector
        swizzledSelector:(SEL)swizzledSelector
{
  Class class = NSClassFromString(classname);
  
  Method originalMethod = class_getInstanceMethod(class, originalSelector);
  Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
  
  BOOL didAddMethod =
  class_addMethod(class,
                  originalSelector,
                  method_getImplementation(swizzledMethod),
                  method_getTypeEncoding(swizzledMethod));
  
  if (didAddMethod) {
    class_replaceMethod(class,
                        swizzledSelector,
                        method_getImplementation(originalMethod),
                        method_getTypeEncoding(originalMethod));
  } else {
    method_exchangeImplementations(originalMethod, swizzledMethod);
  }
}

/**
 *  Swizzles a selector with a block. This is a very versatile way of swizzling
 *  due to the way instance swizzling works. Also very easy to actually use to 
 *  swizzle unknown classes.
 *
 *  @param classname        The class' name.
 *  @param originalSelector The selector to be swizzled.
 *  @param block            The block which will replace the original implementation.
 *
 *  @return An IMP pointer so the block can call the original implementation.
 */
+ (IMP)swizzleClassWithClassname:(NSString *)classname
                originalSelector:(SEL)originalSelector
                           block:(id)block
{
  IMP newImplementation = imp_implementationWithBlock(block);
  Class class = NSClassFromString(classname);
  Method method = class_getInstanceMethod(class, originalSelector);
  if (method == nil) {
    class_addMethod(class, originalSelector, newImplementation, "");
    return nil;
  } else {
    return class_replaceMethod(class, originalSelector, newImplementation, method_getTypeEncoding(method));
  }
}

#pragma mark - HokoDeeplinking Swizzles
+ (void)swizzleHokoDeeplinking
{
  NSString *appDelegateClassName = [self appDelegateClassName];
  if (appDelegateClassName) {
    [self swizzleOpenURLWithAppDelegateClassName:appDelegateClassName];
    [self swizzleLegacyOpenURLWithAppDelegateClassName:appDelegateClassName];
  } else {
    //NSLog(@"Could not Swizzle AppDelegate, please delegate application:openURL:sourceApplication:annotation: to [Hoko deeplinking]");
  }
}

+ (void)swizzleOpenURLWithAppDelegateClassName:(NSString *)appDelegateClassName
{
  __block IMP implementation = [HKSwizzling swizzleClassWithClassname:appDelegateClassName originalSelector:@selector(application:openURL:sourceApplication:annotation:) block:^BOOL(id blockSelf, UIApplication *application, NSURL *url, NSString *sourceApplication, id annotation){
    BOOL result = [[Hoko deeplinking] openURL:url sourceApplication:sourceApplication annotation:annotation];
    if (!result && implementation) {
      BOOL (*func)() = (void *)implementation;
      result = func(blockSelf, @selector(application:openURL:sourceApplication:annotation:), application, url, sourceApplication, annotation);
    }
    return result;
  }];
}

+ (void)swizzleLegacyOpenURLWithAppDelegateClassName:(NSString *)appDelegateClassName
{
  __block IMP implementation = [HKSwizzling swizzleClassWithClassname:appDelegateClassName originalSelector:@selector(application:handleOpenURL:) block:^BOOL(id blockSelf, UIApplication *application, NSURL *url){
    BOOL result = [[Hoko deeplinking] handleOpenURL:url];
    if (!result && implementation) {
      BOOL (*func)() = (void *)implementation;
      result = func(blockSelf, @selector(application:handleOpenURL:), application, url);
    }
    return result;
  }];
}

#pragma mark - Swizzle Push Notifications
+ (void)swizzleIOS8PushNotifications
{
  NSString *appDelegateClassName = [self appDelegateClassName];
  if (appDelegateClassName) {
    [self swizzleDidReceiveRemoteNotificationWithAppDelegateClassName:appDelegateClassName];
    [self swizzleDidRegisterForRemoteNotificationsWithDeviceTokenWithAppDelegateClassName:appDelegateClassName];
  } else {
    //NSLog(@"Could not Swizzle AppDelegate, please delegate all the push notification methods to [Hoko pushNotifications]");
  }
}

+ (void)swizzleLegacyPushNotifications
{
  NSString *appDelegateClassName = [self appDelegateClassName];
  if (appDelegateClassName) {
    [self swizzleDidReceiveRemoteNotificationWithAppDelegateClassName:appDelegateClassName];
    [self swizzleDidRegisterForRemoteNotificationsWithDeviceTokenWithAppDelegateClassName:appDelegateClassName];
  } else {
    //NSLog(@"Could not Swizzle AppDelegate, please delegate all the push notification methods to [Hoko pushNotifications]");
  }
}

+ (void)swizzleDidReceiveRemoteNotificationWithAppDelegateClassName:(NSString *)appDelegateClassName
{
  __block IMP implementation = [HKSwizzling swizzleClassWithClassname:appDelegateClassName originalSelector:@selector(application:didReceiveRemoteNotification:) block:^void(id blockSelf, UIApplication *application, NSDictionary *userInfo){
    BOOL handledNotification = [[Hoko pushNotifications] applicationDidReceiveRemoteNotification:userInfo];
    if (implementation && !handledNotification) {
      void (*func)() = (void *)implementation;
      func(blockSelf, @selector(application:didReceiveRemoteNotification:), application, userInfo);
    }
  }];
}

+ (void)swizzleDidRegisterForRemoteNotificationsWithDeviceTokenWithAppDelegateClassName:(NSString *)appDelegateClassName
{
  __block IMP implementation = [HKSwizzling swizzleClassWithClassname:appDelegateClassName originalSelector:@selector(application:didRegisterForRemoteNotificationsWithDeviceToken:) block:^void(id blockSelf, UIApplication *application, NSData *deviceToken){
    [[Hoko pushNotifications] applicationDidRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
    if (implementation) {
      void (*func)() = (void *)implementation;
      func(blockSelf, @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:), application, deviceToken);
    }
  }];
}

//+ (void)swizzleAppDelegateWithSelector:(SEL)selector block:(id)block returnBlock:(id)returnBlock
//{
//  __block void *(^cBlock)(void *) = block;
//  __block void *(^cReturnBlock)(void *, void *) = returnBlock;
//  NSString *appDelegateClassName = [HKSwizzling applicationDelegateClassName];
//  if (appDelegateClassName) {
//    __block IMP implementation = [HKSwizzling swizzleClassWithClassname:appDelegateClassName originalSelector:selector block:^void*(id blockSelf, ...){
//      va_list va_args;
//      va_start(va_args, blockSelf);
//      for (id arg = blockSelf; arg != nil; arg = va_arg(va_args, id))
//      {
//        NSLog(@"%@",arg);
//      }
//      va_end(va_args);
//      return NO;
//      //va_list args;
//      //va_start(args, blockSelf);
//      //NSLog(@"%@",va_arg(args, id));
////      void *result = cBlock(__VA_ARGS__);
////      if (implementation) {
////        void *(*func)(id, SEL, ...) = (void *)implementation;
////        void *originalResult = func(blockSelf, selector, __VA_ARGS__);
////        return cReturnBlock(result, originalResult);
////      }
////      return result;
//    }];
//  } else {
//    HKErrorLog([HKError couldNotFindAppDelegateError]);
//  }
//}

@end