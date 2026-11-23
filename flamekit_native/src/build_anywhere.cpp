// build_anywhere.cpp: Free build and Bigger altar areas, both through the game's build zone list.
//
// FREE BUILD (per player, Experimental tab > Building). Hooked: BuildZoneSystem_addZone. On each rebuild of the build
// zone list, when the game adds its first altar zone, this adds to the same list:
//  - the server only: a zone over each remembered spot (free_build_spots.txt, "x y z" in m per line, written by
//    features/building.lua): a 48 m box, from the server's start, so what was built there is saved and kept like
//    inside an altar's area;
//  - (0.15.465) a 16 m box around each player Free build is on for, only while a building item is selected
//    (free_build_server.txt / free_build_client.txt: one player a line, "<entity id>" or "<entity id> a"; read every 15
//    steps), in the server and in that player's own game. The box sits on a kAimStep grid (a box that moved smoothly
//    made the server resend the whole zone list every step). The positions are read on the world's own step (on_tick) and
//    kept for this code. Until 0.15.462 the box was 112 m around the player, always: on G-Portal that made the server's
//    steps 48 ms instead of 17 ("server overloaded"; the game does much more work for everything inside a build zone).
//    The game draws the border only while the building tool is selected.
// Free build works only outside flame altar areas (owner 2026-11-22 11:06): no box while the player stands inside
// an altar's area (as added, after the bigger size), unless the player's line has "a" (an admin's "Free build inside
// altar areas" in the Building tab, owner 17:29). A remembered spot's area reaches free_build_spot_half.txt m from its
// centre. The server writes its altar areas to altar_areas_server.txt (min xyz, max xyz in m per line) for the Lua,
// which then makes no remembered spot for a piece placed in one.
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
// (0.15.460, #5) FlameKit's zones go into the list right after the game empties it each step (programs clear_buildzones,
// clear_buildzones_client; EMF hook_program), so Free build no longer needs a flame altar on the map; the old way (from
// the first altar's addZone) is the fallback when those hooks cannot be set (fkbuild clear off switches to it).
//
// Console: fkbuild stats | free on|off | altar on|off | clear on|off (debug master switches; free and altar on at start)
//          | size <m>|off (0.15.466, a test on the owner's own server: the moving area's size, see read_test_size).
//
// (0.15.466) SERVER SPEED LOG (speed_tick): one line a minute in emf_core.log ("server speed, minute N"): the steps, the
// average and the slowest step, the process's CPU, each Free build area that was on and the remembered spots; a minute
// whose steps average more than kSlowMs is logged as SLOW with the threads that used the most CPU in it, each next to
// what it uses in a normal minute. Logging only. (0.15.467) THE SAMPLER (see sampler_thread): with speed_sampler.txt "on",
// where the world step thread is while the server runs slow; (0.15.468) and every exception raised, counted each minute;
// (0.15.469) and how many terrain chunks the game unpacks each minute (see kUnpackSig).
#include <windows.h>
#include <tlhelp32.h>

#include <algorithm>
#include <cstdlib>
#include <iterator>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <set>
#include <string>
#include <unordered_map>
#include <thread>
#include <tuple>
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

// the players Free build is on for, per side (read from the files on the world's own tick thread), and (0.15.453, owner
// 2026-11-22 17:19/17:29 "add the setting for admin free build mode staying on inside other peoples bases") those whose
// Free build works inside altar areas too (an admin's switch in the Building tab: an "a" after the id in the file)
std::mutex g_mx;
std::set<uint32_t> g_free_server, g_free_client, g_alt_server, g_alt_client;

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

// Reads the Lua part's list file `name` (one player a line: "<entity id>" or "<entity id> a", a: Free build also inside
// altar areas) into `out` and `alt`; logged when it changed. (0.15.453) A file that cannot be opened (the Lua part is
// just replacing it) leaves the lists as they are.
void read_list(const wchar_t* name, std::set<uint32_t>& out, std::set<uint32_t>& alt, const char* side) {
    std::set<uint32_t> ids, alts;
    FILE* f = _wfopen(lua_file(name).c_str(), L"rb");
    if (!f) return;
    char line[64];
    while (std::fgets(line, sizeof line, f)) {
        unsigned v = 0;
        char flag = 0;
        const int got = std::sscanf(line, "%u %c", &v, &flag);
        if (got >= 1 && v) {
            ids.insert(v);
            if (got == 2 && flag == 'a') alts.insert(v);
        }
    }
    std::fclose(f);
    std::lock_guard<std::mutex> lk(g_mx);
    if (ids != out || alts != alt) {
        std::string list;
        for (uint32_t id : ids) list += " " + std::to_string(id) + (alts.count(id) ? " (also in altar areas)" : "");
        EMF_LOG(kMod, "free build (%s): on for%s", side, list.empty() ? " nobody" : list.c_str());
        out.swap(ids);
        alt.swap(alts);
    }
}

// Whether entity `id` is in `list`.
bool free_for(std::set<uint32_t>& list, uint32_t id) {
    std::lock_guard<std::mutex> lk(g_mx);
    return list.count(id) != 0;
}

// (0.15.440) Free build's remembered spots: the centres (m) of the 32 m grid cells where pieces were placed with Free
// build (features/building.lua writes free_build_spots.txt). The server adds a build zone over each, every step,
// from its start: what was built there should be kept like inside an altar's area.
// (0.15.453, owner 17:29 "#9 ok fix this") how far a spot's area reaches from its centre comes from the Lua part
// (free_build_spot_half.txt, features/building.lua's SPOT_HALF), so the area and the tab's "nearest spot" always agree;
// kSpotHalfDefault until the file is there.
constexpr double kSpotHalfDefault = 24.0;
std::atomic<double> g_spot_half{kSpotHalfDefault};
std::vector<std::array<int64_t, 3>> g_spots;  // under g_mx
std::string g_spots_text;

// Reads free_build_spot_half.txt and free_build_spots.txt ("x y z" in m per line) into g_spot_half and g_spots (2^32 per
// m); logged when they changed.
void read_spots(const char* side) {
    if (FILE* f = _wfopen(lua_file(L"free_build_spot_half.txt").c_str(), L"rb")) {
        double h = 0;
        if (std::fscanf(f, "%lf", &h) == 1 && h >= 8.0 && h <= 64.0 && h != g_spot_half.load()) {
            g_spot_half = h;
            EMF_LOG(kMod, "free build (%s): a remembered spot's area reaches %.0f m from its centre", side, h);
        }
        std::fclose(f);
    }
    std::string text;
    FILE* f = _wfopen(lua_file(L"free_build_spots.txt").c_str(), L"rb");
    if (!f) return;  // (0.15.453) the Lua part is just replacing it: the spots stay as they are
    {
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

// Reads the bigger altar factor from file `name` (1 to kMaxFactor; `missing` when there is no file) into g_factor; logged when it changed.
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

// (0.15.470, owner 07:30 "can you start figuring out how we can add the missing base data its looking for", 07:41
// "lets start on that.. the problem is a 16 m area won't stay that way as a player builds it bigger") A TEST of the base
// data on the owner's own server: free_build_test_base.txt (the server's FlameKit folder) says what FlameKit passes to
// addZone for its moving area: "none" (or no file: entity 0, no base id, as always), "entity" (the player's own entity
// id, no base id) or "altar" (the entity, base id and abandoned flag of the real flame altar nearest to the player, as
// the game passes them for that altar). Read every 15 steps, logged on change; the server only. The real altars' values
// are taken from the game's own addZone calls (the detour), the first ones logged with their base id.
struct AltarInfo { int64_t cx = 0, cy = 0, cz = 0; uint32_t entity = 0; uint8_t abandoned = 0; uint8_t base_id[16] = {}; };
std::mutex g_altar_info_mx;
std::unordered_map<uint32_t, AltarInfo> g_altar_info;  // altar entity -> what the game passed (under g_altar_info_mx)
enum class TestBase { None, Entity, Altar };
std::atomic<int> g_test_base{int(TestBase::None)};

// (0.15.463, owner 2026-11-22 21:35-21:46: G-Portal "server overloaded" while in Free build outside an altar area,
// confirmed by switching it off and on: 48 ms steps instead of 17; "112m wide is way to fucking big", "as small as
// possible", "yes" to 16 m) the area is no longer a 112 m box around the player (40 m + half a 32 m grid step each way).
// 0.15.463 put a 16 m box around where the player aims, but on the server the construction cursor's position reads
// 0 0 0 (the box went to the map's corner: "says I need a flame alter near by", owner 21:55). (0.15.464, owner 21:57
// "fix it") a box around the player, only while a building item is selected (NetworkCursor.currentBuildingItemId not
// 0). 0.15.464 made it 24 m without asking (the owner had agreed to 16 m; 22:18 "why the fuck are you constantly
// changing shit you say you're going to do on me?"). (0.15.465, owner 22:19 "do what we agreed to make it. 16 m") 16 m:
// 8 m each way from the middle of the player's 4 m grid cell. It moves in 4 m steps (each move sends every player the
// zone list again, about 1 KB).
constexpr double kAimHalf = 8.0;   // m each way from the middle of the player's grid cell (16 m box)
// (0.15.466, owner 22:34 "yes" to a test size) what is used: kAimHalf, unless free_build_test_size.txt says otherwise
std::atomic<double> g_aim_half{kAimHalf};
constexpr double kAimStep = 4.0;   // m: the box moves only when the player crosses a grid line
std::atomic<uint64_t> g_steps{0};     // world steps (on_tick), so the player boxes go in once per step
// (0.15.453, owner 17:19 "#7 go ahead") the positions of the players Free build is on for, read on each world's own
// step (on_tick, the world thread) and used by the box code, which runs inside the game's addZone (its thread is not
// known): no game data is read there. Per side: 1 the server, 0 the player's own game. (0.15.464) Only while the player
// has a building item selected (NetworkCursor.currentBuildingItemId); without one there is no entry, so no box.
struct Pos { int64_t x, y, z; };
std::mutex g_pos_mx;
std::unordered_map<uint64_t, Pos> g_pos;  // (side << 32 | entity) -> position (2^32 per m), under g_pos_mx
std::atomic<int> g_box_said{0};
// (0.15.466) the server's Free build areas this minute, for the speed log: player -> steps with an area, where it was
struct BoxSeen { uint32_t passes = 0; int64_t x = 0, z = 0; };
std::mutex g_seen_mx;
std::unordered_map<uint32_t, BoxSeen> g_seen;  // under g_seen_mx

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
// A copy of zone list `bzs`'s altar areas from its last full rebuild.
std::vector<Box> altar_last(void* bzs) {
    std::lock_guard<std::mutex> lk(g_altar_mx);
    auto it = g_altar_boxes.find(bzs);
    return it == g_altar_boxes.end() ? std::vector<Box>{} : it->second.last;
}
// Whether x, y, z (2^32 per m) lies in box b.
bool in_box(const Box& b, int64_t x, int64_t y, int64_t z) {
    return x >= b[0] && x <= b[3] && y >= b[1] && y <= b[4] && z >= b[2] && z <= b[5];
}
std::string g_altars_text;  // what altar_areas_server.txt holds (the tick thread only)
bool g_altars_written = false;  // (0.15.453) written once at least, also when there is no altar (a new map: "" not the old map's)
// Writes zone list `bzs`'s altar areas to altar_areas_server.txt for the Lua (min xyz, max xyz in m per line), when they changed.
void write_altar_areas(void* bzs) {
    std::string text;
    char line[160];
    for (const Box& b : altar_last(bzs)) {
        std::snprintf(line, sizeof line, "%.1f %.1f %.1f %.1f %.1f %.1f\n", double(b[0]) / 4294967296.0, double(b[1]) / 4294967296.0,
                      double(b[2]) / 4294967296.0, double(b[3]) / 4294967296.0, double(b[4]) / 4294967296.0, double(b[5]) / 4294967296.0);
        text += line;
    }
    if (g_altars_written && text == g_altars_text) return;
    // (0.15.453, owner 17:19 "#8 go ahead") a temporary file moved over the old one, so the Lua part never reads half a file
    const std::wstring dest = lua_file(L"altar_areas_server.txt"), tmp = lua_file(L"altar_areas_server.tmp");
    if (FILE* f = _wfopen(tmp.c_str(), L"wb")) {
        const bool ok = text.empty() || std::fwrite(text.data(), 1, text.size(), f) == text.size();
        std::fclose(f);
        if (!ok || !MoveFileExW(tmp.c_str(), dest.c_str(), MOVEFILE_REPLACE_EXISTING)) {
            static std::atomic<int> said{0};
            if (said.fetch_add(1) < 3) EMF_LOG(kMod, "free build (server): altar_areas_server.txt could not be written (error %lu)", GetLastError());
            return;
        }
        const bool first = !g_altars_written;
        g_altars_written = true;
        g_altars_text = text;
        size_t n = 0;
        for (char c : text) n += c == '\n';
        EMF_LOG(kMod, "free build (server): %zu altar area(s) written for the Lua%s", n, first ? " (first time)" : "");
    }
}

// (0.15.460, #5) how FlameKit's zones get into the list. true (the default): right after the game empties the list
// (EMF hook_program, post of clear_buildzones / clear_buildzones_client), once per rebuild, with or without a flame
// altar on the map. false (fkbuild clear off, or the program hooks could not be set): the old way, from inside the
// game's addZone call for the first altar of each rebuild (no altar on the map: no Free build).
std::atomic<bool> g_clear_path{true};
// (0.15.461) Writes which way is in use to free_build_way.txt for the Lua part: "clear" (no altar needed) or "altar"
// (the old way: the Building tab warns on a map without an altar).
void write_way() {
    const char* way = g_clear_path.load() ? "clear\n" : "altar\n";
    if (FILE* f = _wfopen(lua_file(L"free_build_way.txt").c_str(), L"wb")) {
        std::fwrite(way, 1, std::strlen(way), f);
        std::fclose(f);
    }
}
// (0.15.460) the flag the game passes to addZone for an altar (list 0), per zone list, learned from its calls (the
// probe of 0.15.459 saw 0 for list 1 on both sides and 1 for list 2 in the player's game); FlameKit passes the same
// one for its zones. Until an altar was seen (a map without one): kFlagUnknown, then 0 is used.
constexpr int kFlagUnknown = -1;
std::unordered_map<void*, int> g_list0_flag;  // under g_altar_mx
int list0_flag(void* bzs) {
    std::lock_guard<std::mutex> lk(g_altar_mx);
    auto it = g_list0_flag.find(bzs);
    return it == g_list0_flag.end() ? kFlagUnknown : it->second;
}

void add_player_boxes(void* bzs, uint8_t flag, uint32_t altar_entity, bool from_clear = false) {
    // once per rebuild of the zone list: a new world step (on_tick) or (0.15.440) the altar that came first in the
    // last rebuild coming again (while the world loads, before any on_tick, the list is rebuilt too: the remembered
    // spots must be in it then). (0.15.460) Called right after the game emptied the list (from_clear): always a new one.
    struct Pass { uint64_t step = ~0ull; uint32_t first = 0; };
    static std::mutex mx;
    static std::unordered_map<void*, Pass> last;
    const uint64_t now = g_steps.load();
    {
        std::lock_guard<std::mutex> lk(mx);
        Pass& p = last[bzs];
        const bool fresh = from_clear || p.step != now || (p.first != 0 && p.first == altar_entity);
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
        const int64_t sh = int64_t(g_spot_half.load() * 4294967296.0);
        for (const auto& c : spots) {  // (0.15.440) the remembered spots
            int64_t b[6] = {c[0] - sh, c[1] - sh, c[2] - sh, c[0] + sh, c[1] + sh, c[2] + sh};
            uint8_t no_base[16] = {};
            g_add_zone(bzs, 0, flag, 0, b, 0, 0, no_base);
        }
        static std::atomic<int> spots_said{0};
        if (!spots.empty() && spots_said.fetch_add(1) == 0)
            EMF_LOG(kMod, "free build (server): %zu remembered spot zone(s) %.0f m wide in the zone list", spots.size(), g_spot_half.load() * 2);
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
    const int64_t step = int64_t(kAimStep * 4294967296.0);
    const double half_m = g_aim_half.load();  // (0.15.466) kAimHalf or the test size
    const int64_t half = int64_t(half_m * 4294967296.0);  // (0.15.464) around the middle of the player's grid cell
    auto cell_mid = [step](int64_t v) {
        int64_t q = v / step;
        if (v % step < 0) --q;  // floor for negative values
        return q * step + step / 2;
    };
    {
        static std::atomic<int> thread_said{0};
        if (thread_said.fetch_add(1) < 2)
            EMF_LOG(kMod, "free build (%s): the zone list is rebuilt on thread %lu", side, GetCurrentThreadId());  // (0.15.453, #7)
    }
    const uint64_t side_bit = uint64_t(w.is_server() ? 1 : 0) << 32;
    std::set<uint32_t> bypass;
    {
        std::lock_guard<std::mutex> lk(g_mx);
        bypass = w.is_server() ? g_alt_server : g_alt_client;
    }
    for (uint32_t id : ids) {
        Pos p{};
        {
            std::lock_guard<std::mutex> lk(g_pos_mx);
            auto it = g_pos.find(side_bit | id);
            if (it == g_pos.end()) continue;  // no building tool out (or not read on a world step yet): no box
            p = it->second;
        }
        bool inside = false;  // (0.15.443) in an altar's area: the game's own rules, no Free build box
        for (const Box& a : altars) if (in_box(a, p.x, p.y, p.z)) { inside = true; break; }
        const bool also = inside && bypass.count(id) != 0;  // (0.15.453) an admin's "also inside altar areas"
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
                        altars.size(), inside ? (also ? ": Free build box anyway (admin, also in altar areas)" : ": no Free build box") : "");
            }
        }
        if (inside && !also) continue;
        const int64_t cx = cell_mid(p.x), cy = cell_mid(p.y), cz = cell_mid(p.z);
        int64_t b[6] = {cx - half, cy - half, cz - half, cx + half, cy + half, cz + half};
        uint8_t no_base[16] = {};
        uint32_t z_entity = 0;  // (0.15.470) the base data test (free_build_test_base.txt): none unless asked
        uint8_t z_abandoned = 0;
        const TestBase tb = w.is_server() ? TestBase(g_test_base.load()) : TestBase::None;
        if (tb == TestBase::Entity) {
            z_entity = id;
        } else if (tb == TestBase::Altar) {
            std::lock_guard<std::mutex> lk(g_altar_info_mx);
            double best = -1;
            for (const auto& kv : g_altar_info) {
                const double dx = double(kv.second.cx - p.x), dz = double(kv.second.cz - p.z), d2 = dx * dx + dz * dz;
                if (best < 0 || d2 < best) {
                    best = d2;
                    z_entity = kv.second.entity;
                    z_abandoned = kv.second.abandoned;
                    memcpy(no_base, kv.second.base_id, 16);
                }
            }
        }
        g_add_zone(bzs, 0, flag, 0, b, z_entity, z_abandoned, no_base);
        g_boxes.fetch_add(1);
        if (w.is_server()) {  // (0.15.466) for the speed log
            std::lock_guard<std::mutex> lk(g_seen_mx);
            BoxSeen& bs = g_seen[id];
            ++bs.passes;
            bs.x = cx;
            bs.z = cz;
        }
        if (g_box_said.fetch_add(1) < 4)
            EMF_LOG(kMod, "free build (%s): a build zone %.0f m wide around player %u at %.1f %.1f %.1f (grid cell centre %.0f %.0f %.0f)", side,
                    half_m * 2, id, double(p.x) / 4294967296.0, double(p.y) / 4294967296.0, double(p.z) / 4294967296.0,
                    double(cx) / 4294967296.0, double(cy) / 4294967296.0, double(cz) / 4294967296.0);
    }
}

// (0.15.459, #5 "is there a way to make free build mode not require a flame alter?", owner 19:41 "go ahead": research)
// A probe, logging only: the game empties the zone list each step in its programs clear_buildzones (server) and
// clear_buildzones_client (EMF 0.6.19's docs/ecs_programs.md #120, #121) and fills it in add_buildzones_server /
// add_buildzones_client (#55, #54). If our zones went in right after the clear (EMF hook_program, post), they would
// not need an altar's addZone call. The probe logs, for the first steps, the order these run in, their threads, and
// the flag the game passes to addZone for an altar (needed to add our zones without an altar's call).
std::atomic<uint32_t> g_probe_seq{0};
// One probe line, the first 10 of each kind (`said` counts them).
void probe(std::atomic<int>& said, const char* what) {
    if (said.fetch_add(1) >= 10) return;
    EMF_LOG(kMod, "free build probe #%u: %s (step %llu, thread %lu)", g_probe_seq.fetch_add(1), what,
            (unsigned long long)g_steps.load(), GetCurrentThreadId());
}
std::atomic<int> g_said_cs{0}, g_said_cc{0}, g_said_as{0}, g_said_ac{0}, g_said_zone{0};
// (0.15.460, #5) right after the game emptied zone list `bzs`: FlameKit's zones go in first, with or without an altar.
void after_clear(void* bzs, const char* side) {
    if (!bzs || !g_clear_path.load()) return;
    const int known = list0_flag(bzs);
    {
        static std::mutex mx;
        static std::unordered_map<void*, int> said;  // zone list -> the flag last logged for it
        std::lock_guard<std::mutex> lk(mx);
        auto it = said.find(bzs);
        if (it == said.end() || it->second != known) {
            said[bzs] = known;
            EMF_LOG(kMod, "free build (%s): FlameKit's zones go in right after the game empties its zone list %p (flag %d%s)", side, bzs,
                    known == kFlagUnknown ? 0 : known, known == kFlagUnknown ? ": no altar seen yet, 0 used" : ", as the game's altars");
        }
    }
    add_player_boxes(bzs, uint8_t(known == kFlagUnknown ? 0 : known), 0, true);
}
void probe_clear_server(void*, void*) {
    probe(g_said_cs, "clear_buildzones done (server)");
    if (emf::World ws = emf::server_world()) after_clear(ws.singleton("BuildZoneSystem"), "server");
}
void probe_clear_client(void*, void*) {
    probe(g_said_cc, "clear_buildzones_client done (this game)");
    if (emf::World wc = emf::client_world()) after_clear(wc.singleton("BuildZoneSystem"), "this game");
}
void probe_add_server(void*, void*) { probe(g_said_as, "add_buildzones_server starts"); }
void probe_add_client(void*, void*) { probe(g_said_ac, "add_buildzones_client starts"); }

uint64_t add_zone_detour(void* bzs, uint8_t list, uint8_t flag, uint8_t owner, int64_t* box, uint32_t entity,
                         uint8_t abandoned, void* base_id) {
    {  // (0.15.459, probe) what the game passes
        if (g_said_zone.load() < 10) {
            char line[200];
            snprintf(line, sizeof line, "addZone(list %u, flag %u, owner kind %u, entity %u, abandoned %u, zone list %p)", list, flag, owner,
                     entity, abandoned, bzs);
            probe(g_said_zone, line);
        }
    }
    if (box && list == 0 && owner == 0 && entity != 0 && base_id) {  // (0.15.470) a real altar's values, for the base data test
        AltarInfo ai;
        ai.cx = box[0] / 2 + box[3] / 2;
        ai.cy = box[1] / 2 + box[4] / 2;
        ai.cz = box[2] / 2 + box[5] / 2;
        ai.entity = entity;
        ai.abandoned = abandoned;
        memcpy(ai.base_id, base_id, 16);
        std::lock_guard<std::mutex> lk(g_altar_info_mx);
        const bool fresh = g_altar_info.find(entity) == g_altar_info.end();
        g_altar_info[entity] = ai;
        static int said = 0;
        if (fresh && said < 20) {
            ++said;
            const uint8_t* g = ai.base_id;
            EMF_LOG(kMod, "free build: altar zone of entity %u at %.0f %.0f %.0f, abandoned %u, base id %02x%02x%02x%02x-%02x%02x%02x%02x-%02x%02x%02x%02x-%02x%02x%02x%02x",
                    entity, double(ai.cx) / 4294967296.0, double(ai.cy) / 4294967296.0, double(ai.cz) / 4294967296.0, abandoned,
                    g[0], g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], g[9], g[10], g[11], g[12], g[13], g[14], g[15]);
        }
    }
    if (box && list == 0 && owner == 0) {  // (0.15.460) the flag the game uses for an altar, per zone list (logged when it changes)
        std::lock_guard<std::mutex> lk(g_altar_mx);
        auto it = g_list0_flag.find(bzs);
        if (it == g_list0_flag.end() || it->second != flag) {
            g_list0_flag[bzs] = flag;
            EMF_LOG(kMod, "free build: the game adds altars to zone list %p with flag %u (entity %u)", bzs, flag, entity);
        }
    }
    // (0.15.443) called with Free build off too: it starts each rebuild's altar list (then adds no boxes). (0.15.460)
    // Only when FlameKit's zones are not added right after the list is emptied (g_clear_path).
    if (box && list == 0 && owner == 0 && !g_clear_path.load()) add_player_boxes(bzs, flag, entity);
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
// (0.15.466, owner 22:33 "im not convinced it was just the size", 22:34 "yes" to "fkbuild size <m>") a test size for the
// moving Free build area on the owner's own server: free_build_test_size.txt (FlameKit's folder, the server's) holds the
// area's width in m (4 to 112); without the file (or another value) it is the normal 16 m (kAimHalf). Written by the
// command "fkbuild size <m>" ("fkbuild size off" removes it) or by hand. Read every 15 steps; logged on change. Only
// the server's area: the player's own game keeps 16 m (what the server does is what is being measured).
constexpr double kTestMinM = 4.0, kTestMaxM = 112.0;
void read_test_base() {  // (0.15.470) see g_test_base
    char w[16] = {};
    if (FILE* f = _wfopen(lua_file(L"free_build_test_base.txt").c_str(), L"r")) {
        if (fscanf(f, "%15s", w) != 1) w[0] = 0;
        fclose(f);
    }
    const TestBase tb = strcmp(w, "entity") == 0 ? TestBase::Entity : strcmp(w, "altar") == 0 ? TestBase::Altar : TestBase::None;
    if (int(tb) != g_test_base.load()) {
        g_test_base = int(tb);
        EMF_LOG(kMod, "free build (server): TEST base data from free_build_test_base.txt: %s",
                tb == TestBase::Entity ? "the player's own entity id, no base id"
                : tb == TestBase::Altar ? "the nearest real flame altar's entity, base id and abandoned flag"
                                        : "none (entity 0, no base id, as normal)");
    }
}

void read_test_size() {
    double m = 0;
    if (FILE* f = _wfopen(lua_file(L"free_build_test_size.txt").c_str(), L"r")) {
        if (fscanf(f, "%lf", &m) != 1) m = 0;
        fclose(f);
    }
    const double half = (m >= kTestMinM && m <= kTestMaxM) ? m / 2 : kAimHalf;
    if (half != g_aim_half.load()) {
        g_aim_half = half;
        if (half == kAimHalf) EMF_LOG(kMod, "free build (server): the Free build area is the normal %.0f m again (no test size)", kAimHalf * 2);
        else EMF_LOG(kMod, "free build (server): TEST size from free_build_test_size.txt: the Free build area is %.0f m (normal %.0f m)", half * 2, kAimHalf * 2);
    }
}

// ---- (0.15.466) the server speed log (see the header) ----
constexpr double kSlowMs = 20.0;      // a minute whose steps average more than this is SLOW (normal: 16.7 ms, 60 a second)
constexpr double kMinuteS = 60.0;     // one line per this many seconds
constexpr size_t kTopThreads = 6;     // threads named in a SLOW line
constexpr uint32_t kListEvery = 30;   // also name the busiest threads in a normal minute every this many minutes
uint64_t ft(const FILETIME& f) { return (uint64_t(f.dwHighDateTime) << 32) | f.dwLowDateTime; }
struct ThreadUse { uint64_t last = 0; double normal = -1; std::string name; };  // CPU (100 ns), % of a core normally

// A thread's name, when the game gave it one (GetThreadDescription, Windows 10 1607 and newer; looked up at run time).
std::string thread_name(HANDLE h) {
    using Fn = HRESULT(WINAPI*)(HANDLE, PWSTR*);
    static Fn fn = reinterpret_cast<Fn>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "GetThreadDescription"));
    std::string out;
    PWSTR wname = nullptr;
    if (fn && SUCCEEDED(fn(h, &wname)) && wname) {
        char buf[96] = {};
        WideCharToMultiByte(CP_UTF8, 0, wname, -1, buf, sizeof(buf) - 1, nullptr, nullptr);
        out = buf;
        LocalFree(wname);
    }
    return out;
}

// The CPU time (100 ns) each thread of this process used since the last call, as (thread id, time); a thread seen for
// the first time counts with all its time. Threads that ended are forgotten.
std::vector<std::pair<uint32_t, uint64_t>> thread_cpu(std::unordered_map<uint32_t, ThreadUse>& use) {
    std::vector<std::pair<uint32_t, uint64_t>> out;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snap == INVALID_HANDLE_VALUE) return out;
    const DWORD pid = GetCurrentProcessId();
    std::set<uint32_t> alive;
    THREADENTRY32 te{};
    te.dwSize = sizeof(te);
    if (Thread32First(snap, &te)) {
        do {
            if (te.th32OwnerProcessID != pid) continue;
            HANDLE h = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, FALSE, te.th32ThreadID);
            if (!h) continue;
            FILETIME c, e, k, u;
            if (GetThreadTimes(h, &c, &e, &k, &u)) {
                const uint64_t now = ft(k) + ft(u);
                auto it = use.find(te.th32ThreadID);
                if (it == use.end()) {
                    ThreadUse t;
                    t.last = now;
                    t.name = thread_name(h);
                    use.emplace(te.th32ThreadID, t);
                    out.emplace_back(te.th32ThreadID, now);
                } else {
                    out.emplace_back(te.th32ThreadID, now >= it->second.last ? now - it->second.last : 0);
                    it->second.last = now;
                }
                alive.insert(te.th32ThreadID);
            }
            CloseHandle(h);
        } while (Thread32Next(snap, &te));
    }
    CloseHandle(snap);
    for (auto it = use.begin(); it != use.end();) it = alive.count(it->first) ? std::next(it) : use.erase(it);
    return out;
}

uint64_t process_cpu() {
    FILETIME c, e, k, u;
    return GetProcessTimes(GetCurrentProcess(), &c, &e, &k, &u) ? ft(k) + ft(u) : 0;
}

// ---- (0.15.467, owner 00:22 "doesnt sound like you know how to identify the problem", "yes" to a sampler) ----
// THE SAMPLER: where the world step thread spends its time while the server runs slow. Only when the server's FlameKit
// folder has speed_sampler.txt saying "on" (Claude sets it on the owner's own test server; never on G-Portal), and only
// in the minute after a SLOW minute (and on while the minutes stay SLOW). About kSamplesPerMin times a minute a thread of
// its own pauses the world step thread (SuspendThread), reads where it is and walks its call chain (RtlVirtualUnwind, up
// to kFrames calls, guarded by __try: nothing is allocated or logged while it is paused; a few microseconds), then lets
// it go. At the minute's end the functions it was in most (and those most often in its call chain) are logged as
// "module 0xADDRESS" (the game's own code at its usual base 0x140000000, so the addresses match EMF's notes).
constexpr int kFrames = 16;
constexpr uint32_t kSamplesPerMin = 1000;
std::atomic<bool> g_sampling{false};
std::atomic<uint32_t> g_sample_tid{0};
std::mutex g_sample_mx;
std::unordered_map<uint64_t, uint32_t> g_leaf, g_chain;  // function start -> samples (under g_sample_mx)
uint32_t g_samples = 0, g_sample_fail = 0;               // under g_sample_mx

// One sample of thread `h` (paused by the caller): the start of each function in its call chain, innermost first.
// Plain C (no objects with destructors) so __try can guard it. Returns how many were found (0: none read).
int walk_stack(HANDLE h, uint64_t* starts) {
    alignas(16) CONTEXT c;
    memset(&c, 0, sizeof(c));
    c.ContextFlags = CONTEXT_FULL;
    if (!GetThreadContext(h, &c)) return 0;
    int n = 0;
    __try {
        for (int i = 0; i < kFrames && c.Rip; ++i) {
            DWORD64 base = 0;
            PRUNTIME_FUNCTION f = RtlLookupFunctionEntry(c.Rip, &base, nullptr);
            starts[n++] = f ? base + f->BeginAddress : c.Rip;
            if (!f) {  // a leaf without unwind data: its return address is on top of the stack
                if (c.Rsp & 7) break;
                c.Rip = *reinterpret_cast<DWORD64*>(c.Rsp);
                c.Rsp += 8;
            } else {
                PVOID handler_data = nullptr;
                DWORD64 frame = 0;
                RtlVirtualUnwind(UNW_FLAG_NHANDLER, base, c.Rip, f, &c, &handler_data, &frame, nullptr);
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
    return n;
}

void sampler_thread() {
    const DWORD wait_ms = 60000 / kSamplesPerMin;
    for (;;) {
        if (!g_sampling.load() || !g_sample_tid.load()) {
            Sleep(250);
            continue;
        }
        uint64_t starts[kFrames] = {};
        int n = 0;
        if (HANDLE h = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, g_sample_tid.load())) {
            if (SuspendThread(h) != DWORD(-1)) {
                n = walk_stack(h, starts);
                ResumeThread(h);
            }
            CloseHandle(h);
        }
        {
            std::lock_guard<std::mutex> lk(g_sample_mx);
            if (n == 0) {
                ++g_sample_fail;
            } else {
                ++g_samples;
                ++g_leaf[starts[0]];
                for (int i = 0; i < n; ++i) {  // each function once per sample
                    bool seen = false;
                    for (int j = 0; j < i; ++j) seen = seen || starts[j] == starts[i];
                    if (!seen) ++g_chain[starts[i]];
                }
            }
        }
        Sleep(wait_ms);
    }
}

// (0.15.468) The exported function of module `m` at or before `rva`, as "Name+0xoff" ("" when it has no exports).
std::string export_near(HMODULE m, uint32_t rva) {
    const auto* base = reinterpret_cast<const uint8_t*>(m);
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    const IMAGE_DATA_DIRECTORY& dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT];
    if (!dir.VirtualAddress || !dir.Size) return "";
    const auto* ed = reinterpret_cast<const IMAGE_EXPORT_DIRECTORY*>(base + dir.VirtualAddress);
    const auto* fns = reinterpret_cast<const uint32_t*>(base + ed->AddressOfFunctions);
    const auto* names = reinterpret_cast<const uint32_t*>(base + ed->AddressOfNames);
    const auto* ords = reinterpret_cast<const uint16_t*>(base + ed->AddressOfNameOrdinals);
    uint32_t best = 0;
    const char* best_name = nullptr;
    for (uint32_t i = 0; i < ed->NumberOfNames; ++i) {
        const uint32_t f = fns[ords[i]];
        if (f <= rva && f >= best) {
            best = f;
            best_name = reinterpret_cast<const char*>(base + names[i]);
        }
    }
    if (!best_name) return "";
    char b[120];
    snprintf(b, sizeof(b), "%s+0x%x", best_name, rva - best);
    return b;
}

// "module 0xADDRESS": the game's own code at its usual base (from its PE header), other modules as module+offset.
std::string where(uint64_t a) {
    HMODULE m = nullptr;
    char buf[160];
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(a), &m) || !m) {
        snprintf(buf, sizeof(buf), "0x%llx (no module)", (unsigned long long)a);
        return buf;
    }
    wchar_t wpath[MAX_PATH] = {};
    GetModuleFileNameW(m, wpath, MAX_PATH);
    std::wstring wp(wpath);
    wp = wp.substr(wp.find_last_of(L"\\/") + 1);
    char name[96] = {};
    WideCharToMultiByte(CP_UTF8, 0, wp.c_str(), -1, name, sizeof(name) - 1, nullptr, nullptr);
    const uint64_t rva = a - uint64_t(m);
    // (0.15.468) the game at its usual base 0x140000000 (Windows writes the real base into the loaded header, so the
    // header cannot tell it); other modules by their nearest exported name (ntdll's RtlAllocateHeap and the like)
    if (m == GetModuleHandleW(nullptr)) {
        snprintf(buf, sizeof(buf), "%s 0x%llx", name, (unsigned long long)(0x140000000ull + rva));
        return buf;
    }
    const std::string ex = export_near(m, uint32_t(rva));
    if (!ex.empty()) snprintf(buf, sizeof(buf), "%s!%s", name, ex.c_str());
    else snprintf(buf, sizeof(buf), "%s+0x%llx", name, (unsigned long long)rva);
    return buf;
}

std::string top_list(const std::unordered_map<uint64_t, uint32_t>& m, uint32_t total, size_t count) {
    std::vector<std::pair<uint64_t, uint32_t>> v(m.begin(), m.end());
    std::sort(v.begin(), v.end(), [](const auto& a, const auto& b) { return a.second > b.second; });
    std::string out;
    char b[200];
    for (size_t i = 0; i < v.size() && i < count; ++i) {
        snprintf(b, sizeof(b), "%s%s %.0f%%", out.empty() ? "" : "; ", where(v[i].first).c_str(), total ? v[i].second * 100.0 / total : 0.0);
        out += b;
    }
    return out.empty() ? "none" : out;
}

// (0.15.468, owner 07:10 "its probably running into an exception over and over or something like that") THE EXCEPTION
// COUNTER: with the sampler on, a vectored handler counts every exception raised in the process (it only counts: the
// search goes on as before), by where it was raised and its code, kept in a fixed table without locks (an exception
// can come while any lock is held). Logged once a minute with the speed line: how many, how many on the world step
// thread, and the most frequent places.
struct ExcSlot { std::atomic<uint64_t> addr{0}; std::atomic<uint32_t> code{0}; std::atomic<uint32_t> count{0}; };
constexpr size_t kExcSlots = 64;
ExcSlot g_exc[kExcSlots];
std::atomic<uint32_t> g_exc_total{0}, g_exc_world{0}, g_exc_lost{0};
std::atomic<bool> g_exc_on{false};

LONG CALLBACK exc_counter(PEXCEPTION_POINTERS ep) {
    if (!g_exc_on.load(std::memory_order_relaxed) || !ep || !ep->ExceptionRecord) return EXCEPTION_CONTINUE_SEARCH;
    g_exc_total.fetch_add(1, std::memory_order_relaxed);
    if (GetCurrentThreadId() == g_sample_tid.load(std::memory_order_relaxed)) g_exc_world.fetch_add(1, std::memory_order_relaxed);
    const uint64_t a = uint64_t(ep->ExceptionRecord->ExceptionAddress);
    size_t i = size_t((a >> 4) * 0x9E3779B97F4A7C15ull >> 58) % kExcSlots;
    for (size_t n = 0; n < kExcSlots; ++n, i = (i + 1) % kExcSlots) {
        uint64_t cur = g_exc[i].addr.load(std::memory_order_relaxed);
        if (cur == 0 && g_exc[i].addr.compare_exchange_strong(cur, a)) {
            g_exc[i].code = ep->ExceptionRecord->ExceptionCode;
            cur = a;
        }
        if (cur == a) {
            g_exc[i].count.fetch_add(1, std::memory_order_relaxed);
            return EXCEPTION_CONTINUE_SEARCH;
        }
    }
    g_exc_lost.fetch_add(1, std::memory_order_relaxed);
    return EXCEPTION_CONTINUE_SEARCH;
}

// The minute's exceptions as one log line (and the counts back to 0).
void exc_report(uint32_t minute, bool slow) {
    const uint32_t total = g_exc_total.exchange(0), world = g_exc_world.exchange(0), lost = g_exc_lost.exchange(0);
    std::vector<std::tuple<uint32_t, uint64_t, uint32_t>> v;  // count, address, code
    for (auto& e : g_exc) {
        const uint32_t c = e.count.exchange(0);
        if (c) v.emplace_back(c, e.addr.load(), e.code.load());
    }
    std::sort(v.begin(), v.end(), [](const auto& a, const auto& b) { return std::get<0>(a) > std::get<0>(b); });
    std::string top;
    char b[220];
    for (size_t i = 0; i < v.size() && i < 8; ++i) {
        snprintf(b, sizeof(b), "%s%u x code 0x%08x at %s", top.empty() ? "" : "; ", std::get<0>(v[i]), std::get<2>(v[i]),
                 where(std::get<1>(v[i])).c_str());
        top += b;
    }
    EMF_LOG(kMod, "server speed, minute %u%s: exceptions: %u (%u on the world step thread)%s%s%s", minute, slow ? " SLOW" : "",
            total, world, lost ? ", some not placed" : "", top.empty() ? "" : ": ", top.c_str());
}

// (0.15.469, owner 07:24 "build it") THE CHUNK COUNTER: how often the game unpacks terrain (terraforming) chunk data.
// The sampler found the slow work in the server's two terraforming voxel data stores (made at 0x1407ab3ba / 0x1407ab415
// by 0x140834510, budgets 38 MB and 20 MB), which unpack chunks with the game's decompressor 0x1408514b0
// (enshrouded_server.exe build 1287369; its 40 first bytes, unique in the server exe: kUnpackSig). Its arguments:
// (result*, destination slice*, source slice*), a slice's length at +8. Hooked only on a dedicated server whose
// speed_sampler.txt says "on" when it starts; the detour only counts (calls, packed and unpacked bytes, the world step
// thread apart) and calls the game's own function. Logged each minute with the sampler's lines.
constexpr const char* kUnpackSig = "48 89 6C 24 18 48 89 74 24 20 48 89 4C 24 08 57 41 54 41 55 41 56 41 57 49 8B 30 48 8B FA 49 8B 68 08 45 33 D2 45 33 C9";
using UnpackFn = void* (*)(void*, void*, void*);
UnpackFn g_unpack = nullptr;
std::atomic<uint64_t> g_unpack_world{0}, g_unpack_other{0}, g_unpack_in{0}, g_unpack_out{0};

void* unpack_detour(void* result, void* dst, void* src) {
    if (GetCurrentThreadId() == g_sample_tid.load(std::memory_order_relaxed)) g_unpack_world.fetch_add(1, std::memory_order_relaxed);
    else g_unpack_other.fetch_add(1, std::memory_order_relaxed);
    if (src) g_unpack_in.fetch_add(*reinterpret_cast<const uint64_t*>(static_cast<const char*>(src) + 8), std::memory_order_relaxed);
    if (dst) g_unpack_out.fetch_add(*reinterpret_cast<const uint64_t*>(static_cast<const char*>(dst) + 8), std::memory_order_relaxed);
    return g_unpack(result, dst, src);
}

bool sampler_file_on() {
    bool on = false;
    if (FILE* f = _wfopen(lua_file(L"speed_sampler.txt").c_str(), L"r")) {
        char w[8] = {};
        on = fscanf(f, "%7s", w) == 1 && strcmp(w, "on") == 0;
        fclose(f);
    }
    return on;
}

// At each minute's end (world thread): the report of the minute just sampled, and whether to sample the next one.
void sampler_minute(uint32_t minute, bool slow, uint32_t world_tid) {
    const bool on = sampler_file_on();
    static bool started = false, said_on = false;
    if (on && !said_on) EMF_LOG(kMod, "server speed: the sampler is on (speed_sampler.txt): it samples the minute after a SLOW one");
    said_on = on;
    if (on && !started) {
        std::thread(sampler_thread).detach();
        AddVectoredExceptionHandler(1, exc_counter);  // (0.15.468) first in line: it only counts
        started = true;
    }
    if (g_exc_on.load()) exc_report(minute, slow);  // (0.15.468) the minute that just ended
    if (g_unpack) {  // (0.15.469) the chunk counter, every minute
        const uint64_t w = g_unpack_world.exchange(0), o = g_unpack_other.exchange(0), in = g_unpack_in.exchange(0), out = g_unpack_out.exchange(0);
        EMF_LOG(kMod, "server speed, minute %u%s: terrain chunks unpacked: %llu on the world step thread, %llu on other threads; %.1f MB packed -> %.1f MB",
                minute, slow ? " SLOW" : "", (unsigned long long)w, (unsigned long long)o, in / 1048576.0, out / 1048576.0);
    }
    g_exc_on = on;
    if (g_sampling.load()) {  // the minute just ended was sampled
        std::unordered_map<uint64_t, uint32_t> leaf, chain;
        uint32_t samples = 0, fail = 0;
        {
            std::lock_guard<std::mutex> lk(g_sample_mx);
            leaf.swap(g_leaf);
            chain.swap(g_chain);
            samples = g_samples;
            fail = g_sample_fail;
            g_samples = g_sample_fail = 0;
        }
        EMF_LOG(kMod, "server speed, minute %u%s: sampler: %u samples of the world step thread (%u not read); where it was: %s", minute,
                slow ? " SLOW" : "", samples, fail, top_list(leaf, samples, 12).c_str());
        EMF_LOG(kMod, "server speed, minute %u%s: sampler: most often in its call chain: %s", minute, slow ? " SLOW" : "",
                top_list(chain, samples, 20).c_str());
    }
    g_sample_tid = world_tid;
    g_sampling = on && slow && minute > 1;  // the first minute is the world coming up with nobody on (always slow)
}

// Called on each server world step (its own thread). Counts the steps and their length; once a minute writes the line.
void speed_tick() {
    static LARGE_INTEGER freq{}, last{}, minute_start{};
    static bool started = false;
    static uint32_t steps = 0, minute = 0;
    static double slowest = 0;
    static uint64_t proc_last = 0;
    static std::unordered_map<uint32_t, ThreadUse> use;
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    if (!started) {  // the first step: only the starting values (the threads' time so far is not this minute's)
        QueryPerformanceFrequency(&freq);
        last = minute_start = now;
        proc_last = process_cpu();
        thread_cpu(use);
        started = true;
        EMF_LOG(kMod, "server speed: logged once a minute from now (SLOW: steps averaging more than %.0f ms; normal 16.7 ms)", kSlowMs);
        return;
    }
    const double ms = double(now.QuadPart - last.QuadPart) * 1000.0 / double(freq.QuadPart);
    last = now;
    ++steps;
    if (ms > slowest) slowest = ms;
    const double span = double(now.QuadPart - minute_start.QuadPart) / double(freq.QuadPart);
    if (span < kMinuteS) return;
    ++minute;
    const double avg = steps ? span * 1000.0 / steps : 0;
    const uint64_t pc = process_cpu();
    const double cores = double(pc - proc_last) / (span * 1e7);
    proc_last = pc;
    std::string areas;
    {
        std::lock_guard<std::mutex> lk(g_seen_mx);
        char b[160];
        for (const auto& kv : g_seen) {
            snprintf(b, sizeof(b), "%splayer %u: %.0f m in %u zone list rebuild(s), last at %.0f %.0f", areas.empty() ? "" : "; ",
                     kv.first, g_aim_half.load() * 2, kv.second.passes, double(kv.second.x) / 4294967296.0, double(kv.second.z) / 4294967296.0);
            areas += b;
        }
        g_seen.clear();
    }
    size_t spots = 0;
    {
        std::lock_guard<std::mutex> lk(g_mx);
        spots = g_spots.size();
    }
    const bool slow = avg > kSlowMs;
    EMF_LOG(kMod, "server speed, minute %u%s: %u steps, average %.1f ms, slowest %.0f ms, process CPU %.2f cores; Free build areas: %s; remembered spots %zu (%.0f m)",
            minute, slow ? " SLOW" : "", steps, avg, slowest, cores, areas.empty() ? "none" : areas.c_str(), spots, g_spot_half.load() * 2);
    // the threads: % of one core each used this minute
    std::vector<std::pair<uint32_t, uint64_t>> t = thread_cpu(use);
    std::sort(t.begin(), t.end(), [](const auto& a, const auto& b) { return a.second > b.second; });
    const uint32_t world_thread = GetCurrentThreadId();
    if (slow || minute == 1 || minute % kListEvery == 0) {
        std::string line;
        char b[200];
        for (size_t i = 0; i < t.size() && i < kTopThreads; ++i) {
            const auto it = use.find(t[i].first);
            const double pct = double(t[i].second) * 100.0 / (span * 1e7);
            const std::string nm = it != use.end() ? it->second.name : "";
            const double normal = it != use.end() ? it->second.normal : -1;
            char nb[24] = "not known yet";
            if (normal >= 0) snprintf(nb, sizeof(nb), "%.0f%%", normal);
            snprintf(b, sizeof(b), "%sthread %u%s%s%s%s: %.0f%% of a core (normal %s)", line.empty() ? "" : "; ", t[i].first,
                     nm.empty() ? "" : " '", nm.c_str(), nm.empty() ? "" : "'", t[i].first == world_thread ? " (the world step)" : "", pct, nb);
            line += b;
        }
        EMF_LOG(kMod, "server speed, minute %u%s: busiest threads: %s", minute, slow ? " SLOW" : "", line.empty() ? "none read" : line.c_str());
    }
    if (!slow && minute > 1) {  // a normal minute (not the first, while the world comes up): what each thread normally uses
        for (const auto& x : t) {
            auto it = use.find(x.first);
            if (it == use.end()) continue;
            const double pct = double(x.second) * 100.0 / (span * 1e7);
            it->second.normal = it->second.normal < 0 ? pct : it->second.normal * 0.7 + pct * 0.3;
        }
    }
    sampler_minute(minute, slow, world_thread);  // (0.15.467)
    minute_start = now;
    steps = 0;
    slowest = 0;
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
    if (dedicated && sampler_file_on()) {  // (0.15.469) the chunk counter: test servers only
        const bool u = emf::hook_pattern("flamekit: terrain chunk unpack (counter)", kUnpackSig, reinterpret_cast<void*>(&unpack_detour),
                                         reinterpret_cast<void**>(&g_unpack));
        if (!u) g_unpack = nullptr;
        EMF_LOG(kMod, "server speed: the terrain chunk counter is %s", u ? "on" : "NOT on (the game's function was not found)");
    }
    if (emf::api()->hook_program) {  // (0.15.459, #5 research) the probe: logging only
        const bool a = emf::api()->hook_program("clear_buildzones", nullptr, probe_clear_server, nullptr);
        const bool b = emf::api()->hook_program("clear_buildzones_client", nullptr, probe_clear_client, nullptr);
        const bool c = emf::api()->hook_program("add_buildzones_server", probe_add_server, nullptr, nullptr);
        const bool d = emf::api()->hook_program("add_buildzones_client", probe_add_client, nullptr, nullptr);
        EMF_LOG(kMod, "free build probe: program hooks clear_buildzones %s, clear_buildzones_client %s, add_buildzones_server %s, add_buildzones_client %s",
                a ? "on" : "NOT on", b ? "on" : "NOT on", c ? "on" : "NOT on", d ? "on" : "NOT on");
        g_clear_path = a && b;  // (0.15.460) both needed, else the old way
    } else {
        g_clear_path = false;
    }
    EMF_LOG(kMod, "free build: FlameKit's zones are added %s", g_clear_path.load() ? "right after the game empties its zone list (no altar needed)"
                                                                                  : "with the first altar of each rebuild (the old way: an altar is needed)");
    write_way();  // (0.15.461)
    emf::on_tick([](emf::World w) {  // the lists of players and the factor, every 15 steps of each world
        g_steps.fetch_add(1);  // the player boxes: once per step
        static uint32_t steps_server = 0, steps_client = 0;
        // (0.15.453, #7) the positions of the players Free build is on for, every step, here on the world's own thread
        {
            const bool server = w.is_server();
            std::vector<uint32_t> ids;
            {
                std::lock_guard<std::mutex> lk(g_mx);
                if (server) ids.assign(g_free_server.begin(), g_free_server.end());
                else if (w.is_client()) {
                    const uint32_t me = emf::local_player();
                    if (me && g_free_client.count(me)) ids.push_back(me);
                }
            }
            const uint64_t side_bit = uint64_t(server ? 1 : 0) << 32;
            std::lock_guard<std::mutex> lk(g_pos_mx);
            for (auto it = g_pos.begin(); it != g_pos.end();) {  // players no longer on the list
                if ((it->first >> 32) == (side_bit >> 32) && std::find(ids.begin(), ids.end(), uint32_t(it->first)) == ids.end()) it = g_pos.erase(it);
                else ++it;
            }
            for (uint32_t id : ids) {
                // (0.15.464) the player's position while a building item is selected; nothing (no box) otherwise
                bool aiming = false;
                Pos aim{};
                const auto* nc = w.get<gen::ecs::NetworkCursor>(id);
                if (nc && nc->currentBuildingItemId.value != 0) {
                    if (auto* ct = w.get<gen::ecs::CurrentTransform>(id)) {
                        const auto& p = ct->transform.position;
                        aim = Pos{p.x, p.y, p.z};
                        aiming = true;
                    }
                }
                {
                    static std::unordered_map<uint64_t, bool> said;  // (side, player) -> a building item selected, logged on change
                    static std::mutex said_mx;
                    std::lock_guard<std::mutex> slk(said_mx);
                    auto it = said.find(side_bit | id);
                    if (it == said.end() || it->second != aiming) {
                        said[side_bit | id] = aiming;
                        if (aiming)
                            EMF_LOG(kMod, "free build (%s): player %u has a building item selected: a %.0f m Free build area around them",
                                    server ? "server" : "this game", id, g_aim_half.load() * 2);
                        else
                            EMF_LOG(kMod, "free build (%s): player %u has no building item selected: no Free build area",
                                    server ? "server" : "this game", id);
                    }
                }
                if (aiming) g_pos[side_bit | id] = aim;
                else g_pos.erase(side_bit | id);
            }
        }
        if (w.is_server() || w.is_client()) {  // (0.15.459, probe) once more 10 s into the running world: the steady order
            static uint32_t probe_steps = 0;
            if (++probe_steps == 1200) {
                EMF_LOG(kMod, "free build probe: again, 10 s into the running world(s)");
                g_said_cs = 0, g_said_cc = 0, g_said_as = 0, g_said_ac = 0, g_said_zone = 0;
            }
        }
        if (w.is_server()) {
            speed_tick();  // (0.15.466)
            if (steps_server++ % 15 == 0) {
                read_test_size();  // (0.15.466)
                read_test_base();  // (0.15.470)
                read_list(L"free_build_server.txt", g_free_server, g_alt_server, "server");
                read_spots("server");
                read_factor(L"altar_size_server.txt", "server", kMaxFactor);
                if (void* bzs = w.singleton("BuildZoneSystem")) write_altar_areas(bzs);  // (0.15.443)
            }
        } else if (w.is_client()) {
            if (steps_client++ % 15 == 0) {
                read_list(L"free_build_client.txt", g_free_client, g_alt_client, "this game");
                if (!emf::server_world()) read_factor(L"altar_size_client.txt", "this game");  // a hosting game: the server's file counts
            }
        }
    });
    emf::add_command("fkbuild", " stats | free on|off | altar on|off | clear on|off | size <m>|off: Free build and the bigger altar areas (debug)",
                     [](emf::World, const std::vector<std::string>& args) {
        std::string all;  // (0.15.416) the words however EMF splits them
        for (const auto& x : args) all += " " + x;
        all += " ";
        if (all.find(" free on ") != std::string::npos) g_free_on = true;
        if (all.find(" free off ") != std::string::npos) g_free_on = false;
        if (all.find(" altar on ") != std::string::npos) g_altar_on = true;
        if (all.find(" altar off ") != std::string::npos) g_altar_on = false;
        if (all.find(" clear on ") != std::string::npos) g_clear_path = true;    // (0.15.460)
        if (all.find(" clear off ") != std::string::npos) g_clear_path = false;
        write_way();  // (0.15.461)
        {  // (0.15.466) the test size: written to free_build_test_size.txt, read by read_test_size on the server's steps
            const size_t at = all.find(" size ");
            if (at != std::string::npos) {
                const std::string v = all.substr(at + 6);
                const std::wstring file = lua_file(L"free_build_test_size.txt");
                const double m = atof(v.c_str());
                if (v.rfind("off", 0) == 0 || m == kAimHalf * 2) {
                    DeleteFileW(file.c_str());
                    EMF_REPLY("free build test size off: the area goes back to the normal %.0f m within a second", kAimHalf * 2);
                } else if (m >= kTestMinM && m <= kTestMaxM) {
                    if (FILE* f = _wfopen(file.c_str(), L"w")) {
                        fprintf(f, "%.0f\n", m);
                        fclose(f);
                    }
                    EMF_REPLY("free build test size: the server's area becomes %.0f m within a second (normal %.0f m; 'fkbuild size off' to go back)", m, kAimHalf * 2);
                } else {
                    EMF_REPLY("free build test size: give %.0f to %.0f m, or off", kTestMinM, kTestMaxM);
                }
            }
        }
        EMF_LOG(kMod, "fkbuild:%s", all.c_str());
        size_t ns = 0, nc = 0;
        {
            std::lock_guard<std::mutex> lk(g_mx);
            ns = g_free_server.size();
            nc = g_free_client.size();
        }
        EMF_REPLY("free build %s (server list %zu, this game %zu; %llu player box(es) added; zones added %s); bigger altar areas %s (%llu zone(s) made bigger)",
                  g_free_on.load() ? "on" : "off", ns, nc, (unsigned long long)g_boxes.load(),
                  g_clear_path.load() ? "after the list is emptied" : "with the first altar", g_altar_on.load() ? "on" : "off",
                  (unsigned long long)g_altars.load());
    });
    return al;
}
