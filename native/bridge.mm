// SPDX-License-Identifier: MPL-2.0
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <unordered_map>
using Command = void (*)(void*, const char*, const char*);
@interface RibbonHost : NSObject <WKScriptMessageHandler, WKNavigationDelegate, NSMenuDelegate>
@property(nonatomic,retain) WKWebView *web, *sidebar, *status, *modal, *formula, *sheets;
@property(nonatomic,assign) NSView* parent;
@property(nonatomic,retain) id wrapper;
@property(nonatomic,retain) NSTimer* accessibilityTimer, *refreshTimer;
@property(nonatomic,assign) Command command;
@property(nonatomic,assign) BOOL themeApplied;
@property(nonatomic,assign) NSWindowTitleVisibility originalTitleVisibility;
@property(nonatomic,assign) BOOL originalDocumentIconHidden, windowChromeApplied;
@property(nonatomic,assign) void* context;
@property(nonatomic,retain) NSURL* directory;
@property(nonatomic,retain) NSDictionary* details;
@property(nonatomic,retain) NSDictionary* documentState;
@property(nonatomic,retain) NSDictionary* preferences;
@property(nonatomic,retain) NSMenu* menu;
@property(nonatomic,copy) NSString* colourProperty;
@property(nonatomic,copy) NSString* editor;
@property(nonatomic,retain) NSImage* editorIcon;
- (NSArray*)views;
- (void)refreshNative;
- (void)preferencesChanged:(NSNotification*)notification;
- (void)matchNativeTheme;
- (void)matchWindowChrome;
- (void)activateMenu;
- (void)windowBecameKey:(NSNotification*)notification;
- (void)activateWindow:(NSMenuItem*)item;
- (void)attachAccessibility;
- (void)publish:(NSString*)function value:(NSDictionary*)value;
- (void)showModal:(NSString*)file;
- (void)closeModal;
- (void)menuAction:(NSMenuItem*)item;
@end
static const char ribbonKey = 0;
struct AccessibilityMethods { IMP attributes; IMP hitTest; };
static std::unordered_map<Class, AccessibilityMethods> accessibilityMethods;
static AccessibilityMethods methodsFor(id object) {
 for(Class type=object_getClass(object);type;type=class_getSuperclass(type)){auto item=accessibilityMethods.find(type);if(item!=accessibilityMethods.end())return item->second;}
 return {nullptr,nullptr};
}
static NSMenu* originalMenu = nil;
static NSMenu* originalServicesMenu = nil;
static NSMenu* originalWindowsMenu = nil;
static NSAppearance* originalAppearance = nil;
static NSUInteger hostCount = 0;
static NSMutableArray* allHosts = nil;
static id ribbonAttributes(id object, SEL selector, NSString* attribute) {
 id result=((id(*)(id,SEL,NSString*))methodsFor(object).attributes)(object,selector,attribute);
 RibbonHost* host=objc_getAssociatedObject(object,&ribbonKey);
 if(host && ([attribute isEqualToString:NSAccessibilityChildrenAttribute] || [attribute isEqualToString:NSAccessibilityVisibleChildrenAttribute])) {
  NSMutableArray* children=[NSMutableArray arrayWithArray:[result isKindOfClass:NSArray.class]?result:@[]];
  for(WKWebView* view in [host views])if(!view.hidden && ![children containsObject:view])[children insertObject:view atIndex:0];
  return children;
 }
 return result;
}
static id ribbonHitTest(id object,SEL selector,NSPoint point) {
 RibbonHost* host=objc_getAssociatedObject(object,&ribbonKey);
 if(host)for(WKWebView* view in [[host views] reverseObjectEnumerator]) {
  NSPoint local=[host.parent convertPoint:[host.parent.window convertPointFromScreen:point] fromView:nil];
  if(!view.hidden && NSPointInRect(local,view.frame))return [view accessibilityHitTest:point];
 }
 return ((id(*)(id,SEL,NSPoint))methodsFor(object).hitTest)(object,selector,point);
}
static WKWebView* createView(RibbonHost* host,NSString* file) {
 WKWebViewConfiguration* config=[[[WKWebViewConfiguration alloc] init] autorelease];
 [config.userContentController addScriptMessageHandler:host name:@"writer"];
 WKWebView* web=[[[WKWebView alloc] initWithFrame:NSZeroRect configuration:config] autorelease];
 [web setValue:@NO forKey:@"drawsBackground"];
 web.navigationDelegate=host;
 [host.parent addSubview:web];
 [web loadFileURL:[host.directory URLByAppendingPathComponent:file] allowingReadAccessToURL:host.directory];
 return web;
}
static NSMenuItem* addMenu(RibbonHost* host,NSMenu* menu,NSString* label,NSString* command,NSString* key,NSString* argument) {
 NSMenuItem* item=[[[NSMenuItem alloc] initWithTitle:label action:@selector(menuAction:) keyEquivalent:key ?: @""] autorelease];
 item.target=host;item.representedObject=@{ @"command":command,@"argument":argument ?: @"" };
 [menu addItem:item];return item;
}
static NSMenu* makeMenu(RibbonHost* host) {
 NSMenu* main=[[[NSMenu alloc] initWithTitle:@"Docua"] autorelease];
 BOOL sheet=[host.editor containsString:@"sheet"],slides=[host.editor containsString:@"presentation"],draw=[host.editor containsString:@"drawing"],home=[host.editor isEqualToString:@"home"];
 NSString* factory=sheet?@"scalc":slides?@"simpress":draw?@"sdraw":@"swriter";
 NSArray* insert=sheet?@[@"Insert",@[@"Rows",@"InsertRows",@""],@[@"Columns",@"InsertColumns",@""],@[@"Sheet…",@"Insert",@""],@[@"Chart…",@"InsertObjectChart",@""],@[@"Picture…",@"InsertGraphic",@""],@[@"Link…",@"HyperlinkDialog",@"k"]]:(slides||draw)?@[@"Insert",@[@"New page",@"InsertPage",@""],@[@"Text box",@"Text",@""],@[@"Picture…",@"InsertGraphic",@""],@[@"Table…",@"InsertTable",@""],@[@"Chart…",@"InsertObjectChart",@""],@[@"Link…",@"HyperlinkDialog",@"k"]]:@[@"Insert",@[@"Table…",@"InsertTable",@""],@[@"Picture…",@"InsertGraphic",@""],@[@"Link…",@"HyperlinkDialog",@"k"],@[@"Page break",@"InsertPagebreak",@""],@[@"Comment",@"InsertAnnotation",@""]];
 NSArray* review=sheet?@[@"Data",@[@"Sort…",@"DataSort",@""],@[@"AutoFilter",@"DataFilterAutoFilter",@""],@[@"Filter…",@"DataFilterStandardFilter",@""],@[@"Validation…",@"Validation",@""],@[@"Protect sheet…",@"Protect",@""]]:(slides||draw)?@[@"Page",@[@"Duplicate",@"DuplicatePage",@""],@[@"Delete",@"DeletePage",@""],@[@"Layout…",@"AssignLayout",@""],@[@"Page properties…",@"PageSetup",@""],@[@"Slide show",@"Presentation",@""]]:@[@"Review",@[@"Spelling…",@"SpellingAndGrammarDialog",@""],@[@"Track changes",@"TrackChanges",@""],@[@"Accept all changes",@"AcceptAllTrackedChanges",@""],@[@"Word count",@"WordCountDialog",@""]];
 NSArray* groups=@[
 @[@"LibreOffice", @[@"About LibreOffice",@"About",@""],@[@"Settings…",@"@settings",@","]],
 @[@"File",@[@"New document",[@"private:factory/" stringByAppendingString:factory],@"n"],@[@"Open…",@"Open",@"o"],@[@"Save",@"Save",@"s"],@[@"Save as…",@"SaveAs",@""],@[@"Export PDF…",@"ExportDirectToPDF",@""],@[@"Print…",@"Print",@"p"],@[@"Close document",@"CloseDoc",@"w"]],
 @[@"Edit",@[@"Undo",@"Undo",@"z"],@[@"Redo",@"Redo",@"y"],@[@"Cut",@"Cut",@"x"],@[@"Copy",@"Copy",@"c"],@[@"Paste",@"Paste",@"v"],@[@"Select all",@"SelectAll",@"a"],@[@"Find…",@"@find",@"f"]],
 insert,
 @[@"Format",@[@"Bold",@"Bold",@"b"],@[@"Italic",@"Italic",@"i"],@[@"Underline",@"Underline",@"u"],@[sheet?@"Cells…":@"Paragraph…",sheet?@"FormatCellDialog":(slides||draw)?@"ParagraphDialog":@"@paragraph",@""],@[@"Page setup…",sheet||slides||draw?@"PageSetup":@"@page",@""]],
 @[@"View",@[@"Navigation",@"@sidebar",@""],@[@"Styles",@"@styles",@""],@[@"Ruler",@"Ruler",@""],@[@"Command search",@"@search",@""],@[@"Full screen",@"FullScreen",@""]],
 review,
 @[@"Help",@[@"Keyboard shortcuts",@"@shortcuts",@""],@[@"All commands",@"@search",@""]]
 ];
 if(home)groups=@[groups[0],@[@"File",@[@"New Writer document",@"private:factory/swriter",@"n"],@[@"New Calc spreadsheet",@"private:factory/scalc",@""],@[@"New Impress presentation",@"private:factory/simpress",@""],@[@"New Draw drawing",@"private:factory/sdraw",@""],@[@"Open…",@"Open",@"o"]],groups.lastObject];
 for(NSArray* group in groups) {
  NSMenuItem* top=[[[NSMenuItem alloc] initWithTitle:group[0] action:nil keyEquivalent:@""] autorelease];
  NSMenu* submenu=[[[NSMenu alloc] initWithTitle:group[0]] autorelease];submenu.autoenablesItems=NO;submenu.delegate=host;
  for(NSUInteger i=1;i<group.count;++i){NSArray* item=group[i];addMenu(host,submenu,item[0],item[1],item[2],nil);}
  top.submenu=submenu;[main addItem:top];
 }
 NSMenu* application=main.itemArray.firstObject.submenu;
 [application addItem:NSMenuItem.separatorItem];
 NSMenuItem* services=[[[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""] autorelease];services.tag=598;services.submenu=[[[NSMenu alloc] initWithTitle:@"Services"] autorelease];[application addItem:services];
 [application addItem:NSMenuItem.separatorItem];
 for(NSArray* definition in @[@[@"Hide LibreOffice",@"hide:",@"h"],@[@"Hide Others",@"hideOtherApplications:",@"h"],@[@"Show All",@"unhideAllApplications:",@""]]){
  NSMenuItem* item=[[[NSMenuItem alloc] initWithTitle:definition[0] action:NSSelectorFromString(definition[1]) keyEquivalent:definition[2]] autorelease];item.target=NSApp;if([definition[1] isEqualToString:@"hideOtherApplications:"])item.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagOption;[application addItem:item];
 }
 [application addItem:NSMenuItem.separatorItem];addMenu(host,application,@"Quit LibreOffice",@"Quit",@"q",nil);
 NSMenuItem* windowItem=[[[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""] autorelease];windowItem.tag=599;windowItem.submenu=[[[NSMenu alloc] initWithTitle:@"Window"] autorelease];
 for(NSArray* definition in @[@[@"Minimize",@"performMiniaturize:",@"m"],@[@"Zoom",@"performZoom:",@""]]){NSMenuItem* item=[[[NSMenuItem alloc] initWithTitle:definition[0] action:NSSelectorFromString(definition[1]) keyEquivalent:definition[2]] autorelease];item.target=host.parent.window;[windowItem.submenu addItem:item];}
 windowItem.submenu.delegate=host;
 addMenu(host,windowItem.submenu,@"Next Document Window",@"@nextWindow",@"`",nil);
 NSMenuItem* previous=addMenu(host,windowItem.submenu,@"Previous Document Window",@"@previousWindow",@"`",nil);previous.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagShift;
 [windowItem.submenu addItem:NSMenuItem.separatorItem];[main insertItem:windowItem atIndex:main.numberOfItems-1];
 return main;
}
@implementation RibbonHost
- (void)activateMenu { if(_menu && _menu.numberOfItems<3)self.menu=makeMenu(self);if(_menu && NSApp.mainMenu!=_menu){NSApp.mainMenu=_menu;NSApp.servicesMenu=[_menu.itemArray.firstObject.submenu itemWithTag:598].submenu;NSApp.windowsMenu=[_menu itemWithTag:599].submenu;} }
- (void)windowBecameKey:(NSNotification*)notification { [self activateMenu]; }
- (void)activateWindow:(NSMenuItem*)item { [(NSWindow*)item.representedObject makeKeyAndOrderFront:nil]; }
- (void)menuNeedsUpdate:(NSMenu*)menu {
 if(menu==[_menu itemWithTag:599].submenu){
  for(NSMenuItem* item in [[menu.itemArray copy] autorelease])if(item.tag==601)[menu removeItem:item];
  for(NSValue* value in allHosts){RibbonHost* host=(RibbonHost*)value.pointerValue;NSWindow* window=host.parent.window;if(!window)continue;NSMenuItem* item=[[[NSMenuItem alloc] initWithTitle:host.documentState[@"title"] ?: window.title action:@selector(activateWindow:) keyEquivalent:@""] autorelease];item.tag=601;item.target=self;item.representedObject=window;item.state=window==_parent.window?NSControlStateValueOn:NSControlStateValueOff;[menu addItem:item];}
 }
 NSResponder* responder=_parent.window.firstResponder;BOOL inWeb=NO;
 for(WKWebView* view in [self views])if([responder isKindOfClass:NSView.class] && [(NSView*)responder isDescendantOf:view])inWeb=YES;
 for(NSMenuItem* item in menu.itemArray){NSString* command=[item.representedObject isKindOfClass:NSDictionary.class]?item.representedObject[@"command"]:nil;id enabled=_details[@"commandStates"][command ?: @""];if(enabled)item.enabled=inWeb && [@[@"Cut",@"Copy",@"Paste",@"Undo",@"Redo"] containsObject:command]?YES:[enabled boolValue];}
}
- (void)preferencesChanged:(NSNotification*)notification { NSDictionary* value=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"DocuaInterface"] ?: @{};if([value isEqual:_preferences])return;self.preferences=value;[self publish:@"updatePreferences" value:value];[self matchWindowChrome]; }
- (void)matchWindowChrome {
 if(![_details[@"adapter"] isEqualToString:@"public-uno"])return;
 NSWindow* window=_parent.window;NSButton* icon=[window standardWindowButton:NSWindowDocumentIconButton];
 if(!_windowChromeApplied){_originalTitleVisibility=window.titleVisibility;_originalDocumentIconHidden=icon.hidden;_windowChromeApplied=YES;}
 BOOL minimal=![_preferences[@"nativeTitlebar"] isEqualToString:@"document"];
 window.titleVisibility=minimal?NSWindowTitleHidden:_originalTitleVisibility;icon.hidden=minimal?YES:_originalDocumentIconHidden;
}
- (void)matchNativeTheme { if(_command && [_details[@"adapter"] isEqualToString:@"public-uno"]){BOOL enabled=!_preferences[@"matchNativeAppearance"] || [_preferences[@"matchNativeAppearance"] boolValue];NSApp.appearance=enabled?[NSAppearance appearanceNamed:[_preferences[@"theme"] isEqualToString:@"dark"]?NSAppearanceNameDarkAqua:NSAppearanceNameAqua]:originalAppearance;_command(_context,"@nativeTheme",enabled?([_preferences[@"theme"] isEqualToString:@"dark"]?"2":"1"):"restore");} }
- (void)refreshNative { if(_command)_command(_context,"@refresh",""); }
- (void)attachAccessibility {
 Ivar ivar=class_getInstanceVariable(_parent.class,"mpChildWrapper");
 id wrapper=ivar?object_getIvar(_parent,ivar):nil;
 if(!wrapper || wrapper==_wrapper)return;
 if(_wrapper && objc_getAssociatedObject(_wrapper,&ribbonKey)==self)objc_setAssociatedObject(_wrapper,&ribbonKey,nil,OBJC_ASSOCIATION_ASSIGN);
 self.wrapper=wrapper;objc_setAssociatedObject(wrapper,&ribbonKey,self,OBJC_ASSOCIATION_ASSIGN);
 Class type=object_getClass(wrapper);
 if(accessibilityMethods.find(type)==accessibilityMethods.end()){
  Method attributes=class_getInstanceMethod(type,@selector(accessibilityAttributeValue:)),hitTest=class_getInstanceMethod(type,@selector(accessibilityHitTest:));
  if(!attributes || !hitTest)return;
  IMP attributesIMP=method_getImplementation(attributes),hitTestIMP=method_getImplementation(hitTest);
  if(attributesIMP==(IMP)ribbonAttributes)attributesIMP=methodsFor(wrapper).attributes;
  if(hitTestIMP==(IMP)ribbonHitTest)hitTestIMP=methodsFor(wrapper).hitTest;
  accessibilityMethods[type]={attributesIMP,hitTestIMP};
  class_addMethod(type,@selector(accessibilityAttributeValue:),attributesIMP,method_getTypeEncoding(attributes));
  class_addMethod(type,@selector(accessibilityHitTest:),hitTestIMP,method_getTypeEncoding(hitTest));
  method_setImplementation(class_getInstanceMethod(type,@selector(accessibilityAttributeValue:)),(IMP)ribbonAttributes);
  method_setImplementation(class_getInstanceMethod(type,@selector(accessibilityHitTest:)),(IMP)ribbonHitTest);
 }
 [_accessibilityTimer invalidate];self.accessibilityTimer=nil;
 NSAccessibilityPostNotification(wrapper,NSAccessibilityLayoutChangedNotification);
}
- (NSArray*)views { NSMutableArray* result=[NSMutableArray array];for(id value in @[_web ?: (id)NSNull.null,_sidebar ?: (id)NSNull.null,_status ?: (id)NSNull.null,_formula ?: (id)NSNull.null,_sheets ?: (id)NSNull.null,_modal ?: (id)NSNull.null])if(value!=NSNull.null)[result addObject:value];return result; }
- (void)publish:(NSString*)function value:(NSDictionary*)value {
 NSData* data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
 NSString* json=[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
 NSString* script=[NSString stringWithFormat:@"window.%@ && window.%@(%@)",function,function,json];
 for(WKWebView* view in [self views])[view evaluateJavaScript:script completionHandler:nil];
}
- (void)showModal:(NSString*)file {
 [self closeModal];self.modal=createView(self,file);
 CGFloat requestedWidth=[file isEqualToString:@"colour.html"]?480:([file isEqualToString:@"sheetname.html"]?460:([file isEqualToString:@"paragraph.html"]?600:960)),requestedHeight=[file isEqualToString:@"colour.html"]?320:([file isEqualToString:@"sheetname.html"]?260:([file isEqualToString:@"paragraph.html"]?400:720));
 CGFloat width=MIN(requestedWidth,_parent.bounds.size.width-40),height=MIN(requestedHeight,_parent.bounds.size.height-40);
 _modal.frame=NSMakeRect((_parent.bounds.size.width-width)/2,(_parent.bounds.size.height-height)/2,width,height);
 [_parent.window makeFirstResponder:_modal];NSAccessibilityPostNotification(_wrapper,NSAccessibilityLayoutChangedNotification);
}
- (void)closeModal {
 if(_modal){[_modal.configuration.userContentController removeScriptMessageHandlerForName:@"writer"];[_modal removeFromSuperview];self.modal=nil;}
 if(_command)_command(_context,"@focus","");
 [_parent.window makeFirstResponder:_parent];
}
- (void)webView:(WKWebView*)web didFinishNavigation:(WKNavigation*)navigation {
 [self publish:@"updatePreferences" value:_preferences ?: @{}];
 if(_details)[self publish:@"updateDetails" value:_details];
 if(_documentState)[self publish:@"updateDocument" value:_documentState];
}
- (void)webView:(WKWebView*)web decidePolicyForNavigationAction:(WKNavigationAction*)action decisionHandler:(void (^)(WKNavigationActionPolicy))decision {
 NSURL* url=action.request.URL;
 NSString* root=[_directory.path.stringByStandardizingPath stringByAppendingString:@"/"];
 BOOL local=url.isFileURL && [url.path.stringByStandardizingPath hasPrefix:root];
 decision(local?WKNavigationActionPolicyAllow:WKNavigationActionPolicyCancel);
}
- (void)menuAction:(NSMenuItem*)item {
 NSString* command=item.representedObject[@"command"];
 NSDictionary* selectors=@{@"Cut":@"cut:",@"Copy":@"copy:",@"Paste":@"paste:",@"SelectAll":@"selectAll:",@"Undo":@"undo:",@"Redo":@"redo:"};
 NSResponder* responder=_parent.window.firstResponder;
 BOOL inWeb=NO;for(WKWebView* view in [self views])if([responder isKindOfClass:NSView.class] && [(NSView*)responder isDescendantOf:view])inWeb=YES;
 if(inWeb && selectors[command] && [NSApp sendAction:NSSelectorFromString(selectors[command]) to:nil from:item])return;
 [self handle:item.representedObject];
}
- (void)handle:(NSDictionary*)body {
 [[self retain] autorelease];
 NSString* cmd=body[@"command"];NSString* arg=body[@"argument"] ?: @"";
 if(![cmd isKindOfClass:NSString.class] || ![arg isKindOfClass:NSString.class])return;
 if([cmd isEqualToString:@"@colour"] || [cmd isEqualToString:@"@highlight"]){self.colourProperty=[cmd isEqualToString:@"@colour"]?@"CharColor":@"CharBackColor";[self showModal:@"colour.html"];return;}
 if([cmd isEqualToString:@"@colourValue"]){if(_command)_command(_context,"@format",[[NSString stringWithFormat:@"%@=%@",_colourProperty ?: @"CharColor",arg] UTF8String]);return;}
 if([cmd isEqualToString:@"Quit"]){if(_command)_command(_context,"@quit","");return;}
 if([cmd isEqualToString:@"@nextWindow"] || [cmd isEqualToString:@"@previousWindow"]){NSMutableArray* windows=[NSMutableArray array];for(NSValue* value in allHosts){NSWindow* window=((RibbonHost*)value.pointerValue).parent.window;if(window && ![windows containsObject:window])[windows addObject:window];}NSUInteger current=[windows indexOfObject:_parent.window];if(windows.count && current!=NSNotFound){NSUInteger index=[cmd isEqualToString:@"@nextWindow"]?(current+1)%windows.count:(current+windows.count-1)%windows.count;[windows[index] makeKeyAndOrderFront:nil];}return;}
 if([cmd isEqualToString:@"@settings"]){[self showModal:@"settings.html"];return;}
 if([cmd isEqualToString:@"@search"]){[self showModal:@"search.html"];return;}
 if([cmd isEqualToString:@"@renameSheet"]){[self showModal:@"sheetname.html"];return;}
 if([cmd isEqualToString:@"@paragraph"]){[self showModal:@"paragraph.html"];return;}
 if([cmd isEqualToString:@"@page"]){[self showModal:@"page.html"];return;}
 if([cmd isEqualToString:@"@shortcuts"]){[self showModal:@"shortcuts.html"];return;}
 if([cmd isEqualToString:@"@closeModal"]){[self closeModal];return;}
 if([cmd isEqualToString:@"@preferences"]) {
  NSData* data=[arg dataUsingEncoding:NSUTF8StringEncoding];id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if([value isKindOfClass:NSDictionary.class]){self.preferences=value;[NSUserDefaults.standardUserDefaults setObject:value forKey:@"DocuaInterface"];[self publish:@"updatePreferences" value:value];[self matchNativeTheme];[self matchWindowChrome];}
  return;
 }
 if([cmd isEqualToString:@"@styles"] || [cmd isEqualToString:@"@find"]) {
  NSString* panel=[cmd isEqualToString:@"@styles"]?@"styles":@"find";
  [self publish:@"setSidebar" value:@{@"panel":panel}];if(_command)_command(_context,"@sidebar","open");return;
 }
 if(_command)_command(_context,cmd.UTF8String,arg.UTF8String);
 if(![cmd hasPrefix:@"@ribbonHeight"]){
  if(_preferences[@"returnFocus"] && ![_preferences[@"returnFocus"] boolValue]){NSString* surface=body[@"surface"];WKWebView* target=[surface isEqualToString:@"formula"]?_formula:[surface isEqualToString:@"sidebar"]?_sidebar:_web;[_parent.window makeFirstResponder:target];}
  else [_parent.window makeFirstResponder:_parent];
 }
}
- (void)userContentController:(WKUserContentController*)controller didReceiveScriptMessage:(WKScriptMessage*)message { if([message.body isKindOfClass:NSDictionary.class])[self handle:message.body]; }
- (void)dealloc { [_accessibilityTimer invalidate];[_accessibilityTimer release]; [_wrapper release];[_web release];[_sidebar release];[_status release];[_modal release];[_formula release];[_sheets release];[_directory release];[_details release];[_documentState release];[_preferences release];[_menu release];[_colourProperty release];[_editor release];[_editorIcon release];[super dealloc]; }
@end
extern "C" bool ribbonCanAttach(void* view) {
 NSView* parent=(NSView*)view;return NSThread.isMainThread && [parent isKindOfClass:NSView.class] && parent.window && class_getInstanceVariable(parent.class,"mpChildWrapper");
}
extern "C" void ribbonStartRefresh(void* handle) { RibbonHost* host=(RibbonHost*)handle;[host.refreshTimer invalidate];host.refreshTimer=[NSTimer timerWithTimeInterval:1 target:host selector:@selector(refreshNative) userInfo:nil repeats:YES];[NSRunLoop.mainRunLoop addTimer:host.refreshTimer forMode:NSRunLoopCommonModes]; }
extern "C" void* ribbonCreate(void* view,void* context,Command command) {
 RibbonHost* host=[[RibbonHost alloc] init];host.parent=(NSView*)view;host.context=context;host.command=command;
 Dl_info info;dladdr((void*)&ribbonCreate,&info);host.directory=[NSURL fileURLWithPath:[[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent] isDirectory:YES];
 host.preferences=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"DocuaInterface"] ?: @{};
 [NSNotificationCenter.defaultCenter addObserver:host selector:@selector(preferencesChanged:) name:NSUserDefaultsDidChangeNotification object:nil];
 [NSNotificationCenter.defaultCenter addObserver:host selector:@selector(windowBecameKey:) name:NSWindowDidBecomeKeyNotification object:host.parent.window];
 host.web=createView(host,@"ribbon.html");host.sidebar=createView(host,@"sidebar.html");host.status=createView(host,@"status.html");
 [host attachAccessibility];
 if(!host.wrapper)host.accessibilityTimer=[NSTimer scheduledTimerWithTimeInterval:0.1 target:host selector:@selector(attachAccessibility) userInfo:nil repeats:YES];
 if(!hostCount++){originalMenu=[NSApp.mainMenu retain];originalServicesMenu=[NSApp.servicesMenu retain];originalWindowsMenu=[NSApp.windowsMenu retain];originalAppearance=[NSApp.appearance retain];allHosts=[[NSMutableArray alloc] init];}[allHosts addObject:[NSValue valueWithPointer:host]];host.menu=makeMenu(host);
 NSAccessibilityPostNotification(host.wrapper,NSAccessibilityLayoutChangedNotification);return host;
}
extern "C" void ribbonUpdate(void* handle,double x,double y,double width,double height,const char* title,bool modified,bool saved,bool autosave) {
 RibbonHost* host=(RibbonHost*)handle;[host attachAccessibility];NSView* parent=host.parent;
 host.web.frame=NSMakeRect(0,parent.bounds.size.height-y-height,parent.bounds.size.width,height);
 host.status.frame=NSMakeRect(0,0,parent.bounds.size.width,24);
 if(parent.window.isKeyWindow)[host activateMenu];
 NSButton* documentIcon=[parent.window standardWindowButton:NSWindowDocumentIconButton];if(host.editorIcon && documentIcon.image!=host.editorIcon)documentIcon.image=host.editorIcon;
 host.documentState=@{@"title":[NSString stringWithUTF8String:title],@"modified":@(modified),@"saved":@(saved),@"autosave":@(autosave)};
 [host publish:@"updateDocument" value:host.documentState];
 [host publish:@"updatePreferences" value:host.preferences];
}
extern "C" void ribbonDetails(void* handle,const char* json) {
 RibbonHost* host=(RibbonHost*)handle;
 NSData* bytes=[[NSString stringWithUTF8String:json] dataUsingEncoding:NSUTF8StringEncoding];
 NSDictionary* data=[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];if(![data isKindOfClass:NSDictionary.class])return;
 if(data[@"notification"]){[host publish:@"updateDetails" value:data];return;}
 NSMutableDictionary* merged=[NSMutableDictionary dictionaryWithDictionary:host.details ?: @{}];[merged addEntriesFromDictionary:data];host.details=merged;data=merged;
 if(!host.themeApplied && [data[@"adapter"] isEqualToString:@"public-uno"]){host.themeApplied=YES;[host matchNativeTheme];}
 [host matchWindowChrome];
 if(host.parent.window.isKeyWindow)[host activateMenu];
 NSString* editor=data[@"module"];if(editor && ![editor isEqualToString:host.editor]){host.editor=editor;NSString* icon=[editor containsString:@"sheet"]?@"calc":[editor containsString:@"presentation"]?@"impress":[editor containsString:@"drawing"]?@"draw":@"writer";host.editorIcon=[[[NSImage alloc] initWithContentsOfURL:[host.directory URLByAppendingPathComponent:[NSString stringWithFormat:@"icons/%@.png",icon]]] autorelease];NSMenu* old=host.menu;host.menu=makeMenu(host);if(host.parent.window.isKeyWindow || NSApp.mainMenu==old)[host activateMenu];}
 double top=NSMinY(host.web.frame);
 if([editor containsString:@"sheet"]){
  if(!host.formula){host.formula=createView(host,@"formula.html");host.sheets=createView(host,@"sheets.html");}

 }
 double right=[data[@"viewX"] doubleValue]+[data[@"viewWidth"] doubleValue]+16;
 double width=MAX(42,host.parent.bounds.size.width-right);
 if(width>host.parent.bounds.size.width/2)width=42;
 if(host.formula){host.formula.frame=NSMakeRect(0,top-38,host.parent.bounds.size.width-width,38);host.sheets.frame=NSMakeRect(0,24,host.parent.bounds.size.width-width,26);}
 double y=24;
 host.sidebar.frame=NSMakeRect(host.parent.bounds.size.width-width,y,width,MAX(0,top-y));
 [host publish:@"updateDetails" value:data];
}
extern "C" void ribbonDestroy(void* handle) {
 RibbonHost* host=(RibbonHost*)handle;[NSNotificationCenter.defaultCenter removeObserver:host];host.command=nullptr;[host.refreshTimer invalidate];host.refreshTimer=nil;
 [allHosts removeObject:[NSValue valueWithPointer:host]];
 if(host.windowChromeApplied){host.parent.window.titleVisibility=host.originalTitleVisibility;[host.parent.window standardWindowButton:NSWindowDocumentIconButton].hidden=host.originalDocumentIconHidden;}
 [host.accessibilityTimer invalidate];host.accessibilityTimer=nil;
 if(host.wrapper && objc_getAssociatedObject(host.wrapper,&ribbonKey)==host)objc_setAssociatedObject(host.wrapper,&ribbonKey,nil,OBJC_ASSOCIATION_ASSIGN);
 for(WKWebView* view in [host views]){[view.configuration.userContentController removeScriptMessageHandlerForName:@"writer"];[view removeFromSuperview];}
 if(NSApp.mainMenu==host.menu)NSApp.mainMenu=originalMenu;
 if(!--hostCount){NSApp.appearance=originalAppearance;[originalAppearance release];originalAppearance=nil;NSApp.mainMenu=originalMenu;NSApp.servicesMenu=originalServicesMenu;NSApp.windowsMenu=originalWindowsMenu;[originalServicesMenu release];originalServicesMenu=nil;[originalWindowsMenu release];originalWindowsMenu=nil;[originalMenu release];originalMenu=nil;[allHosts release];allHosts=nil;}
 [host release];
}

extern "C" void* officeStartCreate(void* view,void* context,Command command) {
 RibbonHost* host=(RibbonHost*)ribbonCreate(view,context,command);
 for(WKWebView* web in [host views]){[web.configuration.userContentController removeScriptMessageHandlerForName:@"writer"];[web removeFromSuperview];}
 host.sidebar=nil;host.status=nil;host.web=createView(host,@"home.html");
 host.web.frame=host.parent.bounds;host.web.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
 host.editor=@"home";host.menu=makeMenu(host);[host activateMenu];return host;
}
