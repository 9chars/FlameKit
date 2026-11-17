// fk_server_probe (2026-11-17, owner: find what makes a body a player): a READ-ONLY server-side test mod. Never
// published; installed on the local dedicated server only, removed afterwards.
//
// Console (or emf\commands.txt on the server):
//   fkprobe.players [entries 1-16]   hex dump of the "BasicPlayerInfos" world singleton: its first 0x40 bytes and one
//                                    0xA0-byte entry per player slot (entry = player entity - 1), with the connection
//                                    handle (+0x04) and the account (+0x08) read out
//   fkprobe.dump <singleton> [bytes] [offset]   hex dump of any world singleton by name (bytes up to 4096)
// Every read goes through ReadProcessMemory: a wrong guess fails, it never crashes the server.
#include <windows.h>

#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <vector>

#include "emf/emf.hpp"
#include "emf/query.hpp"

namespace {
constexpr const char* kMod = "fk_server_probe";

bool peek(uint64_t at, void* into, size_t bytes) {
    SIZE_T got = 0;
    return at > 0x10000 && ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<LPCVOID>(at), into, bytes, &got) && got == bytes;
}

void hexdump(const char* title, uint64_t base, size_t bytes) {
    std::vector<uint8_t> buf(bytes);
    if (!peek(base, buf.data(), bytes)) {
        EMF_LOG(kMod, "%s: %zu bytes at %llx cannot be read", title, bytes, (unsigned long long)base);
        return;
    }
    EMF_LOG(kMod, "%s at %llx (%zu bytes):", title, (unsigned long long)base, bytes);
    for (size_t off = 0; off < bytes; off += 16) {
        char line[160];
        int n = std::snprintf(line, sizeof line, "  +%04zx:", off);
        for (size_t i = 0; i < 16 && off + i < bytes; ++i) n += std::snprintf(line + n, sizeof line - n, " %02x", buf[off + i]);
        EMF_LOG(kMod, "%s", line);
    }
}

// A template GUID as the game stores it (Windows layout: the first three groups little-endian).
bool parse_guid(const std::string& t, uint8_t out[16]) {
    std::string hex;
    for (char c : t) if (c != '-') hex += c;
    if (hex.size() != 32) return false;
    uint8_t b[16];
    for (int i = 0; i < 16; ++i) b[i] = (uint8_t)std::strtoul(hex.substr(i * 2, 2).c_str(), nullptr, 16);
    const int order[16] = {3, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15};
    for (int i = 0; i < 16; ++i) out[i] = b[order[i]];
    return true;
}

#pragma pack(push, 1)
struct WorldTransform {  // CurrentTransform (56 bytes): position in fixed point (1 m = 2^32), orientation, scale
    int64_t px, py, pz;
    float qx, qy, qz, qw;
    float sx, sy, sz;
    uint32_t pad;
};
#pragma pack(pop)
static_assert(sizeof(WorldTransform) == 56, "CurrentTransform is 56 bytes");
struct SpawnComponent { uint32_t hash; uint32_t pad; const void* data; uint64_t size; };
struct SpawnSlice { const SpawnComponent* items; uint64_t count; };
// the server's "spawn a player's body" (EMF ENGINE_MAP 1.4 "spawn player-owned"; found in enshrouded_server.exe at
// exe+0x628e20 on 2026-11-17): createEntity(world+0xE179C0, id = slot + 1, {parent 0, guid, comps, mask 1 << slot,
// kind 2}, 0); returns the new entity id (0 = refused)
using SpawnPlayerFn = uint32_t (*)(void* world, uint32_t slot, const uint8_t* guid, const SpawnSlice* comps);
constexpr const char* kSpawnPlayer = "48 83 EC 58 41 0F 10 00 4C 8B D1 8B CA 41 0F 10 09 B8 01 00 00 00 C7 44";

uint64_t find_singleton(emf::World w, const std::string& name) {
    const char* tries[] = {"", "ecs::", "keen::", "keen::ecs::"};
    for (const char* pre : tries) {
        const std::string full = std::string(pre) + name;
        const void* p = w.singleton(full.c_str());
        if (p) {
            EMF_LOG(kMod, "singleton %s found as %s", name.c_str(), full.c_str());
            return reinterpret_cast<uint64_t>(p);
        }
    }
    EMF_LOG(kMod, "singleton %s not found (tried with and without ecs::, keen::)", name.c_str());
    return 0;
}
}  // namespace

extern "C" __declspec(dllexport) bool emf_mod_load(const EmfApi* api) {
    if (!emf::init(api)) return false;

    emf::add_command("fkprobe.players", "[entries 1-16]: hex dump of BasicPlayerInfos (read only)",
                     [](emf::World w, const std::vector<std::string>& args) {
                         if (!w.is_server()) { EMF_REPLY("server world only"); return; }
                         int count = args.size() > 1 ? std::atoi(args[1].c_str()) : 4;
                         if (count < 1) count = 1;
                         if (count > 16) count = 16;
                         const uint64_t base = find_singleton(w, "BasicPlayerInfos");
                         if (!base) { EMF_REPLY("not found (see the log)"); return; }
                         hexdump("BasicPlayerInfos head", base, 0x40);
                         for (int i = 0; i < count; ++i) {
                             char title[96];
                             const uint64_t e = base + uint64_t(i) * 0xA0;
                             uint32_t handle = 0;
                             uint64_t account = 0;
                             peek(e + 0x04, &handle, 4);
                             peek(e + 0x08, &account, 8);
                             std::snprintf(title, sizeof title, "entry %d (player entity %d): handle %x, account %016llx", i,
                                           i + 1, handle, (unsigned long long)account);
                             hexdump(title, e, 0xA0);
                         }
                         EMF_REPLY("dumped %d entries (see the log)", count);
                     });

    emf::add_command("fkprobe.dump", "<singleton> [bytes] [offset]: hex dump of a world singleton (read only)",
                     [](emf::World w, const std::vector<std::string>& args) {
                         if (args.size() < 2) { EMF_REPLY("usage: fkprobe.dump <singleton> [bytes] [offset]"); return; }
                         size_t bytes = args.size() > 2 ? std::strtoul(args[2].c_str(), nullptr, 0) : 0x100;
                         if (bytes < 16) bytes = 16;
                         if (bytes > 4096) bytes = 4096;
                         const uint64_t off = args.size() > 3 ? std::strtoull(args[3].c_str(), nullptr, 0) : 0;
                         const uint64_t base = find_singleton(w, args[1]);
                         if (!base) { EMF_REPLY("not found (see the log)"); return; }
                         hexdump(args[1].c_str(), base + off, bytes);
                         EMF_REPLY("dumped (see the log)");
                     });

    // (2026-11-17, owner: "let us methodically work through it one byte at a time") a WRITE test: a player's body
    // made the way the server makes one, for player slot <slot> (entity slot + 1), next to the given player
    emf::add_command("fkprobe.spawnplayer", "<slot 1-15> [template guid] [near player entity] [metres]: a player body as the server makes one (test)",
                     [](emf::World w, const std::vector<std::string>& args) {
                         if (!w.is_server()) { EMF_REPLY("server world only"); return; }
                         const int slot = args.size() > 1 ? std::atoi(args[1].c_str()) : 0;
                         if (slot < 1 || slot > 15) { EMF_REPLY("usage: fkprobe.spawnplayer <slot 1-15> [guid] [player] [metres]"); return; }
                         const std::string guid_text = args.size() > 2 ? args[2] : "c3db66d6-89a5-4a6c-a8e3-d9a1f6009812";  // 1_Player
                         const uint32_t near_id = args.size() > 3 ? (uint32_t)std::strtoul(args[3].c_str(), nullptr, 10) : 1;
                         const double metres = args.size() > 4 ? std::atof(args[4].c_str()) : 2.0;
                         uint8_t guid[16];
                         if (!parse_guid(guid_text, guid)) { EMF_REPLY("bad template guid"); return; }
                         const auto pos = emf::position(w, near_id);
                         if (!pos) { EMF_REPLY("no position for entity %u", near_id); return; }
                         const uintptr_t fn = emf::find_pattern(kSpawnPlayer);
                         if (!fn) { EMF_REPLY("the server's spawn-player function was not found (see the log)"); return; }
                         WorldTransform t{};
                         t.px = (int64_t)((pos->x + metres) * 4294967296.0);
                         t.py = (int64_t)((pos->y + 0.5) * 4294967296.0);
                         t.pz = (int64_t)(pos->z * 4294967296.0);
                         t.qw = 1.0f;
                         t.sx = t.sy = t.sz = 1.0f;
                         SpawnComponent comp{0x027ac564u, 0, &t, sizeof t};  // CurrentTransform
                         SpawnSlice slice{&comp, 1};
                         EMF_LOG(kMod, "spawnplayer: slot %d (entity %d), template %s, near %u (%.1f %.1f %.1f) + %.1f m, function at %llx",
                                 slot, slot + 1, guid_text.c_str(), near_id, pos->x, pos->y, pos->z, metres, (unsigned long long)fn);
                         const uint32_t id = reinterpret_cast<SpawnPlayerFn>(fn)(w.raw(), (uint32_t)slot, guid, &slice);
                         EMF_LOG(kMod, "spawnplayer: the server returned entity %u", id);
                         EMF_REPLY("spawnplayer: entity %u", id);
                     });

    // (2026-11-17) a WRITE test: one value into a player-list slot (BasicPlayerInfos + slot * 0xA0 + offset), the old
    // and the new value logged
    emf::add_command("fkprobe.slotset", "<slot> <offset> <u8|u16|u32|u64> <value>: write one value into a player-list slot (test)",
                     [](emf::World w, const std::vector<std::string>& args) {
                         if (!w.is_server()) { EMF_REPLY("server world only"); return; }
                         if (args.size() < 5) { EMF_REPLY("usage: fkprobe.slotset <slot> <offset> <u8|u16|u32|u64> <value>"); return; }
                         const int slot = std::atoi(args[1].c_str());
                         const uint64_t off = std::strtoull(args[2].c_str(), nullptr, 0);
                         const std::string type = args[3];
                         const uint64_t value = std::strtoull(args[4].c_str(), nullptr, 0);
                         const size_t n = type == "u8" ? 1 : type == "u16" ? 2 : type == "u32" ? 4 : type == "u64" ? 8 : 0;
                         if (slot < 0 || slot > 15 || off + n > 0xA0 || !n) { EMF_REPLY("bad slot, offset or type"); return; }
                         const uint64_t base = find_singleton(w, "BasicPlayerInfos");
                         if (!base) { EMF_REPLY("player list not found"); return; }
                         const uint64_t at = base + uint64_t(slot) * 0xA0 + off;
                         uint64_t before = 0, after = 0;
                         peek(at, &before, n);
                         const bool ok = emf::api()->write_memory && emf::api()->write_memory(reinterpret_cast<void*>(at), &value, n);
                         peek(at, &after, n);
                         EMF_LOG(kMod, "slotset: slot %d +0x%llx (%s): %llx -> %llx (%s)", slot, (unsigned long long)off, type.c_str(),
                                 (unsigned long long)before, (unsigned long long)after, ok ? "written" : "NOT written");
                         EMF_REPLY("slot %d +0x%llx: %llx -> %llx", slot, (unsigned long long)off, (unsigned long long)before, (unsigned long long)after);
                     });

    EMF_LOG(kMod, "loaded (test commands: fkprobe.players, fkprobe.dump, fkprobe.spawnplayer, fkprobe.slotset)");
    return true;
}
