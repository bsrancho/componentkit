/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKStatefulViewComponentController.h"

#import <ComponentKit/CKComponent.h>
#import <ComponentKit/CKComponentInternal.h>

#import "CKStatefulViewComponent.h"
#import "CKStatefulViewReusePool.h"

#import <objc/runtime.h>

@implementation CKStatefulViewComponentController
{
  UIView *_statefulView;
  BOOL _mounted;
  id _statefulViewContext;
}

+ (UIView *)newStatefulView:(id)context
{
  NSAssert(false, @"Should be implemented by subclasses.");
  return nil;
}

+ (id)contextForNewStatefulView:(CKComponent *)component
{
  return nil;
}

+ (void)configureStatefulView:(UIView *)statefulView
                 forComponent:(CKComponent *)component
{
  NSAssert(false, @"Should be implemented by subclasses.");
}

+ (NSInteger)maximumPoolSize:(id)context
{
  return -1;
}

- (UIView *)statefulView
{
  return _statefulView;
}

- (void)didAcquireStatefulView:(UIView *)statefulView {}
- (void)willRelinquishStatefulView:(UIView *)statefulView {}

- (BOOL)canRelinquishStatefulView
{
  return YES;
}

- (void)canRelinquishStatefulViewDidChange
{
  [self _relinquishStatefulViewIfPossible];
}

#pragma mark - Lifecycle

- (void)didMount
{
  [super didMount];

  NSAssert([[self component] isKindOfClass:[CKStatefulViewComponent class]], @"Component should be a stateful view component.");
  NSAssert(
    method_getImplementation(class_getInstanceMethod([CKStatefulViewComponentController class], @selector(statefulView))) ==
    method_getImplementation(class_getInstanceMethod([self class], @selector(statefulView))),
    @"Should not override the method -statefulView.");

  if (_statefulView == nil) {
    _statefulViewContext = [[self class] contextForNewStatefulView:[self component]];
    _statefulView = [[CKStatefulViewReusePool sharedPool] dequeueStatefulViewForControllerClass:[self class]
                                                                             preferredSuperview:[self view]
                                                                                        context:_statefulViewContext];
    if (_statefulView == nil) {
      _statefulView = [[self class] newStatefulView:_statefulViewContext];
    }
    [[self class] configureStatefulView:_statefulView forComponent:[self component]];
    [self didAcquireStatefulView:_statefulView];
  }
  [self _presentStatefulView];
  _mounted = YES;
}

- (void)didRemount
{
  [super didRemount];
  [self _presentStatefulView];
}

- (void)didUpdateComponent
{
  [super didUpdateComponent];
  if (_statefulView) {
    [[self class] configureStatefulView:_statefulView forComponent:[self component]];
  }
}

- (void)didUnmount
{
  [super didUnmount];
  _mounted = NO;
  [self _relinquishStatefulViewIfPossible];
}

#pragma mark - Helpers

- (void)_presentStatefulView
{
  const CKComponentViewContext &context = [[self component] viewContext];
  [_statefulView setFrame:context.frame];

  NSAssert([context.view.subviews count] <= 1, @"Should never have more than a single stateful subview.");
  UIView *existingView = [context.view.subviews lastObject];
  if (existingView != _statefulView) {
    [existingView removeFromSuperview];
  }

  [context.view addSubview:_statefulView];
}

- (void)_relinquishStatefulViewIfPossible
{
  if ([self canRelinquishStatefulView]) {
    // There is no guarantee when this reuse pool will execute this block
    CKStatefulViewComponentController *__weak weakSelf = self;
    [[CKStatefulViewReusePool sharedPool]
     enqueueStatefulView:_statefulView
     forControllerClass:[self class]
     context:_statefulViewContext
     mayRelinquishBlock:^BOOL{
       CKStatefulViewComponentController *strongSelf = weakSelf;
       if (!strongSelf) {
         return YES;
       }
       if (!strongSelf->_mounted && [strongSelf canRelinquishStatefulView]) {
         [strongSelf willRelinquishStatefulView:strongSelf->_statefulView];
         strongSelf->_statefulView = nil;
         strongSelf->_statefulViewContext = nil;
         return YES;
       }
       return NO;
     }];
  }
}

@end
