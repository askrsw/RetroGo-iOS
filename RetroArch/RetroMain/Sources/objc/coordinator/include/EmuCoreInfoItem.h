//
//  EmuCoreInfoItem.h
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
//  Copyright © 2026 haharsw. All rights reserved.
//
//  ---------------------------------------------------------------------------------
//  This file is part of RetroGo.
//  ---------------------------------------------------------------------------------
//
//  RetroGo is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  RetroGo is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class EmuCoreFirmware;

@interface EmuCoreInfoItem : NSObject
@property(nonatomic, copy, readonly) NSString *coreId;
@property(nonatomic, copy, readonly) NSString *corePath;
@property(nonatomic, copy, readonly) NSString *displayName;
@property(nonatomic, copy, readonly) NSString *coreName;
@property(nonatomic, copy, nullable, readonly) NSString *systemName;
@property(nonatomic, copy, nullable, readonly) NSString *systemID;
@property(nonatomic, copy, nullable, readonly) NSString *version;
@property(nonatomic, copy, nullable, readonly) NSArray<NSString *> *categories;
@property(nonatomic, copy, nullable, readonly) NSArray<NSString *> *licenses;
@property(nonatomic, copy, nullable, readonly) NSString *manufacturer;
@property(nonatomic, copy, nullable, readonly) NSArray<NSString *> *extensions;
@property(nonatomic, copy, nullable, readonly) NSArray<NSString *> *authors;
@property(nonatomic, assign, readonly) BOOL supportNoContent;
@property(nonatomic, assign, readonly) BOOL experimental;
@property(nonatomic, assign, readonly) BOOL singlePurpose;
@property(nonatomic, copy, nullable, readonly) NSArray<NSString *> *permissions;
@property(nonatomic, copy, nullable, readonly) NSArray<NSString *> *databases;
@property(nonatomic, copy, nullable, readonly) NSArray<NSString *> *hwApis;
@property(nonatomic, copy, nullable, readonly) NSString *desc;
@property(nonatomic, copy, nullable, readonly) NSArray<NSString *> *notes;
@property(nonatomic, copy, nullable, readonly) NSArray<EmuCoreFirmware *> *firmwares;

@property(nonatomic, copy, nullable, readonly) NSString *licensesLine;

@property(nonatomic, copy, readonly) NSString *frameworkName;

@property(nonatomic, assign) BOOL expanded;
@property(nonatomic, assign) BOOL isHidden;
@property(nonatomic, assign) NSInteger itemCount;

@property(nonatomic, assign, readonly) BOOL supportsAnalog;
@property(nonatomic, copy, nullable, readonly) NSString *overlayName;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)noneCore;

- (void)scanFirmwareFolder:(NSURL *)url match:(BOOL)match processing:(void (^)(NSString *fileName))processing errorHandler:(void (^)(NSError *error))errorHandler completion:(void (^)(NSArray<EmuCoreFirmware *> *))completion;
- (nullable EmuCoreFirmware *)importFirmwareFile:(NSURL *)url;
- (BOOL)deleteFirmware:(EmuCoreFirmware *)firmware;

- (nullable NSString *)getLocalDesc:(NSString *)language;
- (nullable NSArray<NSDictionary<NSString *, NSString *> *> *)getLicenseDictionaryArray;
- (nullable NSString *)getSourceURL;

- (BOOL)extractPPSSPPAssets;
@end

NS_ASSUME_NONNULL_END
