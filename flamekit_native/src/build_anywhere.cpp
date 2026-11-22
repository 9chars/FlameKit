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
#include <unordered_map>
#include <vector>

#include "emf/generated/components.hpp"
#include "emf/emf.hpp"

namespace gen = emf::gen;

namespace {
constexpr const char* kMod = "flamekit build";
// (0.15.425, owner 2026-11-22 07:41 "same error. I feel like we did not have it fully figured out the other day": far
// from every altar (here ~560 m) the hammer still says "Needs a Flame Altar nearby" with bits 1 and 3 off; bit 10
// (0x400) came on in both cursors as he tried to place (07:31:00); the 2026-11-21 success was ~90 m from an altar.
// Guess, not checked: bit 10 = too far from any altar. Switched off too, and the raw words (before any change) are
// logged when they change, so the next test shows every bit the game sets.)
constexpr uint32_t kOutsideZone = 0x8 | 0x2 | 0x400;  // bit 3 "needs a flame altar", bit 1 "needs building area", bit 10 (0.15.425)
std::atomic<int> g_raw_said{0};
void log_raw(const char* side, uint32_t id, uint32_t p, uint32_t s, uint64_t& last) {  // (0.15.425) changes only, 400 at most
    const uint64_t v = (uint64_t(p) << 32) | s;
    if (v == last) return;
    last = v;
    if (g_raw_said.fetch_add(1) < 400) EMF_LOG(kMod, "free build: %s cursor of %u before the change: primary 0x%08X, secondary 0x%08X", side, id, p, s);
}
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

void read_factor(const wchar_t* name, const char* side, float missing = 1.0f) {
    float f = missing;  // (0.15.423) no file yet: the server's default is on (kMaxFactor), a player's game waits for the server
    if (FILE* file = _wfopen(lua_file(name).c_str(), L"rb")) {
        f = 1.0f;
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
    static uint64_t last_raw = ~0ull;
    log_raw("this game's", me, c->primaryFlags, c->secondaryFlags, last_raw);
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
        static uint64_t last_raw[65];
        static bool init = false;
        if (!init) { for (auto& x : last_raw) x = ~0ull; init = true; }
        log_raw("the server's", id, c->primaryFlags, c->secondaryFlags, last_raw[id <= 64 ? id : 0]);
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

// (0.15.426, owner 2026-11-22 07:48 "if im closer to a base it works outside the base... we need to dig deeper ... we
// need to make this mode work"): far from every altar the hammer's "Needs a Flame Altar nearby" does not come from the
// cursor words (0.15.425 raw log). It is a NegativeFeedback command (type 0x3771274d) of the hammer's action sequence in
// actor_client_play, so the sequence itself tests something about altars/zones. Test: a build zone box around each
// player Free build is on for (kPlayerHalf each way), added to the game's own zone list right after the game adds the
// first altar zone of a step: then every check that asks the zone list sees "inside a build zone". The box is given no
// altar entity and an empty base id. Logged once per world.
constexpr double kPlayerHalf = 40.0;  // m each way: a box 80 m wide, high and deep around the player
std::atomic<uint64_t> g_steps{0};     // world steps (on_tick), so the player boxes go in once per step
std::atomic<int> g_box_said{0};

void add_player_boxes(void* bzs, uint8_t flag) {
    static std::mutex mx;
    static std::unordered_map<void*, uint64_t> last;
    const uint64_t now = g_steps.load();
    {
        std::lock_guard<std::mutex> lk(mx);
        auto it = last.find(bzs);
        if (it != last.end() && it->second == now) return;
        last[bzs] = now;
    }
    emf::World ws = emf::server_world(), wc = emf::client_world();
    emf::World w;
    std::vector<uint32_t> ids;
    const char* side = "";
    if (ws && ws.singleton("BuildZoneSystem") == bzs) {
        w = ws;
        side = "server";
        std::lock_guard<std::mutex> lk(g_mx);
        ids.assign(g_free_server.begin(), g_free_server.end());
    } else if (wc && wc.singleton("BuildZoneSystem") == bzs) {
        w = wc;
        side = "this game";
        const uint32_t me = emf::local_player();
        if (me && free_for(g_free_client, me)) ids.push_back(me);
    } else {
        static std::atomic<int> said{0};
        if (said.fetch_add(1) == 0)
            EMF_LOG(kMod, "free build: the zone list %p is neither world's BuildZoneSystem (server %p, this game %p): no player boxes", bzs,
                    ws ? ws.singleton("BuildZoneSystem") : nullptr, wc ? wc.singleton("BuildZoneSystem") : nullptr);
        return;
    }
    const int64_t half = int64_t(kPlayerHalf * 4294967296.0);
    for (uint32_t id : ids) {
        auto* ct = w.get<gen::ecs::CurrentTransform>(id);
        if (!ct) continue;
        const auto& p = ct->transform.position;
        int64_t b[6] = {p.x - half, p.y - half, p.z - half, p.x + half, p.y + half, p.z + half};
        uint8_t no_base[16] = {};
        g_add_zone(bzs, 0, flag, 0, b, 0, 0, no_base);
        if (g_box_said.fetch_add(1) < 4)
            EMF_LOG(kMod, "free build (%s): a build zone %.0f m wide around player %u at %.1f %.1f %.1f", side, kPlayerHalf * 2, id,
                    double(p.x) / 4294967296.0, double(p.y) / 4294967296.0, double(p.z) / 4294967296.0);
    }
}

uint64_t add_zone_detour(void* bzs, uint8_t list, uint8_t flag, uint8_t owner, int64_t* box, uint32_t entity,
                         uint8_t abandoned, void* base_id) {
    if (g_free_on.load() && box && list == 0 && owner == 0) add_player_boxes(bzs, flag);  // (0.15.426)
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
    // (0.15.423, owner 20:38 "so that option has to be on when the server comes up") the factor is read now, before
    // the world loads (the game decides what to keep then), not only at the first world step
    if (dedicated) read_factor(L"altar_size_server.txt", "server, at start", kMaxFactor);
    else read_factor(L"altar_size_client.txt", "this game, at start");
    bool c = false;
    if (!dedicated) c = a->hook_program("client_cursor", nullptr, client_post, nullptr);
    const bool s = a->hook_program("server_cursor_no_prediction", nullptr, server_post, nullptr);
    const bool al = emf::hook_pattern("flamekit: build zone (bigger altar areas)", "48 83 EC 78 8B 84 24 A8 00 00 00 4C",
                                      reinterpret_cast<void*>(&add_zone_detour), reinterpret_cast<void**>(&g_add_zone));
    EMF_LOG(kMod, "free build: hook after client_cursor %s, after server_cursor_no_prediction %s; bigger altar areas (up to x%.1f, the world's option): hook on addZone %s",
            dedicated ? "(not here)" : (c ? "installed" : "NOT installed"), s ? "installed" : "NOT installed", kMaxFactor,
            al ? "installed" : "NOT installed");
    emf::on_tick([](emf::World w) {  // the lists of players, every 60 steps of each world
        g_steps.fetch_add(1);  // (0.15.426) the player boxes: once per step
        static uint32_t steps_server = 0, steps_client = 0;
        if (w.is_server()) {
            if (steps_server++ % 60 == 0) {
                read_list(L"free_build_server.txt", g_free_server, "server");
                read_factor(L"altar_size_server.txt", "server", kMaxFactor);
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
