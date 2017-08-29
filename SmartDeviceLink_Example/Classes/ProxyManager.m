//
//  ProxyManager.m
//  SmartDeviceLink-iOS

#import "SmartDeviceLink.h"
#import "ProxyManager.h"
#import "Preferences.h"
#import "SDLDebugTool.h"
#import "TemplateManager.h"
#import "AddCommandManager.h"
#import "SoftButtonManager.h"

NSString *const SDLAppName = @"SDL Example App";
NSString *const SDLAppId = @"9999";
NSString *const PointingSoftButtonArtworkName = @"PointingSoftButtonIcon";
NSString *const MainGraphicArtworkName = @"MainArtwork";

BOOL const ShouldRestartOnDisconnect = NO;

typedef NS_ENUM(NSUInteger, SDLHMIFirstState) {
    SDLHMIFirstStateNone,
    SDLHMIFirstStateNonNone,
    SDLHMIFirstStateFull
};

typedef NS_ENUM(NSUInteger, SDLHMIInitialShowState) {
    SDLHMIInitialShowStateNone,
    SDLHMIInitialShowStateDataAvailable,
    SDLHMIInitialShowStateShown
};


NS_ASSUME_NONNULL_BEGIN

@interface ProxyManager () <SDLManagerDelegate>

// Describes the first time the HMI state goes non-none and full.
@property (assign, nonatomic) SDLHMIFirstState firstTimeState;
@property (assign, nonatomic) SDLHMIInitialShowState initialShowState;

@end


@implementation ProxyManager

#pragma mark - Initialization

+ (instancetype)sharedManager {
    static ProxyManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[ProxyManager alloc] init];
    });

    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _state = ProxyStateStopped;
    _firstTimeState = SDLHMIFirstStateNone;
    _initialShowState = SDLHMIInitialShowStateNone;

    return self;
}

- (void)startIAP {
    [self sdlex_updateProxyState:ProxyStateSearchingForConnection];
    // Check for previous instance of sdlManager
    if (self.sdlManager) { return; }
    SDLLifecycleConfiguration *lifecycleConfig = [self.class sdlex_setLifecycleConfigurationPropertiesOnConfiguration:[SDLLifecycleConfiguration defaultConfigurationWithAppName:SDLAppName appId:SDLAppId]];

    // Assume this is production and disable logging
    lifecycleConfig.logFlags = SDLLogOutputNone;

    SDLConfiguration *config = [SDLConfiguration configurationWithLifecycle:lifecycleConfig lockScreen:[SDLLockScreenConfiguration enabledConfiguration]];
    self.sdlManager = [[SDLManager alloc] initWithConfiguration:config delegate:self];

    [self startManager];
}

- (void)startTCP {
    [self sdlex_updateProxyState:ProxyStateSearchingForConnection];
    // Check for previous instance of sdlManager
    if (self.sdlManager) { return; }
    SDLLifecycleConfiguration *lifecycleConfig = [self.class sdlex_setLifecycleConfigurationPropertiesOnConfiguration:[SDLLifecycleConfiguration debugConfigurationWithAppName:SDLAppName appId:SDLAppId ipAddress:[Preferences sharedPreferences].ipAddress port:[Preferences sharedPreferences].port]];
    SDLConfiguration *config = [SDLConfiguration configurationWithLifecycle:lifecycleConfig lockScreen:[SDLLockScreenConfiguration enabledConfiguration]];
    self.sdlManager = [[SDLManager alloc] initWithConfiguration:config delegate:self];

    [self startManager];
}

- (void)startManager {
    __weak typeof (self) weakSelf = self;
    [self.sdlManager startWithReadyHandler:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            NSLog(@"SDL errored starting up: %@", error);
            [weakSelf sdlex_updateProxyState:ProxyStateStopped];
            return;
        }

        [weakSelf sdlex_updateProxyState:ProxyStateConnected];

        [weakSelf sdlex_setupPermissionsCallbacks];

        if ([weakSelf.sdlManager.hmiLevel isEqualToEnum:[SDLHMILevel FULL]]) {
            [weakSelf sdlex_showInitialData];
        }
    }];
}

- (void)reset {
    [self sdlex_updateProxyState:ProxyStateStopped];
    [self.sdlManager stop];
    // Remove reference
    self.sdlManager = nil;
}


#pragma mark - Helpers

- (void)sdlex_showInitialData {
    if ((self.initialShowState != SDLHMIInitialShowStateDataAvailable) || ![self.sdlManager.hmiLevel isEqualToEnum:[SDLHMILevel FULL]]) {
        return;
    }

    NSLog(@"Sending capability requests");
    SDLGetSystemCapability *getNavigationCapability = [[SDLGetSystemCapability alloc] initWithType:[SDLSystemCapabilityType NAVIGATION]];
    [self.sdlManager sendRequest:getNavigationCapability withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLRPCResponse * _Nullable response, NSError * _Nullable error) {
        NSLog(@"Navigation Capability:\n"
              "Request: %@"
              "Response: %@"
              "Error: %@", request, response, error);
    }];
    SDLGetSystemCapability *getPhoneCapability = [[SDLGetSystemCapability alloc] initWithType:[SDLSystemCapabilityType PHONE_CALL]];
    [self.sdlManager sendRequest:getPhoneCapability withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLRPCResponse * _Nullable response, NSError * _Nullable error) {
        NSLog(@"Phone Capability:\n"
              "Request: %@"
              "Response: %@"
              "Error: %@", request, response, error);
    }];
    SDLGetSystemCapability *getVideoStreamingCapability = [[SDLGetSystemCapability alloc] initWithType:[SDLSystemCapabilityType VIDEO_STREAMING]];
    [self.sdlManager sendRequest:getVideoStreamingCapability withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLRPCResponse * _Nullable response, NSError * _Nullable error) {
        NSLog(@"Video Streaming Capability:\n"
              "Request: %@"
              "Response: %@"
              "Error: %@", request, response, error);
    }];

    SDLSetDisplayLayout *displayLayout = [[SDLSetDisplayLayout alloc] initWithLayout:[[SDLPredefinedLayout NON_MEDIA] value]];
    [self.sdlManager sendRequest:displayLayout];

    self.initialShowState = SDLHMIInitialShowStateShown;

    SDLShow* show = [[SDLShow alloc] initWithMainField1:@"SDL" mainField2:@"Test App" alignment:[SDLTextAlignment CENTERED]];

    SDLSoftButton *pointingSoftButton = [SoftButtonManager createSoftButtonWithTextAndImage:@"Press" imageName:PointingSoftButtonArtworkName softButtonId:100 manager:self.sdlManager handler:^{
        SDLAlert* alert = [[SDLAlert alloc] init];
        alert.alertText1 = @"You pushed the button!";
        [self.sdlManager sendRequest:alert];

    }];

    show.softButtons = [@[pointingSoftButton] mutableCopy];
    show.graphic = [self.class sdlex_mainGraphicImage];

    [self.sdlManager sendRequest:show];
}

- (void)sdlex_setupPermissionsCallbacks {
    // This will tell you whether or not you can use the Show RPC right at this moment
    BOOL isAvailable = [self.sdlManager.permissionManager isRPCAllowed:@"Show"];
    NSLog(@"Show is allowed? %@", @(isAvailable));

    // This will set up a block that will tell you whether or not you can use none, all, or some of the RPCs specified, and notifies you when those permissions change
    SDLPermissionObserverIdentifier observerId = [self.sdlManager.permissionManager addObserverForRPCs:@[@"Show", @"Alert"] groupType:SDLPermissionGroupTypeAllAllowed withHandler:^(NSDictionary<SDLPermissionRPCName, NSNumber<SDLBool> *> * _Nonnull change, SDLPermissionGroupStatus status) {
        NSLog(@"Show changed permission to status: %@, dict: %@", @(status), change);
    }];
    // The above block will be called immediately, this will then remove the block from being called any more
    [self.sdlManager.permissionManager removeObserverForIdentifier:observerId];

    // This will give us the current status of the group of RPCs, as if we had set up an observer, except these are one-shot calls
    NSArray *rpcGroup =@[@"AddCommand", @"PerformInteraction"];
    SDLPermissionGroupStatus commandPICSStatus = [self.sdlManager.permissionManager groupStatusOfRPCs:rpcGroup];
    NSDictionary *commandPICSStatusDict = [self.sdlManager.permissionManager statusOfRPCs:rpcGroup];
    NSLog(@"Command / PICS status: %@, dict: %@", @(commandPICSStatus), commandPICSStatusDict);

    // This will set up a long-term observer for the RPC group and will tell us when the status of any specified RPC changes (due to the `SDLPermissionGroupTypeAny`) option.
    [self.sdlManager.permissionManager addObserverForRPCs:rpcGroup groupType:SDLPermissionGroupTypeAny withHandler:^(NSDictionary<SDLPermissionRPCName, NSNumber<SDLBool> *> * _Nonnull change, SDLPermissionGroupStatus status) {
        NSLog(@"Command / PICS changed permission to status: %@, dict: %@", @(status), change);
    }];
}

+ (SDLLifecycleConfiguration *)sdlex_setLifecycleConfigurationPropertiesOnConfiguration:(SDLLifecycleConfiguration *)config {
    SDLArtwork *appIconArt = [SDLArtwork persistentArtworkWithImage:[UIImage imageNamed:@"AppIcon60x60@2x"] name:@"AppIcon" asImageFormat:SDLArtworkImageFormatPNG];

    config.shortAppName = @"SDL Example";
    config.appIcon = appIconArt;
    config.voiceRecognitionCommandNames = @[@"S D L Example"];
    config.ttsName = [SDLTTSChunk textChunksFromString:config.shortAppName];
    config.appType = SDLAppHMIType.MEDIA;

    return config;
}

- (void)sdlex_updateProxyState:(ProxyState)newState {
    if (self.state != newState) {
        [self willChangeValueForKey:@"state"];
        _state = newState;
        [self didChangeValueForKey:@"state"];
    }
}

#pragma mark - RPC builders


+ (SDLAddSubMenu *)sdlex_changeTemplateAddSubmenuWithManager:(SDLManager *)manager commandId:(int)commandId {
    return [[SDLAddSubMenu alloc] initWithId:commandId menuName:@"Change the Template"];
}

+ (void)sdlex_createSliderWithManager:(SDLManager *)manager {
    SDLSlider *slider = [[SDLSlider alloc] init];
    slider.timeout = @10000;
    slider.position = @1;
    slider.numTicks = @8;
    slider.sliderHeader = @"Slider Header";
    slider.sliderFooter = [[NSMutableArray alloc] initWithObjects:@"1 - Start", @"2", @"3", @"4", @"5", @"6", @"7", @"8 - End", nil];
    [manager sendRequest:slider];
}

+ (void)sdlex_createAlertManeuverWithManager:(SDLManager *)manager {
    SDLAlertManeuver *alertManeuver = [[SDLAlertManeuver alloc] init];
    alertManeuver.ttsChunks = [SDLTTSChunk textChunksFromString:@"Alert maneuver example"];
    SDLSoftButton *cancelButton = [SoftButtonManager createSoftButtonWithText:@"Cancel" softButtonId:300 manager:manager handler:^{
        // Alert will be dismissed
    }];
    alertManeuver.softButtons = [@[cancelButton] mutableCopy];
    [manager sendRequest:alertManeuver withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLRPCResponse * _Nullable response, NSError * _Nullable error) {
        if (![response.resultCode isEqualToEnum:SDLResult.SUCCESS]) {
            SDLAlert* alert = [[SDLAlert alloc] init];
            alert.alertText1 = @"Alert Maneuvers are only allowed in navigation apps";
            [manager sendRequest:alert];
            return;
        }
    }];
}

+ (void)sdlex_createScrollableMessageWithManager:(SDLManager *)manager {
    SDLScrollableMessage *scrollableMessage = [[SDLScrollableMessage alloc] init];
    scrollableMessage.scrollableMessageBody = @"Four score and seven years ago our fathers brought forth, upon this continent, a new nation, conceived in liberty, and dedicated to the proposition that all men are created equal. Now we are engaged in a great civil war, testing whether that nation, or any nation so conceived, and so dedicated, can long endure. We are met on a great battle field of that war. We come to dedicate a portion of it, as a final resting place for those who died here, that the nation might live.";
    scrollableMessage.timeout = @(10000);
    SDLSoftButton *cancelButton = [SoftButtonManager createSoftButtonWithText:@"Cancel" softButtonId:300 manager:manager handler:^{
        // Alert will be dismissed
    }];
    scrollableMessage.softButtons = [@[cancelButton] mutableCopy];
    [manager sendRequest:scrollableMessage];
}

+ (void)sdlex_createAlertWithManager:(SDLManager *)manager {
    SDLAlert* alert = [[SDLAlert alloc] init];
    alert.alertText1 = @"This is an alert";
    alert.alertText2 = @"alert text 2";
    alert.alertText3 = @"alert text 3";
    alert.ttsChunks = [SDLTTSChunk textChunksFromString:@"Alert example"];
    alert.duration = @(10000);
    alert.playTone = @(YES);
    alert.progressIndicator = @(YES);
    SDLSoftButton *cancelButton = [SoftButtonManager createSoftButtonWithText:@"Cancel" softButtonId:300 manager:manager handler:^{
        // Alert will be dismissed
    }];
    alert.softButtons = [@[cancelButton] mutableCopy];
    [manager sendRequest:alert];
}

+ (NSArray<SDLAddCommand *> *)sdlex_templateNamesAddCommand_WithManager:(SDLManager *)manager parentCommandId:(int)parentCommandId startingCommandId:(int)startingCommandId {
    int commandId = startingCommandId;
    NSMutableArray<SDLAddCommand *> *templatesAddCommands = [NSMutableArray array];
    for(SDLPredefinedLayout *template in SDLPredefinedLayout.values) {
        SDLMenuParams *commandMenuParams = [[SDLMenuParams alloc] init];
        commandMenuParams.menuName = [NSString stringWithFormat:@"%@", template];
        commandMenuParams.parentID = @(parentCommandId);

        SDLAddCommand *changeTemplateCommand = [[SDLAddCommand alloc] init];
        changeTemplateCommand.vrCommands = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@", template]];
        changeTemplateCommand.menuParams = commandMenuParams;
        changeTemplateCommand.cmdID = @(commandId++);

        changeTemplateCommand.handler = ^(__kindof SDLRPCNotification * _Nonnull notification) {
            [TemplateManager changeTemplateWithManager:manager toTemplate:template image:[self.class sdlex_mainGraphicImage]];
        };

        [templatesAddCommands addObject:changeTemplateCommand];
    }

    return templatesAddCommands;
}

+ (SDLSpeak *)sdlex_appNameSpeak {
    SDLSpeak *speak = [[SDLSpeak alloc] init];
    speak.ttsChunks = [SDLTTSChunk textChunksFromString:@"S D L Example App"];

    return speak;
}

+ (SDLSpeak *)sdlex_goodJobSpeak {
    SDLSpeak *speak = [[SDLSpeak alloc] init];
    speak.ttsChunks = [SDLTTSChunk textChunksFromString:@"Good Job"];

    return speak;
}

+ (SDLSpeak *)sdlex_youMissedItSpeak {
    SDLSpeak *speak = [[SDLSpeak alloc] init];
    speak.ttsChunks = [SDLTTSChunk textChunksFromString:@"You missed it"];

    return speak;
}

+ (SDLCreateInteractionChoiceSet *)sdlex_createOnlyChoiceInteractionSet {
    SDLCreateInteractionChoiceSet *createInteractionSet = [[SDLCreateInteractionChoiceSet alloc] init];
    createInteractionSet.interactionChoiceSetID = @0;

    NSString *theOnlyChoiceName = @"The Only Choice";
    SDLChoice *theOnlyChoice = [[SDLChoice alloc] init];
    theOnlyChoice.choiceID = @0;
    theOnlyChoice.menuName = theOnlyChoiceName;
    theOnlyChoice.vrCommands = [NSMutableArray arrayWithObject:theOnlyChoiceName];

    createInteractionSet.choiceSet = [NSMutableArray arrayWithArray:@[theOnlyChoice]];

    return createInteractionSet;
}

+ (void)sdlex_sendPerformOnlyChoiceInteractionWithManager:(SDLManager *)manager {
    SDLPerformInteraction *performOnlyChoiceInteraction = [[SDLPerformInteraction alloc] init];
    performOnlyChoiceInteraction.initialText = @"Choose the only one! You have 5 seconds...";
    performOnlyChoiceInteraction.initialPrompt = [SDLTTSChunk textChunksFromString:@"Choose it"];
    performOnlyChoiceInteraction.interactionMode = [SDLInteractionMode BOTH];
    performOnlyChoiceInteraction.interactionChoiceSetIDList = [NSMutableArray arrayWithObject:@0];
    performOnlyChoiceInteraction.helpPrompt = [SDLTTSChunk textChunksFromString:@"Do it"];
    performOnlyChoiceInteraction.timeoutPrompt = [SDLTTSChunk textChunksFromString:@"Too late"];
    performOnlyChoiceInteraction.timeout = @5000;
    performOnlyChoiceInteraction.interactionLayout = [SDLLayoutMode LIST_ONLY];

    [manager sendRequest:performOnlyChoiceInteraction withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLPerformInteractionResponse * _Nullable response, NSError * _Nullable error) {
        if ((response == nil) || (error != nil)) {
            NSLog(@"Something went wrong, no perform interaction response: %@", error);
        }

        if ([response.choiceID isEqualToNumber:@0]) {
            [manager sendRequest:[self sdlex_goodJobSpeak]];
        } else {
            [manager sendRequest:[self sdlex_youMissedItSpeak]];
        }
    }];
}

+ (void)sdlex_sendGetVehicleDataWithManager:(SDLManager *)manager {
    SDLGetVehicleData *getVehicleData = [[SDLGetVehicleData alloc] initWithAccelerationPedalPosition:YES airbagStatus:YES beltStatus:YES bodyInformation:YES clusterModeStatus:YES deviceStatus:YES driverBraking:YES eCallInfo:YES emergencyEvent:YES engineTorque:YES externalTemperature:YES fuelLevel:YES fuelLevelState:YES gps:YES headLampStatus:YES instantFuelConsumption:YES myKey:YES odometer:YES prndl:YES rpm:YES speed:YES steeringWheelAngle:YES tirePressure:YES vin:YES wiperStatus:YES];

    [manager sendRequest:getVehicleData withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLRPCResponse * _Nullable response, NSError * _Nullable error) {
        NSLog(@"vehicle data response: %@", response);
    }];
}

#pragma mark - Files / Artwork

+ (SDLImage *)sdlex_mainGraphicImage {
    SDLImage* image = [[SDLImage alloc] init];
    image.imageType = SDLImageType.DYNAMIC;
    image.value = MainGraphicArtworkName;

    return image;
}

+ (SDLArtwork *)sdlex_pointingSoftButtonArtwork {
    return [SDLArtwork artworkWithImage:[UIImage imageNamed:@"sdl_softbutton_icon"] name:PointingSoftButtonArtworkName asImageFormat:SDLArtworkImageFormatPNG];
}

+ (SDLArtwork *)sdlex_mainGraphicArtwork {
    return [SDLArtwork artworkWithImage:[UIImage imageNamed:@"sdl_logo_green"] name:MainGraphicArtworkName asImageFormat:SDLArtworkImageFormatPNG];
}

- (void)sdlex_prepareRemoteSystem {
    int commandId = 1;
    [self.sdlManager sendRequest:[AddCommandManager addCommandWithManager:self.sdlManager commandId:(commandId++) menuName:@"Speak App Name" handler:^{
        [self.sdlManager sendRequest:[self.class sdlex_appNameSpeak]];
    }] withResponseHandler:nil];

    [self.sdlManager sendRequest:[AddCommandManager addCommandWithManager:self.sdlManager commandId:(commandId++) menuName:@"Perform Interaction" handler:^{
        // NOTE: You may want to preload your interaction sets, because they can take a while for the remote system to process. We're going to ignore our own advice here.
        [self.class sdlex_sendPerformOnlyChoiceInteractionWithManager:self.sdlManager];
    }] withResponseHandler:nil];

    [self.sdlManager sendRequest:[AddCommandManager addCommandWithManager:self.sdlManager commandId:(commandId++) menuName:@"Get Vehicle Data" handler:^{
        [self.class sdlex_sendGetVehicleDataWithManager:self.sdlManager];
    }] withResponseHandler:nil];

    [self.sdlManager sendRequest:[AddCommandManager addCommandWithManager:self.sdlManager commandId:(commandId++) menuName:@"Show Slider" handler:^{
        [self.class sdlex_createSliderWithManager:self.sdlManager];
    }] withResponseHandler:nil];

    [self.sdlManager sendRequest:[AddCommandManager addCommandWithManager:self.sdlManager commandId:(commandId++) menuName:@"Alert Maneuver" handler:^{
        [self.class sdlex_createAlertManeuverWithManager:self.sdlManager];
    }] withResponseHandler:nil];

    [self.sdlManager sendRequest:[AddCommandManager addCommandWithManager:self.sdlManager commandId:(commandId++) menuName:@"Alert" handler:^{
        [self.class sdlex_createAlertWithManager:self.sdlManager];
    }] withResponseHandler:nil];

    [self.sdlManager sendRequest:[AddCommandManager addCommandWithManager:self.sdlManager commandId:(commandId++) menuName:@"Alert Maneuver" handler:^{
        [self.class sdlex_createAlertManeuverWithManager:self.sdlManager];
    }] withResponseHandler:nil];

    [self.sdlManager sendRequest:[AddCommandManager addCommandWithManager:self.sdlManager commandId:(commandId++) menuName:@"Scrollable Message" handler:^{
        [self.class sdlex_createScrollableMessageWithManager:self.sdlManager];
    }] withResponseHandler:nil];

    int parentMenuId = (commandId++);
    [self.sdlManager sendRequest:[self.class sdlex_changeTemplateAddSubmenuWithManager:self.sdlManager commandId:parentMenuId] withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLRPCResponse * _Nullable response, NSError * _Nullable error) {
        if([[response resultCode] isEqualToEnum:SDLResult.SUCCESS]) {
            for (SDLAddCommand *addCommand in [self.class sdlex_templateNamesAddCommand_WithManager:self.sdlManager parentCommandId:parentMenuId startingCommandId:(parentMenuId + 1)]) {
                [self.sdlManager sendRequest:addCommand];
            }
        } else {
            [SDLDebugTool logInfo:@"The submenu was not created successfully"];
        }
    }];

    dispatch_group_t dataDispatchGroup = dispatch_group_create();
    dispatch_group_enter(dataDispatchGroup);

    dispatch_group_enter(dataDispatchGroup);
    [self.sdlManager.fileManager uploadFile:[self.class sdlex_mainGraphicArtwork] completionHandler:^(BOOL success, NSUInteger bytesAvailable, NSError * _Nullable error) {
        dispatch_group_leave(dataDispatchGroup);

        if (success == NO) {
            NSLog(@"Something went wrong, image could not upload: %@", error);
            return;
        }
    }];

    dispatch_group_enter(dataDispatchGroup);
    [self.sdlManager.fileManager uploadFile:[self.class sdlex_pointingSoftButtonArtwork] completionHandler:^(BOOL success, NSUInteger bytesAvailable, NSError * _Nullable error) {
        dispatch_group_leave(dataDispatchGroup);

        if (success == NO) {
            NSLog(@"Something went wrong, image could not upload: %@", error);
            return;
        }
    }];

    dispatch_group_enter(dataDispatchGroup);
    [self.sdlManager sendRequest:[self.class sdlex_createOnlyChoiceInteractionSet] withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLRPCResponse * _Nullable response, NSError * _Nullable error) {
        // Interaction choice set ready
        dispatch_group_leave(dataDispatchGroup);
    }];

    dispatch_group_leave(dataDispatchGroup);
    dispatch_group_notify(dataDispatchGroup, dispatch_get_main_queue(), ^{
        self.initialShowState = SDLHMIInitialShowStateDataAvailable;
        [self sdlex_showInitialData];
    });
}


#pragma mark - SDLManagerDelegate

- (void)managerDidDisconnect {
    // Reset our state
    self.firstTimeState = SDLHMIFirstStateNone;
    self.initialShowState = SDLHMIInitialShowStateNone;
    [self sdlex_updateProxyState:ProxyStateStopped];
    [self startManager];
    //    if (ShouldRestartOnDisconnect) {
    //        [self startManager];
    //    }
}

- (void)hmiLevel:(SDLHMILevel *)oldLevel didChangeToLevel:(SDLHMILevel *)newLevel {
    if (![newLevel isEqualToEnum:[SDLHMILevel NONE]] && (self.firstTimeState == SDLHMIFirstStateNone)) {
        // This is our first time in a non-NONE state
        self.firstTimeState = SDLHMIFirstStateNonNone;

        // Send Add Commands
        [self sdlex_prepareRemoteSystem];
    }

    if ([newLevel isEqualToEnum:[SDLHMILevel FULL]] && (self.firstTimeState != SDLHMIFirstStateFull)) {
        // This is our first time in a FULL state
        self.firstTimeState = SDLHMIFirstStateFull;
    }

    if ([newLevel isEqualToEnum:[SDLHMILevel FULL]]) {
        // We're always going to try to show the initial state, because if we've already shown it, it won't be shown, and we need to guard against some possible weird states
        [self sdlex_showInitialData];
    }
}

@end

NS_ASSUME_NONNULL_END
