// item_icons.hpp: item and buff icons, read from the game's own data files.
//
// The game keeps a 2D icon for every item: a UiTextureResource filed under the item's GUID. Those records are in
// enshrouded.kfc_resources, zstd-compressed in chunks of 8 MB; enshrouded.kfc lists where each one is. A record
// names its picture by content key (size and hash), and the picture itself lies uncompressed in one of the
// enshrouded_NNN.dat files: a BC7 texture for items (256 x 256 with its smaller copies behind it), plain RGBA (8 bits
// each) for buffs (mostly 64 x 64, white symbols the UI puts on a coloured badge).
//
// Buffs (since 0.15.49): the buff registry is the one record of type 0x1be67cef (game build 1287369, read from the
// data files on 2026-11-13). Its third list (offset and count at +24 and +28) holds every buff type, 184 bytes each:
// +0 the buff type id (the id EMF's buff calls use), +4 its slot, +8 its default time (ns), +52 the GUID of its icon
// (a UiTextureResource; 267 of the 274 types have one, e.g. Wet 0xac13c6c3 -> "debuff_wet").
//
// Everything is checked (sizes, counts, the format); an icon that is not as expected is simply not there, and the
// window shows the item or buff without a picture. Third-party code: zstd's decoder (zstddeclib.c) and bcdec.h (BC7).
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
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

    // Unpacked chunk `c` into `unpacked` (the last one is kept).
    bool unpack(size_t c) {
        if (unpacked_index == static_cast<int>(c)) return true;
        unpacked_index = -1;
        const Chunk& ch = chunks[c];
        FILE* f = open("enshrouded.kfc_resources", user);
        if (!f) return false;
        std::vector<uint8_t> packed(ch.compressed);
        const bool read = fseek(f, static_cast<long>(ch.offset), SEEK_SET) == 0 && fread(packed.data(), 1, packed.size(), f) == packed.size();
        fclose(f);
        if (!read) return false;
        unpacked.resize(ch.bytes);
        const size_t got = ZSTD_decompress(unpacked.data(), unpacked.size(), packed.data(), packed.size());
        if (ZSTD_isError(got) || got != ch.bytes) return false;
        unpacked_index = static_cast<int>(c);
        return true;
    }

    // Resource number `i`, unpacked (it may lie across two chunks); false when it cannot be had.
    bool resource_at(size_t i, std::vector<uint8_t>& out) {
        const uint32_t at = u32(&dir[res_values + i * 8]), bytes = u32(&dir[res_values + i * 8 + 4]);
        if (bytes == 0 || bytes > (4u << 20)) return false;
        out.clear();
        for (size_t c = 0; c < chunks.size() && out.size() < bytes; ++c) {
            const Chunk& ch = chunks[c];
            const uint64_t lo = std::max<uint64_t>(at, ch.start), hi = std::min<uint64_t>(static_cast<uint64_t>(at) + bytes, static_cast<uint64_t>(ch.start) + ch.bytes);
            if (lo >= hi) continue;
            if (!unpack(c)) return false;
            out.insert(out.end(), unpacked.begin() + static_cast<std::ptrdiff_t>(lo - ch.start), unpacked.begin() + static_cast<std::ptrdiff_t>(hi - ch.start));
        }
        return out.size() == bytes;
    }

    // The record of `type` filed under `guid` (part 0), unpacked; false when there is none.
    bool resource(const uint8_t guid[16], uint32_t type, std::vector<uint8_t>& out) {
        for (size_t i = 0; i < res_count; ++i) {
            const uint8_t* k = &dir[res_keys + i * 32];
            if (u32(k + 16) == type && u32(k + 20) == 0 && std::memcmp(k, guid, 16) == 0) return resource_at(i, out);
        }
        return false;
    }

    // A texture's pixels, full size (4 bytes each: red, green, blue, opacity): BC7 (items) or plain RGBA (buffs).
    bool texture(const uint8_t guid[16], uint32_t& w, uint32_t& h, std::vector<uint8_t>& full) {
        std::vector<uint8_t> rec;
        if (!resource(guid, 0xf9e86997u, rec) || rec.size() < 52) return false;  // UiTextureResource
        w = u32(&rec[40]), h = u32(&rec[44]);
        const uint8_t format = rec[49];
        if (w < 4 || h < 4 || w > 1024 || h > 1024) return false;
        size_t bytes;
        if (format == 0x91) {  // BC7: square, a power of two, 16 bytes for 16 pixels
            if (w != h || (w & (w - 1)) != 0) return false;
            bytes = static_cast<size_t>(w) * h;
        } else if (format == 0x25) {  // RGBA, 8 bits each
            bytes = static_cast<size_t>(w) * h * 4;
        } else {
            return false;
        }
        if (u32(&rec[0]) < bytes) return false;
        size_t found = con_count;
        for (size_t i = 0; i < con_count && found == con_count; ++i)
            if (std::memcmp(&dir[con_keys + i * 16], rec.data(), 16) == 0) found = i;
        if (found == con_count) return false;
        const uint32_t at = u32(&dir[con_values + found * 16]);
        const unsigned file = dir[con_values + found * 16 + 6] | (dir[con_values + found * 16 + 7] << 8);
        char name[40];
        snprintf(name, sizeof name, "enshrouded_%03u.dat", file);
        FILE* f = open(name, user);
        if (!f) return false;
        std::vector<uint8_t> packed(bytes);
#if defined(_WIN32)
        const bool read = _fseeki64(f, at, SEEK_SET) == 0 && fread(packed.data(), 1, packed.size(), f) == packed.size();
#else
        const bool read = fseek(f, static_cast<long>(at), SEEK_SET) == 0 && fread(packed.data(), 1, packed.size(), f) == packed.size();
#endif
        fclose(f);
        if (!read) return false;
        if (format == 0x25) {
            full = std::move(packed);
            return true;
        }
        full.assign(static_cast<size_t>(w) * h * 4, 0);
        for (uint32_t by = 0; by < h / 4; ++by)
            for (uint32_t bx = 0; bx < w / 4; ++bx)
                bcdec_bc7(&packed[(static_cast<size_t>(by) * (w / 4) + bx) * 16], &full[(static_cast<size_t>(by) * 4 * w + bx * 4) * 4],
                          static_cast<int>(w * 4));
        return true;
    }

    // `full` (w x h) fitted into size x size, in the middle, keeping its shape; averaged, colour weighted by opacity so
    // clear pixels do not darken the edges.
    static void fit(const std::vector<uint8_t>& full, uint32_t w, uint32_t h, int size, std::vector<uint8_t>& rgba) {
        rgba.assign(static_cast<size_t>(size) * size * 4, 0);
        const double scale = static_cast<double>(std::max(w, h)) / size;  // source pixels per output pixel
        const double ox = (size - w / scale) / 2, oy = (size - h / scale) / 2;
        for (int y = 0; y < size; ++y)
            for (int x = 0; x < size; ++x) {
                const double sx0 = (x - ox) * scale, sy0 = (y - oy) * scale;
                const int x0 = static_cast<int>(std::floor(sx0)), y0 = static_cast<int>(std::floor(sy0));
                const int x1 = static_cast<int>(std::ceil(sx0 + scale)), y1 = static_cast<int>(std::ceil(sy0 + scale));
                uint64_t r = 0, g = 0, b = 0, a = 0, n = 0;
                for (int yy = y0; yy < y1; ++yy)
                    for (int xx = x0; xx < x1; ++xx) {
                        ++n;
                        if (xx < 0 || yy < 0 || xx >= static_cast<int>(w) || yy >= static_cast<int>(h)) continue;
                        const uint8_t* p = &full[(static_cast<size_t>(yy) * w + xx) * 4];
                        r += static_cast<uint64_t>(p[0]) * p[3];
                        g += static_cast<uint64_t>(p[1]) * p[3];
                        b += static_cast<uint64_t>(p[2]) * p[3];
                        a += p[3];
                    }
                uint8_t* o = &rgba[(static_cast<size_t>(y) * size + x) * 4];
                if (a > 0 && n > 0) {
                    o[0] = static_cast<uint8_t>(r / a);
                    o[1] = static_cast<uint8_t>(g / a);
                    o[2] = static_cast<uint8_t>(b / a);
                    o[3] = static_cast<uint8_t>(a / n);
                }
            }
    }

    // The icon of the item with this GUID as size x size pixels of 4 bytes (red, green, blue, opacity); false when
    // it cannot be had.
    bool icon(const uint8_t guid[16], int size, std::vector<uint8_t>& rgba) {
        load();
        if (!ok || size <= 0) return false;
        uint32_t w = 0, h = 0;
        std::vector<uint8_t> full;
        if (!texture(guid, w, h, full)) return false;
        fit(full, w, h, size, rgba);
        return true;
    }

    // ---- buffs ----
    bool buffs_tried = false;
    std::unordered_map<uint32_t, std::vector<uint8_t>> buff_icon_guid;  // buff type id -> its icon's GUID (16 bytes)
    int buff_types = 0;  // in the registry (0: not read)

    void load_buffs() {
        if (buffs_tried) return;
        buffs_tried = true;
        load();
        if (!ok) return;
        std::vector<uint8_t> reg;
        for (size_t i = 0; i < res_count && reg.empty(); ++i)
            if (u32(&dir[res_keys + i * 32 + 16]) == 0x1be67cefu && !resource_at(i, reg)) reg.clear();
        if (reg.size() < 32) return void(note = "the buff registry is not there");
        const size_t at = 24 + static_cast<size_t>(u32(&reg[24])), n = u32(&reg[28]);
        if (n == 0 || n > 4096 || at + n * 184 > reg.size()) return void(note = "the buff registry is not as expected");
        for (size_t k = 0; k < n; ++k) {
            const uint8_t* e = &reg[at + k * 184];
            if (e[4] > 4) return void(note = "a buff type's slot is not as expected");  // food, buff, debuff, rested, terrain
            static const uint8_t kNone[16] = {};
            if (std::memcmp(e + 52, kNone, 16) != 0) buff_icon_guid[u32(e)] = std::vector<uint8_t>(e + 52, e + 68);
        }
        buff_types = static_cast<int>(n);
    }

    // The icon of buff type `id` (as EMF names it), size x size; false when it cannot be had.
    bool buff_icon(uint32_t id, int size, std::vector<uint8_t>& rgba) {
        load_buffs();
        const auto it = buff_icon_guid.find(id);
        if (it == buff_icon_guid.end() || size <= 0) return false;
        uint32_t w = 0, h = 0;
        std::vector<uint8_t> full;
        if (!texture(it->second.data(), w, h, full)) return false;
        fit(full, w, h, size, rgba);
        return true;
    }
};
