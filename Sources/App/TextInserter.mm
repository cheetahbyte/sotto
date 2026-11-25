#import "TextInserter.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>

#include <initializer_list>

// How long the frontmost app gets to read the clipboard before it is restored.
static const NSTimeInterval kRestoreDelay = 0.4;

// Everything on the clipboard, so it can be put back after pasting.
static NSArray<NSPasteboardItem *> *CopyItems(NSPasteboard *pasteboard) {
  NSMutableArray *copies = [NSMutableArray new];
  for (NSPasteboardItem *item in pasteboard.pasteboardItems) {
    NSPasteboardItem *copy = [NSPasteboardItem new];
    for (NSPasteboardType type in item.types) {
      if (NSData *data = [item dataForType:type]) [copy setData:data forType:type];
    }
    [copies addObject:copy];
  }
  return copies;
}

@implementation TextInserter

+ (BOOL)isAllowed { return AXIsProcessTrusted(); }

+ (void)requestPermission {
  AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef) @{(__bridge NSString *)kAXTrustedCheckOptionPrompt : @YES});
}

// Pasting works in nearly every app, including ones that ignore the
// accessibility text APIs. The cost is borrowing the clipboard for a moment.
+ (BOOL)insert:(NSString *)text {
  NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
  if (!self.isAllowed) {
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
    [self requestPermission];
    return NO;
  }

  NSArray<NSPasteboardItem *> *previous = CopyItems(pasteboard);
  [pasteboard clearContents];
  [pasteboard setString:text forType:NSPasteboardTypeString];
  const NSInteger ours = pasteboard.changeCount;

  // Command-V. Only Command is set, whatever keys are still held from the shortcut.
  CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
  for (bool down : {true, false}) {
    CGEventRef event = CGEventCreateKeyboardEvent(source, kVK_ANSI_V, down);
    CGEventSetFlags(event, kCGEventFlagMaskCommand);
    CGEventPost(kCGAnnotatedSessionEventTap, event);
    CFRelease(event);
  }
  CFRelease(source);

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRestoreDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (pasteboard.changeCount != ours) return;  // someone copied something meanwhile; leave it
    [pasteboard clearContents];
    if (previous.count) [pasteboard writeObjects:previous];
  });
  return YES;
}

@end
