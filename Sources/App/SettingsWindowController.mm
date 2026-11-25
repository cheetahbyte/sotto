#import "SettingsWindowController.h"

#import "Defaults.h"
#import "SettingsPanes.h"

#include <utility>

@interface SettingsTabViewController : NSTabViewController
@end

@implementation SettingsTabViewController

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item {
  [super tabView:tabView didSelectTabViewItem:item];
  [NSUserDefaults.standardUserDefaults setInteger:self.selectedTabViewItemIndex forKey:kSettingsPaneKey];
  [self fitWindowToPane:item animated:YES];
}

- (void)fitWindowToPane:(NSTabViewItem *)item animated:(BOOL)animated {
  NSWindow *window = self.view.window;
  self.title = item.label;
  if (!window) return;
  const NSSize size = item.viewController.view.fittingSize;
  NSRect frame = [window frameRectForContentRect:NSMakeRect(0, 0, size.width, size.height)];
  frame.origin = NSMakePoint(NSMinX(window.frame), NSMaxY(window.frame) - NSHeight(frame));
  const BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  [window setFrame:frame display:YES animate:animated && !reduceMotion];
}

@end

@implementation SettingsWindowController

- (instancetype)init {
  SettingsTabViewController *tabs = [SettingsTabViewController new];
  tabs.tabStyle = NSTabViewControllerTabStyleToolbar;
  tabs.transitionOptions = NSViewControllerTransitionNone;

  NSArray<NSArray *> *panes = @[
    @[ @"General", @"gearshape", [GeneralPane new] ],
    @[ @"Dictation", @"mic", [DictationPane new] ],
    @[ @"Vocabulary", @"character.book.closed", [VocabularyPane new] ],
    @[ @"Privacy", @"hand.raised", [PrivacyPane new] ],
  ];
  for (NSArray *pane in panes) {
    NSTabViewItem *item = [NSTabViewItem tabViewItemWithViewController:pane[2]];
    item.label = pane[0];
    item.image = [NSImage imageWithSystemSymbolName:pane[1] accessibilityDescription:nil];
    [tabs addTabViewItem:item];
  }
  const NSInteger lastPane = [NSUserDefaults.standardUserDefaults integerForKey:kSettingsPaneKey];
  if (lastPane > 0 && std::cmp_less(lastPane, panes.count)) tabs.selectedTabViewItemIndex = lastPane;

  NSWindow *window = [NSWindow windowWithContentViewController:tabs];
  window.styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
  window.toolbarStyle = NSWindowToolbarStylePreference;
  self = [super initWithWindow:window];
  if (!self) return nil;
  [tabs fitWindowToPane:tabs.tabViewItems[static_cast<NSUInteger>(tabs.selectedTabViewItemIndex)] animated:NO];
  [window center];
  return self;
}

@end
