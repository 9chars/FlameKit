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

    EMF_LOG(kMod, "loaded (read-only test commands: fkprobe.players, fkprobe.dump)");
    return true;
}
