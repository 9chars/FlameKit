// item_icons.hpp: an item's icon, read from the game's own data files.
//
// The game keeps a 2D icon for every item: a UiTextureResource filed under the item's GUID. Those records are in
// enshrouded.kfc_resources, zstd-compressed in chunks of 8 MB; enshrouded.kfc lists where each one is. A record
// names its picture by content key (size and hash), and the picture itself lies uncompressed in one of the
// enshrouded_NNN.dat files as a BC7 texture (256 x 256 with its smaller copies behind it).
//
// Everything is checked (sizes, counts, the format); an icon that is not as expected is simply not there, and the
// panel shows the item without a picture. Third-party code: zstd's decoder (zstddeclib.c) and bcdec.h (BC7).
#pragma once

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

extern "C" {
size_t ZSTD_decompress(void* dst, size_t dstCapacity, const void* src, size_t compressedSize);
unsigned ZSTD_isError(size_t code);
}

#define BCDEC_IMPLEMENTATION
#include "bcdec.h"

struct ItemIcons {
    using Open = FILE* (*)(const char* name, void* user);  // opens one of the game's files for reading ("rb")

    Open open = nullptr;
    void* user = nullptr;
    std::vector<uint8_t> dir;       // enshrouded.kfc
    bool tried = false, ok = false;
    std::string note;               // why it is not ok
    size_t res_keys = 0, res_values = 0, res_count = 0, con_keys = 0, con_values = 0, con_count = 0;
    struct Chunk {
        uint32_t offset, size, compressed, start, bytes;  // start, bytes: where its content is in the unpacked whole
    };
    std::vector<Chunk> chunks;
    std::vector<uint8_t> unpacked;  // the chunk unpacked last
    int unpacked_index = -1;

    static uint32_t u32(const uint8_t* p) {
        uint32_t v;
        std::memcpy(&v, p, 4);
        return v;
    }

    void load() {
        if (tried) return;
        tried = true;
        FILE* f = open("enshrouded.kfc", user);
        if (!f) return void(note = "enshrouded.kfc could not be opened");
        fseek(f, 0, SEEK_END);
        const long size = ftell(f);
        fseek(f, 0, SEEK_SET);
        if (size >= 256 && size <= (1L << 30)) {
            dir.resize(static_cast<size_t>(size));
            if (fread(dir.data(), 1, dir.size(), f) != dir.size()) dir.clear();
        }
        fclose(f);
        if (dir.empty() || u32(&dir[0]) != 0x3443464B) return void(note = "enshrouded.kfc is not in the known format (KFC4)");
        auto place = [&](int i, size_t& at, size_t& count) {
            const size_t field = 16 + static_cast<size_t>(i) * 8;
            at = field + u32(&dir[field]);
            count = u32(&dir[field + 4]);
        };
        size_t n2, chunk_at, chunk_count;
        place(7, con_keys, con_count);
        place(8, con_values, n2);
        if (n2 != con_count || con_keys + con_count * 16 > dir.size() || con_values + con_count * 16 > dir.size())
            return void(note = "the content list is not where it was expected");
        place(10, res_keys, res_count);
        place(11, res_values, n2);
        if (n2 != res_count || res_keys + res_count * 32 > dir.size() || res_values + res_count * 8 > dir.size())
            return void(note = "the resource list is not where it was expected");
        place(15, chunk_at, chunk_count);
        if (chunk_count == 0 || chunk_count > 4096 || chunk_at + chunk_count * 20 > dir.size())
            return void(note = "the resource chunks are not where they were expected");
        for (size_t i = 0; i < chunk_count; ++i) {
            const uint8_t* p = &dir[chunk_at + i * 20];
            const Chunk c{u32(p), u32(p + 4), u32(p + 8), u32(p + 12), u32(p + 16)};
            if (c.bytes > (64u << 20) || c.compressed > (64u << 20)) return void(note = "a resource chunk has an unexpected size");
            chunks.push_back(c);
        }
        ok = true;
    }

    // The record of `type` filed under `guid` (part 0), unpacked; empty when there is none.
    bool resource(const uint8_t guid[16], uint32_t type, std::vector<uint8_t>& out) {
        for (size_t i = 0; i < res_count; ++i) {
            const uint8_t* k = &dir[res_keys + i * 32];
            if (u32(k + 16) != type || u32(k + 20) != 0 || std::memcmp(k, guid, 16) != 0) continue;
            const uint32_t at = u32(&dir[res_values + i * 8]), bytes = u32(&dir[res_values + i * 8 + 4]);
            if (bytes == 0 || bytes > (1u << 20)) return false;
            for (size_t c = 0; c < chunks.size(); ++c) {
                const Chunk& ch = chunks[c];
                if (at < ch.start || at + bytes > ch.start + ch.bytes) continue;
                if (unpacked_index != static_cast<int>(c)) {
                    unpacked_index = -1;
                    FILE* f = open("enshrouded.kfc_resources", user);
                    if (!f) return false;
                    std::vector<uint8_t> packed(ch.compressed);
                    const bool read = fseek(f, static_cast<long>(ch.offset), SEEK_SET) == 0 &&
                                      fread(packed.data(), 1, packed.size(), f) == packed.size();
                    fclose(f);
                    if (!read) return false;
                    unpacked.resize(ch.bytes);
                    const size_t got = ZSTD_decompress(unpacked.data(), unpacked.size(), packed.data(), packed.size());
                    if (ZSTD_isError(got) || got != ch.bytes) return false;
                    unpacked_index = static_cast<int>(c);
                }
                out.assign(unpacked.begin() + (at - ch.start), unpacked.begin() + (at - ch.start) + bytes);
                return true;
            }
            return false;
        }
        return false;
    }

    // The icon of the item with this GUID as size x size pixels of 4 bytes (red, green, blue, opacity); false when
    // it cannot be had. `size` must divide the stored picture's side (256): 32, 64, 128 or 256.
    bool icon(const uint8_t guid[16], int size, std::vector<uint8_t>& rgba) {
        load();
        if (!ok) return false;
        std::vector<uint8_t> rec;
        if (!resource(guid, 0xf9e86997u, rec) || rec.size() < 52) return false;  // UiTextureResource
        const uint32_t w = u32(&rec[40]), h = u32(&rec[44]);
        if (rec[49] != 0x91 || w != h || w < 64 || w > 1024 || (w & (w - 1)) != 0 || size <= 0 || w % size != 0) return false;  // BC7 only
        size_t found = con_count;
        for (size_t i = 0; i < con_count && found == con_count; ++i)
            if (std::memcmp(&dir[con_keys + i * 16], rec.data(), 16) == 0) found = i;
        if (found == con_count || u32(&rec[0]) < w * h) return false;
        const uint32_t at = u32(&dir[con_values + found * 16]);
        const unsigned file = dir[con_values + found * 16 + 6] | (dir[con_values + found * 16 + 7] << 8);
        char name[40];
        snprintf(name, sizeof name, "enshrouded_%03u.dat", file);
        FILE* f = open(name, user);
        if (!f) return false;
        std::vector<uint8_t> packed(static_cast<size_t>(w) * h);  // BC7: 16 bytes for 16 pixels
#if defined(_WIN32)
        const bool read = _fseeki64(f, at, SEEK_SET) == 0 && fread(packed.data(), 1, packed.size(), f) == packed.size();
#else
        const bool read = fseek(f, static_cast<long>(at), SEEK_SET) == 0 && fread(packed.data(), 1, packed.size(), f) == packed.size();
#endif
        fclose(f);
        if (!read) return false;
        std::vector<uint8_t> full(static_cast<size_t>(w) * h * 4);
        for (uint32_t by = 0; by < h / 4; ++by)
            for (uint32_t bx = 0; bx < w / 4; ++bx)
                bcdec_bc7(&packed[(static_cast<size_t>(by) * (w / 4) + bx) * 16], &full[(static_cast<size_t>(by) * 4 * w + bx * 4) * 4],
                          static_cast<int>(w * 4));
        // shrunk by averaging, colour weighted by opacity so clear pixels do not darken the edges
        const uint32_t k = w / static_cast<uint32_t>(size);
        rgba.assign(static_cast<size_t>(size) * size * 4, 0);
        for (int y = 0; y < size; ++y)
            for (int x = 0; x < size; ++x) {
                uint64_t r = 0, g = 0, b = 0, a = 0;
                for (uint32_t yy = 0; yy < k; ++yy)
                    for (uint32_t xx = 0; xx < k; ++xx) {
                        const uint8_t* p = &full[((static_cast<size_t>(y) * k + yy) * w + x * k + xx) * 4];
                        r += static_cast<uint64_t>(p[0]) * p[3];
                        g += static_cast<uint64_t>(p[1]) * p[3];
                        b += static_cast<uint64_t>(p[2]) * p[3];
                        a += p[3];
                    }
                uint8_t* o = &rgba[(static_cast<size_t>(y) * size + x) * 4];
                if (a > 0) {
                    o[0] = static_cast<uint8_t>(r / a);
                    o[1] = static_cast<uint8_t>(g / a);
                    o[2] = static_cast<uint8_t>(b / a);
                    o[3] = static_cast<uint8_t>(a / (k * k));
                }
            }
        return true;
    }

    // A PNG file of w x h pixels (4 bytes each), not compressed: icons are small.
    static std::vector<uint8_t> png(const std::vector<uint8_t>& rgba, int w, int h) {
        static uint32_t table[256];
        if (!table[1])
            for (uint32_t i = 0; i < 256; ++i) {
                uint32_t c = i;
                for (int k = 0; k < 8; ++k) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                table[i] = c;
            }
        std::vector<uint8_t> out = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
        auto be = [](std::vector<uint8_t>& v, uint32_t x) {
            for (int s = 24; s >= 0; s -= 8) v.push_back(static_cast<uint8_t>(x >> s));
        };
        auto chunk = [&](const char* type, const std::vector<uint8_t>& data) {
            be(out, static_cast<uint32_t>(data.size()));
            const size_t from = out.size();
            out.insert(out.end(), type, type + 4);
            out.insert(out.end(), data.begin(), data.end());
            uint32_t c = 0xFFFFFFFFu;
            for (size_t i = from; i < out.size(); ++i) c = table[(c ^ out[i]) & 0xFF] ^ (c >> 8);
            be(out, c ^ 0xFFFFFFFFu);
        };
        std::vector<uint8_t> head;
        be(head, static_cast<uint32_t>(w));
        be(head, static_cast<uint32_t>(h));
        head.insert(head.end(), {8, 6, 0, 0, 0});
        chunk("IHDR", head);
        std::vector<uint8_t> raw;  // each row: a filter byte (none), then its pixels
        for (int y = 0; y < h; ++y) {
            raw.push_back(0);
            raw.insert(raw.end(), rgba.begin() + static_cast<size_t>(y) * w * 4, rgba.begin() + static_cast<size_t>(y + 1) * w * 4);
        }
        std::vector<uint8_t> z = {0x78, 0x01};  // zlib, stored blocks of at most 65535 bytes
        uint32_t s1 = 1, s2 = 0;
        for (size_t at = 0; at < raw.size();) {
            const size_t n = raw.size() - at < 65535 ? raw.size() - at : 65535;
            z.push_back(at + n == raw.size() ? 1 : 0);
            z.push_back(static_cast<uint8_t>(n));
            z.push_back(static_cast<uint8_t>(n >> 8));
            z.push_back(static_cast<uint8_t>(~n));
            z.push_back(static_cast<uint8_t>(~n >> 8));
            for (size_t i = 0; i < n; ++i) {
                z.push_back(raw[at + i]);
                s1 = (s1 + raw[at + i]) % 65521;
                s2 = (s2 + s1) % 65521;
            }
            at += n;
        }
        be(z, (s2 << 16) | s1);
        chunk("IDAT", z);
        chunk("IEND", {});
        return out;
    }
};
