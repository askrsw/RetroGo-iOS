//
//  RAZipWriter.m
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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

#import "RAZipWriter.h"
#import "RAArchiveEntry+Zip.h"

#include <zlib.h>
#include <stdio.h>
#include <unistd.h>
#include <utils/retrogo_log.h>

static const uint32_t kRAZipLocalSignature = 0x04034b50;
static const uint32_t kRAZipCentralSignature = 0x02014b50;
static const uint32_t kRAZipEndSignature = 0x06054b50;
enum { kRAZipLocalHeaderLength = 30 };
static const uint16_t kRAZipVersion = 20;
static const uint16_t kRAZipFlagEncrypted = 0x0001;
static const uint16_t kRAZipFlagUTF8 = 0x0800;
static const uint16_t kRAZipStored = 0;
static const uint16_t kRAZipDeflated = 8;
/// 1980-01-01 00:00 in DOS format; fixed so identical input gives identical output.
static const uint16_t kRAZipDosTime = 0;
static const uint16_t kRAZipDosDate = (0 << 9) | (1 << 5) | 1;
static const uint64_t kRAZipLimit = 0xFFFFFFFFull;
static const NSUInteger kRAZipMaxEntries = 0xFFFF;
static const size_t kRAZipCopyChunk = 256 * 1024;

NS_ASSUME_NONNULL_BEGIN

static NSError *RAZipError(RAArchiveErrorCode code, NSString *message) {
    RETROGO_LOGE(IMPORT, "Zip writer: %@", message);
    return [NSError errorWithDomain:RAArchiveErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void RAPut16(NSMutableData *data, uint16_t value) {
    uint8_t bytes[2] = { (uint8_t)value, (uint8_t)(value >> 8) };
    [data appendBytes:bytes length:2];
}

static void RAPut32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = { (uint8_t)value, (uint8_t)(value >> 8), (uint8_t)(value >> 16), (uint8_t)(value >> 24) };
    [data appendBytes:bytes length:4];
}

static uint16_t RARead16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static uint32_t RARead32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }

/// What the central directory needs about one written entry.
@interface RAZipWrittenEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSData *nameBytes;
@property (nonatomic, assign) uint16_t flags;
@property (nonatomic, assign) uint16_t method;
@property (nonatomic, assign) uint32_t crc32;
@property (nonatomic, assign) uint32_t compressedSize;
@property (nonatomic, assign) uint32_t size;
@property (nonatomic, assign) uint32_t headerOffset;
@end

@implementation RAZipWrittenEntry
@end

@implementation RAZipWriter {
    NSString *_partialPath;
    FILE *_file;
    uint64_t _offset;
    NSMutableArray<RAZipWrittenEntry *> *_entries;
    NSMutableSet<NSString *> *_names;
    BOOL _finished;
}

- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error {
    self = [super init];
    if (self) {
        _path = [path copy];
        // Keeps a .zip extension so the finished file can be read back for verification.
        _partialPath = [path stringByAppendingString:@".partial.zip"];
        _entries = [NSMutableArray array];
        _names = [NSMutableSet set];
        [[NSFileManager defaultManager] removeItemAtPath:_partialPath error:nil];
        _file = fopen(_partialPath.fileSystemRepresentation, "wb");
        if (_file == NULL) {
            if (error) *error = RAZipError(RAArchiveErrorWriteFailed, [NSString stringWithFormat:@"Cannot create %@", _partialPath]);
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (!_finished) {
        [self cancel];
    }
}

- (NSUInteger)entryCount {
    return _entries.count;
}

- (void)cancel {
    if (_file != NULL) {
        fclose(_file);
        _file = NULL;
    }
    if (!_finished) {
        [[NSFileManager defaultManager] removeItemAtPath:_partialPath error:nil];
    }
}

#pragma mark - Adding entries

- (BOOL)checkCanAdd:(NSString *)name error:(NSError **)error {
    if (_file == NULL) {
        if (error) *error = RAZipError(RAArchiveErrorWriteFailed, @"Writer is already finished or cancelled");
        return NO;
    }
    if (name.length == 0 || [_names containsObject:name]) {
        if (error) *error = RAZipError(RAArchiveErrorWriteFailed, [NSString stringWithFormat:@"Invalid or duplicate entry name %@", name]);
        return NO;
    }
    if (_entries.count >= kRAZipMaxEntries) {
        if (error) *error = RAZipError(RAArchiveErrorUnsupportedEntry, @"Too many entries for a zip without zip64");
        return NO;
    }
    return YES;
}

- (BOOL)addEntry:(RAArchiveEntry *)entry fromArchiveAtPath:(NSString *)archivePath asName:(NSString *)name error:(NSError **)error {
    return [self addEntries:@[entry] fromArchiveAtPath:archivePath asNames:@[name] error:error];
}

static BOOL RAZipCanCopyRaw(RAArchiveEntry *entry) {
    return entry.hasZipLocation && (entry.zipMethod == kRAZipStored || entry.zipMethod == kRAZipDeflated);
}

- (BOOL)addEntries:(NSArray<RAArchiveEntry *> *)entries fromArchiveAtPath:(NSString *)archivePath
           asNames:(NSArray<NSString *> *)names error:(NSError **)error {
    if (entries.count != names.count) {
        if (error) *error = RAZipError(RAArchiveErrorWriteFailed, @"Entry and name counts differ");
        return NO;
    }
    for (NSString *name in names) {
        if (![self checkCanAdd:name error:error]) {
            return NO;
        }
    }
    if ([NSSet setWithArray:names].count != names.count) {
        if (error) *error = RAZipError(RAArchiveErrorWriteFailed, @"Duplicate entry names in one batch");
        return NO;
    }

    // Entries that cannot be copied raw (7z, unusual zip methods) are extracted together
    // first: one walk over the archive decompresses each solid 7z block only once.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"RAZipWriter-%@", [NSUUID UUID].UUIDString]];
    NSMutableDictionary<NSString *, NSString *> *extracted = [NSMutableDictionary dictionary];
    for (RAArchiveEntry *entry in entries) {
        if (!RAZipCanCopyRaw(entry) && extracted[entry.name] == nil) {
            extracted[entry.name] = [temp stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu", (unsigned long)extracted.count]];
        }
    }
    BOOL ok = extracted.count == 0
        || [RAArchiveReader extractEntries:extracted fromArchiveAtPath:archivePath error:error];

    // Errors created inside the pool are autoreleased there; keep them in a strong local
    // so they outlive the pool before reaching the caller.
    NSError *entryError = nil;
    for (NSUInteger i = 0; ok && i < entries.count; i++) {
        @autoreleasepool {
            NSError *poolError = nil;
            RAArchiveEntry *entry = entries[i];
            if (RAZipCanCopyRaw(entry)) {
                ok = [self copyRawEntry:entry fromZipAtPath:archivePath asName:names[i] error:&poolError];
            } else {
                NSData *data = [NSData dataWithContentsOfFile:extracted[entry.name] options:NSDataReadingMappedIfSafe error:&poolError];
                ok = data != nil && [self addData:data name:names[i] error:&poolError];
            }
            entryError = poolError;
        }
    }
    [fileManager removeItemAtPath:temp error:nil];
    if (!ok && error) {
        *error = entryError;
    }
    return ok;
}

- (BOOL)addData:(NSData *)data name:(NSString *)name error:(NSError **)error {
    if (![self checkCanAdd:name error:error]) {
        return NO;
    }
    if (data.length >= kRAZipLimit) {
        if (error) *error = RAZipError(RAArchiveErrorUnsupportedEntry, [NSString stringWithFormat:@"%@ is too large for a zip without zip64", name]);
        return NO;
    }

    uint32_t crc = (uint32_t)crc32(0L, data.bytes, (uInt)data.length);
    NSData *payload = data;
    uint16_t method = kRAZipStored;

    z_stream stream = {0};
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) == Z_OK) {
        uLong bound = deflateBound(&stream, (uLong)data.length);
        NSMutableData *compressed = [NSMutableData dataWithLength:bound];
        stream.next_in = (Bytef *)data.bytes;
        stream.avail_in = (uInt)data.length;
        stream.next_out = compressed.mutableBytes;
        stream.avail_out = (uInt)bound;
        int result = deflate(&stream, Z_FINISH);
        if (result == Z_STREAM_END && stream.total_out < data.length) {
            compressed.length = stream.total_out;
            payload = compressed;
            method = kRAZipDeflated;
        }
        deflateEnd(&stream);
    }

    RAZipWrittenEntry *written = [self newEntryNamed:name method:method crc:crc
                                      compressedSize:(uint32_t)payload.length size:(uint32_t)data.length];
    return [self writeLocalHeader:written error:error]
        && [self writeBytes:payload.bytes length:payload.length error:error]
        && [self commit:written error:error];
}

/// Copies an entry's compressed bytes as they are. They are inflated alongside only
/// to check the CRC and size, so a damaged source never ends up in the new archive.
- (BOOL)copyRawEntry:(RAArchiveEntry *)entry fromZipAtPath:(NSString *)archivePath asName:(NSString *)name error:(NSError **)error {
    FILE *source = fopen(archivePath.fileSystemRepresentation, "rb");
    if (source == NULL) {
        if (error) *error = RAZipError(RAArchiveErrorOpenFailed, [NSString stringWithFormat:@"Cannot open %@", archivePath.lastPathComponent]);
        return NO;
    }
    BOOL ok = [self copyRawEntry:entry from:source archiveName:archivePath.lastPathComponent asName:name error:error];
    fclose(source);
    return ok;
}

- (BOOL)copyRawEntry:(RAArchiveEntry *)entry from:(FILE *)source archiveName:(NSString *)archiveName
              asName:(NSString *)name error:(NSError **)error {
    uint8_t header[kRAZipLocalHeaderLength];
    if (fseeko(source, (off_t)entry.zipHeaderOffset, SEEK_SET) != 0
        || fread(header, 1, sizeof(header), source) != sizeof(header)
        || RARead32(header) != kRAZipLocalSignature) {
        if (error) *error = RAZipError(RAArchiveErrorDecompressFailed, [NSString stringWithFormat:@"Bad local header for %@ in %@", entry.name, archiveName]);
        return NO;
    }
    if (RARead16(header + 6) & kRAZipFlagEncrypted) {
        if (error) *error = RAZipError(RAArchiveErrorUnsupportedEntry, [NSString stringWithFormat:@"%@ in %@ is encrypted", entry.name, archiveName]);
        return NO;
    }
    off_t dataOffset = (off_t)entry.zipHeaderOffset + kRAZipLocalHeaderLength + RARead16(header + 26) + RARead16(header + 28);
    if (fseeko(source, dataOffset, SEEK_SET) != 0) {
        if (error) *error = RAZipError(RAArchiveErrorDecompressFailed, [NSString stringWithFormat:@"Cannot seek to %@ in %@", entry.name, archiveName]);
        return NO;
    }

    RAZipWrittenEntry *written = [self newEntryNamed:name method:entry.zipMethod crc:entry.crc32
                                      compressedSize:entry.zipCompressedSize size:(uint32_t)entry.size];
    if (![self writeLocalHeader:written error:error]) {
        return NO;
    }

    BOOL deflated = entry.zipMethod == kRAZipDeflated;
    z_stream stream = {0};
    if (deflated && inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
        if (error) *error = RAZipError(RAArchiveErrorDecompressFailed, @"inflateInit2 failed");
        return NO;
    }

    NSMutableData *input = [NSMutableData dataWithLength:kRAZipCopyChunk];
    NSMutableData *output = [NSMutableData dataWithLength:kRAZipCopyChunk];
    uLong crc = crc32(0L, Z_NULL, 0);
    uint64_t produced = 0;
    uint64_t remaining = entry.zipCompressedSize;
    BOOL ok = YES;
    int inflateResult = Z_OK;

    while (ok && remaining > 0) {
        size_t chunk = (size_t)MIN(remaining, (uint64_t)kRAZipCopyChunk);
        if (fread(input.mutableBytes, 1, chunk, source) != chunk) {
            ok = NO;
            break;
        }
        remaining -= chunk;
        ok = [self writeBytes:input.bytes length:chunk error:error];
        if (!ok) {
            break;
        }
        if (!deflated) {
            crc = crc32(crc, input.bytes, (uInt)chunk);
            produced += chunk;
            continue;
        }
        stream.next_in = input.mutableBytes;
        stream.avail_in = (uInt)chunk;
        while (stream.avail_in > 0 && inflateResult != Z_STREAM_END) {
            stream.next_out = output.mutableBytes;
            stream.avail_out = (uInt)kRAZipCopyChunk;
            inflateResult = inflate(&stream, Z_NO_FLUSH);
            if (inflateResult != Z_OK && inflateResult != Z_STREAM_END) {
                ok = NO;
                break;
            }
            size_t have = kRAZipCopyChunk - stream.avail_out;
            crc = crc32(crc, output.bytes, (uInt)have);
            produced += have;
        }
    }
    if (deflated) {
        inflateEnd(&stream);
    }

    if (!ok || crc != entry.crc32 || produced != entry.size || (deflated && inflateResult != Z_STREAM_END)) {
        if (error && (*error == nil)) {
            *error = RAZipError(RAArchiveErrorCRCMismatch,
                                [NSString stringWithFormat:@"%@ in %@ is damaged (crc %08lx/%08x, size %llu/%llu)",
                                 entry.name, archiveName, crc, entry.crc32, produced, entry.size]);
        }
        return NO;
    }
    return [self commit:written error:error];
}

#pragma mark - Writing

- (RAZipWrittenEntry *)newEntryNamed:(NSString *)name method:(uint16_t)method crc:(uint32_t)crc
                      compressedSize:(uint32_t)compressedSize size:(uint32_t)size {
    RAZipWrittenEntry *written = [[RAZipWrittenEntry alloc] init];
    written.name = name;
    written.nameBytes = [name dataUsingEncoding:NSUTF8StringEncoding];
    BOOL ascii = [name canBeConvertedToEncoding:NSASCIIStringEncoding];
    written.flags = ascii ? 0 : kRAZipFlagUTF8;
    written.method = method;
    written.crc32 = crc;
    written.compressedSize = compressedSize;
    written.size = size;
    written.headerOffset = (uint32_t)_offset;
    return written;
}

- (BOOL)writeLocalHeader:(RAZipWrittenEntry *)entry error:(NSError **)error {
    uint64_t end = _offset + kRAZipLocalHeaderLength + entry.nameBytes.length + entry.compressedSize;
    if (end >= kRAZipLimit || entry.nameBytes.length > 0xFFFF) {
        if (error) *error = RAZipError(RAArchiveErrorUnsupportedEntry, [NSString stringWithFormat:@"Archive would exceed 4 GiB at %@", entry.name]);
        return NO;
    }
    NSMutableData *header = [NSMutableData dataWithCapacity:kRAZipLocalHeaderLength + entry.nameBytes.length];
    RAPut32(header, kRAZipLocalSignature);
    RAPut16(header, kRAZipVersion);
    RAPut16(header, entry.flags);
    RAPut16(header, entry.method);
    RAPut16(header, kRAZipDosTime);
    RAPut16(header, kRAZipDosDate);
    RAPut32(header, entry.crc32);
    RAPut32(header, entry.compressedSize);
    RAPut32(header, entry.size);
    RAPut16(header, (uint16_t)entry.nameBytes.length);
    RAPut16(header, 0);
    [header appendData:entry.nameBytes];
    return [self writeBytes:header.bytes length:header.length error:error];
}

- (BOOL)writeBytes:(const void *)bytes length:(size_t)length error:(NSError **)error {
    if (length > 0 && fwrite(bytes, 1, length, _file) != length) {
        if (error) *error = RAZipError(RAArchiveErrorWriteFailed, [NSString stringWithFormat:@"Write to %@ failed", _partialPath.lastPathComponent]);
        return NO;
    }
    _offset += length;
    return YES;
}

- (BOOL)commit:(RAZipWrittenEntry *)entry error:(NSError **)error {
    [_entries addObject:entry];
    [_names addObject:entry.name];
    return YES;
}

- (BOOL)finish:(NSError **)error {
    if (_file == NULL) {
        if (error) *error = RAZipError(RAArchiveErrorWriteFailed, @"Writer is already finished or cancelled");
        return NO;
    }

    uint64_t directoryOffset = _offset;
    NSMutableData *directory = [NSMutableData data];
    for (RAZipWrittenEntry *entry in _entries) {
        RAPut32(directory, kRAZipCentralSignature);
        RAPut16(directory, kRAZipVersion);
        RAPut16(directory, kRAZipVersion);
        RAPut16(directory, entry.flags);
        RAPut16(directory, entry.method);
        RAPut16(directory, kRAZipDosTime);
        RAPut16(directory, kRAZipDosDate);
        RAPut32(directory, entry.crc32);
        RAPut32(directory, entry.compressedSize);
        RAPut32(directory, entry.size);
        RAPut16(directory, (uint16_t)entry.nameBytes.length);
        RAPut16(directory, 0);  // extra
        RAPut16(directory, 0);  // comment
        RAPut16(directory, 0);  // disk
        RAPut16(directory, 0);  // internal attributes
        RAPut32(directory, 0);  // external attributes
        RAPut32(directory, entry.headerOffset);
        [directory appendData:entry.nameBytes];
    }
    if (directoryOffset + directory.length >= kRAZipLimit) {
        [self cancel];
        if (error) *error = RAZipError(RAArchiveErrorUnsupportedEntry, @"Archive would exceed 4 GiB");
        return NO;
    }
    NSMutableData *end = [NSMutableData data];
    RAPut32(end, kRAZipEndSignature);
    RAPut16(end, 0);
    RAPut16(end, 0);
    RAPut16(end, (uint16_t)_entries.count);
    RAPut16(end, (uint16_t)_entries.count);
    RAPut32(end, (uint32_t)directory.length);
    RAPut32(end, (uint32_t)directoryOffset);
    RAPut16(end, 0);

    BOOL written = [self writeBytes:directory.bytes length:directory.length error:error]
        && [self writeBytes:end.bytes length:end.length error:error]
        && fflush(_file) == 0 && fsync(fileno(_file)) == 0;
    fclose(_file);
    _file = NULL;
    if (!written) {
        [self cancel];
        if (error && *error == nil) *error = RAZipError(RAArchiveErrorWriteFailed, @"Flushing the archive failed");
        return NO;
    }

    if (![self verifyPartial:error]) {
        [self cancel];
        return NO;
    }

    // rename(2) replaces an existing file atomically.
    if (rename(_partialPath.fileSystemRepresentation, _path.fileSystemRepresentation) != 0) {
        [self cancel];
        if (error) *error = RAZipError(RAArchiveErrorWriteFailed, [NSString stringWithFormat:@"Cannot move archive to %@", _path.lastPathComponent]);
        return NO;
    }
    _finished = YES;
    return YES;
}

/// Reads the written directory back with the regular reader and compares it with
/// what was meant to be written.
- (BOOL)verifyPartial:(NSError **)error {
    NSArray<RAArchiveEntry *> *listed = [RAArchiveReader entriesOfArchiveAtPath:_partialPath error:error];
    if (listed == nil) {
        return NO;
    }
    BOOL matches = listed.count == _entries.count;
    for (NSUInteger i = 0; matches && i < listed.count; i++) {
        RAArchiveEntry *got = listed[i];
        RAZipWrittenEntry *want = _entries[i];
        matches = [got.name isEqualToString:want.name] && got.size == want.size && got.crc32 == want.crc32;
    }
    if (!matches) {
        if (error) *error = RAZipError(RAArchiveErrorWriteFailed, @"Written archive does not read back as expected");
        return NO;
    }
    return YES;
}

@end

NS_ASSUME_NONNULL_END
