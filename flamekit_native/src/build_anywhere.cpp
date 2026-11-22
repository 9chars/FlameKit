// build_anywhere.cpp: Free build and Bigger altar areas, both through the game's build zone list.
//
// FREE BUILD (per player, Experimental tab > Building). Hooked: BuildZoneSystem_addZone. On each rebuild of the build
// zone list, when the game adds its first altar zone, this adds to the same list:
//  - the server only: a zone over each remembered spot (free_build_spots.txt, "x y z" in m per line, written by
//    features/experimental.lua): a 48 m box, from the server's start, so what was built there is saved and kept like
//    inside an altar's area;
//  - a box around each player Free build is on for (free_build_server.txt / free_build_client.txt, entity ids, read
//    every 15 steps), in the server and in that player's own game. The box sits on a kGridStep grid (a box that moved
//    smoothly made the server resend the whole zone list every step). The game draws its border only while the
//    building tool is selected.
// Free build works only outside flame altar areas (owner 2026-11-22 11:06): no player box while the player stands in
// an altar's area (as added, after the bigger size). The server writes its altar areas to altar_areas_server.txt
// (min xyz, max xyz in m per line) for the Lua, which then makes no remembered spot for a piece placed in one.
//
// BIGGER ALTAR AREAS (the world's option, admins only, on by default): an altar zone (list 0, owner kind 0: what
// add_buildzones_server/_client pass for each altar) gets a box g_factor times as wide, high and deep around the same
// centre (altar_size_server.txt / altar_size_client.txt; at most kMaxFactor 1.5: 2x lost outer blocks, 4x froze the
// server). addZone(bzs, u8 list, u8 flag, u8 ownerKind, WorldAABB* {min xyz, max xyz int64, 2^32 per m}, u32 entity,
// u8 wasAbandoned, BaseId*) (called in add_buildzones_server, server exe 0x1400ee750; signature in both exes).
//
// WHAT WE FOUND ABOUT THE GAME (build 1287369; addresses are the exes' own, image base 0x140000000; for anyone who
// wants to reuse this, e.g. in EMF):
//  - The build zone list (BuildZoneSystem, an ECS singleton) decides where building is allowed. Its entries come from
//    BuildZoneSystem_addZone (signature "48 83 EC 78 8B 84 24 A8 00 00 00 4C"; client 0x140e6f2e0, server
//    0x140916310), called by add_buildzones_server/_client with list 0, owner kind 0 for every flame altar. The list
//    is rebuilt over and over (once per world step while we watched), so a zone added from this hook stays only as
//    long as it is added again on every rebuild.
//  - Every change of the list is logged by the server ("[ecs] Build zones changed") and sends every player a
//    BuildingZones message (about 1.1 KB). A zone that moves a little every step floods the network: keep added zones
//    still (here: a 32 m grid).
//  - The hammer's "Needs a Flame Altar nearby" is a NegativeFeedback sequence command (type 0x3771274d, in
//    actor_client_play 0x1402653b0). The cursor's flag words (ClientCursor / ServerCursor primaryFlags,
//    secondaryFlags) carry "outside a building area" bits (1 and 3), but clearing them is not enough: away from an
//    altar the placement is still refused. Only a zone in the list makes building work there.
//  - Saving: the save's base zones are the list-0 zones at save time (server fn 0x140932a30, 0x48-byte entries);
//    terraforming is saved per chunk. Outside those zones the game resets terrain and buildings after about 30 minutes
//    or at a restart. A zone that is in the list from the server's start (before the world loads) keeps what is built
//    in it through restarts; a zone only added later (here: the moving player box) does not. Villagers stay anyway.
//  - The game draws a building area's border only while the building tool (or the pickaxe; not the axe) is selected.
//  - BuildingPlaceEvent (server, 72 bytes): the placed piece's position (float3) and ownerId (the player's entity).
//  - Writing an altar's TriggerShape does not change its build zone. Bigger altar zones: 1.5x kept everything, 2x lost
//    the outer blocks after a restart, 4x froze the server's world step.
//
// Console: fkbuild stats | free on|off | altar on|off (debug master switches; both on at start).
#include <windows.h>

#include <array>
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

// (0.15.440) Free build's remembered spots: the centres (m) of the 32 m grid cells where pieces were placed with Free
// build (features/experimental.lua writes free_build_spots.txt). The server adds a build zone over each, every step,
// from its start: what was built there should be kept like inside an altar's area.
constexpr double kSpotHalf = 16.0 + 8.0;  // m each way: the 32 m cell and 8 m more (pieces can stick out of their cell)
std::vector<std::array<int64_t, 3>> g_spots;  // under g_mx
std::string g_spots_text;

void read_spots(const char* side) {
    std::string text;
    if (FILE* f = _wfopen(lua_file(L"free_build_spots.txt").c_str(), L"rb")) {
        char buf[4096];
        size_t n;
        while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) text.append(buf, n);
        std::fclose(f);
    }
    std::lock_guard<std::mutex> lk(g_mx);
    if (text == g_spots_text) return;
    g_spots_text = text;
    g_spots.clear();
    const char* p = text.c_str();
    double x, y, z;
    int used = 0;
    while (std::sscanf(p, "%lf %lf %lf%n", &x, &y, &z, &used) == 3) {
        g_spots.push_back({int64_t(x * 4294967296.0), int64_t(y * 4294967296.0), int64_t(z * 4294967296.0)});
        p += used;
    }
    EMF_LOG(kMod, "free build (%s): %zu remembered spot(s)", side, g_spots.size());
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
std::atomic<uint64_t> g_steps{0};     // world steps (on_tick), so the player boxes go in once per step
std::atomic<int> g_box_said{0};

// (0.15.443, owner 11:04 "the free build mode should not work while inside a flame alter base", 11:06 "if you're
// inside a flame alter area from the game I want the games default behaviors to work. free build mode should only
// happen and work when you're outside of the flame alters boundries") the altar areas of each zone list as the game
// adds them (after the bigger altar areas), kept from the last full rebuild: no player box while the player stands in
// one, and the server's are written to altar_areas_server.txt for the Lua (no remembered spot for a piece in one).
using Box = std::array<int64_t, 6>;
struct Altars { std::vector<Box> cur, last; };
std::mutex g_altar_mx;
std::unordered_map<void*, Altars> g_altar_boxes;  // under g_altar_mx
void altar_add(void* bzs, const int64_t* b) {
    std::lock_guard<std::mutex> lk(g_altar_mx);
    g_altar_boxes[bzs].cur.push_back({b[0], b[1], b[2], b[3], b[4], b[5]});
}
void altar_new_pass(void* bzs) {  // a new rebuild: what was gathered is the list now
    std::lock_guard<std::mutex> lk(g_altar_mx);
    Altars& a = g_altar_boxes[bzs];
    a.last.swap(a.cur);
    a.cur.clear();
}
std::vector<Box> altar_last(void* bzs) {
    std::lock_guard<std::mutex> lk(g_altar_mx);
    auto it = g_altar_boxes.find(bzs);
    return it == g_altar_boxes.end() ? std::vector<Box>{} : it->second.last;
}
bool in_box(const Box& b, int64_t x, int64_t y, int64_t z) {
    return x >= b[0] && x <= b[3] && y >= b[1] && y <= b[4] && z >= b[2] && z <= b[5];
}
std::string g_altars_text;  // what altar_areas_server.txt holds (the tick thread only)
void write_altar_areas(void* bzs) {
    std::string text;
    char line[160];
    for (const Box& b : altar_last(bzs)) {
        std::snprintf(line, sizeof line, "%.1f %.1f %.1f %.1f %.1f %.1f\n", double(b[0]) / 4294967296.0, double(b[1]) / 4294967296.0,
                      double(b[2]) / 4294967296.0, double(b[3]) / 4294967296.0, double(b[4]) / 4294967296.0, double(b[5]) / 4294967296.0);
        text += line;
    }
    if (text == g_altars_text) return;
    if (FILE* f = _wfopen(lua_file(L"altar_areas_server.txt").c_str(), L"wb")) {
        std::fwrite(text.data(), 1, text.size(), f);
        std::fclose(f);
        const bool first = g_altars_text.empty();
        g_altars_text = text;
        size_t n = 0;
        for (char c : text) n += c == '\n';
        EMF_LOG(kMod, "free build (server): %zu altar area(s) written for the Lua%s", n, first ? " (first time)" : "");
    }
}

void add_player_boxes(void* bzs, uint8_t flag, uint32_t altar_entity) {
    // once per rebuild of the zone list: a new world step (on_tick) or (0.15.440) the altar that came first in the
    // last rebuild coming again (while the world loads, before any on_tick, the list is rebuilt too: the remembered
    // spots must be in it then)
    struct Pass { uint64_t step = ~0ull; uint32_t first = 0; };
    static std::mutex mx;
    static std::unordered_map<void*, Pass> last;
    const uint64_t now = g_steps.load();
    {
        std::lock_guard<std::mutex> lk(mx);
        Pass& p = last[bzs];
        const bool fresh = p.step != now || (p.first != 0 && p.first == altar_entity);
        if (!fresh) return;
        p.step = now;
        p.first = altar_entity;
    }
    altar_new_pass(bzs);  // (0.15.443)
    if (!g_free_on.load()) return;  // fkbuild free off: the altar list only
    const std::vector<Box> altars = altar_last(bzs);
    emf::World ws = emf::server_world(), wc = emf::client_world();
    emf::World w;
    std::vector<uint32_t> ids;
    const char* side = "";
    if (ws && ws.singleton("BuildZoneSystem") == bzs) {
        w = ws;
        side = "server";
        std::vector<std::array<int64_t, 3>> spots;
        {
            std::lock_guard<std::mutex> lk(g_mx);
            ids.assign(g_free_server.begin(), g_free_server.end());
            spots = g_spots;
        }
        const int64_t sh = int64_t(kSpotHalf * 4294967296.0);
        for (const auto& c : spots) {  // (0.15.440) the remembered spots
            int64_t b[6] = {c[0] - sh, c[1] - sh, c[2] - sh, c[0] + sh, c[1] + sh, c[2] + sh};
            uint8_t no_base[16] = {};
            g_add_zone(bzs, 0, flag, 0, b, 0, 0, no_base);
        }
        static std::atomic<int> spots_said{0};
        if (!spots.empty() && spots_said.fetch_add(1) == 0)
            EMF_LOG(kMod, "free build (server): %zu remembered spot zone(s) %.0f m wide in the zone list", spots.size(), kSpotHalf * 2);
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
        bool inside = false;  // (0.15.443) in an altar's area: the game's own rules, no Free build box
        for (const Box& a : altars) if (in_box(a, p.x, p.y, p.z)) { inside = true; break; }
        {
            static std::mutex said_mx;
            static std::unordered_map<uint64_t, bool> said;  // (world side, player) -> inside, logged on change
            std::lock_guard<std::mutex> lk(said_mx);
            const uint64_t k = (uint64_t(w.is_server() ? 1 : 0) << 32) | id;
            auto it = said.find(k);
            if (it == said.end() || it->second != inside) {
                said[k] = inside;
                EMF_LOG(kMod, "free build (%s): player %u at %.1f %.1f %.1f is %s an altar area (%zu known)%s", side, id,
                        double(p.x) / 4294967296.0, double(p.y) / 4294967296.0, double(p.z) / 4294967296.0, inside ? "inside" : "outside",
                        altars.size(), inside ? ": no Free build box" : "");
            }
        }
        if (inside) continue;
        const int64_t cx = cell_mid(p.x), cy = cell_mid(p.y), cz = cell_mid(p.z);
        int64_t b[6] = {cx - half, cy - half, cz - half, cx + half, cy + half, cz + half};
        uint8_t no_base[16] = {};
        g_add_zone(bzs, 0, flag, 0, b, 0, 0, no_base);
        g_boxes.fetch_add(1);
        if (g_box_said.fetch_add(1) < 4)
            EMF_LOG(kMod, "free build (%s): a build zone %.0f m wide around player %u at %.1f %.1f %.1f (grid cell centre %.0f %.0f %.0f)", side,
                    (kPlayerHalf + kGridStep / 2) * 2, id, double(p.x) / 4294967296.0, double(p.y) / 4294967296.0, double(p.z) / 4294967296.0,
                    double(cx) / 4294967296.0, double(cy) / 4294967296.0, double(cz) / 4294967296.0);
    }
}

uint64_t add_zone_detour(void* bzs, uint8_t list, uint8_t flag, uint8_t owner, int64_t* box, uint32_t entity,
                         uint8_t abandoned, void* base_id) {
    // (0.15.443) called with Free build off too: it starts each rebuild's altar list (then adds no boxes)
    if (box && list == 0 && owner == 0) add_player_boxes(bzs, flag, entity);
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
        altar_add(bzs, big);  // (0.15.443)
        const uint64_t r = g_add_zone(bzs, list, flag, owner, big, entity, abandoned, base_id);
        static std::atomic<int> back{0};
        if (back.fetch_add(1) < 3) EMF_LOG(kMod, "bigger altar areas: addZone returned for %u", entity);  // (0.15.418) where a freeze is
        return r;
    }
    if (box && list == 0 && owner == 0) altar_add(bzs, box);  // (0.15.443)
    return g_add_zone(bzs, list, flag, owner, box, entity, abandoned, base_id);
}
}  // namespace

// called by flamekit_native's emf_mod_load in every process (a dedicated server, a player's game)
bool fk_build_anywhere_load(bool dedicated) {
    // (0.15.423) the factor is read now, before the world loads (the game decides what to keep then)
    if (dedicated) read_spots("server, at start");  // (0.15.440) before the world loads
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
                read_spots("server");
                read_factor(L"altar_size_server.txt", "server", kMaxFactor);
                if (void* bzs = w.singleton("BuildZoneSystem")) write_altar_areas(bzs);  // (0.15.443)
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
