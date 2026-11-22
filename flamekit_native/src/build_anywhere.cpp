// build_anywhere.cpp: Free build and Bigger altar areas (both through the game's build zone list).
//
// FREE BUILD (owner 2026-11-21 18:38 "add a setting for this and call it "Free build" -- build anywhere in the world,
// but note its temporary"; per player, Experimental tab > Building). How it works (0.15.426, owner 2026-11-22 08:00
// "it works", 09:07 "its working exactly as it should"): every step, right after the game puts the first altar zone of
// the step into its build zone list (BuildZoneSystem_addZone, hooked below), a zone box around each player Free build
// is on for is added to the same list, in the server and in that player's own game. Every check that asks the list
// ("Needs a Flame Altar nearby" far from altars, "needs building area") then sees a build zone. The box sits on a
// kGridStep grid (0.15.428: a box that followed the player smoothly made the server send every player the whole zone
// list each step: 4,678 times in a minute). The game draws its border only while the building tool is selected.
// Who: features/experimental.lua writes the entity ids, one a line, into free_build_server.txt (the server) and
// free_build_client.txt (the player's own game) beside FlameKit's Lua part; read every 15 steps.
// What did not work and was taken out (0.15.438, owner 09:17 "clean up all the old free build stuff that didn't work
// ... keep all the logging"): switching off the cursor's "outside" bits after client_cursor / server_cursor_no_prediction
// (0.15.413-0.15.425: enough only near an altar, ~90 m); showing the box only while the building tool is out
// (0.15.429-0.15.435: no reliable signal; the input mask is dead, displayCursor flickers and is not seen at addZone).
// The save keeps terrain inside the list's zones at save time (0x140932a30, called by the ServerSaveGame save): what is
// built with Free build is still gone after a restart or the game's 30-minute reset (not solved).
//
// BIGGER ALTAR AREAS (owner 2026-11-21 18:05 / 18:38; the world's option, admins only, on by default 0.15.423): a base
// zone (list 0, owner kind 0: what add_buildzones_server/_client pass for each altar) gets a box g_factor times as wide,
// high and deep around the same centre. 1.5x kept every block through restarts (0.15.419/421), 2x lost outer blocks
// (0.15.418/420), 4x froze the server (0.15.417). The altars' TriggerShape (0.15.415/416) did not reach the zones.
// addZone(bzs, u8 list, u8 flag, u8 ownerKind, WorldAABB* {min xyz, max xyz int64, 2^32 per m}, u32 entity,
// u8 wasAbandoned, BaseId*) (the call in add_buildzones_server, server exe 0x1400ee750; signature in both exes).
//
// Console: fkbuild stats | free on|off | altar on|off (debug master switches; both on at start).
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
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
// (0.15.422) the altar factor comes from FlameKit's Lua part: altar_size_server.txt (the server) /
// altar_size_client.txt (a player's own game), "1" = off. Values above kMaxFactor are not used.
constexpr float kMaxFactor = 1.5f;
std::atomic<float> g_factor{1.0f};
std::atomic<bool> g_free_on{true}, g_altar_on{true};
std::atomic<uint64_t> g_altars{0}, g_boxes{0};

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

using AddZoneFn = uint64_t (*)(void* bzs, uint8_t list, uint8_t flag, uint8_t owner, int64_t* box, uint32_t entity,
                               uint8_t abandoned, void* base_id);
AddZoneFn g_add_zone = nullptr;
std::atomic<int> g_zone_said{0};

constexpr double kPlayerHalf = 40.0;  // m each way the box always covers around the player
constexpr double kGridStep = 32.0;    // m: the box moves only when the player crosses a grid line
constexpr bool kBoxUsesAltarBase = true;  // (0.15.439 TEST) the box borrows an altar's base id
std::atomic<uint64_t> g_steps{0};     // world steps (on_tick), so the player boxes go in once per step
std::atomic<int> g_box_said{0};

void add_player_boxes(void* bzs, uint8_t flag, const void* altar_base_id, uint32_t altar_entity) {
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
    const int64_t step = int64_t(kGridStep * 4294967296.0);
    const int64_t half = int64_t((kPlayerHalf + kGridStep / 2) * 4294967296.0);
    auto cell_mid = [step](int64_t v) {
        int64_t q = v / step;
        if (v % step < 0) --q;  // floor for negative values
        return q * step + step / 2;
    };
    for (uint32_t id : ids) {
        auto* ct = w.get<gen::ecs::CurrentTransform>(id);
        if (!ct) continue;
        const auto& p = ct->transform.position;
        const int64_t cx = cell_mid(p.x), cy = cell_mid(p.y), cz = cell_mid(p.z);
        int64_t b[6] = {cx - half, cy - half, cz - half, cx + half, cy + half, cz + half};
        // (0.15.439 TEST, owner 09:43 "we can try that for testing, but ideally that would not be a long term fix"):
        // the box gets the base id of the altar zone the game is adding right now (the first of the step), so the game
        // may count it as part of that altar's base: does the save then keep what is built in it? (0.15.426-0.15.438:
        // an empty base id; 09:40 A/B test: nothing kept.)
        uint8_t base[16] = {};
        if (kBoxUsesAltarBase && altar_base_id) std::memcpy(base, altar_base_id, 16);
        g_add_zone(bzs, 0, flag, 0, b, 0, 0, base);
        static std::atomic<int> base_said{0};
        if (kBoxUsesAltarBase && base_said.fetch_add(1) < 2) {
            char hex[33] = {};
            for (int i = 0; i < 16; ++i) std::snprintf(hex + i * 2, 3, "%02x", base[i]);
            EMF_LOG(kMod, "free build (%s): the box of player %u uses the base id %s (of altar %u's zone)", side, id, hex, altar_entity);
        }
        g_boxes.fetch_add(1);
        if (g_box_said.fetch_add(1) < 4)
            EMF_LOG(kMod, "free build (%s): a build zone %.0f m wide around player %u at %.1f %.1f %.1f (grid cell centre %.0f %.0f %.0f)", side,
                    (kPlayerHalf + kGridStep / 2) * 2, id, double(p.x) / 4294967296.0, double(p.y) / 4294967296.0, double(p.z) / 4294967296.0,
                    double(cx) / 4294967296.0, double(cy) / 4294967296.0, double(cz) / 4294967296.0);
    }
}

uint64_t add_zone_detour(void* bzs, uint8_t list, uint8_t flag, uint8_t owner, int64_t* box, uint32_t entity,
                         uint8_t abandoned, void* base_id) {
    if (g_free_on.load() && box && list == 0 && owner == 0) add_player_boxes(bzs, flag, base_id, entity);
    const float factor = g_factor.load();
    if (g_altar_on.load() && factor > 1.001f && box && list == 0 && owner == 0) {
        int64_t big[6];
        for (int i = 0; i < 3; ++i) {
            const int64_t lo = box[i], hi = box[3 + i];
            const int64_t mid = lo / 2 + hi / 2;
            const int64_t half = hi / 2 - lo / 2;
            big[i] = mid - int64_t(double(half) * factor);
            big[3 + i] = mid + int64_t(double(half) * factor);
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
    // (0.15.423) the factor is read now, before the world loads (the game decides what to keep then)
    if (dedicated) read_factor(L"altar_size_server.txt", "server, at start", kMaxFactor);
    else read_factor(L"altar_size_client.txt", "this game, at start");
    const bool al = emf::hook_pattern("flamekit: build zone (bigger altar areas)", "48 83 EC 78 8B 84 24 A8 00 00 00 4C",
                                      reinterpret_cast<void*>(&add_zone_detour), reinterpret_cast<void**>(&g_add_zone));
    EMF_LOG(kMod, "free build and bigger altar areas (up to x%.1f, the world's option): hook on addZone %s", kMaxFactor,
            al ? "installed" : "NOT installed");
    emf::on_tick([](emf::World w) {  // the lists of players and the factor, every 15 steps of each world
        g_steps.fetch_add(1);  // the player boxes: once per step
        static uint32_t steps_server = 0, steps_client = 0;
        if (w.is_server()) {
            if (steps_server++ % 15 == 0) {
                read_list(L"free_build_server.txt", g_free_server, "server");
                read_factor(L"altar_size_server.txt", "server", kMaxFactor);
            }
        } else if (w.is_client()) {
            if (steps_client++ % 15 == 0) {
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
        EMF_REPLY("free build %s (server list %zu, this game %zu; %llu player box(es) added); bigger altar areas %s (%llu zone(s) made bigger)",
                  g_free_on.load() ? "on" : "off", ns, nc, (unsigned long long)g_boxes.load(), g_altar_on.load() ? "on" : "off",
                  (unsigned long long)g_altars.load());
    });
    return al;
}
