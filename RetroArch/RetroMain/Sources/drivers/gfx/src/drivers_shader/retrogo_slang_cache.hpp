//
//  retrogo_slang_cache.hpp
//  RetroGo
//
//  Created by haharsw on 2026/10/23.
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

#ifndef RETROGO_SLANG_CACHE_HPP
#define RETROGO_SLANG_CACHE_HPP

// glslang_output must be declared by the caller. This cache owns no renderer or GPU resources.
#include <CommonCrypto/CommonDigest.h>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

namespace retrogo_slang_cache {
static std::mutex directory_mutex;
static std::string directory;
static std::atomic<unsigned long> sequence{0};
static constexpr size_t max_bytes = 64 * 1024 * 1024;

inline std::string identity(const std::string &vertex, const std::string &fragment, const std::string &source)
{
   CC_SHA256_CTX context;
   CC_SHA256_Init(&context);
   // AppConfig.shaderCacheVersion selects the directory namespace. Only source contents
   // identify entries within that version; unrelated App builds must preserve cache hits.
   CC_SHA256_Update(&context, vertex.data(), static_cast<CC_LONG>(vertex.size()));
   const char separator = 0;
   CC_SHA256_Update(&context, &separator, 1);
   CC_SHA256_Update(&context, fragment.data(), static_cast<CC_LONG>(fragment.size()));
   CC_SHA256_Update(&context, &separator, 1);
   CC_SHA256_Update(&context, source.data(), static_cast<CC_LONG>(source.size()));
   unsigned char hash[CC_SHA256_DIGEST_LENGTH];
   CC_SHA256_Final(hash, &context);
   char hex[65];
   for (size_t i = 0; i < sizeof(hash); i++) snprintf(hex + i * 2, 3, "%02x", hash[i]);
   return std::string(hex, 64);
}

inline std::string path(const std::string &key)
{
   std::lock_guard<std::mutex> lock(directory_mutex);
   return directory.empty() ? "" : directory + "/" + key + ".spvc";
}

struct Writer {
   std::vector<uint8_t> bytes;
   void word(uint32_t value) { for (unsigned i = 0; i < 4; i++) bytes.push_back(static_cast<uint8_t>(value >> (i * 8))); }
   void text(const std::string &value) { word(static_cast<uint32_t>(value.size())); bytes.insert(bytes.end(), value.begin(), value.end()); }
   void real(float value) { uint32_t bits; memcpy(&bits, &value, 4); word(bits); }
   void spirv(const std::vector<uint32_t> &value) { word(static_cast<uint32_t>(value.size())); for (auto v : value) word(v); }
};

struct Reader {
   const std::vector<uint8_t> &bytes;
   size_t offset = 0;
   bool word(uint32_t &value) {
      if (offset + 4 > bytes.size()) return false;
      value = 0;
      for (unsigned i = 0; i < 4; i++) value |= uint32_t(bytes[offset++]) << (i * 8);
      return true;
   }
   bool text(std::string &value) {
      uint32_t size;
      if (!word(size) || size > 4096 || offset + size > bytes.size()) return false;
      value.assign(reinterpret_cast<const char *>(bytes.data() + offset), size); offset += size;
      return true;
   }
   bool real(float &value) { uint32_t bits; if (!word(bits)) return false; memcpy(&value, &bits, 4); return std::isfinite(value); }
   bool spirv(std::vector<uint32_t> &value) {
      uint32_t size;
      if (!word(size) || size < 5 || size > max_bytes / 4 || size > (bytes.size() - offset) / 4) return false;
      value.resize(size);
      for (auto &v : value) if (!word(v)) return false;
      return value[0] == 0x07230203;
   }
};

inline bool load(const std::string &file, glslang_output &output)
{
   struct stat status;
   if (file.empty() || stat(file.c_str(), &status) || status.st_size < 32 || status.st_size > max_bytes) return false;
   FILE *input = fopen(file.c_str(), "rb");
   if (!input) return false;
   std::vector<uint8_t> bytes(static_cast<size_t>(status.st_size));
   const bool read = fread(bytes.data(), 1, bytes.size(), input) == bytes.size();
   fclose(input);
   if (!read) return false;
   unsigned char checksum[32];
   CC_SHA256(bytes.data(), static_cast<CC_LONG>(bytes.size() - 32), checksum);
   if (memcmp(checksum, bytes.data() + bytes.size() - 32, 32)) return false;
   bytes.resize(bytes.size() - 32);
   Reader reader{bytes};
   glslang_output candidate;
   uint32_t magic, format, count;
   if (!reader.word(magic) || magic != 0x31534752 || !reader.spirv(candidate.vertex) || !reader.spirv(candidate.fragment)
         || !reader.text(candidate.meta.name) || !reader.word(format) || format >= SLANG_FORMAT_MAX
         || !reader.word(count) || count > 4096) return false;
   candidate.meta.rt_format = static_cast<glslang_format>(format);
   for (uint32_t i = 0; i < count; i++)
   {
      glslang_parameter parameter;
      if (!reader.text(parameter.id) || !reader.text(parameter.desc) || !reader.real(parameter.initial)
            || !reader.real(parameter.minimum) || !reader.real(parameter.maximum) || !reader.real(parameter.step)) return false;
      candidate.meta.parameters.push_back(std::move(parameter));
   }
   if (reader.offset != bytes.size()) return false;
   output = std::move(candidate);
   // The Swift index owns LRU timestamps. Cache reads must preserve artifact fingerprints.
   return true;
}

inline bool store(const std::string &file, const glslang_output &output)
{
   if (file.empty() || output.vertex.size() < 5 || output.fragment.size() < 5
         || output.vertex[0] != 0x07230203 || output.fragment[0] != 0x07230203
         || output.meta.name.size() > 4096 || output.meta.parameters.size() > 4096) return false;
   for (const auto &p : output.meta.parameters)
      if (p.id.size() > 4096 || p.desc.size() > 4096 || !std::isfinite(p.initial)
            || !std::isfinite(p.minimum) || !std::isfinite(p.maximum) || !std::isfinite(p.step)) return false;
   Writer writer;
   writer.word(0x31534752);
   writer.spirv(output.vertex); writer.spirv(output.fragment);
   writer.text(output.meta.name); writer.word(output.meta.rt_format);
   writer.word(static_cast<uint32_t>(output.meta.parameters.size()));
   for (const auto &p : output.meta.parameters)
   {
      writer.text(p.id); writer.text(p.desc); writer.real(p.initial);
      writer.real(p.minimum); writer.real(p.maximum); writer.real(p.step);
   }
   if (writer.bytes.size() > max_bytes - 32) return false;
   unsigned char checksum[32];
   CC_SHA256(writer.bytes.data(), static_cast<CC_LONG>(writer.bytes.size()), checksum);
   writer.bytes.insert(writer.bytes.end(), checksum, checksum + 32);
   const std::string temporary = file + "." + std::to_string(getpid()) + "." + std::to_string(sequence++) + ".tmp";
   FILE *output_file = fopen(temporary.c_str(), "wb");
   if (!output_file) return false;
   const bool written = fwrite(writer.bytes.data(), 1, writer.bytes.size(), output_file) == writer.bytes.size();
   const bool closed = fclose(output_file) == 0;
   const bool published = written && closed && rename(temporary.c_str(), file.c_str()) == 0;
   if (!published) unlink(temporary.c_str());
   return published;
}
}
#endif
