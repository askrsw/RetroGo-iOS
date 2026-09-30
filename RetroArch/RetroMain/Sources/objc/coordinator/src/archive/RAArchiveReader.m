//
//  RAArchiveReader.m
//  RetroGo
//
//  Created by haharsw on 2026/9/26.
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

#import "RAArchiveReader.h"
#import "RAArchiveEntry+Zip.h"

#include <file/archive_file.h>
#include <streams/file_stream.h>
#include <encodings/crc32.h>

NSErrorDomain const RAArchiveErrorDomain = @"com.retrogame.archive";

static const uint32_t kRAZipLocalHeaderSignature = 0x04034b50;
enum { kRAZipLocalHeaderSize = 30 };
static const uint32_t kRAZip64Marker = 0xFFFFFFFF;
static const unsigned kRAZipModeStored = 0;
static const unsigned kRAZipModeDeflated = 8;

NS_ASSUME_NONNULL_BEGIN

static NSError *RAArchiveMakeError(RAArchiveErrorCode code, NSString *message) {
    NSLog(@"[RAArchive] %@", message);
    return [NSError errorWithDomain:RAArchiveErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark - RAArchiveEntry

@implementation RAArchiveEntry

- (instancetype)initWithName:(NSString *)name size:(uint64_t)size crc32:(uint32_t)crc32 hasCRC:(BOOL)hasCRC {
    self = [super init];
    if (self) {
        _name = [name copy];
        _size = size;
        _crc32 = crc32;
        _hasCRC = hasCRC;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<RAArchiveEntry %@ size=%llu crc=%@>",
        _name, _size, _hasCRC ? [NSString stringWithFormat:@"%08x", _crc32] : @"none"];
}

@end

#pragma mark - Walk context

/// Carries state through the C callbacks of file_archive_parse_file_iterate.
@interface RAArchiveWalkContext : NSObject
@property (nonatomic, assign) RAArchiveFormat format;
/// Listing mode.
@property (nonatomic, strong, nullable) NSMutableArray<RAArchiveEntry *> *entries;
/// Extraction mode: entry name -> destination path, removed once written.
@property (nonatomic, strong, nullable) NSMutableDictionary<NSString *, NSString *> *pending;
/// First callback failure; stops the walk.
@property (nonatomic, strong, nullable) NSError *error;
@end

@implementation RAArchiveWalkContext
@end

#pragma mark - Helpers

static BOOL RAArchiveIsDirectoryName(const char *name) {
    // The 7z backend reports directories (and over-long names) with an empty name.
    size_t length = name ? strlen(name) : 0;
    if (length == 0) {
        return YES;
    }
    char last = name[length - 1];
    return last == '/' || last == '\\';
}

static NSString * _Nullable RAArchiveDecodeName(const char *name) {
    // 7z names are converted from UTF-16; zip names are UTF-8 or legacy CP437.
    NSString *decoded = [NSString stringWithUTF8String:name];
    if (decoded == nil) {
        decoded = [NSString stringWithCString:name encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSLatinUS)];
    }
    return decoded;
}

/// libretro's 7z backend reports an undefined CRC as 0. A non-empty file whose real
/// CRC is 0 is a 1-in-2^32 case, so treat it as "no CRC recorded".
static BOOL RAArchiveEntryHasCRC(RAArchiveFormat format, uint32_t crc32, uint64_t size) {
    return format == RAArchiveFormatZip || crc32 != 0 || size == 0;
}

static uint32_t RAReadLE16(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8);
}

static uint32_t RAReadLE32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/// The zlib backend trusts the local header and, when the archive is mmapped, reads
/// straight from the mapping. Verify the entry data lies inside the file first so a
/// truncated or corrupt zip fails cleanly instead of reading past the mapping.
static BOOL RAZipEntryDataInBounds(file_archive_transfer_t *transfer, uint64_t headerOffset,
                                   unsigned cmode, uint32_t csize, uint32_t size) {
    uint64_t archiveSize = (uint64_t)transfer->archive_size;
    uint8_t header[kRAZipLocalHeaderSize];

    if (transfer->archive_file == NULL || headerOffset + kRAZipLocalHeaderSize > archiveSize) {
        return NO;
    }
    filestream_seek(transfer->archive_file, (int64_t)headerOffset, RETRO_VFS_SEEK_POSITION_START);
    if (filestream_read(transfer->archive_file, header, kRAZipLocalHeaderSize) != kRAZipLocalHeaderSize) {
        return NO;
    }
    if (RAReadLE32(header) != kRAZipLocalHeaderSignature) {
        return NO;
    }

    uint64_t dataOffset = headerOffset + kRAZipLocalHeaderSize + RAReadLE16(header + 26) + RAReadLE16(header + 28);
    uint64_t dataLength = cmode == kRAZipModeStored ? size : csize;
    return dataOffset + dataLength <= archiveSize;
}

static BOOL RAArchiveWriteData(const void * _Nullable bytes, uint32_t size, NSString *destination, NSError **error) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *directory = destination.stringByDeletingLastPathComponent;
    NSError *ioError = nil;

    if (directory.length > 0 && ![manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&ioError]) {
        *error = RAArchiveMakeError(RAArchiveErrorWriteFailed,
                                    [NSString stringWithFormat:@"Cannot create %@: %@", directory, ioError.localizedDescription]);
        return NO;
    }

    NSData *data = size > 0 ? [NSData dataWithBytesNoCopy:(void *)bytes length:size freeWhenDone:NO] : [NSData data];
    // Atomic write replaces an existing file (or hard link) instead of writing through it.
    if (![data writeToFile:destination options:NSDataWritingAtomic error:&ioError]) {
        *error = RAArchiveMakeError(RAArchiveErrorWriteFailed,
                                    [NSString stringWithFormat:@"Cannot write %@: %@", destination, ioError.localizedDescription]);
        return NO;
    }
    return YES;
}

/// Decompresses the entry the walk is currently positioned on, verifies it and writes it out.
static BOOL RAArchiveExtractCurrentEntry(RAArchiveFormat format, struct archive_extract_userdata *userdata,
                                         NSString *entryName, const uint8_t *cdata, unsigned cmode,
                                         uint32_t csize, uint32_t size, uint32_t crc32,
                                         NSString *destination, NSError **error) {
    file_archive_transfer_t *transfer = userdata->transfer;
    BOOL isZip = format == RAArchiveFormatZip;

    if (transfer == NULL || transfer->backend == NULL || transfer->context == NULL) {
        *error = RAArchiveMakeError(RAArchiveErrorDecompressFailed,
                                    [NSString stringWithFormat:@"No open archive while extracting %@", entryName]);
        return NO;
    }

    if (isZip) {
        if (size == kRAZip64Marker || csize == kRAZip64Marker) {
            *error = RAArchiveMakeError(RAArchiveErrorUnsupportedEntry,
                                        [NSString stringWithFormat:@"Zip64 entry %@ is not supported", entryName]);
            return NO;
        }
        if (cmode != kRAZipModeStored && cmode != kRAZipModeDeflated) {
            *error = RAArchiveMakeError(RAArchiveErrorUnsupportedEntry,
                                        [NSString stringWithFormat:@"Entry %@ uses unsupported compression method %u", entryName, cmode]);
            return NO;
        }
        if (!RAZipEntryDataInBounds(transfer, (uint64_t)(uintptr_t)cdata, cmode, csize, size)) {
            *error = RAArchiveMakeError(RAArchiveErrorDecompressFailed,
                                        [NSString stringWithFormat:@"Entry %@ has a corrupt local header or is truncated", entryName]);
            return NO;
        }
    }

    if (size == 0) {
        return RAArchiveWriteData(NULL, 0, destination, error);
    }

    const struct file_archive_file_backend *backend = transfer->backend;
    file_archive_file_handle_t handle = {0};
    int ret = -1;

    if (backend->stream_decompress_data_to_file_init(transfer->context, &handle, cdata, cmode, csize, size)) {
        if (isZip) {
            // Each deflate step consumes up to 128 KiB. The cap turns a stalled read into an
            // error instead of spinning forever.
            uint64_t maxSteps = csize / (64 * 1024) + 4;
            uint64_t steps = 0;
            do {
                ret = backend->stream_decompress_data_to_file_iterate(transfer->context, &handle);
            } while (ret == 0 && ++steps < maxSteps);
        } else {
            // The 7z backend extracts in one call and reports failure as 0 ("in progress"),
            // so it must not be retried.
            ret = backend->stream_decompress_data_to_file_iterate(transfer->context, &handle);
        }
    }

    if (ret != 1 || handle.data == NULL) {
        *error = RAArchiveMakeError(RAArchiveErrorDecompressFailed,
                                    [NSString stringWithFormat:@"Failed to decompress %@", entryName]);
        return NO;
    }

    if (RAArchiveEntryHasCRC(format, crc32, size)) {
        uint32_t actual = encoding_crc32(0, handle.data, size);
        if (actual != crc32) {
            *error = RAArchiveMakeError(RAArchiveErrorCRCMismatch,
                                        [NSString stringWithFormat:@"CRC mismatch for %@: expected %08x, got %08x", entryName, crc32, actual]);
            return NO;
        }
    }

    // handle.data is owned by the backend context and freed when the walk ends.
    return RAArchiveWriteData(handle.data, size, destination, error);
}

#pragma mark - Callbacks

/// Return value: non-zero continues the walk, 0 stops it.
static int RAArchiveListCallback(const char *name, const char *valid_exts,
                                 const uint8_t *cdata, unsigned cmode, uint32_t csize, uint32_t size,
                                 uint32_t crc32, struct archive_extract_userdata *userdata) {
    RAArchiveWalkContext *context = (__bridge RAArchiveWalkContext *)userdata->cb_data;

    if (RAArchiveIsDirectoryName(name)) {
        return 1;
    }
    if (context.format == RAArchiveFormatZip && (size == kRAZip64Marker || csize == kRAZip64Marker)) {
        context.error = RAArchiveMakeError(RAArchiveErrorUnsupportedEntry,
                                           [NSString stringWithFormat:@"Zip64 entry %s is not supported", name]);
        return 0;
    }

    NSString *entryName = RAArchiveDecodeName(name);
    if (entryName == nil) {
        NSLog(@"[RAArchive] Skip entry with undecodable name in %s", userdata->archive_path);
        return 1;
    }

    BOOL hasCRC = RAArchiveEntryHasCRC(context.format, crc32, size);
    RAArchiveEntry *entry = [[RAArchiveEntry alloc] initWithName:entryName size:size crc32:hasCRC ? crc32 : 0 hasCRC:hasCRC];
    if (context.format == RAArchiveFormatZip) {
        // The zip backend passes the local header offset as cdata.
        entry.hasZipLocation = YES;
        entry.zipHeaderOffset = (uint64_t)(uintptr_t)cdata;
        entry.zipCompressedSize = csize;
        entry.zipMethod = (uint16_t)cmode;
    }
    [context.entries addObject:entry];
    return 1;
}

static int RAArchiveExtractCallback(const char *name, const char *valid_exts,
                                    const uint8_t *cdata, unsigned cmode, uint32_t csize, uint32_t size,
                                    uint32_t crc32, struct archive_extract_userdata *userdata) {
    @autoreleasepool {
        RAArchiveWalkContext *context = (__bridge RAArchiveWalkContext *)userdata->cb_data;

        if (RAArchiveIsDirectoryName(name)) {
            return 1;
        }

        NSString *entryName = RAArchiveDecodeName(name);
        NSString *destination = entryName ? context.pending[entryName] : nil;
        if (destination == nil) {
            return 1;
        }

        NSError *error = nil;
        if (!RAArchiveExtractCurrentEntry(context.format, userdata, entryName, cdata, cmode, csize, size, crc32, destination, &error)) {
            context.error = error;
            return 0;
        }

        // Duplicate names inside the archive: the first one wins.
        [context.pending removeObjectForKey:entryName];
        return context.pending.count > 0 ? 1 : 0;
    }
}

/// Mirrors libretro's static file_archive_walk(), which does not report a failed open:
/// an init failure leaves the state in DEINIT_ERROR without running its cleanup step,
/// so returnerr stays true and the file handle / mapping would leak.
static BOOL RAArchiveWalk(NSString *path, file_archive_file_cb callback, RAArchiveWalkContext *context) {
    struct archive_extract_userdata userdata;
    file_archive_transfer_t state;
    bool returnerr = true;
    const char *cPath = path.fileSystemRepresentation;

    memset(&userdata, 0, sizeof(userdata));
    memset(&state, 0, sizeof(state));
    userdata.cb_data = (__bridge void *)context;
    state.type = ARCHIVE_TRANSFER_INIT;

    while (file_archive_parse_file_iterate(&state, &returnerr, cPath, NULL, callback, &userdata) == 0) {
    }

    BOOL failed = !returnerr || state.type == ARCHIVE_TRANSFER_DEINIT_ERROR;
    if (state.archive_file != NULL || state.context != NULL) {
        file_archive_parse_file_iterate(&state, &returnerr, cPath, NULL, callback, &userdata);
    }
    return !failed;
}

static BOOL RAArchiveCheckPath(NSString *path, RAArchiveFormat *format, NSError **error) {
    *format = path.length > 0 ? [RAArchiveReader formatOfArchiveAtPath:path] : RAArchiveFormatUnknown;
    if (*format == RAArchiveFormatUnknown) {
        *error = RAArchiveMakeError(RAArchiveErrorUnsupportedFormat,
                                    [NSString stringWithFormat:@"Not a zip/7z archive: %@", path.lastPathComponent]);
        return NO;
    }
    return YES;
}

#pragma mark - RAArchiveReader

@implementation RAArchiveReader

+ (RAArchiveFormat)formatOfArchiveAtPath:(NSString *)path {
    NSString *extension = path.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"zip"]) {
        return RAArchiveFormatZip;
    }
    if ([extension isEqualToString:@"7z"]) {
        return RAArchiveFormat7z;
    }
    return RAArchiveFormatUnknown;
}

+ (nullable NSArray<RAArchiveEntry *> *)entriesOfArchiveAtPath:(NSString *)path
                                                         error:(NSError * _Nullable * _Nullable)error {
    NSError *localError = nil;
    RAArchiveFormat format;
    if (!RAArchiveCheckPath(path, &format, &localError)) {
        if (error) *error = localError;
        return nil;
    }

    RAArchiveWalkContext *context = [[RAArchiveWalkContext alloc] init];
    context.format = format;
    context.entries = [NSMutableArray array];

    BOOL walked = RAArchiveWalk(path, RAArchiveListCallback, context);
    if (context.error != nil || !walked) {
        if (error) {
            *error = context.error ?: RAArchiveMakeError(RAArchiveErrorOpenFailed,
                                                         [NSString stringWithFormat:@"Cannot read archive %@", path.lastPathComponent]);
        }
        return nil;
    }
    return [context.entries copy];
}

+ (BOOL)extractEntry:(NSString *)entryName
   fromArchiveAtPath:(NSString *)path
              toPath:(NSString *)destination
               error:(NSError * _Nullable * _Nullable)error {
    return [self extractEntries:@{entryName: destination} fromArchiveAtPath:path error:error];
}

+ (BOOL)extractEntries:(NSDictionary<NSString *, NSString *> *)destinations
     fromArchiveAtPath:(NSString *)path
                 error:(NSError * _Nullable * _Nullable)error {
    NSError *localError = nil;
    RAArchiveFormat format;
    if (!RAArchiveCheckPath(path, &format, &localError)) {
        if (error) *error = localError;
        return NO;
    }
    if (destinations.count == 0) {
        return YES;
    }

    RAArchiveWalkContext *context = [[RAArchiveWalkContext alloc] init];
    context.format = format;
    context.pending = [destinations mutableCopy];

    BOOL walked = RAArchiveWalk(path, RAArchiveExtractCallback, context);
    if (context.error != nil) {
        if (error) *error = context.error;
        return NO;
    }
    if (!walked) {
        if (error) {
            *error = RAArchiveMakeError(RAArchiveErrorOpenFailed,
                                        [NSString stringWithFormat:@"Cannot read archive %@", path.lastPathComponent]);
        }
        return NO;
    }
    if (context.pending.count > 0) {
        if (error) {
            NSArray *missing = [context.pending.allKeys sortedArrayUsingSelector:@selector(compare:)];
            *error = RAArchiveMakeError(RAArchiveErrorEntryNotFound,
                                        [NSString stringWithFormat:@"%@ not found in %@",
                                         [missing componentsJoinedByString:@", "], path.lastPathComponent]);
        }
        return NO;
    }
    return YES;
}

@end

NS_ASSUME_NONNULL_END
