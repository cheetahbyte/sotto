#import <AppKit/AppKit.h>

#import "AppDelegate.h"

int main() {
  @autoreleasepool {
    NSApplication *app = NSApplication.sharedApplication;
    AppDelegate *delegate = [AppDelegate new];
    app.delegate = delegate;
    [app run];
  }
  return 0;
}
