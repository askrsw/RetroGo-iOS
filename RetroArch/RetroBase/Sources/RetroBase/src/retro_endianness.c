//
//  retro_endianness.c
//  RetroArch
//
//  Created by haharsw on 2025/7/27.
//

#include "retro_endianness.h"

#if defined(_MSC_VER) && _MSC_VER > 1200
#else

uint16_t SWAP16(uint16_t x) {
    return ((x & 0x00ff) << 8) |
        ((x & 0xff00) >> 8);
}

uint32_t SWAP32(uint32_t x) {
    return ((x & 0x000000ff) << 24) |
        ((x & 0x0000ff00) <<  8) |
        ((x & 0x00ff0000) >>  8) |
        ((x & 0xff000000) >> 24);
}

#endif

#if defined(_MSC_VER) && _MSC_VER <= 1200
uint64_t SWAP64(uint64_t val) {
    return
        ((val & 0x00000000000000ff) << 56)
        | ((val & 0x000000000000ff00) << 40)
        | ((val & 0x0000000000ff0000) << 24)
        | ((val & 0x00000000ff000000) << 8)
        | ((val & 0x000000ff00000000) >> 8)
        | ((val & 0x0000ff0000000000) >> 24)
        | ((val & 0x00ff000000000000) >> 40)
        | ((val & 0xff00000000000000) >> 56);
}
#else
/**
 * Swaps the byte order of a 64-bit unsigned integer.
 * @param x The integer to byteswap.
 * @return \c with its bytes swapped.
 */
uint64_t SWAP64(uint64_t val) {
    return   ((val & 0x00000000000000ffULL) << 56)
        | ((val & 0x000000000000ff00ULL) << 40)
        | ((val & 0x0000000000ff0000ULL) << 24)
        | ((val & 0x00000000ff000000ULL) << 8)
        | ((val & 0x000000ff00000000ULL) >> 8)
        | ((val & 0x0000ff0000000000ULL) >> 24)
        | ((val & 0x00ff000000000000ULL) >> 40)
        | ((val & 0xff00000000000000ULL) >> 56);
}
#endif

void store32be(uint32_t *addr, uint32_t data) {
    *addr = swap_if_little32(data);
}

uint32_t load32be(const uint32_t *addr) {
    return swap_if_little32(*addr);
}

uint16_t retro_get_unaligned_16be(void *addr) {
    return retro_be_to_cpu16(retro_unaligned16(addr));
}

uint32_t retro_get_unaligned_32be(void *addr) {
    return retro_be_to_cpu32(retro_unaligned32(addr));
}

uint64_t retro_get_unaligned_64be(void *addr) {
    return retro_be_to_cpu64(retro_unaligned64(addr));
}

uint16_t retro_get_unaligned_16le(void *addr) {
    return retro_le_to_cpu16(retro_unaligned16(addr));
}

uint32_t retro_get_unaligned_32le(void *addr) {
    return retro_le_to_cpu32(retro_unaligned32(addr));
}

uint64_t retro_get_unaligned_64le(void *addr) {
    return retro_le_to_cpu64(retro_unaligned64(addr));
}

void retro_set_unaligned_16le(void *addr, uint16_t v) {
    retro_unaligned16(addr) = retro_cpu_to_le16(v);
}

void retro_set_unaligned_32le(void *addr, uint32_t v) {
    retro_unaligned32(addr) = retro_cpu_to_le32(v);
}

void retro_set_unaligned_64le(void *addr, uint64_t v) {
    retro_unaligned64(addr) = retro_cpu_to_le64(v);
}

void retro_set_unaligned_16be(void *addr, uint16_t v) {
    retro_unaligned16(addr) = retro_cpu_to_be16(v);
}

void retro_set_unaligned_32be(void *addr, uint32_t v) {
    retro_unaligned32(addr) = retro_cpu_to_be32(v);
}

void retro_set_unaligned_64be(void *addr, uint64_t v) {
    retro_unaligned64(addr) = retro_cpu_to_be64(v);
}
