//
//  SDLMacros.h
//  SmartDeviceLink-iOS
//
//  Created by Muller, Alexander (A.) on 10/17/16.
//  Copyright © 2016 smartdevicelink. All rights reserved.
//

#ifndef SDLMacros_h
#define SDLMacros_h

// Resolves issue of pre-xcode 8 versions due to NS_STRING_ENUM unavailability.
#if __has_attribute(swift_wrapper)
#define SDL_SWIFT_ENUM NS_STRING_ENUM
#else
#define SDL_SWIFT_ENUM
#endif

#define ENUM_PTR(class, name)   typedef class* name SDL_SWIFT_ENUM

#define STRING_ENUM(name)   ENUM_PTR(NSString, name)

#endif /* SDLMacros_h */