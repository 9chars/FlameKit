// build_anywhere.cpp: Free build (0.15.415) and the bigger altar areas test (0.15.415).
//
// FREE BUILD (owner 2026-11-21 18:12 "lets try to change the may I build here check"; 18:38 "add a setting for this
// and call it "Free build" -- build anywhere in the world, but note its temporary", "make it player specific and put
// these settings under the "Experimental" tab under a new section called "Building"").
// Learned (0.15.412-0.15.414 on the local server): the cursor's flag words say why the hammer refuses. Bit 3 (0x8) =
// "Needs a Flame Altar nearby", bit 1 (0x2) = "needs building area": ClientCursor.primaryFlags / .secondaryFlags in
// the player's own game, ServerCursor.primaryFlags on the server (the server's secondaryFlags have bits 1, 2, 3 on
// INSIDE an altar's area: a different meaning, left alone). The game's cursor programs work them out each step:
// client_cursor (the player's game) and server_cursor_no_prediction (the server). A hook after each (EMF hook_program,
// post) switches both bits off for the players Free build is on for, and placing works (18:31 "that worked", with the
// materials in the bag: outside an altar's area the hammer uses only the bag). What is built outside an altar's area
// is gone after a restart (18:36: the game's own rule).
// Who: features/experimental.lua writes the entity ids, one a line, into free_build_server.txt (the server) and
// free_build_client.txt (the player's own game) beside FlameKit's Lua part; read again every 60 steps.
//
// BIGGER ALTAR AREAS (test, owner 18:05 "adjust the build area of the flames alters", 18:38 "instead of doubling it,
// lets quadruple it"). 0.15.415/416 changed the altars' TriggerShape (after upgrade_building_range, before
// add_buildzones_*): the log showed the writes, but 18:46 / 18:53 owner: "the boundry area looks the same" (the game's
// programs evidently read another copy). 0.15.417 instead: the game's BuildZoneSystem_addZone (the one function that
// puts every build zone box into the list, server and player's game; EMF's engine notes 3.5, signature found in both
// exes) is hooked; a base zone (list 0, owner kind 0: what add_buildzones_server/_client pass for each altar) gets a
// box kAltarFactor times as wide, tall and deep around the same centre. (0.15.422) the world's option (below).
// addZone(bzs, u8 list, u8 flag, u8 ownerKind, WorldAABB* {min xyz, max xyz int64, 2^32 per m}, u32 entity,
// u8 wasAbandoned, BaseId*) (the call in add_buildzones_server, server exe 0x1400ee750).
//
// Console: fkbuild stats | free on|off | altar on|off (debug master switches; both on at start).
// (0.15.417) the first 20 bigger zones are logged (the game rebuilds the zones every step).
// (0.15.418) 2x: 4x froze the server's world step right after the zones (18:55:25; cause not known).
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <mutex>
#include <set>
#include <string>
#include <vector>

#include "emf/generated/components.hpp"
#include "emf/emf.hpp"

namespace gen = emf::gen;

namespace {
constexpr const char* kMod = "flamekit build";
constexpr uint32_t kOutsideZone = 0x8 | 0x2;  // bit 3 "needs a flame altar", bit 1 "needs building area"
// (0.15.422, owner 20:20 "1.5 seems safe so lets add an option for that", 20:21 admins only) the factor comes from
// FlameKit's Lua part: altar_size_server.txt (the server) / altar_size_client.txt (a player's own game), "1" = off.
// Tested: 1.5x kept every block through restarts (0.15.419/421); 2x lost outer blocks at restarts (0.15.418/420); 4x
// froze the server (0.15.417). Values above kMaxFactor are not used.
constexpr float kMaxFactor = 1.5f;
std::atomic<float> g_factor{1.0f};


std::atomic<bool> g_free_on{true}, g_altar_on{true};
std::atomic<uint64_t> g_client_cleared{0}, g_server_cleared{0}, g_altars{0};
std::atomic<int> g_said{0};

// the players Free build is on for, per side (read from the files on the world's own tick thread)
std::mutex g_mx;
std::set<uint32_t> g_free_server, g_free_client;

std::wstring lua_file(const wchar_t* name) {  // <this DLL's folder>\..\flamekit\<name>
    HMODULE me = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&lua_file), &me);
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(me, path, MAX_PATH);
    std::wstring s(path);
    s = s.substr(0, s.find_last_of(L"\\/"));
    s = s.substr(0, s.find_last_of(L"\\/"));
    return s + L"\\flamekit\\" + name;
}

void read_list(const wchar_t* name, std::set<uint32_t>& out, const char* side) {
    std::set<uint32_t> ids;
    if (FILE* f = _wfopen(lua_file(name).c_str(), L"rb")) {
        unsigned v = 0;
        while (std::fscanf(f, "%u", &v) == 1) if (v) ids.insert(v);
        std::fclose(f);
    }
    std::lock_guard<std::mutex> lk(g_mx);
    if (ids != out) {
        std::string list;
        for (uint32_t id : ids) list += " " + std::to_string(id);
        EMF_LOG(kMod, "free build (%s): on for%s", side, list.empty() ? " nobody" : list.c_str());
        out.swap(ids);
    }
}

bool free_for(std::set<uint32_t>& list, uint32_t id) {
    std::lock_guard<std::mutex> lk(g_mx);
    return list.count(id) != 0;
}

void read_factor(const wchar_t* name, const char* side) {
    float f = 1.0f;
    if (FILE* file = _wfopen(lua_file(name).c_str(), L"rb")) {
        float v = 1.0f;
        if (std::fscanf(file, "%f", &v) == 1 && v >= 1.0f && v <= kMaxFactor) f = v;
        std::fclose(file);
    }
    const float old = g_factor.exchange(f);
    if (old != f) EMF_LOG(kMod, "bigger altar areas (%s): %s", side, f > 1.001f ? (f > 1.49f ? "on, 1.5x" : "on") : "off");
}

void client_post(void*, void*) {
    if (!g_free_on.load()) return;
    const uint32_t me = emf::local_player();
    if (!me || !free_for(g_free_client, me)) return;
    emf::World w = emf::client_world();
    if (!w) return;
    auto* c = w.get<gen::ecs::ClientCursor>(me);
    if (!c) return;
    if ((c->primaryFlags | c->secondaryFlags) & kOutsideZone) {
        c->primaryFlags &= ~kOutsideZone;
        c->secondaryFlags &= ~kOutsideZone;
        if (g_client_cleared.fetch_add(1) == 0) EMF_LOG(kMod, "free build: the hammer's altar check is off in this game for %u", me);
    }
}

void server_post(void*, void*) {
    if (!g_free_on.load()) return;
    std::vector<uint32_t> ids;
    {
        std::lock_guard<std::mutex> lk(g_mx);
        ids.assign(g_free_server.begin(), g_free_server.end());
    }
    if (ids.empty()) return;
    emf::World w = emf::server_world();
    if (!w) return;
    for (uint32_t id : ids) {
        auto* c = w.get<gen::ecs::ServerCursor>(id);
        if (!c) continue;
        if (c->primaryFlags & kOutsideZone) {
            c->primaryFlags &= ~kOutsideZone;
            if (g_server_cleared.fetch_add(1) == 0 || g_said.fetch_add(1) < 3)
                EMF_LOG(kMod, "free build: the server's altar check is off for %u", id);
        }
    }
}

using AddZoneFn = uint64_t (*)(void* bzs, uint8_t list, uint8_t flag, uint8_t owner, int64_t* box, uint32_t entity,
                               uint8_t abandoned, void* base_id);
AddZoneFn g_add_zone = nullptr;
std::atomic<int> g_zone_said{0};

uint64_t add_zone_detour(void* bzs, uint8_t list, uint8_t flag, uint8_t owner, int64_t* box, uint32_t entity,
                         uint8_t abandoned, void* base_id) {
    const float kAltarFactor = g_factor.load();
    if (g_altar_on.load() && kAltarFactor > 1.001f && box && list == 0 && owner == 0) {
        int64_t big[6];
        for (int i = 0; i < 3; ++i) {
            const int64_t lo = box[i], hi = box[3 + i];
            const int64_t mid = lo / 2 + hi / 2;
            const int64_t half = hi / 2 - lo / 2;
            big[i] = mid - int64_t(double(half) * kAltarFactor);
            big[3 + i] = mid + int64_t(double(half) * kAltarFactor);
        }
        g_altars.fetch_add(1);
        if (g_zone_said.fetch_add(1) < 20)
            EMF_LOG(kMod, "bigger altar areas: zone of %u: %.0f x %.0f x %.0f m -> %.0f x %.0f x %.0f m", entity,
                    double(box[3] - box[0]) / 4294967296.0, double(box[4] - box[1]) / 4294967296.0, double(box[5] - box[2]) / 4294967296.0,
                    double(big[3] - big[0]) / 4294967296.0, double(big[4] - big[1]) / 4294967296.0, double(big[5] - big[2]) / 4294967296.0);
        const uint64_t r = g_add_zone(bzs, list, flag, owner, big, entity, abandoned, base_id);
        static std::atomic<int> back{0};
        if (back.fetch_add(1) < 3) EMF_LOG(kMod, "bigger altar areas: addZone returned for %u", entity);  // (0.15.418) where a freeze is
        return r;
    }
    return g_add_zone(bzs, list, flag, owner, box, entity, abandoned, base_id);
}
}  // namespace

// called by flamekit_native's emf_mod_load in every process (a dedicated server, a player's game)
bool fk_build_anywhere_load(bool dedicated) {
    auto* a = emf::api();
    if (!a || !a->hook_program) {
        EMF_LOG(kMod, "free build: EMF has no hook_program: off");
        return false;
    }
    bool c = false;
    if (!dedicated) c = a->hook_program("client_cursor", nullptr, client_post, nullptr);
    const bool s = a->hook_program("server_cursor_no_prediction", nullptr, server_post, nullptr);
    const bool al = emf::hook_pattern("flamekit: build zone (bigger altar areas)", "48 83 EC 78 8B 84 24 A8 00 00 00 4C",
                                      reinterpret_cast<void*>(&add_zone_detour), reinterpret_cast<void**>(&g_add_zone));
    EMF_LOG(kMod, "free build: hook after client_cursor %s, after server_cursor_no_prediction %s; bigger altar areas (up to x%.1f, the world's option): hook on addZone %s",
            dedicated ? "(not here)" : (c ? "installed" : "NOT installed"), s ? "installed" : "NOT installed", kMaxFactor,
            al ? "installed" : "NOT installed");
    emf::on_tick([](emf::World w) {  // the lists of players, every 60 steps of each world
        static uint32_t steps_server = 0, steps_client = 0;
        if (w.is_server()) {
            if (steps_server++ % 60 == 0) {
                read_list(L"free_build_server.txt", g_free_server, "server");
                read_factor(L"altar_size_server.txt", "server");
            }
        } else if (w.is_client()) {
            if (steps_client++ % 60 == 0) {
                read_list(L"free_build_client.txt", g_free_client, "this game");
                if (!emf::server_world()) read_factor(L"altar_size_client.txt", "this game");  // a hosting game: the server's file counts
            }
        }
    });
    emf::add_command("fkbuild", " stats | free on|off | altar on|off: Free build and the bigger altar areas (debug)",
                     [](emf::World, const std::vector<std::string>& args) {
        std::string all;  // (0.15.416) the words however EMF splits them
        for (const auto& x : args) all += " " + x;
        all += " ";
        if (all.find(" free on ") != std::string::npos) g_free_on = true;
        if (all.find(" free off ") != std::string::npos) g_free_on = false;
        if (all.find(" altar on ") != std::string::npos) g_altar_on = true;
        if (all.find(" altar off ") != std::string::npos) g_altar_on = false;
        EMF_LOG(kMod, "fkbuild:%s", all.c_str());
        size_t ns = 0, nc = 0;
        {
            std::lock_guard<std::mutex> lk(g_mx);
            ns = g_free_server.size();
            nc = g_free_client.size();
        }
        EMF_REPLY("free build %s (server list %zu, this game %zu; cleared: server %llu, this game %llu); bigger altar areas %s (%llu zone(s) made bigger)",
                  g_free_on.load() ? "on" : "off", ns, nc, (unsigned long long)g_server_cleared.load(),
                  (unsigned long long)g_client_cleared.load(), g_altar_on.load() ? "on" : "off", (unsigned long long)g_altars.load());
    });
    return c || s;
}
