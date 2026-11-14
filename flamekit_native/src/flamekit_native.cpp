// flamekit_native: FlameKit's native part: the minimap, item details, item icons and updates.
//
// EMF gives a mod text lines and windows, but no way to draw a picture that stays on screen. So this mod draws by
// itself, the simple way: a small window of its own that floats over the game's window. The window is "layered"
// (every pixel has its own transparency), lets every click through to the game, never takes the keyboard, and is
// only shown while the game is the window in front. No game code is hooked for it.
//
// What it draws: a round map of the ground around the player, north at the top, painted from the game's own height
// data (read straight from the game's data files), and an arrow for the way the player faces.
//
// Threads: EMF calls on_tick on the game's world thread; that only copies the player's position and facing into
// atomics. A thread of this mod owns the overlay window and redraws it about 30 times a second.
#define NOMINMAX
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <share.h>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "emf/emf.hpp"
#include "emf/generated/components.hpp"
#include "emf/keys.hpp"

#include "fk_log.hpp"
#include "item_icons.hpp"
#include "web_update.hpp"

#ifndef MOD_ID
#define MOD_ID "flamekit_native"
#endif

namespace gen = emf::gen::ecs;

namespace {
constexpr const char* kMod = MOD_ID;
constexpr const char* kKit = "flamekit";  // the settings live in FlameKit's own mod (one place for the whole kit)
constexpr float kPi = 3.14159265358979f;

// ---- settings (in the flamekit mod's mod.json, group Minimap; changed in EMF's Mods tab) ----

struct Settings {
    bool show = true;
    int size = 300;          // the dial's width and height in pixels
    int margin = 24;         // distance from the game window's edges in pixels
    int corner = 1;          // 0 top right, 1 bottom right, 2 bottom left, 3 top left
    uint32_t toggle_vk = VK_F10;
    uint32_t window_vk = VK_F6;   // opens and closes FlameKit's window (setting window_key)
    int pointer_vk = VK_RMENU;    // held: the pointer for the pinned windows (setting pointer_key)
    uint32_t zoom_in_vk = 0, zoom_out_vk = 0;
    int zoom = 2;            // index into kRanges
    bool markers = true;     // altars and the map markers you have found
    bool water = true;       // the water sources you placed
    bool players = true;     // other players
    bool custom = true;      // the markers the player placed on the map
    bool hidden[64] = {};             // by style: its filter is switched off in the Minimap tab
    bool undiscovered = false;        // also the places the player has not found yet, faded
    bool undiscovered_names = false;  // and their name on the line under the dial when one is nearest (same as above)
    bool clock = true;       // the time of day under the dial
    bool big_text = false;   // dials bigger than Large magnify the map, its symbols and its letters (off: they show more of the world)
    bool altitude = true;    // how high the player is, in metres, at the end of the clock's line
    bool where = true;       // the region and the place the player is in, under the clock
    bool labels = true;      // names under the markers at the closer zoom steps
    bool hide_menus = true;  // hidden while the game shows its mouse pointer (the big map, the bag, any menu)
    bool move = false;       // being moved: shown in menus too, and the mouse can drag it
    int pos_x = -1, pos_y = -1;  // where the player dragged it: thousandths of the free width and height; -1: the corner
};
constexpr float kRanges[] = {50, 80, 120, 200, 350, 600, 1000};  // metres from the middle to the rim, per zoom step
constexpr int kRangeCount = 7;
std::mutex g_settings_lock;
Settings g_settings;

void read_filters(Settings& s);  // below, with the list of marker styles

// The height of the minimap's letters for a dial `n` pixels wide. They grow with the dial up to the Large size (300)
// and stay there on bigger dials, where bigger letters only take room; `big_text` lets them keep growing.
int letter_px(const Settings& s, int n) {
    const int px = std::max(12, n / 14);
    return s.big_text ? px : std::min(px, 21);
}

Settings settings() {
    std::lock_guard<std::mutex> l(g_settings_lock);
    return g_settings;
}

void read_settings() {
    Settings s;
    s.show = emf::setting_bool(kKit, "map_show", true);
    s.size = static_cast<int>(emf::setting_float(kKit, "map_size", 300.0));
    s.size = std::clamp(s.size, 100, 600);
    s.margin = std::clamp(static_cast<int>(emf::setting_float(kKit, "map_margin", 24.0)), 0, 400);
    const std::string corner = emf::setting_text(kKit, "map_corner", "bottom_right");
    s.corner = corner == "top_right" ? 0 : corner == "bottom_left" ? 2 : corner == "top_left" ? 3 : 1;
    const std::string key = emf::setting_text(kKit, "map_toggle_key", "F10");
    s.toggle_vk = key.empty() ? 0 : emf::keys::parse_key(std::wstring(key.begin(), key.end()));
    const std::string zin = emf::setting_text(kKit, "map_zoom_in_key", "NumpadAdd");
    s.zoom_in_vk = zin.empty() ? 0 : emf::keys::parse_key(std::wstring(zin.begin(), zin.end()));
    const std::string zout = emf::setting_text(kKit, "map_zoom_out_key", "NumpadSubtract");
    s.zoom_out_vk = zout.empty() ? 0 : emf::keys::parse_key(std::wstring(zout.begin(), zout.end()));
    s.zoom = std::clamp(static_cast<int>(emf::setting_float(kKit, "map_zoom", 2.0) + 0.5), 0, kRangeCount - 1);
    const std::string wkey = emf::setting_text(kKit, "window_key", "F6");
    s.window_vk = wkey.empty() ? 0 : emf::keys::parse_key(std::wstring(wkey.begin(), wkey.end()));
    const std::string pkey = emf::setting_text(kKit, "pointer_key", "right_alt");
    s.pointer_vk = pkey == "caps_lock" ? VK_CAPITAL : pkey == "right_ctrl" ? VK_RCONTROL : VK_RMENU;
    s.markers = true;  // its own switch is gone: the marker filters (map_hide) decide
    s.water = true;  // its own switch is gone: the marker filters (map_hide) decide
    s.players = emf::setting_bool(kKit, "map_players", true);
    s.custom = true;  // its own switch is gone: the marker filters (map_hide) decide
    s.undiscovered = emf::setting_bool(kKit, "map_undiscovered", false);
    read_filters(s);
    s.undiscovered_names = s.undiscovered;  // their names follow "names under the markers", like every other marker's
    s.clock = emf::setting_bool(kKit, "map_clock", true);
    s.altitude = emf::setting_bool(kKit, "map_altitude", true);
    s.big_text = emf::setting_bool(kKit, "map_big_text", false);
    s.where = emf::setting_bool(kKit, "map_where", true);
    s.labels = emf::setting_bool(kKit, "map_labels", true);
    s.hide_menus = emf::setting_bool(kKit, "map_hide_in_menus", true);
    s.move = false;  // set by the UI thread while the pointer is out (the setting map_move is gone since 0.15.34)
    s.pos_x = static_cast<int>(emf::setting_float(kKit, "map_x", -1.0));
    s.pos_y = static_cast<int>(emf::setting_float(kKit, "map_y", -1.0));
    std::lock_guard<std::mutex> l(g_settings_lock);
    g_settings = s;
}

// ---- what the world thread tells the overlay thread ----

std::atomic<float> g_x{0}, g_z{0};        // the player's place in metres (x east, z north)
std::atomic<float> g_y{0};                // how high the player is, in metres
std::atomic<bool> g_travelling{false};    // a fast travel's loading screen is (very likely) up: the minimap hides
std::atomic<float> g_heading{0};          // radians, clockwise from north
std::atomic<uint64_t> g_seen{0};          // GetTickCount64 of the last update; old = no world

double meters(int64_t fixed) { return static_cast<double>(fixed) / 4294967296.0; }  // 1 m = 2^32

// What is drawn on top of the ground. kind: the marker's row in kStyles. state: the game's visibility (2 visible,
// 3 completed).
struct Marker {
    float x, z;
    uint8_t kind, state;
    std::string name;  // the name a player gave it, when the game has one
};
struct Other {  // another player
    float x, z;
    std::string name;
};
struct Ping {
    float x, z;
    uint64_t at;  // GetTickCount64 when it was seen
};
struct Shared {
    std::mutex lock;
    std::vector<Marker> markers;
    std::vector<Other> players;
    std::vector<Ping> pings;
    bool waypoint = false;
    float wx = 0, wz = 0;
    float time_of_day = -1;  // hours, -1 not known
    bool is_day = true;
    float minutes_left = -1;  // real minutes until night (by day) or day (by night); -1 not known
    std::vector<uint32_t> announced;  // the ids of the places the game announced, oldest first (from its events)
    std::string region, place;        // where the player is: the region, and the named place inside it if any
    struct Spire {
        float x, z;
        std::string region;
    };
    std::vector<Spire> spires;        // every Ancient Spire known, with its region's name (for region_at)
};
Shared g_shared;

// The party window and the minimap (both on the UI thread): the player followed on the minimap (clicked in the party
// window; "" none), and the players whose health is 0.
std::string g_tracked;
std::unordered_set<std::string> g_down;

// The region at a place (x east, z north, in metres): the one of the nearest Ancient Spire, the same rule as for the
// player's own region on the minimap. Empty when no spire is known yet.
std::string region_at(float x, float z) {
    std::lock_guard<std::mutex> l(g_shared.lock);
    const Shared::Spire* best = nullptr;
    float best_d = 0;
    for (const Shared::Spire& sp : g_shared.spires) {
        const float d = (sp.x - x) * (sp.x - x) + (sp.z - z) * (sp.z - z);
        if (!best || d < best_d) best = &sp, best_d = d;
    }
    return best ? best->region : std::string();
}

// The game's own name for the place whose name tag has this id (see Loca below); false when it is not known.
bool place_name(uint32_t id, std::string& out);

// The game's marker types (its map marker registry, read with a probe on 2026-11-11, game build 1287369). `label` is this mod's own short name for it; the shapes and colours are this
// mod's own, grouped like the game's map filter: flame things gold and orange, dungeons purple and red, places
// cream, green and brown.
enum Shape : uint8_t { kAltar, kDrop, kDiamond, kSquare, kDisc, kTriangle, kTower, kHouse, kRing };
struct Style {
    uint32_t id;         // the game's number for the type: FNV-1a of the 16 bytes of the type id its markers carry
    const char* label;
    Shape shape;
    uint8_t r, g, b;     // the fill
    uint8_t r2, g2, b2;  // the mark in its middle
    float size;          // in symbol units
    uint8_t show;        // 0: once the player has found it; 1: also when the game keeps no "found" state for it; 2: always
    bool custom;         // a marker the player placed: the icon sits on a dark disc
};
constexpr Style kStyles[] = {
    {2756168611u, "Flame Altar", kAltar, 250, 196, 60, 226, 92, 30, 1.0f, 1, false},  // 658ad7a1-2821-4c8b-a908-c2f2f93fd96f
    {2167439548u, "Flame Altar", kAltar, 250, 196, 60, 226, 92, 30, 1.0f, 1, false},  // 65ac1a61-2153-4d55-9fcf-a9994f35c2a7
    {1116990181u, "", kDrop, 96, 176, 244, 96, 176, 244, 1.0f, 1, false},  // 6581fe05-f752-4b40-9de1-2c647c451406
    {2708501182u, "Ancient Spire", kTower, 250, 196, 60, 120, 70, 20, 1.0f, 0, false},  // 2bad3206-cad7-469a-a358-64ea99181416
    {2561857117u, "Ancient Spire", kTower, 150, 150, 156, 70, 70, 76, 1.0f, 0, false},  // cf788a1f-0f2a-464d-903d-51eca6186ee2
    {278227022u, "Travel Point", kRing, 250, 196, 60, 40, 26, 10, 0.8f, 0, false},  // 5ebdad4b-08b6-4578-8d63-fe9917449eaf
    {2068618774u, "Flame Shrine", kDisc, 240, 130, 40, 255, 226, 120, 0.62f, 0, false},  // d486f2ce-66a3-4ef4-86a4-bf2ea9a24373
    {1844990217u, "Flame Sanctum", kSquare, 250, 196, 60, 40, 60, 130, 0.78f, 0, false},  // aee9062f-4642-438e-a743-1cb156b5673a
    {4099254117u, "Gem Forge", kSquare, 236, 120, 44, 60, 24, 10, 0.72f, 0, false},  // 2db08430-3cb3-4962-bda4-ac6d2e57654b
    {2909445535u, "Obelisk", kTriangle, 250, 196, 60, 120, 70, 20, 0.8f, 0, false},  // 643190e1-b5cf-44a2-8001-7508ea877847
    {4293256260u, "Elixir Well", kDiamond, 160, 96, 204, 236, 214, 250, 0.85f, 0, false},  // 8cc3aae1-5041-462d-a03d-bb81cef9c611
    {3089427013u, "Dungeon", kSquare, 150, 90, 200, 236, 214, 250, 0.74f, 0, false},  // f6889e13-fe04-4a7f-99d2-b02195d7e888
    {1322152652u, "Hollow Halls", kSquare, 190, 44, 60, 255, 220, 200, 1.0f, 0, false},  // 8d041ba5-4af7-46c4-b76b-3751c8d5a4d8
    {660000613u, "Shroud Nest", kDisc, 110, 150, 190, 30, 30, 60, 0.72f, 0, false},  // cbe63957-cac4-48be-a127-8137ff2a9c0e
    {1419656634u, "Vault", kTriangle, 170, 110, 210, 40, 20, 60, 0.8f, 0, false},  // 188d04bd-6710-4fea-b38c-34f0dc42eed6
    {1101555824u, "Tomb", kSquare, 150, 140, 170, 50, 44, 66, 0.72f, 0, false},  // 593043e8-6667-4f5e-94e0-52f6e2807956
    {3050313574u, "Village", kHouse, 226, 216, 186, 90, 70, 50, 0.78f, 0, false},  // 8e313547-131a-46fe-b430-c8d028d52573
    {1359276241u, "Farm", kDisc, 150, 196, 110, 50, 80, 30, 0.62f, 0, false},  // fa92b5da-6559-45d5-a7c0-66e3b5d5a90a
    {3675766579u, "Cave", kDisc, 150, 120, 90, 40, 30, 22, 0.66f, 0, false},  // a9ea4318-7cbc-4804-ad6c-7d7a6e229be5
    {1755200041u, "Mine", kTriangle, 170, 170, 176, 60, 60, 66, 0.72f, 0, false},  // 9bdc9998-a8a4-4ede-979d-9a815e106df0
    {1789853740u, "Camp", kTriangle, 226, 216, 186, 90, 70, 50, 0.72f, 0, false},  // c85fd053-92c1-4827-9aff-d8f0dfe73977
    {2704970124u, "Enemy Camp", kTriangle, 226, 80, 64, 60, 14, 10, 0.78f, 0, false},  // fe05bfcd-bd2b-4761-923f-a00e5abd2579
    {2671522318u, "Balefire", kTriangle, 244, 150, 50, 90, 40, 10, 0.72f, 0, false},  // 073adc32-ceee-488a-9321-1d69c78418bb
    {450427246u, "Grave", kDisc, 226, 60, 50, 60, 10, 10, 0.9f, 2, false},  // mapmarker_player_corpse
    {1784071603u, "Flame Altar", kAltar, 250, 196, 60, 60, 160, 60, 1.0f, 1, false},  // mapmarker_spawn_flame_altar
    {3450519378u, "Base", kHouse, 240, 240, 244, 60, 60, 66, 0.8f, 1, false},  // marker_home_base
    {3308163813u, "Quest", kDiamond, 250, 226, 70, 90, 70, 10, 0.8f, 1, false},  // mapmarker_quest
    {2815089672u, "Quest", kDiamond, 250, 150, 40, 90, 40, 10, 0.9f, 1, false},  // mapmarker_questImportant
    {1589260420u, "", kRing, 226, 216, 186, 40, 44, 52, 0.8f, 1, true},  // icon_goal
    {980816720u, "", kRing, 226, 216, 186, 40, 44, 52, 0.8f, 1, true},  // icon_chest
    {1896031902u, "", kRing, 226, 216, 186, 40, 44, 52, 0.8f, 1, true},  // icon_glider
    {2714037481u, "", kRing, 226, 216, 186, 40, 44, 52, 0.8f, 1, true},  // icon_loot
    {3652295404u, "", kRing, 226, 216, 186, 40, 44, 52, 0.8f, 1, true},  // icon_plants
    {681966380u, "", kRing, 226, 216, 186, 40, 44, 52, 0.8f, 1, true},  // icon_wildlife
    {498680621u, "", kRing, 226, 216, 186, 40, 44, 52, 0.8f, 1, true},  // icon_water
    {4264546349u, "", kRing, 226, 216, 186, 40, 44, 52, 0.8f, 1, true},  // icon_fish
    {4004551358u, "", kRing, 226, 216, 186, 40, 44, 52, 0.8f, 1, true},  // icon_ore
    {241522943u, "", kRing, 226, 216, 186, 40, 44, 52, 0.8f, 1, true},  // icon_combat
};
constexpr int kStyleCount = static_cast<int>(sizeof(kStyles) / sizeof(kStyles[0]));
constexpr int kWaterStyle = 2;
constexpr int kQuestStyle = 26;  // the game's quest mark (mapmarker_quest)
static_assert(kStyles[kQuestStyle].id == 3308163813u, "kQuestStyle is the quest marker's row");

// The filter each style belongs to: its short name in the setting map_hide (a list of the names that are hidden,
// with commas between). The Minimap tab of the panel (features/minimap.lua) has the same names.
constexpr const char* kFilter[] = {
    "al", "al", "wa", "sp", "sp", "tp", "fs", "sa", "sf", "ob", "sr", "ew", "hh", "sn", "va", "to", "vi", "fa", "ca", "mi",
    "cp", "ec", "ba", "gr", "al", "hb", "qu", "qu", "m0", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9",
};
static_assert(sizeof(kFilter) / sizeof(kFilter[0]) == sizeof(kStyles) / sizeof(kStyles[0]), "one filter name per style");

void read_filters(Settings& s) {
    const std::string hide = "," + emf::setting_text(kKit, "map_hide", "") + ",";
    for (int i = 0; i < kStyleCount && i < 64; ++i)
        s.hidden[i] = hide.find(std::string(",") + kFilter[i] + ",") != std::string::npos;
}

// Other players at any distance. The game tells a player's game only about the players near it; FlameKit's half on the
// world's host sends everyone's place, and the Lua part writes it to emf\mods\flamekit\far_players.dat: a line with
// a number that goes up with every list, then a line "x z name" per player. Read here a few times a second; a list
// that stops changing (no FlameKit on this server, or it stopped) is dropped after four seconds.
struct FarPlayers {
    std::wstring path;
    std::vector<Other> list;
    std::string seq;
    uint64_t changed = 0, looked = 0;

    // Adds the far players that `players` (the ones this game knows itself, by name) does not have yet.
    void add_to(std::vector<Other>& players, uint64_t now) {
        if (path.empty()) {
            wchar_t exe[MAX_PATH];
            const DWORD n = GetModuleFileNameW(nullptr, exe, MAX_PATH);
            std::wstring dir(exe, n);
            const size_t slash = dir.find_last_of(L"\\/");
            path = (slash == std::wstring::npos ? std::wstring() : dir.substr(0, slash + 1)) + L"emf\\mods\\flamekit\\far_players.dat";
        }
        if (now - looked > 300) {
            looked = now;
            if (FILE* f = _wfsopen(path.c_str(), L"rb", _SH_DENYNO)) {
                char buf[8192];
                const size_t got = fread(buf, 1, sizeof buf - 1, f);
                fclose(f);
                buf[got] = 0;
                const char* p = buf;
                const char* eol = std::strchr(p, '\n');
                std::string first = eol ? std::string(p, eol) : std::string(p);
                while (!first.empty() && first.back() == '\r') first.pop_back();
                if (!first.empty() && first != seq) {  // a new list
                    seq = first;
                    changed = now;
                    list.clear();
                    while (eol && list.size() < 64) {
                        p = eol + 1;
                        eol = std::strchr(p, '\n');
                        std::string line = eol ? std::string(p, eol) : std::string(p);
                        while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
                        char* after_x = nullptr;
                        char* after_z = nullptr;
                        const float x = std::strtof(line.c_str(), &after_x);
                        if (after_x == line.c_str()) continue;
                        const float z = std::strtof(after_x, &after_z);
                        if (after_z == after_x || x < 0 || x > 10240 || z < 0 || z > 10240) continue;
                        while (*after_z == ' ') ++after_z;
                        list.push_back({x, z, std::string(after_z)});
                    }
                }
            }
        }
        if (now - changed > 4000) return;  // no fresh list: only the players this game knows itself
        // A joined game knows the players near it but not their names (the game keeps those where the world is
        // hosted): a nameless one gets the name of the list's nearest player, when that one is close by.
        for (Other& near_one : players) {
            if (!near_one.name.empty()) continue;
            float best = 30.0f * 30.0f;
            for (const Other& far_one : list) {
                const float dx = near_one.x - far_one.x, dz = near_one.z - far_one.z;
                if (dx * dx + dz * dz < best) {
                    best = dx * dx + dz * dz;
                    near_one.name = far_one.name;
                }
            }
        }
        for (const Other& far_one : list) {
            bool known = false;
            for (const Other& near_one : players) {  // the same player: the same name, or standing in the same place
                const float dx = near_one.x - far_one.x, dz = near_one.z - far_one.z;
                known = known || near_one.name == far_one.name || dx * dx + dz * dz < 30.0f * 30.0f;
            }
            if (!known) players.push_back(far_one);
        }
    }
};
FarPlayers g_far_players;

// The clock: the game's day and night object (EMF's docs: g38_daytime::Daytime). All times in nanoseconds.
void read_clock(emf::World w, float& hours, bool& is_day, float& minutes_left) {
    hours = -1;
    minutes_left = -1;
    const auto* d = static_cast<const uint8_t*>(w.singleton("g38_daytime::Daytime"));
    if (!d) return;
    auto at = [&](size_t offset) {
        int64_t v = 0;
        std::memcpy(&v, d + offset, sizeof v);
        return v;
    };
    const int64_t day = 24ll * 3600ll * 1000000000ll;
    const int64_t day_start = at(0x28), night_start = at(0x30), day_real = at(0x38), night_real = at(0x40), now = at(0x48);
    if (now < 0 || now >= day) return;
    hours = static_cast<float>(static_cast<double>(now) / 3600e9);
    const bool sane = day_start >= 0 && day_start < night_start && night_start < day && day_real > 10000000000ll &&
                      day_real < 36000000000000ll && night_real > 10000000000ll && night_real < 36000000000000ll;
    is_day = sane ? (now >= day_start && now < night_start) : (hours >= 6 && hours < 18);
    static bool said = false;
    if (!said) {
        said = true;
        FK_LOG(fklog::kInfo, "minimap: clock: day starts %.2f h, night starts %.2f h, a day lasts %.1f min, a night %.1f min (%s)",
                day_start / 3600e9, night_start / 3600e9, day_real / 60e9, night_real / 60e9, sane ? "used" : "not used");
    }
    if (!sane) return;
    if (is_day) {
        minutes_left = static_cast<float>(static_cast<double>(night_start - now) / static_cast<double>(night_start - day_start) *
                                          (day_real / 60e9));
    } else {
        const int64_t to_go = now < day_start ? day_start - now : day - now + day_start;
        minutes_left = static_cast<float>(static_cast<double>(to_go) / static_cast<double>(day - (night_start - day_start)) *
                                          (night_real / 60e9));
    }
}

// ---- what the game keeps outside its entities: the player's own map markers and the names players gave things ----
//
// Both live in objects of the client world whose layout EMF's docs do not cover; they were worked out from the running
// game (build 1287369, 2026-11-11). Every read goes through ReadProcessMemory, which fails instead of crashing when
// the memory is not there, and every value is checked; when a check fails the minimap simply shows none of them.
bool peek(uint64_t at, void* into, size_t bytes) {
    SIZE_T got = 0;
    return at > 0x10000 && ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<LPCVOID>(at), into, bytes, &got) && got == bytes;
}

// The names players gave to flame altars, chests and so on: "CustomPlayerStringsSystem" has a pool of entries of
// 0x140 bytes (key at +0x10, a pointer to the text at +0x18 that points at the entry's own +0x38, length at +0x20);
// the pool's size is the u32 at +0x1e0 and its address the pointer at +0x1e8. The game only has the names of things
// near the player, so the ones seen are remembered until the game closes.
void read_custom_names(emf::World w, std::unordered_map<uint64_t, std::string>& names) {
    const uint64_t sys = reinterpret_cast<uint64_t>(w.singleton("CustomPlayerStringsSystem"));
    uint32_t capacity = 0;
    uint64_t pool = 0;
    if (!sys || !peek(sys + 0x1e0, &capacity, 4) || !peek(sys + 0x1e8, &pool, 8)) return;
    if (capacity == 0 || capacity > 8192 || pool < sys || pool > sys + 0x4000) return;
    std::vector<uint8_t> all(static_cast<size_t>(capacity) * 0x140);
    if (!peek(pool, all.data(), all.size())) return;
    for (uint32_t i = 0; i < capacity; ++i) {
        const uint8_t* e = &all[static_cast<size_t>(i) * 0x140];
        uint64_t key, text, length;
        std::memcpy(&key, e + 0x10, 8);
        std::memcpy(&text, e + 0x18, 8);
        std::memcpy(&length, e + 0x20, 8);
        if (!key || text != pool + static_cast<uint64_t>(i) * 0x140 + 0x38 || length == 0 || length > 0x100) continue;
        names[key].assign(reinterpret_cast<const char*>(e + 0x38), static_cast<size_t>(length));
    }
}

// The markers a quest points at. On its map the game draws those with its quest mark ("!") in place of their own icon.
// It keeps the list in its UI data (the client world's "G38UiPlayData"): 8 places of 0x50 bytes from +0x34ef8, each
// with three numbers that name the quest's step and, at +0x10, the number of the marker it points at (FNV-1a of the
// marker's id; 0: none). Found by looking at the game's memory (build 1287369); a game update can move it. Before it
// is believed, the 8 that stands in front of the list is checked: when that is not there, no marker gets the mark.
std::vector<uint32_t> quest_marks(emf::World w) {
    std::vector<uint32_t> out;
    const uint64_t ui = reinterpret_cast<uint64_t>(w.singleton("G38UiPlayData"));
    if (!ui) return out;
    constexpr uint64_t kHead = 0x34ee0, kFirst = 0x34ef8, kEach = 0x50;
    uint64_t places = 0;
    static bool said = false;
    if (!peek(ui + kHead, &places, 8) || places != 8) {
        if (!said) {
            said = true;
            FK_LOG(fklog::kWarn, "quest marks: the game's list is not where it was (found %llu, wanted 8): markers keep their own icons",
                    static_cast<unsigned long long>(places));
        }
        return out;
    }
    uint8_t all[8 * kEach];
    if (!peek(ui + kFirst, all, sizeof all)) return out;
    for (int i = 0; i < 8; ++i) {
        uint32_t step = 0, marker = 0;
        std::memcpy(&step, all + i * kEach, 4);
        std::memcpy(&marker, all + i * kEach + 0x10, 4);
        if (step && marker) out.push_back(marker);
    }
    return out;
}

// ---- item icons for FlameKit's panel ----
// The panel (Lua) lists the items it wants a picture of in emf\mods\flamekit\icon_requests.txt (an item id in hex per
// line). A thread here reads each one's icon from the game's data files (item_icons.hpp), lays it over the colour of
// the item's rarity, as the game's bag does, and saves it as emf\mods\flamekit\icons\<id>.png, where the panel finds
// it. A picture is made once and kept until the game's data files change (icons\stamp.txt).
struct ItemMeta {
    uint8_t guid[16];
    uint8_t rarity;
};
std::mutex g_item_meta_lock;
std::unordered_map<uint32_t, ItemMeta> g_item_meta;  // filled once, when the item details are written
std::atomic<bool> g_icon_thread{false};
std::atomic<bool> g_ui_request{false};  // F6 was pressed: FlameKit's own UI (ui_thread)

void item_icon_thread() {
    constexpr int kSide = 64;
    static const uint8_t kRarity[5][3] = {{138, 134, 126}, {95, 211, 95}, {79, 163, 255}, {181, 107, 255}, {255, 180, 60}};
    wchar_t exe[MAX_PATH];
    const DWORD n = GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring game(exe, n);
    const size_t slash = game.find_last_of(L"\\/");
    game = slash == std::wstring::npos ? std::wstring() : game.substr(0, slash + 1);
    const std::wstring kit = game + L"emf\\mods\\flamekit\\", dir = kit + L"icons\\";
    CreateDirectoryW(dir.c_str(), nullptr);

    // the game's data files changed (an update): the pictures made from the old ones go
    WIN32_FILE_ATTRIBUTE_DATA info{};
    char stamp[64] = "";
    if (GetFileAttributesExW((game + L"enshrouded.kfc").c_str(), GetFileExInfoStandard, &info))
        snprintf(stamp, sizeof stamp, "%lu %lu %lu", info.nFileSizeLow, info.ftLastWriteTime.dwHighDateTime, info.ftLastWriteTime.dwLowDateTime);
    char had[64] = "";
    if (FILE* f = _wfsopen((dir + L"stamp.txt").c_str(), L"rb", _SH_DENYNO)) {
        const size_t got = fread(had, 1, sizeof had - 1, f);
        had[got] = 0;
        fclose(f);
    }
    if (std::strcmp(stamp, had) != 0) {
        WIN32_FIND_DATAW found;
        const HANDLE h = FindFirstFileW((dir + L"*.png").c_str(), &found);
        if (h != INVALID_HANDLE_VALUE) {
            do DeleteFileW((dir + found.cFileName).c_str());
            while (FindNextFileW(h, &found));
            FindClose(h);
        }
        if (FILE* f = _wfsopen((dir + L"stamp.txt").c_str(), L"wb", _SH_DENYNO)) {
            fwrite(stamp, 1, std::strlen(stamp), f);
            fclose(f);
        }
    }

    static std::wstring game_dir;
    game_dir = game;
    ItemIcons icons;
    icons.open = [](const char* name, void*) {
        std::wstring wide(name, name + std::strlen(name));
        return _wfsopen((game_dir + wide).c_str(), L"rb", _SH_DENYNO);
    };
    std::unordered_set<uint32_t> done;
    uint64_t seen = 0;
    int made = 0, failed = 0;
    for (;;) {
        Sleep(400);
        WIN32_FILE_ATTRIBUTE_DATA req{};
        if (!GetFileAttributesExW((kit + L"icon_requests.txt").c_str(), GetFileExInfoStandard, &req)) continue;
        const uint64_t now = (static_cast<uint64_t>(req.ftLastWriteTime.dwHighDateTime) << 32 | req.ftLastWriteTime.dwLowDateTime) ^ req.nFileSizeLow;
        if (now == seen) continue;
        seen = now;
        std::string text;
        if (FILE* f = _wfsopen((kit + L"icon_requests.txt").c_str(), L"rb", _SH_DENYNO)) {
            char buf[16384];
            const size_t got = fread(buf, 1, sizeof buf, f);
            fclose(f);
            text.assign(buf, got);
        }
        for (size_t at = 0; at < text.size();) {
            size_t end = text.find('\n', at);
            if (end == std::string::npos) end = text.size();
            char* stop = nullptr;
            const uint32_t id = static_cast<uint32_t>(std::strtoul(text.substr(at, end - at).c_str(), &stop, 16));
            at = end + 1;
            if (id == 0 || !done.insert(id).second) continue;
            wchar_t name[32];
            swprintf(name, 32, L"%08x.png", id);
            if (GetFileAttributesW((dir + name).c_str()) != INVALID_FILE_ATTRIBUTES) continue;  // made on an earlier day
            ItemMeta meta;
            {
                std::lock_guard<std::mutex> l(g_item_meta_lock);
                const auto it = g_item_meta.find(id);
                if (it == g_item_meta.end()) continue;
                meta = it->second;
            }
            std::vector<uint8_t> icon;
            if (!icons.icon(meta.guid, kSide, icon)) {
                if (++failed == 1) FK_LOG(fklog::kInfo, "item icons: no picture for item %08x (%s)", id, icons.note.empty() ? "not as expected" : icons.note.c_str());
                continue;
            }
            // over the rarity's colour, lighter at the top
            const uint8_t* c = kRarity[meta.rarity < 5 ? meta.rarity : 0];
            for (int y = 0; y < kSide; ++y) {
                const float shade = 0.62f - 0.34f * static_cast<float>(y) / (kSide - 1);
                for (int x = 0; x < kSide; ++x) {
                    uint8_t* p = &icon[(static_cast<size_t>(y) * kSide + x) * 4];
                    const float a = p[3] / 255.0f;
                    for (int k = 0; k < 3; ++k) p[k] = static_cast<uint8_t>(p[k] * a + c[k] * shade * (1.0f - a) + 0.5f);
                    p[3] = 255;
                }
            }
            const std::vector<uint8_t> file = ItemIcons::png(icon, kSide, kSide);
            const std::wstring tmp = dir + name + L".tmp";
            if (FILE* f = _wfsopen(tmp.c_str(), L"wb", _SH_DENYNO)) {
                fwrite(file.data(), 1, file.size(), f);
                fclose(f);
                if (MoveFileExW(tmp.c_str(), (dir + name).c_str(), MOVEFILE_REPLACE_EXISTING) && ++made == 1)
                    FK_LOG(fklog::kInfo, "item icons: the first picture is made (item %08x)", id);
            }
        }
    }
}

void on_world_tick(emf::World w) {
    if (!w.is_client()) return;
    const Settings s = settings();
    static emf::keys::Edge toggle;
    if (toggle.pressed(emf::keys::down(s.toggle_vk))) emf::set_setting(kKit, "map_show", s.show ? "0" : "1");
    static emf::keys::Edge zoom_in, zoom_out;
    if (s.zoom_in_vk && zoom_in.pressed(emf::keys::down(s.zoom_in_vk)) && s.zoom > 0)
        emf::set_setting(kKit, "map_zoom", std::to_string(s.zoom - 1).c_str());
    if (s.zoom_out_vk && zoom_out.pressed(emf::keys::down(s.zoom_out_vk)) && s.zoom < kRangeCount - 1)
        emf::set_setting(kKit, "map_zoom", std::to_string(s.zoom + 1).c_str());

    static emf::keys::Edge ui_key;  // FlameKit's own UI (ui_thread)
    if (ui_key.pressed(emf::keys::down(s.window_vk))) g_ui_request = true;
    const auto* t = w.get<gen::CurrentTransform>(emf::local_player());
    if (!t) return;
    // Item details for FlameKit's panel (a Lua mod cannot read the game's item definitions): once per game start,
    // every item's rarity, level and type go into emf\\mods\\flamekit\\item_details.dat, a line "id rarity level_min
    // level_max category sub_category" per item (the id in hex). Read from the game's own ItemInfo (2088 bytes in
    // build 1287369: +0x17 rarity, +0xcc category, +0xcd its sub-category, +0x674 and +0x678 the level range); with
    // another size nothing is written and the panel shows what it knows itself.
    {
        static bool written = false;
        if (!written) {
            written = true;
            wchar_t exe[MAX_PATH];
            const DWORD n = GetModuleFileNameW(nullptr, exe, MAX_PATH);
            std::wstring dir(exe, n);
            const size_t slash = dir.find_last_of(L"\\/");
            const std::wstring path = (slash == std::wstring::npos ? std::wstring() : dir.substr(0, slash + 1)) + L"emf\\mods\\flamekit\\item_details.dat";
            std::string text;
            int count = 0, odd = 0;
            emf::for_each_item(w, [&](const EmfItemInfo& i) {
                uint64_t size = 0;
                const auto* data = static_cast<const uint8_t*>(emf::api()->item_data(w.raw(), i.item_id, &size));
                if (!data || size != 2088) return void(++odd);
                uint32_t lo, hi;
                std::memcpy(&lo, data + 0x674, 4);
                std::memcpy(&hi, data + 0x678, 4);
                if (data[0x17] > 4 || lo > 200 || hi > 200) return void(++odd);  // not what these fields hold: leave it out
                {
                    std::lock_guard<std::mutex> l(g_item_meta_lock);
                    ItemMeta& meta = g_item_meta[i.item_id];
                    std::memcpy(meta.guid, i.guid, 16);
                    meta.rarity = data[0x17];
                }
                char line[64];
                snprintf(line, sizeof line, "%08x %u %u %u %u %u\n", i.item_id, data[0x17], lo, hi, data[0xcc], data[0xcd]);
                text += line;
                ++count;
            });
            if (count > 0 && odd * 10 < count) {
                if (FILE* f = _wfsopen(path.c_str(), L"wb", _SH_DENYNO)) {
                    fwrite(text.data(), 1, text.size(), f);
                    fclose(f);
                }
                FK_LOG(fklog::kInfo, "item details: %d items written for the panel (%d left out)", count, odd);
                if (!g_icon_thread.exchange(true)) std::thread(item_icon_thread).detach();
            } else {
                _wremove(path.c_str());
                FK_LOG(fklog::kWarn, "item details: the game's item definitions are not as expected (%d read, %d odd): none written", count, odd);
            }
        }
    }
    const auto& q = t->transform.orientation;
    // the way the player faces: the orientation applied to +z, flattened onto the ground
    const float fx = 2.0f * (q.x * q.z + q.w * q.y);
    const float fz = 1.0f - 2.0f * (q.x * q.x + q.y * q.y);
    g_x.store(static_cast<float>(meters(t->transform.position.x)));
    g_z.store(static_cast<float>(meters(t->transform.position.z)));
    g_y.store(static_cast<float>(meters(t->transform.position.y)));
    if (std::fabs(fx) + std::fabs(fz) > 1e-4f) g_heading.store(std::atan2(fx, fz));
    g_seen.store(GetTickCount64());

    // A fast travel: the game counts the player's teleports (TeleportCount). When the count goes up the game shows its
    // loading screen, and the minimap hides until the player first moves at the new place (nothing the game's data
    // shows marks the end of the loading screen), at least 2 seconds and at most 20.
    {
        static int count = -1;
        static uint64_t since = 0;
        static float from_x = 0, from_z = 0;
        const uint64_t tick = GetTickCount64();
        if (const auto* tc = w.get<gen::TeleportCount>(emf::local_player())) {
            const int c = tc->counter;
            if (count >= 0 && c != count) {
                since = tick;
                g_travelling.store(true);
                FK_LOG(fklog::kInfo, "fast travel: the minimap hides (teleport count %d -> %d)", count, c);
            }
            count = c;
        }
        if (g_travelling.load()) {
            const float x = g_x.load(), z = g_z.load();
            const uint64_t gone = tick - since;
            if (gone < 2000) {  // the arrival: the place the player stands at when the 2 seconds are over
                from_x = x;
                from_z = z;
            } else {
                const bool moved = std::fabs(x - from_x) + std::fabs(z - from_z) > 1.0f;
                if (moved || gone > 20000) {
                    g_travelling.store(false);
                    FK_LOG(fklog::kInfo, "fast travel: the minimap is back after %.1f s (%s)", static_cast<double>(gone) / 1000.0,
                            moved ? "the player moved" : "20 seconds are over");
                }
            }
        }
    }

    // markers and players: a look through every entity every two seconds (they seldom change)
    static std::vector<uint32_t> player_ids;
    static uint64_t scanned = 0, updated = 0;
    const uint64_t now = GetTickCount64();
    if (now - scanned > 2000) {
        scanned = now;
        std::vector<Marker> markers;
        player_ids.clear();
        static std::unordered_map<uint64_t, std::string> names;
        if (s.markers) read_custom_names(w, names);
        const uint32_t me = emf::local_player();
        struct Named {  // a flame altar a player named: the name sits on the altar itself, not on its map marker
            float x, z;
            const std::string* name;
        };
        std::vector<Named> altars;
        // Where the player is. The game has no outlines for its regions (Springlands, Revelwood, ...) that a mod can
        // read, and it announces a region only now and then; each region has one Ancient Spire that carries its name,
        // so the region is taken to be the one of the nearest spire. Under it: the named place the player is inside
        // (the game marks that one), else the nearest named place the player has found.
        static std::unordered_set<uint32_t> place_ids, spire_ids;
        std::string place, nearest_region;
        std::vector<Shared::Spire> spires;
        // a place counts as near while it is on the dial (but at least 150 m, so the closest zoom steps still name things)
        const double reach = std::max(150.0, static_cast<double>(kRanges[s.zoom]));
        double nearest = 1e18, nearest_place = reach * reach;
        auto tag_id = [&](uint32_t id, uint32_t& out) {
            const gen::LocaTagComponent* tag = w.get_template<gen::LocaTagComponent>(id);
            if (!tag) tag = w.get<gen::LocaTagComponent>(id);
            if (!tag) return false;
            out = 0x811c9dc5u;
            for (uint8_t b : tag->locaTag.bytes) out = (out ^ b) * 0x01000193u;
            return true;
        };
        const std::vector<uint32_t> quests = quest_marks(w);
        w.for_each_entity([&](uint32_t id) {
            if (const auto* here = w.get<gen::Location>(id)) {
                uint32_t tid;
                if (tag_id(id, tid)) {
                    // an Ancient Spire carries its region's name: the game announces the region through it
                    bool spire = false, drawn = false;
                    if (const auto* m = w.get<gen::MapMarker>(id)) {
                        uint32_t type = 0x811c9dc5u;
                        for (uint8_t b : m->markerType.bytes) type = (type ^ b) * 0x01000193u;
                        for (int i = 0; i < kStyleCount; ++i)
                            if (kStyles[i].id == type) {
                                drawn = true;
                                spire = kStyles[i].shape == kTower;
                            }
                    }
                    if (spire) {
                        spire_ids.insert(tid);
                        {
                            const auto* rt = w.get<gen::RenderTransform>(id);
                            const auto* ct = rt ? nullptr : w.get<gen::CurrentTransform>(id);
                            const bool placed = rt || ct;
                            if (placed) {
                                std::string name;
                                if (place_name(tid, name))
                                    spires.push_back({static_cast<float>(meters((rt ? rt->transform : ct->transform).position.x)),
                                                      static_cast<float>(meters((rt ? rt->transform : ct->transform).position.z)), std::move(name)});
                            }
                            const double dx = placed ? meters((rt ? rt->transform : ct->transform).position.x) - g_x.load() : 1e9;
                            const double dz = placed ? meters((rt ? rt->transform : ct->transform).position.z) - g_z.load() : 1e9;
                            if (dx * dx + dz * dz < nearest) {
                                std::string name;
                                if (place_name(tid, name)) {
                                    nearest = dx * dx + dz * dz;
                                    nearest_region = name;
                                }
                            }
                        }
                    } else {
                        place_ids.insert(tid);
                        // the named place the player is in, else the nearest one the player has found (a village,
                        // a lake, a pass, a part of a town)
                        const auto* seen = w.get<gen::MapMarkerVisibilityState>(id);
                        const auto* rt = w.get<gen::RenderTransform>(id);
                        const auto* ct = rt ? nullptr : w.get<gen::CurrentTransform>(id);
                        if (here->isInLocation) {
                            if (place_name(tid, place)) nearest_place = -1.0;  // inside: nothing is nearer
                        } else if (seen && (static_cast<int>(seen->visibility) >= 2 || (s.undiscovered && s.undiscovered_names)) && (rt || ct) &&
                                   nearest_place >= 0.0) {
                            const auto& at = (rt ? rt->transform : ct->transform).position;
                            const double dx = meters(at.x) - g_x.load(), dz = meters(at.z) - g_z.load();
                            const double dist2 = dx * dx + dz * dz;
                            std::string name;
                            if (dist2 < nearest_place && place_name(tid, name)) {
                                nearest_place = dist2;
                                place = name;
                            }
                        }
                        (void)drawn;
                    }
                }
            }
            if (s.markers && w.get<gen::ClientBaseIdComponent>(id)) {
                const auto* given = w.get<gen::CustomPlayerString>(id);
                const auto* at = given ? w.get<gen::CurrentTransform>(id) : nullptr;
                const auto found = at ? names.find(given->stringId.value) : names.end();
                if (found != names.end())
                    altars.push_back({static_cast<float>(meters(at->transform.position.x)),
                                      static_cast<float>(meters(at->transform.position.z)), &found->second});
            }
            if (id != me && w.get<gen::NetworkPlayerAttributes>(id)) player_ids.push_back(id);
            if (!s.markers) return;
            const auto* m = w.get<gen::MapMarker>(id);
            if (!m) return;
            uint32_t type = 0x811c9dc5u;  // FNV-1a of the type id's bytes: the number the game's registry knows it by
            for (uint8_t b : m->markerType.bytes) type = (type ^ b) * 0x01000193u;
            int kind = -1;
            for (int i = 0; i < kStyleCount; ++i)
                if (type == kStyles[i].id) {
                    kind = i;
                    break;
                }
            if (kind < 0) return;  // name labels, quest hints and other types this mod does not draw
            bool quest = false;  // a quest points at this marker: drawn as the game's quest mark, like on its map
            if (!quests.empty() && kQuestStyle >= 0 && !s.hidden[kQuestStyle]) {
                uint32_t marker = 0x811c9dc5u;
                for (uint8_t b : m->markerId.bytes) marker = (marker ^ b) * 0x01000193u;
                quest = std::find(quests.begin(), quests.end(), marker) != quests.end();
            }
            if (!quest && (s.hidden[kind] || (kind == kWaterStyle && !s.water))) return;
            const auto* vis = w.get<gen::MapMarkerVisibilityState>(id);
            const int state = vis ? static_cast<int>(vis->visibility) : -1;
            const uint8_t show = kStyles[kind].show;
            if (!quest && !(show == 2 || (vis ? state >= 2 || s.undiscovered : show == 1))) return;  // not found yet (unless asked for)
            const auto* rt = w.get<gen::RenderTransform>(id);
            const auto* ct = rt ? nullptr : w.get<gen::CurrentTransform>(id);
            if (!rt && !ct) return;
            const auto& p = rt ? rt->transform.position : ct->transform.position;
            std::string name;
            // (a type without a label of its own, the water sources, shows no name either: the game gives those names
            // such as "Water Dispenser 1" by itself)
            if (const auto* given = kStyles[kind].label[0] ? w.get<gen::CustomPlayerString>(id) : nullptr) {
                const auto found = names.find(given->stringId.value);
                if (found != names.end()) name = found->second;
            }
            if (name.empty() && kStyles[kind].show == 0) {  // a place the player found: the game's own name for it
                const gen::LocaTagComponent* tag = w.get_template<gen::LocaTagComponent>(id);
                if (!tag) tag = w.get<gen::LocaTagComponent>(id);
                if (tag) {
                    uint32_t tag_id = 0x811c9dc5u;
                    for (uint8_t b : tag->locaTag.bytes) tag_id = (tag_id ^ b) * 0x01000193u;
                    place_name(tag_id, name);
                }
            }
            markers.push_back({static_cast<float>(meters(p.x)), static_cast<float>(meters(p.z)),
                               static_cast<uint8_t>(quest ? kQuestStyle : kind),
                               static_cast<uint8_t>(quest ? 2 : state < 0 ? 2 : state), std::move(name)});
        });
        for (Marker& k : markers) {  // flame altars take the name of the named altar that stands where they are
            if (!k.name.empty() || kStyles[k.kind].shape != kAltar) continue;
            for (const Named& a : altars)
                if (std::fabs(a.x - k.x) < 12.0f && std::fabs(a.z - k.z) < 12.0f) {
                    k.name = *a.name;
                    break;
                }
        }
        for (const Marker& k : markers) {  // flame altars count as places too: by the name a player gave them
            if (kStyles[k.kind].shape != kAltar || nearest_place < 0.0) continue;
            const double dx = k.x - g_x.load(), dz = k.z - g_z.load();
            if (dx * dx + dz * dz < nearest_place) {
                nearest_place = dx * dx + dz * dz;
                place = k.name.empty() ? std::string(kStyles[k.kind].label) : k.name;
            }
        }
        // the player's own markers: "MapMarkerRegistry" has a chain of them: the first at the pointer at +0x40, each
        // 0xc0 bytes: the place at +0x00 (x) and +0x10 (z), the type's number at +0x1c, the name at +0x20 with its
        // length at +0xa0, the next one at +0xb8
        if (s.markers && s.custom) {
            const uint64_t reg = reinterpret_cast<uint64_t>(w.singleton("MapMarkerRegistry"));
            uint64_t node = 0;
            if (reg && peek(reg + 0x40, &node, 8)) {
                uint8_t n[0xc0];
                std::string kinds;  // for the log: the kinds of marker the list holds (said when it changes)
                std::unordered_map<uint32_t, int> tally;
                for (int count = 0; node && count < 512 && peek(node, n, sizeof n); ++count) {
                    int64_t x, z;
                    uint32_t type;
                    uint64_t length, next;
                    std::memcpy(&x, n + 0x00, 8);
                    std::memcpy(&z, n + 0x10, 8);
                    std::memcpy(&type, n + 0x1c, 4);
                    std::memcpy(&length, n + 0xa0, 8);
                    std::memcpy(&next, n + 0xb8, 8);
                    const double mx = meters(x), mz = meters(z);
                    if (length > 127 || mx < 0 || mx > 10240 || mz < 0 || mz > 10240) break;  // not what was expected
                    ++tally[type];
                    // the list holds the player's own markers and, it seems, the game's quest markers: any kind this
                    // mod has a picture for is drawn (only the player's own carry a name the player typed)
                    for (int i = 0; i < kStyleCount; ++i)
                        if (kStyles[i].id == type) {
                            if (s.hidden[i]) break;
                            markers.push_back({static_cast<float>(mx), static_cast<float>(mz), static_cast<uint8_t>(i), 2,
                                               kStyles[i].custom ? std::string(reinterpret_cast<const char*>(n + 0x20), static_cast<size_t>(length))
                                                                 : std::string()});
                            break;
                        }
                    node = next;
                }
                for (const auto& [kind, howmany] : tally) kinds += std::to_string(kind) + " x" + std::to_string(howmany) + "  ";
                static std::string said_kinds;
                if (kinds != said_kinds) {
                    said_kinds = kinds;
                    FK_LOG(fklog::kInfo, "minimap: markers the game keeps in its own list (type x count): %s", kinds.empty() ? "none" : kinds.c_str());
                }
            }
        }
        std::lock_guard<std::mutex> l(g_shared.lock);
        g_shared.region = nearest_region;
        g_shared.place = place == nearest_region ? std::string() : place;
        g_shared.markers.swap(markers);
        g_shared.spires.swap(spires);
    }
    // the waypoint, the other players' places and the clock: ten times a second
    if (now - updated > 100) {
        updated = now;
        std::vector<Other> players;
        if (s.players) {
            for (uint32_t id : player_ids) {
                const auto* rt = w.get<gen::RenderTransform>(id);
                const auto* ct = rt ? nullptr : w.get<gen::CurrentTransform>(id);
                if (!rt && !ct) continue;
                const auto& p = rt ? rt->transform.position : ct->transform.position;
                const auto name = emf::player_name(w, id);
                players.push_back({static_cast<float>(meters(p.x)), static_cast<float>(meters(p.z)), name ? *name : std::string()});
            }
        }
        if (s.players) g_far_players.add_to(players, now);
        const auto* wp = w.get<gen::PlayerWaypoint>(emf::local_player());
        float hours, minutes;
        bool is_day = true;
        read_clock(w, hours, is_day, minutes);
        std::lock_guard<std::mutex> l(g_shared.lock);
        g_shared.players.swap(players);
        g_shared.waypoint = wp && wp->enabled;
        if (g_shared.waypoint) {
            g_shared.wx = static_cast<float>(meters(wp->waypointPosition.x));
            g_shared.wz = static_cast<float>(meters(wp->waypointPosition.z));
        }
        g_shared.time_of_day = hours;
        g_shared.is_day = is_day;
        g_shared.minutes_left = minutes;
    }
}

// ---- the map: the game's own height data, read straight from the game's data files ----
//
// The game keeps its map as textures inside its data files (enshrouded.kfc lists every piece of content: its size,
// which enshrouded_NNN.dat file it is in and where). The map's pieces lie one after the other in one file:
//   the base map: the whole world (10,240 m square), 1280 x 1280 heights of 16 bits, 8 m a pixel, north row first;
//   then, for each of 10 x 10 tiles (west to east, row by row from the south): a relief tile (1024 x 1024, BC4
//   compressed, 1 m a pixel, fine relief around the base height, 127.5 = none, north row first) and a shroud tile.
// The game stores identical pieces once. Relief tiles that repeat are the flat ones (open sea), so the tiles with
// the flattest base map are taken to be those. Everything is checked (sizes, counts, the flat tile really being
// flat, neighbouring tiles fitting together); if a check fails the minimap shows a plain dial instead of a map.
struct MapData {
    static constexpr int kBase = 1280, kTile = 1024, kTiles = 10, kWorld = 10240;
    static constexpr uint32_t kBaseBytes = kBase * kBase * 2, kReliefBytes = kTile * kTile / 2,
                              kShroudBytes = kTile * kTile;
    std::vector<uint16_t> base;
    FILE* dat = nullptr;                         // the game data file the tiles are in
    int64_t where[kTiles][kTiles] = {};          // [x][row from the north]: the tile's place in dat
    std::vector<uint8_t> tiles[kTiles][kTiles];  // [x][row from the north], loaded when first needed
    bool tried[kTiles][kTiles] = {};
    bool ok = false;
    std::string note;                            // how opening went, for the log

    static uint32_t u32(const std::vector<uint8_t>& d, size_t at) {
        return static_cast<uint32_t>(d[at]) | (static_cast<uint32_t>(d[at + 1]) << 8) |
               (static_cast<uint32_t>(d[at + 2]) << 16) | (static_cast<uint32_t>(d[at + 3]) << 24);
    }

    bool read_at(int64_t at, void* into, size_t bytes) {
        return dat && _fseeki64(dat, at, SEEK_SET) == 0 && fread(into, 1, bytes, dat) == bytes;
    }

    // Unpacks one BC4 texture of kTile x kTile pixels (blocks of 4 x 4 pixels, 8 bytes each).
    static void unpack_bc4(const uint8_t* in, uint8_t* out) {
        for (int by = 0; by < kTile / 4; ++by) {
            for (int bx = 0; bx < kTile / 4; ++bx, in += 8) {
                int pal[8];
                pal[0] = in[0];
                pal[1] = in[1];
                if (pal[0] > pal[1]) {
                    for (int i = 1; i < 7; ++i) pal[i + 1] = ((7 - i) * pal[0] + i * pal[1]) / 7;
                } else {
                    for (int i = 1; i < 5; ++i) pal[i + 1] = ((5 - i) * pal[0] + i * pal[1]) / 5;
                    pal[6] = 0;
                    pal[7] = 255;
                }
                uint64_t bits = 0;
                for (int i = 0; i < 6; ++i) bits |= static_cast<uint64_t>(in[2 + i]) << (8 * i);
                for (int p = 0; p < 16; ++p, bits >>= 3)
                    out[static_cast<size_t>(by * 4 + p / 4) * kTile + bx * 4 + p % 4] = static_cast<uint8_t>(pal[bits & 7]);
            }
        }
    }

    bool load_tile(int tx, int ty, std::vector<uint8_t>& into) {
        std::vector<uint8_t> packed(kReliefBytes);
        if (!read_at(where[tx][ty], packed.data(), packed.size())) return false;
        into.resize(static_cast<size_t>(kTile) * kTile);
        unpack_bc4(packed.data(), into.data());
        return true;
    }

    // Finds the map in the game's data files in game_dir (ends with a backslash). Sets ok and note.
    void open(const std::wstring& game_dir) {
        ok = false;
        std::vector<uint8_t> dir;
        {
            FILE* f = _wfsopen((game_dir + L"enshrouded.kfc").c_str(), L"rb", _SH_DENYNO);
            if (!f) return void(note = "enshrouded.kfc could not be opened");
            _fseeki64(f, 0, SEEK_END);
            const int64_t size = _ftelli64(f);
            _fseeki64(f, 0, SEEK_SET);
            if (size < 256 || size > (int64_t{1} << 30)) {
                fclose(f);
                return void(note = "enshrouded.kfc has an unexpected size");
            }
            dir.resize(static_cast<size_t>(size));
            const bool read = fread(dir.data(), 1, dir.size(), f) == dir.size();
            fclose(f);
            if (!read) return void(note = "enshrouded.kfc could not be read");
        }
        if (u32(dir, 0) != 0x3443464B) return void(note = "enshrouded.kfc is not in the known format (KFC4)");
        // the header: 16 places, each {where (counted from the field itself), how many}; 7 and 8 list the content
        auto place = [&](int i, size_t& at, size_t& count) {
            const size_t field = 16 + static_cast<size_t>(i) * 8;
            at = field + u32(dir, field);
            count = u32(dir, field + 4);
        };
        size_t keys, key_count, values, value_count;
        place(7, keys, key_count);
        place(8, values, value_count);
        if (key_count != value_count || key_count == 0 || keys + key_count * 16 > dir.size() ||
            values + value_count * 16 > dir.size())
            return void(note = "enshrouded.kfc: the content list is not where it was expected");

        struct Piece {
            uint32_t at, size;
        };
        for (size_t i = 0; i < key_count && !ok; ++i) {
            if (u32(dir, keys + i * 16) != kBaseBytes) continue;  // a base map has exactly this size
            const uint32_t base_at = u32(dir, values + i * 16);
            const uint32_t file = dir[values + i * 16 + 6] | (dir[values + i * 16 + 7] << 8);
            // everything after it in the same file, in the file's order
            std::vector<Piece> after;
            for (size_t j = 0; j < key_count; ++j) {
                const uint32_t f = dir[values + j * 16 + 6] | (dir[values + j * 16 + 7] << 8);
                const uint32_t at = u32(dir, values + j * 16);
                if (f == file && at > base_at) after.push_back({at, u32(dir, keys + j * 16)});
            }
            std::sort(after.begin(), after.end(), [](const Piece& a, const Piece& b) { return a.at < b.at; });
            std::vector<int64_t> relief;  // the relief tiles that follow, in order
            for (const Piece& p : after) {
                if (p.size == kReliefBytes) relief.push_back(p.at);
                else if (p.size != kShroudBytes) break;
            }
            if (relief.size() < 50 || relief.size() > 100) continue;

            wchar_t name[40];
            swprintf(name, 40, L"enshrouded_%03u.dat", file);
            if (dat) fclose(dat);
            dat = _wfsopen((game_dir + name).c_str(), L"rb", _SH_DENYNO);
            if (!dat) {
                note = "the game data file with the map could not be opened";
                continue;
            }
            base.resize(static_cast<size_t>(kBase) * kBase);
            if (!read_at(base_at, base.data(), kBaseBytes)) {
                note = "the base map could not be read";
                continue;
            }
            // the flat tiles: as many as there are relief tiles missing (plus the one that is stored)
            const int total = kTiles * kTiles, stored = static_cast<int>(relief.size());
            const int flat_count = stored < total ? total - stored + 1 : 0;
            std::vector<int> range(total), order(total);
            for (int k = 0; k < total; ++k) {
                const int x = k % kTiles, ty = kTiles - 1 - k / kTiles, n = kBase / kTiles;
                uint16_t lo = 0xFFFF, hi = 0;
                for (int y = ty * n; y < (ty + 1) * n; ++y)
                    for (int xx = x * n; xx < (x + 1) * n; ++xx) {
                        const uint16_t h = base[static_cast<size_t>(y) * kBase + xx];
                        lo = std::min(lo, h);
                        hi = std::max(hi, h);
                    }
                range[k] = hi - lo;
                order[k] = k;
            }
            std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return range[a] < range[b]; });
            std::vector<bool> flat(total, false);
            for (int n = 0; n < flat_count; ++n) flat[order[n]] = true;
            int next = 0;
            int64_t flat_at = -1;
            for (int k = 0; k < total; ++k) {
                const int x = k % kTiles, ty = kTiles - 1 - k / kTiles;
                if (flat[k] && flat_at >= 0) {
                    where[x][ty] = flat_at;
                    continue;
                }
                if (next >= stored) {
                    next = -1;
                    break;
                }
                where[x][ty] = relief[next++];
                if (flat[k]) flat_at = where[x][ty];
            }
            if (next != stored) {
                note = "the map's tiles could not be put in order";
                continue;
            }
            if (flat_at >= 0) {  // the flat tile must really be flat: every block like the first
                std::vector<uint8_t> packed(kReliefBytes);
                bool same = read_at(flat_at, packed.data(), packed.size());
                for (size_t b = 8; same && b < packed.size(); b += 8) same = memcmp(&packed[b], &packed[0], 8) == 0;
                if (!same) {
                    note = "the map's tiles are not laid out as expected (the flat tile is not flat)";
                    continue;
                }
            }
            // neighbouring tiles must fit together along their shared edges
            std::vector<uint8_t> edges(static_cast<size_t>(total) * 4 * kTile);  // per tile: north, south, west, east
            bool read = true;
            {
                std::vector<uint8_t> tile;
                for (int x = 0; x < kTiles && read; ++x)
                    for (int ty = 0; ty < kTiles && read; ++ty) {
                        read = load_tile(x, ty, tile);
                        if (!read) break;
                        uint8_t* e = &edges[static_cast<size_t>(ty * kTiles + x) * 4 * kTile];
                        for (int i = 0; i < kTile; ++i) {
                            e[i] = tile[i];
                            e[kTile + i] = tile[static_cast<size_t>(kTile - 1) * kTile + i];
                            e[2 * kTile + i] = tile[static_cast<size_t>(i) * kTile];
                            e[3 * kTile + i] = tile[static_cast<size_t>(i) * kTile + kTile - 1];
                        }
                    }
            }
            if (!read) {
                note = "a map tile could not be read";
                continue;
            }
            double worst = 0;
            auto seam = [&](int xa, int ya, int ea, int xb, int yb, int eb) {
                const uint8_t* a = &edges[(static_cast<size_t>(ya * kTiles + xa) * 4 + ea) * kTile];
                const uint8_t* b = &edges[(static_cast<size_t>(yb * kTiles + xb) * 4 + eb) * kTile];
                double sum = 0;
                for (int i = 0; i < kTile; ++i) sum += std::abs(static_cast<int>(a[i]) - static_cast<int>(b[i]));
                worst = std::max(worst, sum / kTile);
            };
            for (int x = 0; x < kTiles; ++x)
                for (int ty = 0; ty < kTiles; ++ty) {
                    if (x + 1 < kTiles) seam(x, ty, 3, x + 1, ty, 2);   // east edge against the next tile's west edge
                    if (ty + 1 < kTiles) seam(x, ty, 1, x, ty + 1, 0);  // south edge against the north edge below
                }
            char text[160];
            snprintf(text, sizeof(text), "%d relief tiles, %d flat, worst seam %.1f", stored, flat_count, worst);
            note = text;
            if (worst > 16.0) {
                note += " (tiles do not fit together: not used)";
                continue;
            }
            ok = true;
        }
        if (!ok) {
            if (note.empty()) note = "the map was not found in the game's data files";
            base.clear();
            if (dat) fclose(dat);
            dat = nullptr;
        }
    }

    // One pixel of the fine relief; (ix, iy) in metres from the world's north-west corner.
    float detail_at(int ix, int iy) {
        ix = std::clamp(ix, 0, kWorld - 1);
        iy = std::clamp(iy, 0, kWorld - 1);
        const int tx = ix / kTile, ty = iy / kTile;
        auto& t = tiles[tx][ty];
        if (t.empty()) {
            if (tried[tx][ty]) return 127.5f;
            tried[tx][ty] = true;
            if (!load_tile(tx, ty, t)) {
                std::vector<uint8_t>().swap(t);
                return 127.5f;
            }
        }
        return static_cast<float>(t[static_cast<size_t>(iy % kTile) * kTile + (ix % kTile)]);
    }

    // Frees the tiles far from the player's tile, so memory stays small while travelling.
    void forget_far(float px, float py) {
        const int cx = static_cast<int>(px) / kTile, cy = static_cast<int>(py) / kTile;
        for (int x = 0; x < kTiles; ++x)
            for (int y = 0; y < kTiles; ++y)
                if (std::abs(x - cx) > 2 || std::abs(y - cy) > 2) {
                    if (!tiles[x][y].empty()) std::vector<uint8_t>().swap(tiles[x][y]);
                    tried[x][y] = false;
                }
    }

    float base_at(int bx, int by) const {
        bx = std::clamp(bx, 0, kBase - 1);
        by = std::clamp(by, 0, kBase - 1);
        return static_cast<float>(base[static_cast<size_t>(by) * kBase + bx]);
    }

    // The height at (px, py) metres from the north-west corner, in the base map's units. fine: add the relief.
    float height(float px, float py, bool fine) {
        const float bx = px / 8.0f - 0.5f, by = py / 8.0f - 0.5f;
        const int x0 = static_cast<int>(std::floor(bx)), y0 = static_cast<int>(std::floor(by));
        const float fx = bx - static_cast<float>(x0), fy = by - static_cast<float>(y0);
        float h = (base_at(x0, y0) * (1 - fx) + base_at(x0 + 1, y0) * fx) * (1 - fy) +
                  (base_at(x0, y0 + 1) * (1 - fx) + base_at(x0 + 1, y0 + 1) * fx) * fy;
        if (fine) {
            const float dx = px - 0.5f, dy = py - 0.5f;
            const int u0 = static_cast<int>(std::floor(dx)), v0 = static_cast<int>(std::floor(dy));
            const float gx = dx - static_cast<float>(u0), gy = dy - static_cast<float>(v0);
            const float d = (detail_at(u0, v0) * (1 - gx) + detail_at(u0 + 1, v0) * gx) * (1 - gy) +
                            (detail_at(u0, v0 + 1) * (1 - gx) + detail_at(u0 + 1, v0 + 1) * gx) * gy;
            h += (d - 127.5f) * 4.0f;  // fitted to the contour lines of the game's map
        }
        return h;
    }
};

// The game's map draws a contour line every 160 units of height, at heights of 160 k - 16 (fitted to a screenshot).
constexpr float kLineStep = 160.0f, kLineShift = 16.0f;

// The ground's colour for a height: the game's own colour strip for its map (151 colours, low to high).
// colour number = kGradientAt0 + height * kGradientStep (fitted to a screenshot of the game's map: correlation 0.99).
constexpr float kGradientAt0 = 1.7f, kGradientStep = 0.00906f;
constexpr unsigned char kGradient[151][3] = {
    {59, 42, 55}, {59, 41, 55}, {60, 41, 55}, {59, 42, 55}, {59, 42, 55}, {60, 42, 55}, {60, 43, 55}, {59, 43, 55},
    {60, 42, 55}, {60, 43, 56}, {60, 43, 55}, {60, 43, 55}, {60, 44, 56}, {60, 44, 55}, {60, 44, 55}, {61, 44, 55},
    {61, 44, 55}, {61, 44, 55}, {60, 44, 55}, {61, 45, 54}, {61, 45, 54}, {61, 45, 55}, {61, 45, 55}, {61, 45, 55},
    {61, 45, 54}, {61, 46, 54}, {61, 46, 54}, {61, 47, 54}, {61, 47, 54}, {62, 47, 54}, {62, 47, 54}, {62, 48, 54},
    {62, 47, 54}, {62, 48, 54}, {62, 48, 54}, {62, 48, 54}, {63, 48, 54}, {62, 49, 53}, {63, 49, 54}, {63, 49, 54},
    {64, 49, 54}, {64, 50, 53}, {64, 51, 54}, {64, 50, 54}, {64, 51, 54}, {64, 51, 53}, {64, 52, 54}, {64, 52, 54},
    {64, 52, 53}, {65, 52, 54}, {65, 53, 54}, {65, 53, 53}, {66, 53, 53}, {65, 53, 53}, {65, 54, 53}, {66, 54, 54},
    {67, 55, 54}, {66, 55, 54}, {66, 55, 53}, {66, 55, 54}, {67, 56, 54}, {67, 56, 54}, {68, 56, 54}, {68, 57, 54},
    {68, 57, 54}, {69, 58, 54}, {69, 58, 54}, {69, 59, 54}, {69, 59, 55}, {69, 59, 55}, {70, 60, 55}, {71, 61, 54},
    {71, 61, 55}, {71, 61, 56}, {72, 61, 55}, {71, 62, 56}, {72, 62, 56}, {72, 63, 56}, {73, 63, 56}, {73, 64, 57},
    {74, 64, 57}, {74, 65, 57}, {75, 66, 57}, {75, 66, 58}, {75, 67, 58}, {76, 67, 58}, {77, 68, 59}, {77, 68, 59},
    {78, 69, 59}, {78, 70, 60}, {79, 70, 61}, {81, 72, 61}, {81, 73, 63}, {83, 75, 63}, {84, 77, 65}, {85, 78, 66},
    {86, 79, 67}, {88, 81, 68}, {91, 83, 69}, {92, 84, 71}, {93, 86, 72}, {95, 88, 73}, {97, 90, 75}, {99, 92, 77},
    {100, 94, 78}, {103, 96, 81}, {104, 98, 82}, {106, 100, 84}, {108, 102, 86}, {111, 104, 88}, {113, 106, 89}, {115, 108, 91},
    {117, 111, 93}, {119, 113, 95}, {121, 114, 98}, {123, 117, 99}, {125, 119, 101}, {127, 121, 103}, {129, 124, 105}, {131, 125, 107},
    {134, 127, 109}, {135, 129, 110}, {137, 132, 112}, {139, 134, 114}, {141, 135, 116}, {143, 137, 117}, {144, 139, 119}, {146, 141, 120},
    {148, 142, 122}, {149, 144, 124}, {151, 146, 126}, {152, 147, 127}, {154, 148, 128}, {155, 150, 130}, {156, 152, 130}, {157, 152, 132},
    {160, 156, 135}, {162, 158, 137}, {164, 161, 140}, {166, 163, 142}, {167, 164, 144}, {168, 165, 146}, {168, 166, 148}, {168, 167, 149},
    {169, 168, 150}, {168, 167, 151}, {169, 168, 153}, {169, 169, 153}, {169, 169, 154}, {170, 170, 155}, {169, 169, 156}};

void ground_colour(float h, float& r, float& g, float& b) {
    const float at = std::clamp(kGradientAt0 + h * kGradientStep, 0.0f, 149.999f);
    const int i = static_cast<int>(at);
    const float t = at - static_cast<float>(i);
    r = kGradient[i][0] + (kGradient[i + 1][0] - kGradient[i][0]) * t;
    g = kGradient[i][1] + (kGradient[i + 1][1] - kGradient[i][1]) * t;
    b = kGradient[i][2] + (kGradient[i + 1][2] - kGradient[i][2]) * t;
}

// ---- the game's own marker icons, read from the game's data files like the map ----
//
// Each icon is a small picture of 4 bytes a pixel (red, green, blue, opacity), stored as one piece of content. The
// pieces are found by their content ids (size and three numbers the game derives from the bytes themselves; read with
// a probe on 2026-11-11, game build 1287369). When the game's art changes, an id no longer matches and that marker
// keeps this mod's own drawn symbol.
struct IconRef {
    uint32_t size, hash0, hash1, hash2;
    int w, h;
    float scale;  // against the usual marker size (the game's own display sizes)
};
constexpr IconRef kIcons[] = {  // the first kStyleCount rows belong to kStyles, row for row
    {16384u, 511943985u, 3739089463u, 258719913u, 64, 64, 1.00f},  // mapmarker_flame_altar
    {16384u, 511943985u, 3739089463u, 258719913u, 64, 64, 1.00f},  // mapmarker_flame_altar
    {65536u, 673224124u, 4025193430u, 2346658751u, 128, 128, 0.60f},  // mapmarker_playerWaterSource
    {16384u, 3179167945u, 2454621683u, 1373348907u, 64, 64, 1.00f},  // mapmarker_tower
    {65536u, 2339892285u, 3111655191u, 2462849357u, 128, 128, 1.00f},  // mapmarker_tower_locked
    {65536u, 616344246u, 3938618342u, 2799123197u, 128, 128, 1.00f},  // mapmarker_fastTravel
    {16384u, 1663573834u, 554447804u, 1264960929u, 64, 64, 1.00f},  // mapmarker_flame_essence
    {65536u, 3078959843u, 1922780983u, 2381746606u, 128, 128, 1.00f},  // mapmarker_nighttemple
    {65536u, 3431917313u, 4109631440u, 1472996711u, 128, 128, 1.00f},  // mapmarker_shroudforge
    {65536u, 799950576u, 3954884293u, 50268387u, 128, 128, 1.00f},  // mapmarker_obelisk
    {16384u, 1666387575u, 555089270u, 861826546u, 64, 64, 1.00f},  // mapmarker_well_plant
    {65536u, 482082781u, 3650554489u, 744997189u, 128, 128, 1.00f},  // mapmarker_dungeon
    {65536u, 3483265244u, 1526757667u, 728917313u, 128, 128, 1.00f},  // mapmarker_bigDungeon
    {65536u, 814009353u, 1417597604u, 4020882306u, 128, 128, 1.00f},  // mapmarker_fognest
    {16384u, 4134626610u, 1417370089u, 1045431324u, 64, 64, 1.00f},  // mapmarker_challenge_chamber
    {65536u, 885240485u, 3283078049u, 156119147u, 128, 128, 1.00f},  // mapmarker_tomb
    {16384u, 648809789u, 91953629u, 1854029161u, 64, 64, 1.00f},  // mapmarker_village
    {16384u, 4264358740u, 418475412u, 2597032061u, 64, 64, 1.00f},  // mapmarker_farm
    {16384u, 997792393u, 3362481661u, 992524301u, 64, 64, 1.00f},  // mapmarker_cave
    {16384u, 87018296u, 2316654354u, 181009191u, 64, 64, 1.00f},  // mapmarker_mine
    {65536u, 422969863u, 4249325467u, 532682902u, 128, 128, 1.00f},  // mapmarker_survivorcamp
    {16384u, 1669416812u, 790188021u, 4116868485u, 64, 64, 1.15f},  // mapmarker_special_enemy_camp
    {65536u, 3082310149u, 1847367042u, 4240598420u, 128, 128, 1.00f},  // mapmarker_balefire
    {16384u, 3699699091u, 3890777897u, 741648778u, 64, 64, 1.00f},  // mapmarker_player_corpse
    {65536u, 3477252100u, 3557848775u, 1328772466u, 128, 128, 1.00f},  // mapmarker_spawn_flame_altar
    {16384u, 3630026044u, 746142433u, 315567973u, 64, 64, 1.00f},  // marker_home_base
    {65536u, 258746434u, 2579613154u, 3630612667u, 128, 128, 1.00f},  // mapmarker_quest
    {65536u, 1378955790u, 1901394782u, 2401594232u, 128, 128, 1.00f},  // mapmarker_questImportant
    {65536u, 3377716232u, 1163290808u, 1716631083u, 128, 128, 1.00f},  // icon_goal
    {65536u, 2299573798u, 2480844021u, 3957838657u, 128, 128, 1.00f},  // icon_chest
    {65536u, 4062068787u, 1327149095u, 2957843366u, 128, 128, 1.00f},  // icon_glider
    {65536u, 1400908785u, 3338858860u, 3475498208u, 128, 128, 1.00f},  // icon_loot
    {65536u, 2850377460u, 1863229139u, 3711566616u, 128, 128, 1.00f},  // icon_plants
    {65536u, 1581869194u, 2683568563u, 3271625931u, 128, 128, 1.00f},  // icon_wildlife
    {65536u, 454053519u, 753769762u, 2025824774u, 128, 128, 1.00f},  // icon_water
    {65536u, 943916620u, 2233448268u, 1217996695u, 128, 128, 1.00f},  // icon_fish
    {65536u, 2748578648u, 1204496229u, 2484649697u, 128, 128, 1.00f},  // icon_ore
    {65536u, 910080561u, 1182354097u, 2641106818u, 128, 128, 1.00f},  // icon_combat
    {4096u, 3381602357u, 2296465782u, 7809476u, 32, 32, 1.00f},  // mapmarker_completed
    {16384u, 1611239519u, 3682802717u, 3276021245u, 64, 64, 1.00f},  // mapmarker_waypoint
    {65536u, 2648233764u, 3042888061u, 746622285u, 128, 128, 1.00f},  // mapmarker_playerPing
};
constexpr int kIconCompleted = kStyleCount, kIconWaypoint = kStyleCount + 1, kIconPing = kStyleCount + 2;
constexpr int kIconCount = kStyleCount + 3;
static_assert(sizeof(kIcons) / sizeof(kIcons[0]) == kIconCount);

struct Icon {
    int w = 0, h = 0;
    std::vector<uint8_t> rgba;    // as stored; empty: not found
    std::vector<uint8_t> scaled;  // shrunk to scaled_px x scaled_px
    int scaled_px = 0;
};

struct Icons {
    Icon icon[kIconCount];
    int found = 0;

    // Reads every icon it can find from the game's data files in game_dir (ends with a backslash).
    void load(const std::wstring& game_dir) {
        std::vector<uint8_t> dir;
        FILE* f = _wfsopen((game_dir + L"enshrouded.kfc").c_str(), L"rb", _SH_DENYNO);
        if (!f) return;
        _fseeki64(f, 0, SEEK_END);
        const int64_t size = _ftelli64(f);
        _fseeki64(f, 0, SEEK_SET);
        if (size >= 256 && size <= (int64_t{1} << 30)) {
            dir.resize(static_cast<size_t>(size));
            if (fread(dir.data(), 1, dir.size(), f) != dir.size()) dir.clear();
        }
        fclose(f);
        if (dir.empty() || MapData::u32(dir, 0) != 0x3443464B) return;
        auto place = [&](int i, size_t& at, size_t& count) {
            const size_t field = 16 + static_cast<size_t>(i) * 8;
            at = field + MapData::u32(dir, field);
            count = MapData::u32(dir, field + 4);
        };
        size_t keys, key_count, values, value_count;
        place(7, keys, key_count);
        place(8, values, value_count);
        if (key_count != value_count || keys + key_count * 16 > dir.size() || values + value_count * 16 > dir.size()) return;
        for (size_t i = 0; i < key_count; ++i) {
            const uint32_t bytes = MapData::u32(dir, keys + i * 16);
            if (bytes != 4096 && bytes != 16384 && bytes != 65536) continue;  // the sizes icons have
            for (int k = 0; k < kIconCount; ++k) {
                const IconRef& ref = kIcons[k];
                if (ref.size != bytes || !icon[k].rgba.empty() || MapData::u32(dir, keys + i * 16 + 4) != ref.hash0 ||
                    MapData::u32(dir, keys + i * 16 + 8) != ref.hash1 || MapData::u32(dir, keys + i * 16 + 12) != ref.hash2)
                    continue;
                const uint32_t at = MapData::u32(dir, values + i * 16);
                const uint32_t file = dir[values + i * 16 + 6] | (dir[values + i * 16 + 7] << 8);
                wchar_t name[40];
                swprintf(name, 40, L"enshrouded_%03u.dat", file);
                FILE* d = _wfsopen((game_dir + name).c_str(), L"rb", _SH_DENYNO);
                if (!d) continue;
                std::vector<uint8_t> data(bytes);
                if (_fseeki64(d, at, SEEK_SET) == 0 && fread(data.data(), 1, bytes, d) == bytes) {
                    icon[k].w = ref.w;
                    icon[k].h = ref.h;
                    icon[k].rgba.swap(data);
                    ++found;
                }
                fclose(d);
            }
        }
    }

    // Icon k, shrunk to px x px (4 bytes a pixel, colour not yet times opacity); nullptr when it was not found.
    const uint8_t* sized(int k, int px) {
        Icon& ic = icon[k];
        if (ic.rgba.empty() || px < 2) return nullptr;
        if (ic.scaled_px != px) {
            ic.scaled.assign(static_cast<size_t>(px) * px * 4, 0);
            for (int y = 0; y < px; ++y) {
                const int y0 = y * ic.h / px, y1 = std::max(y0 + 1, (y + 1) * ic.h / px);
                for (int x = 0; x < px; ++x) {
                    const int x0 = x * ic.w / px, x1 = std::max(x0 + 1, (x + 1) * ic.w / px);
                    uint32_t r = 0, g = 0, b = 0, a = 0, n = 0;
                    for (int yy = y0; yy < y1; ++yy)
                        for (int xx = x0; xx < x1; ++xx) {
                            const uint8_t* p = &ic.rgba[(static_cast<size_t>(yy) * ic.w + xx) * 4];
                            r += p[0] * p[3];
                            g += p[1] * p[3];
                            b += p[2] * p[3];
                            a += p[3];
                            ++n;
                        }
                    uint8_t* o = &ic.scaled[(static_cast<size_t>(y) * px + x) * 4];
                    if (a) {
                        o[0] = static_cast<uint8_t>(r / a);
                        o[1] = static_cast<uint8_t>(g / a);
                        o[2] = static_cast<uint8_t>(b / a);
                        o[3] = static_cast<uint8_t>(a / n);
                    }
                }
            }
            ic.scaled_px = px;
        }
        return ic.scaled.data();
    }
};

// ---- the game's own names for places, read from the game's data files ----
//
// The game's texts are one piece of content per language: a list of {id, where the text is, its length, ...} rows
// of 24 bytes, sorted by id, then the texts. A map marker names its place with a tag whose id is FNV-1a of the
// tag's 16 bytes. The English list is found by its content id (read with a probe on 2026-11-11, game build 1287369)
// or, after a game update changed it, by looking for a list that says "Flame Altar" where the flame altar's tag is.
// Without a list the markers keep this mod's own short names.
struct Loca {
    std::vector<uint8_t> blob;
    uint32_t rows = 0, first = 0;
    std::atomic<bool> ready{false};

    static uint32_t u32(const uint8_t* p) {
        return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) | (static_cast<uint32_t>(p[2]) << 16) |
               (static_cast<uint32_t>(p[3]) << 24);
    }

    // The text for `id`; false when there is none.
    static bool find(const std::vector<uint8_t>& b, uint32_t first_row, uint32_t count, uint32_t id, std::string& out) {
        uint32_t lo = 0, hi = count;
        while (lo < hi) {
            const uint32_t mid = (lo + hi) / 2;
            const size_t row = first_row + static_cast<size_t>(mid) * 24;
            const uint32_t at = u32(&b[row]);
            if (at == id) {
                const size_t text = row + 4 + u32(&b[row + 4]), length = u32(&b[row + 8]);
                if (length > 4096 || text + length > b.size()) return false;
                out.assign(reinterpret_cast<const char*>(&b[text]), length);
                return true;
            }
            if (at < id) lo = mid + 1;
            else hi = mid;
        }
        return false;
    }

    // Is `b` a list of texts? Sets its row count and where the rows start.
    static bool valid(const std::vector<uint8_t>& b, uint32_t& first_row, uint32_t& count) {
        if (b.size() < 64) return false;
        first_row = u32(&b[0]);
        count = u32(&b[4]);
        if (first_row != 8 || count < 1000 || count > 400000 || first_row + static_cast<size_t>(count) * 24 > b.size()) return false;
        for (uint32_t i = 1; i < count; i += std::max<uint32_t>(1, count / 64))  // sorted, as far as a few samples show
            if (u32(&b[first_row + static_cast<size_t>(i) * 24]) <= u32(&b[first_row + static_cast<size_t>(i - 1) * 24])) return false;
        return true;
    }

    bool name(uint32_t id, std::string& out) const { return ready.load() && find(blob, first, rows, id, out); }

    void load(const std::wstring& game_dir, std::string& note) {
        constexpr uint32_t kKnown[4] = {1733004u, 3191761838u, 3367547340u, 3724958107u};  // En_Us in build 1287369
        constexpr uint32_t kFlameAltarTag = 4125307802u;  // FNV-1a of 29417954-ce46-4f07-8f0c-60eb804fab28
        std::vector<uint8_t> dir;
        FILE* f = _wfsopen((game_dir + L"enshrouded.kfc").c_str(), L"rb", _SH_DENYNO);
        if (!f) return void(note = "enshrouded.kfc could not be opened");
        _fseeki64(f, 0, SEEK_END);
        const int64_t size = _ftelli64(f);
        _fseeki64(f, 0, SEEK_SET);
        if (size >= 256 && size <= (int64_t{1} << 30)) {
            dir.resize(static_cast<size_t>(size));
            if (fread(dir.data(), 1, dir.size(), f) != dir.size()) dir.clear();
        }
        fclose(f);
        if (dir.empty() || MapData::u32(dir, 0) != 0x3443464B) return void(note = "enshrouded.kfc is not in the known format");
        auto place = [&](int i, size_t& at, size_t& count) {
            const size_t field = 16 + static_cast<size_t>(i) * 8;
            at = field + MapData::u32(dir, field);
            count = MapData::u32(dir, field + 4);
        };
        size_t keys, key_count, values, value_count;
        place(7, keys, key_count);
        place(8, values, value_count);
        if (key_count != value_count || keys + key_count * 16 > dir.size() || values + value_count * 16 > dir.size())
            return void(note = "the content list is not where it was expected");
        FILE* open_file = nullptr;
        uint32_t open_index = 0xFFFFFFFF;
        auto read = [&](size_t i, size_t bytes, std::vector<uint8_t>& into) {
            const uint32_t at = MapData::u32(dir, values + i * 16);
            const uint32_t file = dir[values + i * 16 + 6] | (dir[values + i * 16 + 7] << 8);
            if (file != open_index) {
                if (open_file) fclose(open_file);
                wchar_t name[40];
                swprintf(name, 40, L"enshrouded_%03u.dat", file);
                open_file = _wfsopen((game_dir + name).c_str(), L"rb", _SH_DENYNO);
                open_index = open_file ? file : 0xFFFFFFFF;
            }
            into.resize(bytes);
            return open_file && _fseeki64(open_file, at, SEEK_SET) == 0 && fread(into.data(), 1, bytes, open_file) == bytes;
        };
        std::string text;
        for (int pass = 0; pass < 2 && !ready.load(); ++pass) {  // 0: the known list; 1: any list that fits
            for (size_t i = 0; i < key_count && !ready.load(); ++i) {
                const uint32_t bytes = MapData::u32(dir, keys + i * 16);
                if (pass == 0) {
                    if (bytes != kKnown[0] || MapData::u32(dir, keys + i * 16 + 4) != kKnown[1] ||
                        MapData::u32(dir, keys + i * 16 + 8) != kKnown[2] || MapData::u32(dir, keys + i * 16 + 12) != kKnown[3])
                        continue;
                } else {
                    if (bytes < 300000 || bytes > 16000000) continue;
                    std::vector<uint8_t> head;  // a list starts with 8 and its row count
                    if (!read(i, 8, head) || Loca::u32(&head[0]) != 8) continue;
                    const uint32_t count = Loca::u32(&head[4]);
                    if (count < 1000 || count > 400000 || static_cast<uint64_t>(count) * 24 + 8 > bytes) continue;
                }
                std::vector<uint8_t> whole;
                uint32_t first_row, count;
                if (!read(i, bytes, whole) || !valid(whole, first_row, count)) continue;
                if (!find(whole, first_row, count, kFlameAltarTag, text) || text != "Flame Altar") continue;
                blob.swap(whole);
                first = first_row;
                rows = count;
                note = pass == 0 ? "the known English list" : "found by its content (the game's files have changed)";
                ready.store(true);
            }
        }
        if (open_file) fclose(open_file);
        if (!ready.load() && note.empty()) note = "no English list of the game's texts was found";
    }
};
Loca g_loca;
bool place_name(uint32_t id, std::string& out) {
    std::string raw;
    if (!g_loca.name(id, raw)) return false;
    // the game's texts carry marks such as <location>Ferndale</location>: only the words are wanted
    out.clear();
    bool mark = false;
    for (char ch : raw) {
        if (ch == '<') mark = true;
        else if (ch == '>' && mark) mark = false;
        else if (!mark) out.push_back(ch);
    }
    return !out.empty();
}

// ---- drawing: a picture of w x h pixels, 4 bytes a pixel (blue, green, red, alpha; colours already times alpha) ----

struct Canvas {
    int w = 0, h = 0;
    int dial = 0;  // the dial's width: the picture is wider by `ox` on each side, so a long line of text under it fits
    int ox = 0;    // added to every x: drawing is written as if the dial began at x = 0
    uint32_t* px = nullptr;

    // Paints colour (r, g, b: 0..255) with coverage a (0..1) over pixel (x, y).
    void blend(int x, int y, float r, float g, float b, float a) {
        x += ox;
        if (x < 0 || y < 0 || x >= w || y >= h || a <= 0.0f) return;
        a = std::min(a, 1.0f);
        uint32_t& p = px[y * w + x];
        const float inv = 1.0f - a;
        const float pb = static_cast<float>(p & 0xFF), pg = static_cast<float>((p >> 8) & 0xFF);
        const float pr = static_cast<float>((p >> 16) & 0xFF), pa = static_cast<float>((p >> 24) & 0xFF);
        const uint32_t nb = static_cast<uint32_t>(b * a + pb * inv + 0.5f);
        const uint32_t ng = static_cast<uint32_t>(g * a + pg * inv + 0.5f);
        const uint32_t nr = static_cast<uint32_t>(r * a + pr * inv + 0.5f);
        const uint32_t na = static_cast<uint32_t>(255.0f * a + pa * inv + 0.5f);
        p = (std::min(na, 255u) << 24) | (std::min(nr, 255u) << 16) | (std::min(ng, 255u) << 8) | std::min(nb, 255u);
    }

    // A filled triangle with soft edges.
    void triangle(float x0, float y0, float x1, float y1, float x2, float y2, float r, float g, float b, float alpha) {
        const int minx = static_cast<int>(std::floor(std::min({x0, x1, x2}))) - 1;
        const int maxx = static_cast<int>(std::ceil(std::max({x0, x1, x2}))) + 1;
        const int miny = static_cast<int>(std::floor(std::min({y0, y1, y2}))) - 1;
        const int maxy = static_cast<int>(std::ceil(std::max({y0, y1, y2}))) + 1;
        auto edge = [](float ax, float ay, float bx, float by, float px_, float py_) {
            const float len = std::sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
            if (len < 1e-6f) return 0.0f;
            return ((bx - ax) * (py_ - ay) - (by - ay) * (px_ - ax)) / len;  // signed distance to the edge's line
        };
        const float area = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0);
        const float sign = area < 0 ? -1.0f : 1.0f;
        for (int y = miny; y <= maxy; ++y) {
            for (int x = minx; x <= maxx; ++x) {
                const float cx = static_cast<float>(x) + 0.5f, cy = static_cast<float>(y) + 0.5f;
                const float d0 = sign * edge(x0, y0, x1, y1, cx, cy);
                const float d1 = sign * edge(x1, y1, x2, y2, cx, cy);
                const float d2 = sign * edge(x2, y2, x0, y0, cx, cy);
                const float d = std::min({d0, d1, d2});  // how far inside (pixels); negative outside
                blend(x, y, r, g, b, alpha * std::clamp(d + 0.5f, 0.0f, 1.0f));
            }
        }
    }

    // A filled disc, or with `thick` > 0 a ring of that thickness, with soft edges.
    void disc(float cx, float cy, float radius, float r, float g, float b, float alpha, float thick = 0.0f) {
        const int x0 = static_cast<int>(std::floor(cx - radius)) - 1, x1 = static_cast<int>(std::ceil(cx + radius)) + 1;
        const int y0 = static_cast<int>(std::floor(cy - radius)) - 1, y1 = static_cast<int>(std::ceil(cy + radius)) + 1;
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                const float dx = static_cast<float>(x) + 0.5f - cx, dy = static_cast<float>(y) + 0.5f - cy;
                const float d = std::sqrt(dx * dx + dy * dy);
                float inside = radius - d;
                if (thick > 0.0f) inside = std::min(inside, d - (radius - thick));
                blend(x, y, r, g, b, alpha * std::clamp(inside + 0.5f, 0.0f, 1.0f));
            }
        }
    }

    // A square standing on a corner.
    void diamond(float cx, float cy, float radius, float r, float g, float b, float alpha) {
        triangle(cx, cy - radius, cx - radius, cy, cx + radius, cy, r, g, b, alpha);
        triangle(cx, cy + radius, cx + radius, cy, cx - radius, cy, r, g, b, alpha);
    }

    // A box with round ends.
    void pill(float x0, float y0, float x1, float y1, float r, float g, float b, float alpha) {
        const float rad = (y1 - y0) * 0.5f, cy = (y0 + y1) * 0.5f;
        for (int y = static_cast<int>(std::floor(y0)); y <= static_cast<int>(std::ceil(y1)); ++y) {
            for (int x = static_cast<int>(std::floor(x0)); x <= static_cast<int>(std::ceil(x1)); ++x) {
                const float px_ = static_cast<float>(x) + 0.5f, py_ = static_cast<float>(y) + 0.5f;
                const float ax = std::clamp(px_, x0 + rad, x1 - rad);
                const float d = std::sqrt((px_ - ax) * (px_ - ax) + (py_ - cy) * (py_ - cy));
                blend(x, y, r, g, b, alpha * std::clamp(rad - d + 0.5f, 0.0f, 1.0f));
            }
        }
    }

    // A square picture of px x px pixels (4 bytes a pixel: red, green, blue, opacity) with its middle at (cx, cy).
    // `grey`: drawn in light grey instead of its own colours (a place the player has not found yet).
    void picture(const uint8_t* data, int px, float cx, float cy, float alpha, bool grey = false) {
        const int x0 = static_cast<int>(std::floor(cx - static_cast<float>(px) * 0.5f + 0.5f));
        const int y0 = static_cast<int>(std::floor(cy - static_cast<float>(px) * 0.5f + 0.5f));
        for (int y = 0; y < px; ++y)
            for (int x = 0; x < px; ++x) {
                const uint8_t* p = &data[(static_cast<size_t>(y) * px + x) * 4];
                if (!p[3]) continue;
                if (grey) {  // its brightness only, as a mid grey, so the shape stays readable
                    const float v = 105.0f + (0.30f * p[0] + 0.59f * p[1] + 0.11f * p[2]) * 0.35f;
                    blend(x0 + x, y0 + y, v, v, v, alpha * static_cast<float>(p[3]) / 255.0f);
                } else {
                    blend(x0 + x, y0 + y, p[0], p[1], p[2], alpha * static_cast<float>(p[3]) / 255.0f);
                }
            }
    }
};

// Text, drawn by Windows into a small picture of its own and laid over the canvas (Windows' text drawing does not
// write transparency, so its brightness is used as coverage).
struct TextPainter {
    // The scratch picture Windows draws one line into. 2048 wide: a line is never cut off in a wide window (it was 640
    // until 0.15.31, and width() said no line was wider, so the wrapping never wrapped and long lines were cut off).
    static constexpr int kW = 2048, kH = 64;
    HDC dc = nullptr;
    HBITMAP bitmap = nullptr;
    uint32_t* bits = nullptr;
    HFONT font = nullptr;
    int font_px = 0;
    int weight = FW_SEMIBOLD;  // set before the first ready()

    bool ready(HDC screen, int px) {
        if (!dc) {
            dc = CreateCompatibleDC(screen);
            BITMAPINFO bi{};
            bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
            bi.bmiHeader.biWidth = kW;
            bi.bmiHeader.biHeight = -kH;
            bi.bmiHeader.biPlanes = 1;
            bi.bmiHeader.biBitCount = 32;
            bi.bmiHeader.biCompression = BI_RGB;
            void* p = nullptr;
            bitmap = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &p, nullptr, 0);
            if (!dc || !bitmap || !p) return false;
            bits = static_cast<uint32_t*>(p);
            SelectObject(dc, bitmap);
            SetTextColor(dc, RGB(255, 255, 255));
            SetBkMode(dc, TRANSPARENT);
        }
        if (!bits) return false;
        if (px != font_px) {
            HFONT made = CreateFontW(-px, 0, 0, 0, weight, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                     ANTIALIASED_QUALITY, DEFAULT_PITCH, L"Segoe UI");
            if (!made) return false;
            SelectObject(dc, made);
            if (font) DeleteObject(font);
            font = made;
            font_px = px;
        }
        return true;
    }

    int width(const std::wstring& text) {  // the line's real width (for wrapping); drawing stops at kW
        SIZE sz{};
        GetTextExtentPoint32W(dc, text.c_str(), static_cast<int>(text.size()), &sz);
        return sz.cx;
    }

    // Draws `text` with its top left corner at (x, y), in colour r g b over a dark shadow.
    // Draws `text` small and sharp, its ink centred on (cx, cy): the letters are made `scale` times too big (ready()
    // must have been called with that bigger size) and each pixel takes the average of its scale x scale piece. No
    // shadow. For a mark of a few pixels, where Windows' own small letters come out soft and heavy.
    void draw_fine(Canvas& c, float cx, float cy, const std::wstring& text, int scale, float r, float g, float b) {
        const int wide = std::min(width(text), kW - 2), tall = std::min(kH, font_px + font_px / 2 + 2);
        for (int row = 0; row < tall; ++row) std::fill(bits + row * kW, bits + row * kW + wide + 2, 0u);
        TextOutW(dc, 0, 0, text.c_str(), static_cast<int>(text.size()));
        GdiFlush();
        int x0 = wide, x1 = -1, y0 = tall, y1 = -1;  // the ink's box
        for (int row = 0; row < tall; ++row)
            for (int col = 0; col < wide; ++col)
                if ((bits[row * kW + col] >> 8) & 0xFF) {
                    x0 = std::min(x0, col), x1 = std::max(x1, col);
                    y0 = std::min(y0, row), y1 = std::max(y1, row);
                }
        if (x1 < x0) return;
        const int ow = (x1 - x0 + scale) / scale, oh = (y1 - y0 + scale) / scale;
        const int left = static_cast<int>(std::floor(cx - static_cast<float>(ow) * 0.5f + 0.5f));
        const int top = static_cast<int>(std::floor(cy - static_cast<float>(oh) * 0.5f + 0.5f));
        for (int oy = 0; oy < oh; ++oy)
            for (int ox = 0; ox < ow; ++ox) {
                int sum = 0;
                for (int sy = 0; sy < scale; ++sy)
                    for (int sx = 0; sx < scale; ++sx) {
                        const int col = x0 + ox * scale + sx, row = y0 + oy * scale + sy;
                        if (col <= x1 && row <= y1) sum += (bits[row * kW + col] >> 8) & 0xFF;
                    }
                const float cover = static_cast<float>(sum) / (255.0f * static_cast<float>(scale * scale));
                if (cover > 0.0f) c.blend(left + ox, top + oy, r, g, b, cover);
            }
    }

    void draw(Canvas& c, int x, int y, const std::wstring& text, float r, float g, float b, float alpha = 1.0f) {
        const int wide = std::min(width(text), kW - 2), tall = std::min(kH, font_px + font_px / 2 + 2);
        for (int row = 0; row < tall; ++row) std::fill(bits + row * kW, bits + row * kW + wide + 2, 0u);
        TextOutW(dc, 0, 0, text.c_str(), static_cast<int>(text.size()));
        GdiFlush();
        for (int pass = 0; pass < 2; ++pass) {
            for (int row = 0; row < tall; ++row) {
                for (int col = 0; col < wide; ++col) {
                    const float cover = static_cast<float>((bits[row * kW + col] >> 8) & 0xFF) / 255.0f;
                    if (cover <= 0.0f) continue;
                    if (pass == 0) c.blend(x + col + 1, y + row + 1, 8, 10, 14, alpha * cover * 0.85f);
                    else c.blend(x + col, y + row, r, g, b, alpha * cover);
                }
            }
        }
    }
};

std::wstring widen(const std::string& utf8) {
    if (utf8.empty()) return {};
    const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), nullptr, 0);
    std::wstring out(static_cast<size_t>(std::max(n, 0)), L'\0');
    if (n > 0) MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), out.data(), n);
    return out;
}

// A player's symbol and colour: worked out from the player's name, so the same player gets the same pair on every
// PC and in every session, on the minimap and in the party window alike. 6 shapes x 8 colours.
struct PlayerStyle {
    int shape;  // 0 circle, 1 square, 2 diamond, 3 triangle up, 4 triangle down, 5 star
    uint8_t r, g, b;
};
PlayerStyle player_style(const std::string& name) {
    uint32_t h = 2166136261u;
    for (unsigned char c : name) h = (h ^ c) * 16777619u;
    static const uint8_t kColours[8][3] = {{255, 170, 60}, {255, 230, 90}, {255, 120, 190}, {100, 220, 255},
                                           {190, 140, 255}, {170, 240, 100}, {255, 110, 90}, {240, 240, 240}};
    const uint8_t* c = kColours[(h / 6) % 8];
    return {static_cast<int>(h % 6), c[0], c[1], c[2]};
}
// Draws the symbol centred on (cx, cy), `size` pixels across, with a dark outline.
void draw_player_mark(Canvas& c, float cx, float cy, float size, const PlayerStyle& st) {
    auto shape = [&](float half, float r, float g, float b) {
        switch (st.shape) {
        case 0: c.disc(cx, cy, half, r, g, b, 1.0f); break;
        case 1:
            c.triangle(cx - half, cy - half, cx + half, cy - half, cx + half, cy + half, r, g, b, 1.0f);
            c.triangle(cx - half, cy - half, cx + half, cy + half, cx - half, cy + half, r, g, b, 1.0f);
            break;
        case 2:
            c.triangle(cx, cy - half * 1.25f, cx + half * 1.25f, cy, cx, cy + half * 1.25f, r, g, b, 1.0f);
            c.triangle(cx, cy - half * 1.25f, cx, cy + half * 1.25f, cx - half * 1.25f, cy, r, g, b, 1.0f);
            break;
        case 3: c.triangle(cx, cy - half * 1.2f, cx + half * 1.15f, cy + half * 0.9f, cx - half * 1.15f, cy + half * 0.9f, r, g, b, 1.0f); break;
        case 4: c.triangle(cx, cy + half * 1.2f, cx - half * 1.15f, cy - half * 0.9f, cx + half * 1.15f, cy - half * 0.9f, r, g, b, 1.0f); break;
        default:
            c.triangle(cx, cy - half * 1.25f, cx + half * 1.1f, cy + half * 0.65f, cx - half * 1.1f, cy + half * 0.65f, r, g, b, 1.0f);
            c.triangle(cx, cy + half * 1.25f, cx - half * 1.1f, cy - half * 0.65f, cx + half * 1.1f, cy - half * 0.65f, r, g, b, 1.0f);
            break;
        }
    };
    const float half = size * 0.5f;
    shape(half + 1.6f, 16, 18, 24);
    shape(half, st.r, st.g, st.b);
}

// What draw_dial lays over the ground: a copy of g_shared taken once a frame.
struct Overlay {
    std::vector<Marker> markers;
    std::vector<Other> players;
    std::vector<Ping> pings;
    bool waypoint = false;
    float wx = 0, wz = 0;
    float time_of_day = -1;
    bool is_day = true;
    float minutes_left = -1;
    std::string region, place;
    uint64_t now = 0;
};

// The dial: the map of the ground around (x east, z north; metres) out to `range` metres at the rim, a gold rim, a
// red mark for north, small marks for east, south and west, and the player's arrow in the middle turned to `heading`
// (radians, clockwise from north). Without map data: a dark see-through disc instead of the ground.
void draw_dial(Canvas& c, MapData& map, float x_east, float z_north, float range, float heading, const Overlay& ov,
               const Settings& s, TextPainter& text, Icons& icons) {
    const int n = c.dial;  // the dial is the square at the top of the picture, in its middle
    std::fill(c.px, c.px + static_cast<size_t>(c.w) * c.h, 0u);
    const float mid = static_cast<float>(n) * 0.5f;
    const float R = mid - 2.0f;         // outer edge of the rim
    const float rim = std::max(3.0f, static_cast<float>(n) * 0.022f);
    const float mpp = range / (R - rim);                 // metres a pixel
    const bool fine = mpp < 5.0f;                        // far out, the base map alone is enough
    const float step = kLineStep * (mpp < 1.3f ? 1.0f : mpp < 3.0f ? 2.0f : 4.0f);  // farther out: fewer lines
    const float px0 = x_east, py0 = static_cast<float>(MapData::kWorld) - z_north;
    static std::vector<float> heights;
    if (map.ok) {
        map.forget_far(px0, py0);
        heights.assign(static_cast<size_t>(n + 1) * (n + 1), 0.0f);
        for (int y = 0; y <= n; ++y) {
            for (int x = 0; x <= n; ++x) {
                const float dx = static_cast<float>(x) + 0.5f - mid, dy = static_cast<float>(y) + 0.5f - mid;
                if (dx * dx + dy * dy > (R + 2.0f) * (R + 2.0f)) continue;
                heights[static_cast<size_t>(y) * (n + 1) + x] = map.height(px0 + dx * mpp, py0 + dy * mpp, fine);
            }
        }
    }
    for (int y = 0; y < n; ++y) {
        for (int x = 0; x < n; ++x) {
            const float dx = static_cast<float>(x) + 0.5f - mid, dy = static_cast<float>(y) + 0.5f - mid;
            const float d = std::sqrt(dx * dx + dy * dy);
            if (d > R + 1.0f) continue;
            if (map.ok) {
                const float h = heights[static_cast<size_t>(y) * (n + 1) + x];
                float r, g, b;
                ground_colour(h, r, g, b);
                const float band = std::floor((h + kLineShift) / step);
                const float hr = heights[static_cast<size_t>(y) * (n + 1) + x + 1];
                const float hb = heights[static_cast<size_t>(y + 1) * (n + 1) + x];
                if (std::floor((hr + kLineShift) / step) != band || std::floor((hb + kLineShift) / step) != band) {
                    r *= 0.78f;  // a contour line
                    g *= 0.78f;
                    b *= 0.78f;
                }
                c.blend(x, y, r, g, b, std::clamp(R - d, 0.0f, 1.0f));
            } else {
                c.blend(x, y, 16, 20, 26, 0.62f * std::clamp(R - d, 0.0f, 1.0f));
            }
            const float in_rim = std::min(R - d, d - (R - rim));
            c.blend(x, y, 214, 176, 92, std::clamp(in_rim + 0.5f, 0.0f, 1.0f));                     // the rim
        }
    }
    // ---- on top of the ground: markers, players, the waypoint, pings ----
    const float inner = R - rim;                       // the ground's radius in pixels
    // symbols and icons grow with the dial up to the Large size (300), like the letters, unless asked to keep growing
    const float sym_n = static_cast<float>(s.big_text ? n : std::min(n, 300));
    const float u = sym_n * 0.045f;    // the size all symbols are measured in
    // Where a place in the world is on the dial; false when it is outside. clamp: put it at the edge instead.
    auto place = [&](float wx, float wz, float margin, bool clamp, float& sx, float& sy, bool& outside) {
        float dx = (wx - x_east) / mpp, dy = -(wz - z_north) / mpp;
        const float d = std::sqrt(dx * dx + dy * dy), limit = inner - margin;
        outside = d > limit;
        if (outside) {
            if (!clamp) return false;
            dx *= limit / d;
            dy *= limit / d;
        }
        sx = mid + dx;
        sy = mid + dy;
        return true;
    };
    float sx, sy;
    bool outside;
    // the game's icons: about as large as on its own map when zoomed in, smaller when more ground is in view
    const float icon_px = sym_n * (mpp < 1.3f ? 0.150f : mpp < 4.0f ? 0.125f : 0.100f);
    // the names on the map (markers, other players) are smaller than the lines under the dial, so more of them fit;
    // their own painter, so the two letter sizes are not made anew every frame
    static TextPainter names;
    const int name_px = std::max(11, letter_px(s, n) * 7 / 10);
    const bool labels = s.labels && mpp < 2.5f && names.ready(nullptr, name_px);
    for (int pass = 0; pass < 2; ++pass) {  // flame altars last, on top of everything else
        for (const Marker& k : ov.markers) {
            const Style& st = kStyles[k.kind];
            if ((st.shape == kAltar) != (pass == 1)) continue;
            const float q = u * st.size, a = k.state == 3 ? 0.55f : k.state < 2 ? 0.45f : 1.0f;  // dimmer once completed or not found yet
            if (!place(k.x, k.z, std::max(q + 1.0f, icon_px * 0.45f), false, sx, sy, outside)) continue;
            const int ipx = static_cast<int>(icon_px * kIcons[k.kind].scale + 0.5f);
            if (const uint8_t* pic = icons.sized(k.kind, ipx)) {  // the game's own icon
                if (st.custom) c.disc(sx, sy, static_cast<float>(ipx) * 0.46f, 34, 38, 46, 0.92f);  // a dark disc under it
                c.picture(pic, ipx, sx, sy, k.state < 2 ? 0.8f : 1.0f, k.state < 2);  // light grey while not found yet
                if (k.state < 2) {  // and a small "?" at its lower right
                    static TextPainter badge;
                    badge.weight = FW_NORMAL;  // thin strokes: the mark is only a few pixels high
                    const int bpx = std::max(8, ipx * 7 / 20);
                    if (badge.ready(nullptr, std::min(bpx * 3, 52))) {  // 3 times too big; 52: what the painter's picture holds
                        const float bx = sx + static_cast<float>(ipx) * 0.15f, by = sy + static_cast<float>(ipx) * 0.14f;  // well onto the icon: its picture has empty edges
                        c.disc(bx, by, static_cast<float>(bpx) * 0.56f - 1.0f, 62, 66, 74, 0.96f);  // a dark grey dot
                        badge.draw_fine(c, bx, by, L"?", 3, 255, 232, 150);
                    }
                }
                if (k.state == 3) {  // completed: the game's tick at its lower right
                    const int tpx = std::max(8, ipx * 9 / 20);
                    if (const uint8_t* tick = icons.sized(kIconCompleted, tpx))
                        c.picture(tick, tpx, sx + static_cast<float>(ipx) * 0.30f, sy + static_cast<float>(ipx) * 0.28f, 1.0f);
                }
                if (labels && (!k.name.empty() || st.label[0])) {
                    const std::wstring name = widen(k.name.empty() ? std::string(st.label) : k.name);
                    names.draw(c, static_cast<int>(sx) - names.width(name) / 2, static_cast<int>(sy) + ipx / 2 - 2, name, 240, 232, 210,
                              k.state < 2 ? 0.7f : 1.0f);
                }
                continue;
            }
            const float fr = st.r, fg = st.g, fb = st.b, mr = st.r2, mg = st.g2, mb = st.b2;
            const float dr = fr * 0.16f, dg = fg * 0.16f, db = fb * 0.16f;  // the outline: the fill, very dark
            switch (st.shape) {
            case kAltar:
                c.diamond(sx, sy, q + 1.5f, dr, dg, db, a);
                c.diamond(sx, sy, q, fr, fg, fb, a);
                c.triangle(sx, sy - q * 0.62f, sx - q * 0.36f, sy + q * 0.36f, sx + q * 0.36f, sy + q * 0.36f, mr, mg, mb, a);
                break;
            case kDrop: {
                const float rr = q * 0.46f, cy = sy + q * 0.18f;
                c.disc(sx, cy, rr + 1.3f, 16, 30, 52, a);
                c.triangle(sx, cy - rr * 2.3f - 1.6f, sx - rr - 1.0f, cy - rr * 0.3f, sx + rr + 1.0f, cy - rr * 0.3f, 16, 30, 52, a);
                c.disc(sx, cy, rr, fr, fg, fb, a);
                c.triangle(sx, cy - rr * 2.2f, sx - rr * 0.92f, cy - rr * 0.35f, sx + rr * 0.92f, cy - rr * 0.35f, fr, fg, fb, a);
                break;
            }
            case kDiamond:
                c.diamond(sx, sy, q + 1.4f, dr, dg, db, a);
                c.diamond(sx, sy, q, fr, fg, fb, a);
                c.disc(sx, sy, q * 0.28f, mr, mg, mb, a);
                break;
            case kSquare: {
                const float e = q * 0.78f;
                c.pill(sx - e - 1.4f, sy - e - 1.4f, sx + e + 1.4f, sy + e + 1.4f, dr, dg, db, a);
                c.triangle(sx - e, sy - e, sx - e, sy + e, sx + e, sy + e, fr, fg, fb, a);
                c.triangle(sx - e, sy - e, sx + e, sy + e, sx + e, sy - e, fr, fg, fb, a);
                c.disc(sx, sy, q * 0.30f, mr, mg, mb, a);
                break;
            }
            case kDisc:
                c.disc(sx, sy, q + 1.4f, dr, dg, db, a);
                c.disc(sx, sy, q, fr, fg, fb, a);
                c.disc(sx, sy, q * 0.38f, mr, mg, mb, a);
                break;
            case kTriangle:
                c.triangle(sx, sy - q - 2.2f, sx - q - 2.0f, sy + q * 0.8f + 1.4f, sx + q + 2.0f, sy + q * 0.8f + 1.4f, dr, dg, db, a);
                c.triangle(sx, sy - q, sx - q, sy + q * 0.8f, sx + q, sy + q * 0.8f, fr, fg, fb, a);
                c.disc(sx, sy + q * 0.25f, q * 0.24f, mr, mg, mb, a);
                break;
            case kTower: {  // a tall block with a pointed top
                const float hw = q * 0.42f;
                c.triangle(sx, sy - q * 1.25f - 2.0f, sx - hw - 2.2f, sy - q * 0.3f, sx + hw + 2.2f, sy - q * 0.3f, dr, dg, db, a);
                c.triangle(sx - hw - 1.4f, sy - q * 0.45f, sx - hw - 1.4f, sy + q + 1.4f, sx + hw + 1.4f, sy + q + 1.4f, dr, dg, db, a);
                c.triangle(sx - hw - 1.4f, sy - q * 0.45f, sx + hw + 1.4f, sy + q + 1.4f, sx + hw + 1.4f, sy - q * 0.45f, dr, dg, db, a);
                c.triangle(sx, sy - q * 1.25f, sx - hw - 0.8f, sy - q * 0.4f, sx + hw + 0.8f, sy - q * 0.4f, fr, fg, fb, a);
                c.triangle(sx - hw, sy - q * 0.4f, sx - hw, sy + q, sx + hw, sy + q, fr, fg, fb, a);
                c.triangle(sx - hw, sy - q * 0.4f, sx + hw, sy + q, sx + hw, sy - q * 0.4f, fr, fg, fb, a);
                c.disc(sx, sy + q * 0.25f, q * 0.2f, mr, mg, mb, a);
                break;
            }
            case kHouse: {  // a box with a roof
                const float e = q * 0.66f;
                c.triangle(sx, sy - q - 2.2f, sx - q - 2.2f, sy - q * 0.1f + 1.0f, sx + q + 2.2f, sy - q * 0.1f + 1.0f, dr, dg, db, a);
                c.triangle(sx - e - 1.4f, sy - q * 0.2f, sx - e - 1.4f, sy + q * 0.8f + 1.4f, sx + e + 1.4f, sy + q * 0.8f + 1.4f, dr, dg, db, a);
                c.triangle(sx - e - 1.4f, sy - q * 0.2f, sx + e + 1.4f, sy + q * 0.8f + 1.4f, sx + e + 1.4f, sy - q * 0.2f, dr, dg, db, a);
                c.triangle(sx, sy - q, sx - q, sy - q * 0.1f, sx + q, sy - q * 0.1f, fr, fg, fb, a);
                c.triangle(sx - e, sy - q * 0.1f, sx - e, sy + q * 0.8f, sx + e, sy + q * 0.8f, fr, fg, fb, a);
                c.triangle(sx - e, sy - q * 0.1f, sx + e, sy + q * 0.8f, sx + e, sy - q * 0.1f, fr, fg, fb, a);
                c.disc(sx, sy + q * 0.4f, q * 0.22f, mr, mg, mb, a);
                break;
            }
            case kRing:
                c.disc(sx, sy, q + 1.4f, dr, dg, db, a);
                c.disc(sx, sy, q, fr, fg, fb, a);
                c.disc(sx, sy, q * 0.5f, mr, mg, mb, a);
                break;
            }
            if (labels && (!k.name.empty() || st.label[0])) {
                const std::wstring name = widen(k.name.empty() ? std::string(st.label) : k.name);
                names.draw(c, static_cast<int>(sx) - names.width(name) / 2, static_cast<int>(sy + q) + 1, name, 240, 232, 210, a);
            }
        }
    }
    for (const Ping& k : ov.pings) {  // a ping: bright green, with two rings that keep growing, for eight seconds
        const float age = static_cast<float>(ov.now - k.at) / 1000.0f;
        if (age > 8.0f || !place(k.x, k.z, u, true, sx, sy, outside)) continue;
        const float fade = std::min(1.0f, (8.0f - age) / 1.0f);
        for (int ring = 0; ring < 2; ++ring) {
            const float t = age * 0.9f + static_cast<float>(ring) * 0.5f, beat = t - std::floor(t);
            c.disc(sx, sy, u * (0.7f + 2.4f * beat) + 1.0f, 6, 40, 14, fade * (1.0f - beat) * 0.8f, 5.0f);
            c.disc(sx, sy, u * (0.7f + 2.4f * beat), 70, 255, 110, fade * (1.0f - beat), 3.0f);
        }
        const int ppx = static_cast<int>(icon_px + 0.5f);
        if (const uint8_t* pic = icons.sized(kIconPing, ppx)) {  // the game's own ping icon in the middle
            c.picture(pic, ppx, sx, sy, fade);
        } else {
            c.disc(sx, sy, u * 0.62f + 1.6f, 6, 40, 14, fade);
            c.disc(sx, sy, u * 0.62f, 70, 255, 110, fade);
            c.disc(sx, sy, u * 0.24f, 226, 255, 232, fade);
        }
    }
    if (ov.waypoint && place(ov.wx, ov.wz, u, true, sx, sy, outside)) {  // the waypoint: a light blue ring with a dot
        const int wpx = static_cast<int>(icon_px + 0.5f);
        if (const uint8_t* pic = icons.sized(kIconWaypoint, wpx)) {  // the game's own waypoint icon
            c.picture(pic, wpx, sx, sy, 1.0f);
        } else {
            c.disc(sx, sy, u * 0.86f + 1.4f, 10, 30, 44, 1.0f);
            c.disc(sx, sy, u * 0.86f, 120, 226, 255, 1.0f);
            c.disc(sx, sy, u * 0.52f, 10, 30, 44, 1.0f);
            c.disc(sx, sy, u * 0.26f, 232, 250, 255, 1.0f);
        }
    }
    for (const Other& k : ov.players) {  // other players: their symbol and colour (as in the party window), at the edge when
                                         // far away, and the name; a white dot for a player whose name is not known
        if (!place(k.x, k.z, u, true, sx, sy, outside)) continue;
        if (k.name.empty()) {
            c.disc(sx, sy, u * 0.5f + 1.5f, 20, 22, 28, 1.0f);
            c.disc(sx, sy, u * 0.5f, 246, 246, 250, 1.0f);
            continue;
        }
        const PlayerStyle st = player_style(k.name);
        const bool tracked = !g_tracked.empty() && k.name == g_tracked, down = g_down.count(k.name) > 0;
        if (tracked) c.disc(sx, sy, u * 1.15f + 4.5f, 255, 214, 90, 0.95f);  // followed (party window): a gold ring
        if (down) c.disc(sx, sy, u * 1.15f + 2.0f, 235, 40, 40, 1.0f);       // health 0: a red ring
        draw_player_mark(c, sx, sy, u * 1.15f, st);
        if ((!outside || tracked) && names.ready(nullptr, name_px)) {
            const std::wstring name = widen(k.name);
            names.draw(c, static_cast<int>(sx) - names.width(name) / 2, static_cast<int>(sy - u * 0.6f) - names.font_px - 4, name, st.r, st.g, st.b);
        }
    }

    const float m = sym_n * 0.055f;  // size of the marks
    const float nm = sym_n * 0.055f;                  // north's: narrower and shorter than it was, and a purer red
    c.triangle(mid, mid - R + rim + nm * 1.5f, mid - nm * 0.62f, mid - R + rim + 1.0f, mid + nm * 0.62f, mid - R + rim + 1.0f,
               238, 24, 24, 1.0f);                                                                   // north
    const float t = std::max(1.5f, m * 0.28f), len = m * 1.1f, e = R - rim - 1.0f;
    c.triangle(mid + e, mid - t, mid + e, mid + t, mid + e - len, mid, 222, 214, 190, 0.9f);        // east
    c.triangle(mid - e, mid - t, mid - e, mid + t, mid - e + len, mid, 222, 214, 190, 0.9f);        // west
    c.triangle(mid - t, mid + e, mid + t, mid + e, mid, mid + e - len, 222, 214, 190, 0.9f);        // south

    // the player's arrow, like the one on the game's map: an orange-red arrowhead with a notch, a smaller piece
    // behind it, and a dark outline
    const float L = sym_n * 0.062f, W = L * 0.70f;  // like the other symbols: no bigger than on the Large dial
    const float cs = std::cos(heading), sn = std::sin(heading);
    auto turn = [&](float px_, float py_, float& ox, float& oy) {
        ox = mid + px_ * cs - py_ * sn;
        oy = mid + px_ * sn + py_ * cs;
    };
    // a shape of four corners: tip, left, notch, right (notch between the back corners), as two triangles
    auto quad = [&](float tx_, float ty_, float lx_, float ly_, float nx_, float ny_, float rx_, float ry_, float r, float g,
                    float b, float r2, float g2, float b2) {
        float tx, ty, lx, ly, nx, ny, rx, ry;
        turn(tx_, ty_, tx, ty);
        turn(lx_, ly_, lx, ly);
        turn(nx_, ny_, nx, ny);
        turn(rx_, ry_, rx, ry);
        c.triangle(tx, ty, lx, ly, nx, ny, r, g, b, 1.0f);
        c.triangle(tx, ty, nx, ny, rx, ry, r2, g2, b2, 1.0f);
    };
    const float o = 1.6f;  // the outline's width in pixels
    // outlines first (dark teal), then the two pieces
    quad(0, -L - o * 1.6f, -W - o * 1.3f, L * 0.62f + o, 0, L * 0.20f + o, W + o * 1.3f, L * 0.62f + o, 30, 52, 54, 30, 52, 54);
    quad(0, L * 0.30f - o, -W * 0.62f - o, L + o * 0.9f, 0, L * 0.80f + o, W * 0.62f + o, L + o * 0.9f, 30, 52, 54, 30, 52, 54);
    quad(0, -L, -W, L * 0.62f, 0, L * 0.20f, W, L * 0.62f, 240, 98, 64, 222, 82, 54);
    quad(0, L * 0.42f, -W * 0.55f, L * 0.95f, 0, L * 0.78f, W * 0.55f, L * 0.95f, 240, 98, 64, 222, 82, 54);

    if (s.move) c.disc(mid, mid, R + 1.0f, 110, 226, 255, 0.95f, std::max(3.0f, rim));  // the pointer is out: it can be dragged

    // ---- under the dial: one line with the clock and, at its end, how high the player is ----
    const bool show_clock = s.clock && ov.time_of_day >= 0;
    if ((show_clock || s.altitude) && c.h > n && text.ready(nullptr, letter_px(s, n))) {
        // Always in the usual letters. The line may reach past the dial on both sides (the picture is wider than the
        // dial for that); only when even that is not enough is the shorter wording used.
        const int alt_m = static_cast<int>(std::lround(g_y.load()));
        const int total = show_clock ? static_cast<int>(ov.time_of_day * 60.0f + 0.5f) % (24 * 60) : 0;
        const int left = ov.minutes_left >= 0 ? static_cast<int>(std::ceil(ov.minutes_left)) : -1;
        TextPainter* tp = &text;
        std::wstring t;
        float icon = 0.0f, lead = 0.0f;
        for (int form = 0; form < 2; ++form) {
            wchar_t part[96];
            t.clear();
            if (show_clock) {
                if (left >= 0 && form == 0) {
                    swprintf(part, 96, L"%02d:%02d   %ls in %d min", total / 60, total % 60, ov.is_day ? L"Night" : L"Day", left);
                } else if (left >= 0) {
                    swprintf(part, 96, L"%02d:%02d  %ls in %dm", total / 60, total % 60, ov.is_day ? L"Night" : L"Day", left);
                } else {
                    swprintf(part, 96, L"%02d:%02d", total / 60, total % 60);
                }
                t = part;
            }
            if (s.altitude) {
                swprintf(part, 96, form == 0 ? L"%lsAlt %d m" : L"%lsAlt %dm", !show_clock ? L"" : form == 0 ? L"   " : L"  ", alt_m);
                t += part;
            }
            icon = show_clock ? static_cast<float>(text.font_px) * 0.42f : 0.0f;
            lead = show_clock ? icon * 2.0f + 8.0f : 0.0f;  // room for the sun or the moon
            const float room = static_cast<float>(c.w) - 24.0f - lead;
            if (static_cast<float>(text.width(t)) <= room) break;
        }
        const int tw = tp->width(t), th = text.font_px + text.font_px / 3;  // the pill keeps the line's usual height
        const float full = static_cast<float>(tw) + lead;
        const float x0 = mid - full * 0.5f, y0 = static_cast<float>(n) + 3.0f;
        c.pill(x0 - 10.0f, y0, x0 + full + 10.0f, y0 + static_cast<float>(th) + 4.0f, 14, 17, 22, 0.72f);
        if (show_clock) {
            const float ix = x0 + icon, iy = y0 + (static_cast<float>(th) + 4.0f) * 0.5f;
            if (ov.is_day) {
                c.disc(ix, iy, icon, 255, 208, 84, 1.0f);  // the sun
            } else {
                c.disc(ix, iy, icon, 206, 216, 240, 1.0f);  // the moon: a disc with a bite out of it
                c.disc(ix + icon * 0.45f, iy - icon * 0.2f, icon * 0.86f, 14, 17, 22, 1.0f);
            }
        }
        tp->draw(c, static_cast<int>(x0 + lead), static_cast<int>(y0) + 1 + (text.font_px - tp->font_px) / 2, t, 236, 228, 206);
    }

    // ---- under that: the region, and the named place the player is in ----
    if (s.where && text.ready(nullptr, letter_px(s, n))) {
        const int line = text.font_px * 4 / 3 + 8;
        float y0 = static_cast<float>(n) + 3.0f + ((s.clock || s.altitude) ? static_cast<float>(line) : 0.0f);
        auto put = [&](const std::string& words, float r, float g, float b) {
            if (words.empty()) return;
            std::wstring t = widen(words);
            while (t.size() > 4 && text.width(t) > n - 24) {  // too long for the dial's width: shorten it
                t.resize(t.size() - 2);
                t.back() = L'\u2026';
            }
            const int tw = text.width(t), th = text.font_px + text.font_px / 3;
            const float x0 = mid - static_cast<float>(tw) * 0.5f;
            c.pill(x0 - 10.0f, y0, x0 + static_cast<float>(tw) + 10.0f, y0 + static_cast<float>(th) + 4.0f, 14, 17, 22, 0.72f);
            text.draw(c, static_cast<int>(x0), static_cast<int>(y0) + 1, t, r, g, b);
            y0 += static_cast<float>(line);
        };
        put(ov.region, 250, 206, 110);
        put(ov.place, 236, 228, 206);
    }
}

// ---- the overlay window ----

HWND g_overlay = nullptr;

struct FindGame {
    DWORD pid;
    HWND best;
    long long best_area;
};

BOOL CALLBACK find_game_window(HWND h, LPARAM lp) {
    auto* f = reinterpret_cast<FindGame*>(lp);
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    if (pid != f->pid || h == g_overlay || !IsWindowVisible(h) || GetWindow(h, GW_OWNER)) return TRUE;
    RECT r{};
    if (!GetClientRect(h, &r)) return TRUE;
    const long long area = static_cast<long long>(r.right - r.left) * (r.bottom - r.top);
    if (area > f->best_area) {
        f->best_area = area;
        f->best = h;
    }
    return TRUE;
}

// The game's main window: the largest visible top-level window of this process.
HWND game_window() {
    FindGame f{GetCurrentProcessId(), nullptr, 0};
    EnumWindows(find_game_window, reinterpret_cast<LPARAM>(&f));
    return f.best_area >= 200 * 200 ? f.best : nullptr;
}

// ==== FlameKit's UI framework ====
// One overlay window over the game's picture shows all of FlameKit's UI. Each piece (the minimap, the Auto Junk List
// window, the lines in the lower left corner) is a Layer: it draws into its own picture (a Canvas) and says where that
// goes, in the game window's client coordinates. The Compositor puts the visible layers into one picture the size of
// the game window's client area (the surface: premultiplied BGRA, top row first, plain memory), and the Presenter
// shows the part of it that changed. Today's presenter is a layered window kept in front of the game; a presenter that
// draws the same surface inside the game's own frame (Vulkan) can take its place without the layers changing. Input
// goes the other way: the presenter hands mouse and keys to the layers (Compositor::mouse / key).
// Everything here runs on one thread (ui_thread), so the layers need no locks of their own.

struct Frame {  // what a layer gets to know about this moment
    uint64_t now = 0;
    HWND game = nullptr;
    int gw = 0, gh = 0;      // the game window's client size
    POINT origin{};          // its client area's top left corner on the screen
    bool game_front = false; // the game's own window is the foreground window
    bool ours_front = false; // a window of the game's process is the foreground window (the game, or FlameKit's overlay)
    bool in_world = false;   // a world runs (the player's position came within the last 1.5 s)
    bool in_menu = false;    // one of the game's menus is open (bag, map, skills, ...): the game shows its own pointer
};

struct Layer {
    virtual ~Layer() = default;
    virtual const char* name() const = 0;
    // Brings the layer up to date: visible, rect (where, in the game window's client coordinates; its size is the
    // canvas's) and the picture. Sets changed when the picture changed.
    virtual void update(const Frame& f) = 0;
    virtual bool wants_mouse() const { return false; }  // takes clicks on its own pixels now
    virtual bool wants_keys() const { return false; }   // takes the keyboard: the overlay becomes the front window
    virtual void mouse(UINT msg, int x, int y) {}       // x, y: in the layer's own picture
    virtual void mouse_left() {}
    virtual void wheel(int delta, int x, int y) {}      // the mouse wheel over the layer (delta: WHEEL_DELTA a notch)
    virtual void key(WPARAM vk) {}
    virtual void lost_front() {}                        // another window took the front while the layer had the keys

    bool visible = false;
    bool changed = true;
    RECT rect{};
    Canvas canvas;
    std::vector<uint32_t> pixels;
    void resize(int w, int h) {
        if (canvas.w == w && canvas.h == h && canvas.px) return;
        pixels.assign(static_cast<size_t>(w) * h, 0u);
        canvas.w = w;
        canvas.h = h;
        canvas.px = pixels.data();
        changed = true;
    }
    void place(int x, int y) {
        const RECT r{x, y, x + canvas.w, y + canvas.h};
        if (!EqualRect(&r, &rect)) {
            rect = r;
            changed = true;
        }
    }
};

HDC g_screen = nullptr;  // the screen's DC, for the text painters (UI thread)
std::wstring g_flamekit_dir;  // ...\emf\mods\flamekit\ (ends with a backslash)
std::wstring g_game_dir;      // the game's folder (ends with a backslash)

std::wstring game_dir_of_process() {
    wchar_t exe[MAX_PATH];
    const DWORD n = GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring dir(exe, n);
    return dir.substr(0, dir.find_last_of(L"\\/") + 1);
}

std::string window_info(HWND h) {
    // For the log: a window of the game's process with its class and title; any other program's window only by its
    // program's file name and window class, never its title (another program's titles can hold private things).
    if (!h) return "(none)";
    wchar_t cls[96] = L"";
    GetClassNameW(h, cls, 96);
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    char out[400];
    if (pid == GetCurrentProcessId()) {
        wchar_t title[96] = L"";
        GetWindowTextW(h, title, 96);
        snprintf(out, sizeof out, "%p class '%ls' title '%ls' (the game's process)", static_cast<void*>(h), cls, title);
        return out;
    }
    wchar_t program[MAX_PATH] = L"?";
    if (HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) {
        DWORD n = MAX_PATH;
        wchar_t full[MAX_PATH];
        if (QueryFullProcessImageNameW(proc, 0, full, &n)) {
            const wchar_t* slash = wcsrchr(full, L'\\');
            wcsncpy_s(program, slash ? slash + 1 : full, _TRUNCATE);
        }
        CloseHandle(proc);
    }
    snprintf(out, sizeof out, "%p program %ls, class '%ls'", static_cast<void*>(h), program, cls);
    return out;
}

// ---- the minimap layer ----
// Moving it with the mouse: only while the "move" setting is on.
bool g_pointer_mode = false;  // the pointer is out: FlameKit's window is open or Right Alt is held (UI thread)
bool g_pointer_hold = false;  // Right Alt is held while the game's process is in front (UI thread)

struct MinimapLayer : Layer {
    const char* name() const override { return "minimap"; }
    TextPainter text;
    Icons icons;
    MapData map;
    bool loaded = false;
    uint64_t drawn_at = 0, said_at = 0;
    bool said_shown = false;
    bool dragging = false, has_drag = false, dropped = false;
    POINT grab{}, drag_pos{};  // where in the picture it was grabbed; the picture's top left corner (client coordinates)
    int pad = 0, dial_w = 0, dial_h = 0;
    uint64_t panel_looked = 0;
    bool panel_open = false;
    // timing, for the log at full
    uint64_t draws = 0, draw_us = 0, draw_max_us = 0, timing_at = 0;

    void load() {
        loaded = true;
        const uint64_t began = GetTickCount64();
        map.open(g_game_dir);
        icons.load(g_game_dir);
        FK_LOG(fklog::kInfo, "minimap: icons: %d of %d of the game's marker icons found in its data files", icons.found, kIconCount);
        std::string loca_note;
        g_loca.load(g_game_dir, loca_note);
        FK_LOG(fklog::kInfo, "minimap: names: %s: %s (%u texts)", g_loca.ready.load() ? "the game's place names are used" : "no place names",
               loca_note.c_str(), g_loca.rows);
        FK_LOG(fklog::kInfo, "minimap: map: %s: %s (%llu ms)", map.ok ? "read from the game's data files" : "no map, plain dial",
               map.note.c_str(), GetTickCount64() - began);
    }

    // FlameKit's old panel is open: it is drawn by EMF inside the game's picture, so the minimap would lie over it. The
    // panel (Lua) writes "1" into panel_open.dat twice a second while it is open and "0" when it closes; a file not
    // written for 1.5 s counts as closed.
    bool read_panel_open() {
        WIN32_FILE_ATTRIBUTE_DATA info{};
        const std::wstring flag = g_flamekit_dir + L"panel_open.dat";
        if (!GetFileAttributesExW(flag.c_str(), GetFileExInfoStandard, &info)) return false;
        FILETIME now_ft;
        GetSystemTimeAsFileTime(&now_ft);
        const uint64_t written = static_cast<uint64_t>(info.ftLastWriteTime.dwHighDateTime) << 32 | info.ftLastWriteTime.dwLowDateTime;
        const uint64_t now_100ns = static_cast<uint64_t>(now_ft.dwHighDateTime) << 32 | now_ft.dwLowDateTime;
        if (now_100ns >= written + 15000000ull) return false;
        bool open = false;
        if (FILE* fp = _wfsopen(flag.c_str(), L"rb", _SH_DENYNO)) {
            open = fgetc(fp) == '1';
            fclose(fp);
        }
        return open;
    }

    void update(const Frame& f) override {
        if (!loaded) load();
        Settings s = settings();
        // While the pointer is out (FlameKit's window open, or the pointer key held) the minimap can be dragged, like the
        // pinned windows; let go, its place is kept (map_x, map_y). "Back to its corner" in the Minimap tab undoes it.
        s.move = g_pointer_mode;
        if (!g_pointer_mode && dragging) {
            dragging = false;
            dropped = true;
        }
        bool in_menu = false;  // the game shows its mouse pointer only in its menus (the big map, the bag, ...)
        if (f.game_front && s.hide_menus && !g_pointer_mode) {  // (FlameKit's own pointer is not a game menu)
            CURSORINFO ci{};
            ci.cbSize = sizeof(ci);
            // a pointer that is "showing" but has no picture is not on screen: the game hides its pointer that way too
            in_menu = GetCursorInfo(&ci) && (ci.flags & CURSOR_SHOWING) != 0 && ci.hCursor != nullptr;
        }
        if (f.now - panel_looked > 150) {
            panel_looked = f.now;
            panel_open = read_panel_open();
        }
        const bool want = s.show && f.in_world && !in_menu && !panel_open && !g_travelling.load() && f.game && f.gw > 0;
        if (want != visible) {
            visible = want;
            changed = true;
            FK_LOG(fklog::kDebug, "minimap: %s (show %d, world %d, menu %d, panel %d, travelling %d)", want ? "shown" : "hidden", s.show,
                   f.in_world, in_menu, panel_open, g_travelling.load() ? 1 : 0);
        }
        if (!visible) return;
        if (f.now - drawn_at < 33 && !dragging) return;  // about 30 pictures a second
        drawn_at = f.now;

        const int line = letter_px(s, s.size) * 4 / 3 + 8;  // one line of text under the dial
        dial_w = s.size;
        dial_h = s.size + 4 + ((s.clock || s.altitude) ? line : 0) + (s.where ? 2 * line : 0);
        pad = (s.clock || s.altitude) ? s.size / 4 : 0;  // room on each side for the clock's line
        resize(dial_w + 2 * pad, dial_h);
        canvas.dial = dial_w;
        canvas.ox = pad;
        Overlay over;
        over.now = f.now;
        {
            std::lock_guard<std::mutex> l(g_shared.lock);
            auto& pings = g_shared.pings;
            pings.erase(std::remove_if(pings.begin(), pings.end(), [&](const Ping& p) { return f.now - p.at > 8000; }), pings.end());
            over.markers = g_shared.markers;
            over.players = g_shared.players;
            over.pings = pings;
            over.waypoint = g_shared.waypoint;
            over.wx = g_shared.wx;
            over.wz = g_shared.wz;
            over.time_of_day = g_shared.time_of_day;
            over.is_day = g_shared.is_day;
            over.minutes_left = g_shared.minutes_left;
            over.region = g_shared.region;
            over.place = g_shared.place;
        }
        LARGE_INTEGER t0, t1, freq;
        QueryPerformanceCounter(&t0);
        text.ready(g_screen, letter_px(s, s.size));
        const float more = s.big_text ? 1.0f : std::max(1.0f, static_cast<float>(s.size) / 300.0f);
        draw_dial(canvas, map, g_x.load(), g_z.load(), kRanges[s.zoom] * more, g_heading.load(), over, s, text, icons);
        QueryPerformanceCounter(&t1);
        QueryPerformanceFrequency(&freq);
        const uint64_t us = static_cast<uint64_t>((t1.QuadPart - t0.QuadPart) * 1000000 / freq.QuadPart);
        ++draws;
        draw_us += us;
        draw_max_us = std::max(draw_max_us, us);
        if (f.now - timing_at >= 10000) {
            FK_LOG(fklog::kDebug, "minimap: %llu pictures in %.1f s, %.2f ms each on average, %.2f ms the longest; player at x %.0f z %.0f, "
                   "heading %.2f, %d marker(s), %d other player(s)", draws, (f.now - timing_at) / 1000.0, draws ? draw_us / 1000.0 / draws : 0.0,
                   draw_max_us / 1000.0, g_x.load(), g_z.load(), g_heading.load(), static_cast<int>(over.markers.size()),
                   static_cast<int>(over.players.size()));
            draws = draw_us = draw_max_us = 0;
            timing_at = f.now;
        }
        changed = true;

        // where: the corner, or where the player put it, or where it is being dragged (the dial's corner, then the pad)
        const bool right = s.corner == 0 || s.corner == 1, bottom = s.corner == 1 || s.corner == 2;
        int x = right ? f.gw - dial_w - s.margin : s.margin, y = bottom ? f.gh - dial_h - s.margin : s.margin;
        const int free_x = std::max(1, f.gw - dial_w), free_y = std::max(1, f.gh - dial_h);
        if (has_drag) {
            x = std::clamp(static_cast<int>(drag_pos.x) + pad, 0, free_x);
            y = std::clamp(static_cast<int>(drag_pos.y), 0, free_y);
            if (dropped) {  // let go: remember the place and end the move (on the game's own thread)
                dropped = false;
                has_drag = false;
                const int px = static_cast<int>(x * 1000ll / free_x), py = static_cast<int>(y * 1000ll / free_y);
                FK_LOG(fklog::kInfo, "minimap: moved to %d,%d (thousandths of the free room)", px, py);
                emf::run_on_world(EMF_WORLD_CLIENT, [px, py](emf::World) {
                    emf::set_setting(kKit, "map_x", std::to_string(px));
                    emf::set_setting(kKit, "map_y", std::to_string(py));
                });
            }
        } else if (s.pos_x >= 0 && s.pos_y >= 0) {
            x = static_cast<int>(static_cast<long long>(std::min(s.pos_x, 1000)) * free_x / 1000);
            y = static_cast<int>(static_cast<long long>(std::min(s.pos_y, 1000)) * free_y / 1000);
        }
        place(x - pad, y);
        if (!said_shown) {
            said_shown = true;
            FK_LOG(fklog::kInfo, "minimap: first shown at %ld,%ld (game %dx%d), size %d", rect.left, rect.top, f.gw, f.gh, s.size);
        }
    }

    bool wants_mouse() const override { return g_pointer_mode && visible; }
    void mouse(UINT msg, int x, int y) override {
        if (msg == WM_LBUTTONDOWN) {
            grab = {x, y};
            drag_pos = {rect.left, rect.top};
            dragging = has_drag = true;
        } else if (msg == WM_MOUSEMOVE && dragging) {
            drag_pos = {rect.left + x - grab.x, rect.top + y - grab.y};
        } else if (msg == WM_LBUTTONUP && dragging) {
            dragging = false;
            dropped = true;
        }
    }
};

// ---- pinned windows: shown while the player plays ----
// A pinned window stays on the screen and never takes the mouse or the keyboard, so the game is played as usual. While
// the pointer is out (FlameKit's window is open, or Right Alt is held: g_pointer_mode) every pinned window can be dragged
// by its title bar, made wider or narrower from its lower right corner, collapsed to its title bar (the "-" button) or
// hidden (the "x" button; FlameKit's window, tab Windows, shows it again). Where each one is, its width and whether it is
// collapsed or hidden are kept in emf\mods\flamekit\ui_layout.txt (this DLL is its one writer):
//   <window id> <x> <y> <width> <collapsed 0|1> <hidden 0|1> <height>   (x, y: its top left corner in the game window, -1:
//   default; height: 0 as tall as the content, else at most this tall, the content then scrolls). "window" is FlameKit's
//   own window (F6), which can be moved and resized the same way.

struct LayoutEntry {
    int x = -1, y = -1, w = 0;
    bool collapsed = false, hidden = false;
    int h = 0;  // the height the player gave it (0: as tall as its content); a pinned window is at most this tall
};
struct Layout {
    std::unordered_map<std::string, LayoutEntry> entries;
    bool loaded = false;
    void load() {
        loaded = true;
        if (FILE* fp = _wfsopen((g_flamekit_dir + L"ui_layout.txt").c_str(), L"rb", _SH_DENYNO)) {
            char line[256], id[64];
            while (fgets(line, sizeof line, fp)) {
                int x, y, w, c, hid, h = 0;  // the height came in 0.15.28: older lines have 6 fields
                if (sscanf_s(line, "%63s %d %d %d %d %d %d", id, static_cast<unsigned>(sizeof id), &x, &y, &w, &c, &hid, &h) >= 6)
                    entries[id] = {x, y, w, c != 0, hid != 0, h};
            }
            fclose(fp);
        }
        FK_LOG(fklog::kInfo, "pinned: layout read: %d window(s)", static_cast<int>(entries.size()));
    }
    void save() {
        std::string text;
        for (const auto& [id, e] : entries) {
            char line[160];
            snprintf(line, sizeof line, "%s %d %d %d %d %d %d\n", id.c_str(), e.x, e.y, e.w, e.collapsed ? 1 : 0, e.hidden ? 1 : 0, e.h);
            text += line;
        }
        const std::wstring file = g_flamekit_dir + L"ui_layout.txt", tmp = file + L".tmp";
        bool ok = false;
        if (FILE* fp = _wfsopen(tmp.c_str(), L"wb", _SH_DENYNO)) {
            ok = fwrite(text.data(), 1, text.size(), fp) == text.size();
            ok = fclose(fp) == 0 && ok;
        }
        ok = ok && MoveFileExW(tmp.c_str(), file.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
        if (!ok) FK_LOG(fklog::kError, "pinned: ui_layout.txt could not be written (error %lu)", GetLastError());
    }
    LayoutEntry& get(const std::string& id) {
        if (!loaded) load();
        return entries[id];
    }
};
Layout g_layout;

struct PinnedLayer;
std::vector<PinnedLayer*> g_pinned;  // every pinned window, for the Windows tab

struct PinnedLayer : Layer {
    std::string id;
    std::wstring title;
    int default_w = 300, min_w = 220, max_w = 640;
    int def_x_pm = 12, def_y_pm = 333;  // the first place: per mille of the game window's width and height
    static constexpr int kHead = 28, kGrip = 14;
    TextPainter text, little;  // ("small" is a macro in Windows' headers)
    bool fonts = false, dirty = true, was_pointer = false;
    enum Drag { kNone, kMove, kSize } drag = kNone;
    POINT grab{};
    int mouse_x = -1, mouse_y = -1;
    RECT collapse_r{}, hide_r{};
    int scroll = 0, max_scroll = 0;  // the content scrolls (mouse wheel, pointer out) when the window is shorter than it

    PinnedLayer(std::string i, std::wstring t, int w) : id(std::move(i)), title(std::move(t)), default_w(w) { g_pinned.push_back(this); }
    const char* name() const override { return id.c_str(); }
    LayoutEntry& lay() { return g_layout.get(id); }

    bool hide_in_menus = false;  // hidden while one of the game's menus is open (Frame::in_menu), like the minimap
    virtual bool active(const Frame& f) { return f.in_world && !(hide_in_menus && f.in_menu); }  // shown at all now (besides hidden)
    virtual int content_height(int width) = 0;                  // the content's height at this width
    virtual void draw_content(int top, int width) = 0;          // into canvas, below the title bar
    virtual bool refresh(const Frame& f) { return false; }      // read new data; true when the content changed
    virtual void content_click(int x, int y) {}                 // a click on the content (y from the content's top)

    void box(int x0, int y0, int x1, int y1, float r, float g, float b, float a) {
        for (int y = y0; y < y1; ++y)
            for (int x = x0; x < x1; ++x) canvas.blend(x, y, r, g, b, a);
    }

    void draw_all() {
        if (!fonts) {
            fonts = true;
            text.ready(g_screen, 16);
            little.ready(g_screen, 13);
        }
        LayoutEntry& e = lay();
        const int w = std::clamp(e.w > 0 ? e.w : default_w, min_w, max_w);
        const int natural = kHead + (e.collapsed ? 0 : content_height(w) + 8);
        const int h = e.collapsed ? kHead : e.h > 0 ? std::min(natural, std::max(e.h, kHead + 40)) : natural;  // e.h: at most this tall
        max_scroll = std::max(0, natural - h);
        scroll = std::clamp(scroll, 0, max_scroll);
        resize(w, h);
        std::fill(pixels.begin(), pixels.end(), 0u);
        box(0, 0, w, h, 14, 15, 19, 0.78f);                         // the body
        if (!e.collapsed) {
            draw_content(kHead + 4 - scroll, w - (max_scroll ? 10 : 0));
            std::fill(pixels.begin(), pixels.begin() + static_cast<std::ptrdiff_t>(kHead) * w, 0u);  // scrolled up under the title bar
            if (max_scroll) {  // a thin scroll bar at the right
                const int track = h - kHead - 6, thumb = std::max(20, track * (h - kHead) / std::max(1, natural - kHead));
                const int ty = kHead + 3 + (track - thumb) * scroll / max_scroll;
                box(w - 8, kHead + 3, w - 3, kHead + 3 + track, 40, 42, 50, 1.0f);
                box(w - 8, ty, w - 3, ty + thumb, 120, 128, 145, 1.0f);
            }
        }
        box(0, 0, w, kHead, 30, 34, 44, 0.92f);                     // the title bar
        if (g_pointer_mode) {                                       // movable now: a lit frame
            box(0, 0, w, 1, 120, 160, 220, 1.0f);
            box(0, h - 1, w, h, 120, 160, 220, 1.0f);
            box(0, 0, 1, h, 120, 160, 220, 1.0f);
            box(w - 1, 0, w, h, 120, 160, 220, 1.0f);
        }
        text.draw(canvas, 8, 5, title, 235, 225, 205);
        // the buttons at the right of the title bar: "-" collapse (or "+" open), "x" hide
        hide_r = {w - 26, 3, w - 4, kHead - 3};
        collapse_r = {w - 52, 3, w - 30, kHead - 3};
        auto knob = [&](const RECT& r, const wchar_t* label) {
            const bool over = g_pointer_mode && mouse_x >= r.left && mouse_y >= r.top && mouse_x < r.right && mouse_y < r.bottom;
            box(r.left, r.top, r.right, r.bottom, over ? 80.0f : 50.0f, over ? 84.0f : 54.0f, over ? 96.0f : 64.0f, 1.0f);
            text.draw(canvas, r.left + (r.right - r.left - text.width(label)) / 2, r.top + 1, label, 230, 230, 235);
        };
        knob(collapse_r, e.collapsed ? L"+" : L"\u2013");
        knob(hide_r, L"\u00D7");
        if (g_pointer_mode && !e.collapsed)  // the resize grip: a small stair in the lower right corner
            for (int k = 0; k < kGrip; k += 3) box(w - kGrip + k, h - 2 - k / 3, w - 2, h - 1 - k / 3, 140, 170, 220, 0.9f);
        changed = true;
    }

    void update(const Frame& f) override {
        LayoutEntry& e = lay();
        if (refresh(f)) dirty = true;
        const bool want = !e.hidden && active(f) && f.gw > 0;
        if (want != visible) {
            visible = want;
            changed = true;
            FK_LOG(fklog::kDebug, "pinned: %s %s", id.c_str(), want ? "shown" : "hidden");
        }
        if (!visible) return;
        if (was_pointer != g_pointer_mode) {
            was_pointer = g_pointer_mode;
            dirty = true;
            if (!g_pointer_mode && drag != kNone) end_drag();
        }
        if (dirty) {
            dirty = false;
            draw_all();
        }
        int x = e.x >= 0 ? e.x : f.gw * def_x_pm / 1000, y = e.y >= 0 ? e.y : f.gh * def_y_pm / 1000;
        x = std::clamp(x, 0, std::max(0, f.gw - canvas.w));
        y = std::clamp(y, 0, std::max(0, f.gh - canvas.h));
        place(x, y);
    }

    void end_drag() {
        drag = kNone;
        LayoutEntry& e = lay();
        e.x = rect.left;
        e.y = rect.top;
        e.w = canvas.w;
        g_layout.save();
        FK_LOG(fklog::kInfo, "pinned: %s placed at %d,%d, %d wide, at most %d tall", id.c_str(), e.x, e.y, e.w, e.h);
    }

    void wheel(int delta, int x, int y) override {
        if (!max_scroll) return;
        const int to = std::clamp(scroll - delta * 40 / WHEEL_DELTA, 0, max_scroll);
        if (to != scroll) {
            scroll = to;
            dirty = true;
        }
    }

    bool wants_mouse() const override { return visible && g_pointer_mode; }
    void mouse_left() override {
        mouse_x = mouse_y = -1;
        dirty = true;
    }
    void mouse(UINT msg, int x, int y) override {
        LayoutEntry& e = lay();
        auto in = [&](const RECT& r) { return x >= r.left && y >= r.top && x < r.right && y < r.bottom; };
        if (msg == WM_MOUSEMOVE) {
            if (drag == kMove) {
                e.x = rect.left + x - grab.x;
                e.y = rect.top + y - grab.y;
            } else if (drag == kSize) {  // wider or narrower, and taller or shorter (at most as tall as the content)
                e.w = std::clamp(x + static_cast<int>(grab.x), min_w, max_w);
                e.h = std::max(kHead + 40, y + static_cast<int>(grab.y));
                dirty = true;
            }
            if (x != mouse_x || y != mouse_y) {
                const bool hover_change = in(collapse_r) != (mouse_x >= collapse_r.left && mouse_y >= collapse_r.top && mouse_x < collapse_r.right && mouse_y < collapse_r.bottom) ||
                                          in(hide_r) != (mouse_x >= hide_r.left && mouse_y >= hide_r.top && mouse_x < hide_r.right && mouse_y < hide_r.bottom);
                mouse_x = x;
                mouse_y = y;
                if (hover_change) dirty = true;
            }
            return;
        }
        if (msg == WM_LBUTTONUP) {
            if (drag != kNone) end_drag();
            return;
        }
        if (msg != WM_LBUTTONDOWN) return;
        if (in(hide_r)) {
            e.hidden = true;
            g_layout.save();
            dirty = true;
            FK_LOG(fklog::kInfo, "pinned: %s hidden with its x button", id.c_str());
        } else if (in(collapse_r)) {
            e.collapsed = !e.collapsed;
            g_layout.save();
            dirty = true;
            FK_LOG(fklog::kInfo, "pinned: %s %s", id.c_str(), e.collapsed ? "collapsed" : "opened");
        } else if (!e.collapsed && x >= canvas.w - kGrip && y >= canvas.h - kGrip) {
            drag = kSize;
            grab = {canvas.w - x, canvas.h - y};
        } else if (y < kHead) {
            drag = kMove;
            grab = {x, y};
            e.x = rect.left;
            e.y = rect.top;
        } else if (!e.collapsed) {
            content_click(x, y - (kHead + 4) + scroll);
        }
    }
};

// ---- the party window: every player in the game, with health, mana and level ----
// From the Lua part (features/party.lua) in emf\mods\flamekit\ui_party.dat. Each player has a symbol and a colour from
// their name (player_style), the same as on the minimap. You first, then the others by name.
struct PartyLayer : PinnedLayer {
    struct Member {
        bool you = false;
        int hp = -1, hp_max = -1, mana = -1, mana_max = -1, level = -1;
        float x = -1, z = -1;  // where (metres, x east, z north); -1: not known
        std::string name;
        std::wstring where;    // the location line, made when the list is read
    };
    std::vector<Member> members;
    bool server = false;  // the list came from FlameKit's server half (else: what this game knows itself)
    uint64_t stamp = 0, next_read = 0;
    static constexpr int kRow = 76;

    PartyLayer() : PinnedLayer("party", L"Party", 300) { hide_in_menus = true; }

    bool refresh(const Frame& f) override {
        if (f.now < next_read) return false;
        next_read = f.now + 250;
        const bool read = read_list();
        return update_where() || read;
    }

    // Each player's location line: the region (the one of the nearest Ancient Spire, as on the minimap), and for the
    // others how far away and in which direction from you ("320 m NE"); for you, the named place you are in or near.
    bool update_where() {
        const float mx = g_x.load(), mz = g_z.load();
        std::string my_region, my_place;
        {
            std::lock_guard<std::mutex> l(g_shared.lock);
            my_region = g_shared.region;
            my_place = g_shared.place;
        }
        bool changed = false;
        for (Member& m : members) {
            std::wstring w;
            if (m.you) {
                w = widen(my_region);
                if (!my_place.empty()) w += (w.empty() ? L"" : L" \u00B7 ") + widen(my_place);
            } else if (m.x >= 0 && m.z >= 0) {
                const std::string r = region_at(m.x, m.z);
                const float dx = m.x - mx, dz = m.z - mz, d = std::sqrt(dx * dx + dz * dz);
                std::wstring away;
                if (d < 15.0f) {
                    away = L"next to you";
                } else {
                    static const wchar_t* kDir[] = {L"N", L"NE", L"E", L"SE", L"S", L"SW", L"W", L"NW"};
                    const float deg = std::atan2(dx, dz) * 57.29578f;  // 0 north, 90 east
                    const int k = (static_cast<int>(std::floor((deg + 360.0f + 22.5f) / 45.0f))) % 8;
                    wchar_t buf[48];
                    if (d < 1000.0f) swprintf_s(buf, L"%d m %s", static_cast<int>(d + 0.5f), kDir[k]);
                    else swprintf_s(buf, L"%.1f km %s", d / 1000.0f, kDir[k]);
                    away = buf;
                }
                w = r.empty() ? away : widen(r) + L" \u00B7 " + away;
            } else {
                w = L"location not known";
            }
            if (w != m.where) {
                m.where = std::move(w);
                changed = true;
            }
        }
        return changed;
    }

    bool read_list() {
        WIN32_FILE_ATTRIBUTE_DATA info{};
        const std::wstring file = g_flamekit_dir + L"ui_party.dat";
        const uint64_t st = GetFileAttributesExW(file.c_str(), GetFileExInfoStandard, &info)
                                ? ((static_cast<uint64_t>(info.ftLastWriteTime.dwHighDateTime) << 32 | info.ftLastWriteTime.dwLowDateTime) ^ info.nFileSizeLow) | 1
                                : 2;
        if (st == stamp) return false;
        FILE* fp = _wfsopen(file.c_str(), L"rb", _SH_DENYNO);
        if (!fp) return false;
        std::vector<Member> list;
        bool from_server = false, complete = false;
        char line[512];
        while (fgets(line, sizeof line, fp)) {
            line[std::strcspn(line, "\r\n")] = 0;
            if (std::strcmp(line, "end") == 0) {
                complete = true;
                break;
            }
            if (std::strncmp(line, "source ", 7) == 0) {
                from_server = std::strcmp(line + 7, "server") == 0;
                continue;
            }
            if (line[0] != 'p' || line[1] != '\t') continue;
            Member m;
            int you = 0, used = 0;
            // since 0.15.25 with the place: "... <level> <x> <z> <name>"; before: "... <level> <name>"
            int with_place = 0;
            for (const char* t = line + 2; *t; ++t) with_place += *t == '\t';
            const bool ok = with_place >= 8
                                ? sscanf_s(line + 2, "%d\t%d\t%d\t%d\t%d\t%d\t%f\t%f\t%n", &you, &m.hp, &m.hp_max, &m.mana, &m.mana_max, &m.level, &m.x, &m.z, &used) == 8
                                : sscanf_s(line + 2, "%d\t%d\t%d\t%d\t%d\t%d\t%n", &you, &m.hp, &m.hp_max, &m.mana, &m.mana_max, &m.level, &used) == 6;
            if (ok && used > 0) {
                m.you = you != 0;
                m.name = line + 2 + used;
                list.push_back(std::move(m));
            }
        }
        fclose(fp);
        if (!complete) return false;
        stamp = st;
        std::sort(list.begin(), list.end(), [](const Member& a, const Member& b) {
            if (a.you != b.you) return a.you;
            return _stricmp(a.name.c_str(), b.name.c_str()) < 0;
        });
        members = std::move(list);
        server = from_server;
        g_down.clear();
        for (const Member& m : members)
            if (m.hp == 0 && m.hp_max > 0) g_down.insert(m.name);
        FK_LOG(fklog::kDebug, "party: %d player(s), from %s", static_cast<int>(members.size()), server ? "the server half" : "this game alone");
        return true;
    }

    int content_height(int width) override {
        int h = static_cast<int>(std::max<size_t>(members.size(), 1)) * kRow;
        if (!server) h += 36;           // the note about the server
        if (g_pointer_mode) h += 22;    // how to follow a player
        return h;
    }

    // A click on a player (pointer out): follow that player on the minimap (a gold ring, the name even at the edge);
    // a click on the followed player stops it.
    void content_click(int x, int y) override {
        const int row = y / kRow;
        if (y < 0 || row >= static_cast<int>(members.size())) return;
        const std::string& name = members[static_cast<size_t>(row)].name;
        g_tracked = g_tracked == name ? std::string() : name;
        dirty = true;
        FK_LOG(fklog::kInfo, "party: %s", g_tracked.empty() ? "no player followed on the minimap" : ("following " + g_tracked + " on the minimap").c_str());
    }

    // A bar in the game's style: a dark frame, the fill with a lighter top, a notch every 100 points, a bright end, and
    // the exact values in the middle ("742 / 980"); grey when not known.
    void bar(int x, int y, int w, int h, int cur, int max, float r, float g, float b) {
        box(x, y, x + w, y + h, 10, 12, 14, 0.9f);
        box(x, y, x + w, y + 1, 70, 74, 80, 1.0f);
        const bool known = cur >= 0 && max > 0;
        const int inner = w - 4;
        const int fill = known ? std::clamp(static_cast<int>(static_cast<long long>(inner) * cur / max), 0, inner) : 0;
        for (int yy = y + 2; yy < y + h - 2; ++yy) {
            const float t = static_cast<float>(yy - y - 2) / std::max(1, h - 5);
            const float shade = 1.15f - 0.35f * t;  // lighter at the top
            for (int xx = x + 2; xx < x + 2 + fill; ++xx) canvas.blend(xx, yy, std::min(255.0f, r * shade), std::min(255.0f, g * shade), std::min(255.0f, b * shade), 1.0f);
        }
        if (known && max >= 200)
            for (int k = 100; k < max; k += 100) {
                const int nx = x + 2 + static_cast<int>(static_cast<long long>(inner) * k / max);
                if (nx < x + 2 + fill) box(nx, y + 2, nx + 1, y + h - 2, r * 0.45f, g * 0.45f, b * 0.45f, 0.9f);
            }
        if (fill > 2) box(x + fill, y + 2, x + 2 + fill, y + h - 2, 235, 255, 235, 0.9f);  // the bright end
        const std::wstring v = known ? std::to_wstring(cur) + L" / " + std::to_wstring(max) : std::wstring(L"?");
        little.draw(canvas, x + (w - little.width(v)) / 2, y + (h - little.font_px) / 2 - 2, v, 245, 245, 245);
    }

    void draw_content(int top, int width) override {
        int y = top;
        if (members.empty()) {
            text.draw(canvas, 10, y + 4, L"...", 150, 150, 160);
            y += kRow;
        }
        for (const Member& m : members) {
            const PlayerStyle st = player_style(m.name);
            const bool tracked = !g_tracked.empty() && m.name == g_tracked;
            const bool down = m.hp == 0 && m.hp_max > 0;
            if (tracked) {  // followed on the minimap: a gold frame
                // the mana bar ends at y + 71: the bottom line one pixel under it (y + 73), as the top line is above the name
                box(3, y - 2, width - 3, y - 1, 255, 214, 90, 1.0f);
                box(3, y + kRow - 3, width - 3, y + kRow - 2, 255, 214, 90, 1.0f);
                box(3, y - 2, 4, y + kRow - 2, 255, 214, 90, 1.0f);
                box(width - 4, y - 2, width - 3, y + kRow - 2, 255, 214, 90, 1.0f);
            }
            if (down) box(4, y - 1, width - 4, y + kRow - 3, 120, 20, 20, 0.45f);  // health 0: a red glow
            draw_player_mark(canvas, 16.0f, static_cast<float>(y + 11), 13.0f, st);
            const std::wstring nm = widen(m.name) + (m.you ? L" (you)" : L"");
            text.draw(canvas, 30, y + 2, nm, st.r, st.g, st.b);
            int right = width - 10;
            if (m.level >= 0) {
                const std::wstring lv = L"Lv " + std::to_wstring(m.level);
                right -= text.width(lv);
                text.draw(canvas, right, y + 2, lv, 200, 200, 210);
                right -= 10;
            }
            if (down) text.draw(canvas, right - text.width(L"DOWN"), y + 2, L"DOWN", 255, 70, 60);
            if (!m.where.empty()) little.draw(canvas, 30, y + 23, m.where, 170, 175, 185);  // where they are
            bar(10, y + 42, width - 20, 16, m.hp, m.hp_max, 120, 200, 110);       // health: green
            bar(10, y + 60, width - 20, 12, m.mana, m.mana_max, 80, 150, 225);    // mana: blue, thinner
            y += kRow;
        }
        if (!server) {
            little.draw(canvas, 10, y + 2, L"Mana, level and other players need", 255, 176, 96);
            little.draw(canvas, 10, y + 18, L"FlameKit on the server", 255, 176, 96);
            y += 36;
        }
        if (g_pointer_mode) little.draw(canvas, 10, y + 3, L"Click a player to follow them on the minimap", 160, 190, 230);
    }
};

// ---- the Messages window: what FlameKit's features just did ----
// From the Lua part (kit.note in core/kit.lua) in emf\mods\flamekit\ui_messages.dat: "m <number> <rrggbb> <text>" lines,
// the last 20, oldest first, then "end". On screen all the time in a world (owner, 0.15.41): the last 5 messages, the
// last 10 while the pointer is out. Hidden with its x button, it stays hidden (FlameKit's window, tab Windows, shows it
// again).
struct MessagesLayer : PinnedLayer {
    struct Msg {
        int n = 0;
        uint8_t r = 255, g = 176, b = 96;
        std::wstring text;
        uint64_t at = 0;  // GetTickCount64 when it came; 0: before this game start
    };
    std::vector<Msg> all;
    std::vector<size_t> shown;               // indices into all
    std::vector<std::pair<size_t, std::wstring>> lines;  // the wrapped lines of the shown messages (message index, text)
    int newest = 0;
    bool first = true;
    uint64_t stamp = 0, next_read = 0;
    static constexpr int kLine = 18, kShowMs = 12000, kNew = 5, kAll = 10;

    MessagesLayer() : PinnedLayer("messages", L"Messages", 440) { def_y_pm = 60; }

    bool active(const Frame& f) override { return f.in_world; }

    void read_file(uint64_t now) {
        WIN32_FILE_ATTRIBUTE_DATA info{};
        const std::wstring file = g_flamekit_dir + L"ui_messages.dat";
        const uint64_t st = GetFileAttributesExW(file.c_str(), GetFileExInfoStandard, &info)
                                ? ((static_cast<uint64_t>(info.ftLastWriteTime.dwHighDateTime) << 32 | info.ftLastWriteTime.dwLowDateTime) ^ info.nFileSizeLow) | 1
                                : 2;
        if (st == stamp) return;
        FILE* fp = _wfsopen(file.c_str(), L"rb", _SH_DENYNO);
        if (!fp) return;
        std::vector<Msg> list;
        bool complete = false;
        char line[1024];
        while (fgets(line, sizeof line, fp)) {
            line[std::strcspn(line, "\r\n")] = 0;
            if (std::strcmp(line, "end") == 0) {
                complete = true;
                break;
            }
            Msg m;
            unsigned rgb = 0;
            int used = 0;
            if (sscanf_s(line, "m %d %6x %n", &m.n, &rgb, &used) == 2 && used > 0) {
                m.r = static_cast<uint8_t>(rgb >> 16), m.g = static_cast<uint8_t>(rgb >> 8), m.b = static_cast<uint8_t>(rgb);
                m.text = widen(line + used);
                list.push_back(std::move(m));
            }
        }
        fclose(fp);
        if (!complete) return;
        stamp = st;
        int top = 0;
        for (const Msg& m : list) top = std::max(top, m.n);
        const bool reset = top < newest;  // the Lua part was loaded again: its numbers start again at 1
        for (Msg& m : list) {
            bool known = false;
            for (const Msg& old : all)
                if (old.n == m.n && old.text == m.text) {
                    m.at = old.at;
                    known = true;
                }
            if (!known) m.at = first ? 0 : (reset || m.n > newest) ? now : 0;
        }
        first = false;
        newest = top;
        all = std::move(list);
        FK_LOG(fklog::kDebug, "messages: %d in ui_messages.dat, newest %d", static_cast<int>(all.size()), newest);
    }

    bool refresh(const Frame& f) override {
        if (f.now >= next_read) {
            next_read = f.now + 250;
            read_file(f.now);
        }
        std::vector<size_t> want;  // the last 5, or 10 while the pointer is out
        const size_t n = g_pointer_mode ? kAll : kNew;
        for (size_t i = all.size() > n ? all.size() - n : 0; i < all.size(); ++i) want.push_back(i);
        if (want == shown) return false;
        shown = std::move(want);
        return true;
    }

    int content_height(int width) override {
        lines.clear();
        for (size_t i : shown) {  // each message wrapped to the width, words kept whole where they can be
            const std::wstring& t = all[i].text;
            std::wstring cur;
            size_t at = 0;
            while (at <= t.size()) {
                size_t sp = t.find(L' ', at);
                if (sp == std::wstring::npos) sp = t.size();
                const std::wstring word = t.substr(at, sp - at);
                const std::wstring tryline = cur.empty() ? word : cur + L" " + word;
                if (!cur.empty() && little.width(tryline) > width - 20) {
                    lines.push_back({i, cur});
                    cur = word;
                } else {
                    cur = tryline;
                }
                at = sp + 1;
            }
            lines.push_back({i, cur});
        }
        return std::max<int>(1, static_cast<int>(lines.size())) * kLine + static_cast<int>(shown.size()) * 2 + 4;
    }

    void draw_content(int top, int width) override {
        int y = top;
        if (lines.empty()) little.draw(canvas, 10, y, L"No messages yet", 140, 145, 155);
        size_t last = static_cast<size_t>(-1);
        for (const auto& [i, l] : lines) {
            const Msg& m = all[i];
            if (i != last && last != static_cast<size_t>(-1)) y += 2;  // a little room between two messages
            last = i;
            little.draw(canvas, 10, y, l, m.r, m.g, m.b);
            y += kLine;
        }
    }
};

std::string version_in(const std::wstring& mod_json);  // (the monitor's, further down)

// ---- item tiles: the same everywhere in FlameKit's UI ----
// An Enshrouded item in FlameKit's UI is a tile: its icon on its rarity's colour (WindowLayer::tile) and, under the
// pointer, this tooltip. The details come from the Lua part (core/items.lua items.tip), so the DLL never reads the game
// for them: the Auto Junk List's B and J lines (ui_list.dat) and any tab's item rows ("r i ..." in ui_tabs.dat).
struct ItemTip {
    std::wstring name;     // the game's name in the player's language
    int rarity = -1;       // 0 Common .. 4 Legendary, -1 not known
    std::wstring level;    // item level: "12" or "12-14", "" not known
    std::wstring type;     // "Material", "Ammunition, Arrows", ...
    int count = 0;         // how many the player carries (shown on the tile itself, not in the tooltip)
    std::wstring command;  // the debug name, for chat commands
    std::wstring hint;     // what a click does, dimmed at the bottom
};
constexpr uint8_t kRarityRgb[5][3] = {{217, 212, 199}, {95, 211, 95}, {79, 163, 255}, {181, 107, 255}, {255, 180, 60}};
const wchar_t* const kRarityName[5] = {L"Common", L"Uncommon", L"Rare", L"Epic", L"Legendary"};

// Draws an item's tooltip near the pointer (mx, my), kept inside a canvas of w x h: the name in its rarity's colour, then
// item level, rarity, type, the command name and the hint; a frame in the rarity's colour.
void draw_item_tip(Canvas& c, TextPainter& text, int mx, int my, int w, int h, const ItemTip& t) {
    const bool known = t.rarity >= 0 && t.rarity < 5;
    const uint8_t* rc = known ? kRarityRgb[t.rarity] : kRarityRgb[0];
    struct Line {
        std::wstring s;
        float r, g, b;
    };
    std::vector<Line> lines;
    lines.push_back({t.name.empty() ? t.command : t.name, static_cast<float>(rc[0]), static_cast<float>(rc[1]), static_cast<float>(rc[2])});
    if (!t.level.empty()) lines.push_back({L"Item level " + t.level, 225, 225, 230});
    if (known) lines.push_back({std::wstring(L"Rarity: ") + kRarityName[t.rarity], 225, 225, 230});
    if (!t.type.empty()) lines.push_back({L"Type: " + t.type, 225, 225, 230});
    if (!t.command.empty()) lines.push_back({L"Command name: " + t.command, 140, 145, 155});
    if (!t.hint.empty()) lines.push_back({t.hint, 160, 190, 230});
    int tw = 0;
    for (const Line& l : lines) tw = std::max(tw, text.width(l.s));
    tw += 20;
    const int th = 22 * static_cast<int>(lines.size()) + 12;
    const int x0 = std::clamp(mx + 16, 0, std::max(0, w - tw)), y0 = std::clamp(my + 20, 0, std::max(0, h - th));
    for (int y = y0; y < y0 + th; ++y)
        for (int x = x0; x < x0 + tw; ++x) c.blend(x, y, 24, 25, 30, 0.97f);
    for (int x = x0; x < x0 + tw; ++x) {  // the frame in the rarity's colour
        c.blend(x, y0, rc[0], rc[1], rc[2], 1.0f);
        c.blend(x, y0 + th - 1, rc[0], rc[1], rc[2], 1.0f);
    }
    for (int y = y0; y < y0 + th; ++y) {
        c.blend(x0, y, rc[0], rc[1], rc[2], 1.0f);
        c.blend(x0 + tw - 1, y, rc[0], rc[1], rc[2], 1.0f);
    }
    int ly = y0 + 6;
    for (size_t i = 0; i < lines.size(); ++i) {
        if (i == lines.size() - 1 && !t.hint.empty()) ly += 4;  // a little room before the hint
        text.draw(c, x0 + 10, ly, lines[i].s, lines[i].r, lines[i].g, lines[i].b);
        ly += 22;
    }
}
std::string read_text(const std::wstring& path, size_t max);

// ---- FlameKit's window: a tab per feature ----
// This layer only draws and takes clicks: it never reads the game. What it shows comes from the Lua part
// (features/native_ui.lua), and every click goes back to the Lua part as a line in emf\mods\flamekit\ui_actions.txt;
// the Lua part does exactly what the old panel's buttons do. Each file has one writer; native_ui.lua describes them:
//   ui_tabs.dat   the tabs, and the rows of the tab shown (the same rows the old panel draws, from the feature's
//                 panel(world)): headings, texts, buttons, separators, drawn here by one general row drawer
//   ui_list.dat   the Auto Junk List tab's own view: the bag and the junk list as icons, Auto, Dump Junk, Drop/Delete
// EMF has no channel between a native mod and a Lua mod yet (EMF_REQUESTS.md, 8): when it has, only the read_* and
// act functions change. F6 (while the game is in front) opens the window and it takes the keyboard and mouse; F6 or
// Esc closes it, and so does another window taking the front (Alt+Tab). Long tabs show in pages, never scroll.
struct WindowLayer : Layer {
    const char* name() const override { return "FlameKit window"; }
    struct Entry {
        uint32_t id = 0;    // item id; 0: the game does not know the item (a grey square)
        int count = 0;      // how many you carry
        std::string key;    // the game's debug name: what the Lua part knows the item by
        std::wstring name;  // the game's own name for it
        int rarity = -1;    // the item tile's details (core/items.lua items.tip): for the tooltip
        std::wstring level, type;
    };
    struct Tab {
        std::string id;
        std::wstring title;
    };
    struct Opt {  // the Auto Junk List's own settings, as buttons on its view ("P" lines of ui_list.dat)
        std::string key;  // what a click sends back: "opt <key>"
        bool lit = false;
        std::wstring label, tip;  // the tooltip: the setting's help from mod.json
    };
    struct Row {
        char kind = 't';  // h heading, t text, b button, s separator
        bool same = false, selected = false, disabled = false, dim = false;
        bool has_colour = false;
        uint8_t r = 0, g = 0, b = 0;
        int number = 0;  // a button's number in its generation
        std::wstring text, tip;
        // an item tile (kind i): the item and its details for the tooltip
        uint32_t item = 0;
        int count = 0, rarity = -1;
        std::wstring level, type, command;
    };
    enum Kind { kBagItem, kJunkItem, kAuto, kDump, kDrop, kDropOption, kBagPrev, kBagNext, kJunkPrev, kJunkNext, kTab, kRowButton, kRowPrev, kRowNext, kCheckUpdates, kPinShow, kPinReset, kScrollTrack, kScrollThumb, kClose, kOpt, kRowItem };
    struct Hit {
        RECT r;
        Kind kind;
        size_t index;
        const std::wstring* tip = nullptr;
        const Row* row = nullptr;  // an item tile of a tab of rows: its details for the tooltip
    };
    static constexpr int kIcon = 64, kGap = 8, kPad = 16, kTitle = 32, kGrip = 16, kBarW = 10;
    static constexpr int kDefW = 2 * kPad + 10 * kIcon + 9 * kGap, kDefH = 860, kMinW = 560, kMinH = 440;
    // The window's size and layout now (lay_out). They were constants before the window could be resized (0.15.28),
    // hence the k names. The size comes from ui_layout.txt ("window"), else the default.
    int kW = kDefW, kH = kDefH;
    int kTop = 82;  // where a tab's content starts: under the title bar and the tab rows
    int kCols = 10, kBagRows = 5, kJunkRows = 4, kBagHead = 0, kBagTop = 0, kJunkHead = 0, kJunkTop = 0;
    int kViewTop = 0, kViewBottom = 0;  // a tab of rows: the part of the window it scrolls in
    std::vector<RECT> tab_r;           // where each tab is in the tab rows
    RECT close_r{};
    enum WinDrag { kStill, kMoving, kSizing } win_drag = kStill;
    POINT win_grab{};
    std::string version;  // FlameKit's version, for the title bar (mod.json)

    bool open = false, close_asked = false, dirty = true, drop_open = false;
    // the tabs
    std::vector<Tab> tabs;
    std::string current = "changes";      // the tab shown: What's New the first time in a game, after that the last one
    std::string viewing;                  // what the Lua part was last told it shows ("" none)
    std::string rows_of;                  // the tab the rows belong to
    uint64_t generation = 0;
    std::vector<Row> rows;
    size_t rows_page = 0;
    int rows_scroll = 0, max_scroll = 0;  // a tab of rows: how far it is scrolled down (pixels), and how far it can be
    bool thumb_drag = false;
    int thumb_grab = 0;
    RECT track_r{}, thumb_r{};
    // the Auto Junk List tab
    std::vector<Entry> bag, junk;
    // what the player just moved, while the window is open: a gold frame on it, and its list goes to its page
    std::unordered_set<std::string> moved_junk, moved_bag;
    std::string show_junk, show_bag;  // just moved: go to its page once the new list is read
    uint64_t next_open_check = 0;
    std::vector<Opt> opts;
    int opts_y = 0;  // where the option buttons are: beside Auto / Dump Junk / Drop when they fit, else a line under them
    bool auto_on = false, delete_junk = false;
    size_t bag_page = 0, junk_page = 0;
    int mouse_x = -1, mouse_y = -1;
    std::vector<Hit> hits;
    std::vector<std::string> actions;
    uint64_t last_action = 0, list_stamp = 0, tabs_stamp = 0;
    TextPainter text;
    bool fonts = false;
    ItemIcons icons;
    std::unordered_map<uint32_t, std::vector<uint8_t>> pictures;  // an empty one: no picture to be had

    WindowLayer() {
        icons.open = [](const char* file, void*) {
            std::wstring wide(file, file + std::strlen(file));
            return _wfsopen((g_game_dir + wide).c_str(), L"rb", _SH_DENYNO);
        };
        // the clicks already in ui_actions.txt (from an earlier game): new numbers start above them
        if (FILE* fp = _wfsopen((g_flamekit_dir + L"ui_actions.txt").c_str(), L"rb", _SH_DENYNO)) {
            char line[512];
            while (fgets(line, sizeof line, fp)) last_action = std::max<uint64_t>(last_action, std::strtoull(line, nullptr, 10));
            fclose(fp);
        }
    }

    static uint64_t stamp_of(const std::wstring& file) {
        WIN32_FILE_ATTRIBUTE_DATA info{};
        if (!GetFileAttributesExW(file.c_str(), GetFileExInfoStandard, &info)) return 2;
        return ((static_cast<uint64_t>(info.ftLastWriteTime.dwHighDateTime) << 32 | info.ftLastWriteTime.dwLowDateTime) ^ info.nFileSizeLow) | 1;
    }

    // Reads ui_list.dat. False (and nothing changed) while the file is missing or half written.
    bool read_list() {
        FILE* fp = _wfsopen((g_flamekit_dir + L"ui_list.dat").c_str(), L"rb", _SH_DENYNO);
        if (!fp) return false;
        std::vector<Entry> b, j;
        std::vector<Opt> o;
        bool a = false, del = false, complete = false;
        char line[1024];
        while (fgets(line, sizeof line, fp)) {
            line[std::strcspn(line, "\r\n")] = 0;
            if (std::strcmp(line, "end") == 0) {
                complete = true;
                break;
            }
            char key[400] = "", action[16] = "";
            unsigned id = 0;
            int count = 0, on = 0, used = 0;
            if (sscanf_s(line, "O %d %15s", &on, action, static_cast<unsigned>(sizeof action)) == 2) {
                a = on != 0;
                del = std::strcmp(action, "delete") == 0;
            } else if ((line[0] == 'B' || line[0] == 'J') && line[1] == '\t') {  // an item tile: id, count, key, rarity, level, type, name
                std::vector<std::string> f;
                for (const char* at = line + 2;;) {
                    const char* tab = std::strchr(at, '\t');
                    f.emplace_back(at, tab ? static_cast<size_t>(tab - at) : std::strlen(at));
                    if (!tab) break;
                    at = tab + 1;
                }
                if (f.size() >= 7) {
                    Entry e;
                    e.id = static_cast<uint32_t>(std::strtoul(f[0].c_str(), nullptr, 16));
                    e.count = std::atoi(f[1].c_str());
                    e.key = f[2];
                    e.rarity = std::atoi(f[3].c_str());
                    e.level = widen(f[4]);
                    e.type = widen(f[5]);
                    e.name = widen(f[6]);
                    (line[0] == 'B' ? b : j).push_back(std::move(e));
                }
            } else if ((line[0] == 'B' || line[0] == 'J') &&
                       sscanf_s(line + 1, " %x %d %399s %n", &id, &count, key, static_cast<unsigned>(sizeof key), &used) == 3 && used > 0) {
                Entry e;  // the older form (before 0.15.36): no details
                e.id = id;
                e.count = count;
                e.key = key;
                e.name = widen(line + 1 + used);
                (line[0] == 'B' ? b : j).push_back(std::move(e));
            } else if (line[0] == 'P' && sscanf_s(line + 1, " %399s %d %n", key, static_cast<unsigned>(sizeof key), &on, &used) == 2 && used > 0) {
                const std::string rest = line + 1 + used;  // "<label><tab><tooltip>"
                const size_t tab = rest.find('\t');
                o.push_back({key, on != 0, widen(rest.substr(0, tab)), tab == std::string::npos ? std::wstring() : widen(rest.substr(tab + 1))});
            }
        }
        fclose(fp);
        if (!complete) {
            FK_LOG(fklog::kDebug, "window: ui_list.dat is half written, read again later");
            return false;
        }
        bag = std::move(b);
        junk = std::move(j);
        opts = std::move(o);
        auto_on = a;
        delete_junk = del;
        FK_LOG(fklog::kDebug, "window: ui_list.dat read: %d in the bag, %d on the junk list, auto %d, %s", static_cast<int>(bag.size()),
               static_cast<int>(junk.size()), auto_on, delete_junk ? "delete" : "drop");
        return true;
    }

    static std::wstring unescape(const std::string& s) {  // "\n" in the file is a line break
        std::string out;
        for (size_t i = 0; i < s.size(); ++i) {
            if (s[i] == '\\' && i + 1 < s.size() && s[i + 1] == 'n') {
                out += '\n';
                ++i;
            } else {
                out += s[i];
            }
        }
        return widen(out);
    }

    // Reads ui_tabs.dat. False (and nothing changed) while the file is missing or half written.
    bool read_tabs() {
        FILE* fp = _wfsopen((g_flamekit_dir + L"ui_tabs.dat").c_str(), L"rb", _SH_DENYNO);
        if (!fp) return false;
        std::vector<Tab> t;
        std::vector<Row> r;
        std::string of;
        uint64_t gen = 0;
        bool complete = false;
        std::string line;
        char buf[4096];
        while (fgets(buf, sizeof buf, fp)) {
            line = buf;
            while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) line.pop_back();
            if (line == "end") {
                complete = true;
                break;
            }
            std::vector<std::string> f;
            for (size_t at = 0;;) {
                const size_t tab = line.find('\t', at);
                f.push_back(line.substr(at, tab == std::string::npos ? std::string::npos : tab - at));
                if (tab == std::string::npos) break;
                at = tab + 1;
            }
            if (f[0] == "tab" && f.size() >= 3) {
                t.push_back({f[1], widen(f[2])});
            } else if (f[0] == "view" && f.size() >= 3) {
                of = f[1];
                gen = std::strtoull(f[2].c_str(), nullptr, 10);
            } else if (f[0] == "r" && f.size() >= 10) {
                Row row;
                row.kind = f[1].empty() ? 't' : f[1][0];
                row.same = f[2] == "1";
                row.selected = f[3] == "1";
                row.disabled = f[4] == "1";
                row.dim = f[5] == "1";
                if (f[6].size() == 6) {
                    const unsigned long rgb = std::strtoul(f[6].c_str(), nullptr, 16);
                    row.has_colour = true;
                    row.r = static_cast<uint8_t>(rgb >> 16);
                    row.g = static_cast<uint8_t>(rgb >> 8);
                    row.b = static_cast<uint8_t>(rgb);
                }
                row.number = std::atoi(f[7].c_str());
                row.text = unescape(f[8]);
                row.tip = unescape(f[9]);
                if (row.kind == 'i' && f.size() >= 16) {  // an item tile
                    row.item = static_cast<uint32_t>(std::strtoul(f[10].c_str(), nullptr, 16));
                    row.count = std::atoi(f[11].c_str());
                    row.rarity = std::atoi(f[12].c_str());
                    row.level = widen(f[13]);
                    row.type = unescape(f[14]);
                    row.command = widen(f[15]);
                } else if (row.kind == 'i') {
                    row.kind = 't';
                }
                r.push_back(std::move(row));
            }
        }
        fclose(fp);
        if (!complete) return false;
        tabs = std::move(t);
        tabs.push_back({"windows", L"Windows"});  // this DLL's own tab: the pinned windows
        if (of != rows_of || gen != generation) rows_page = of == rows_of ? rows_page : 0;
        if (of != rows_of) rows_scroll = 0;
        rows_of = of;
        generation = gen;
        rows = std::move(r);
        FK_LOG(fklog::kDebug, "window: ui_tabs.dat read: %d tab(s); rows of '%s' (generation %llu): %d", static_cast<int>(tabs.size()), rows_of.c_str(),
               generation, static_cast<int>(rows.size()));
        return true;
    }

    // A click, for the Lua part: "<what> <argument>". ui_actions.txt is written to a new file and then put in place of
    // the old one in one step, so the Lua part never reads half of it.
    void act(const std::string& what, const std::string& arg) {
        FILETIME ft;
        GetSystemTimeAsFileTime(&ft);
        const uint64_t ms = ((static_cast<uint64_t>(ft.dwHighDateTime) << 32 | ft.dwLowDateTime) - 116444736000000000ull) / 10000;
        last_action = std::max(ms, last_action + 1);
        actions.push_back(std::to_string(last_action) + " " + what + " " + arg);
        if (actions.size() > 16) actions.erase(actions.begin());
        std::string all;
        for (const std::string& line : actions) all += line + "\n";
        const std::wstring file = g_flamekit_dir + L"ui_actions.txt", tmp = file + L".tmp";
        bool ok = false;
        if (FILE* fp = _wfsopen(tmp.c_str(), L"wb", _SH_DENYNO)) {
            ok = fwrite(all.data(), 1, all.size(), fp) == all.size();
            ok = fclose(fp) == 0 && ok;
        }
        ok = ok && MoveFileExW(tmp.c_str(), file.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
        if (ok) FK_LOG(fklog::kInfo, "window: click: %s %s (action %llu)", what.c_str(), arg.c_str(), last_action);
        else FK_LOG(fklog::kError, "window: click: %s %s: ui_actions.txt could not be written (error %lu)", what.c_str(), arg.c_str(), GetLastError());
    }

    // Tells the Lua part which generic tab is shown (it writes that tab's rows only then).
    void tell_view() {
        const std::string want = open && current != "loot_filter" && current != "windows" ? current : "";
        if (want == viewing) return;
        viewing = want;
        act("view", want.empty() ? "-" : want);
    }

    size_t pages(size_t n, int rows) const { return std::max<size_t>(1, (n + kCols * rows - 1) / (kCols * rows)); }

    const std::vector<uint8_t>* picture(uint32_t id) {
        if (id == 0) return nullptr;
        const auto have = pictures.find(id);
        if (have != pictures.end()) return have->second.empty() ? nullptr : &have->second;
        ItemMeta meta{};
        {
            std::lock_guard<std::mutex> l(g_item_meta_lock);
            const auto m = g_item_meta.find(id);
            if (m == g_item_meta.end()) return nullptr;  // not known yet (the item details come at the first world step)
            meta = m->second;
        }
        static const uint8_t kRarity[5][3] = {{138, 134, 126}, {95, 211, 95}, {79, 163, 255}, {181, 107, 255}, {255, 180, 60}};
        std::vector<uint8_t> pic;
        if (icons.icon(meta.guid, kIcon, pic)) {
            const uint8_t* c = kRarity[meta.rarity < 5 ? meta.rarity : 0];
            for (int py = 0; py < kIcon; ++py) {
                const float shade = 0.62f - 0.34f * static_cast<float>(py) / (kIcon - 1);
                for (int px = 0; px < kIcon; ++px) {
                    uint8_t* p = &pic[(static_cast<size_t>(py) * kIcon + px) * 4];
                    const float a = p[3] / 255.0f;
                    for (int k = 0; k < 3; ++k) p[k] = static_cast<uint8_t>(p[k] * a + c[k] * shade * (1.0f - a) + 0.5f);
                    p[3] = 255;
                }
            }
        } else {
            pic.clear();
            FK_LOG(fklog::kDebug, "window: no picture for item %08x", id);
        }
        auto& kept = pictures[id] = std::move(pic);
        return kept.empty() ? nullptr : &kept;
    }

    void box(int x0, int y0, int x1, int y1, float r, float g, float b, float a) {
        for (int y = y0; y < y1; ++y)
            for (int x = x0; x < x1; ++x) canvas.blend(x, y, r, g, b, a);
    }
    void frame_box(int x0, int y0, int x1, int y1, int t, float r, float g, float b) {
        box(x0, y0, x1, y0 + t, r, g, b, 1.0f);
        box(x0, y1 - t, x1, y1, r, g, b, 1.0f);
        box(x0, y0, x0 + t, y1, r, g, b, 1.0f);
        box(x1 - t, y0, x1, y1, r, g, b, 1.0f);
    }
    bool inside(const RECT& r) const { return mouse_x >= r.left && mouse_y >= r.top && mouse_x < r.right && mouse_y < r.bottom; }
    void button(int x, int y, int w, const std::wstring& label, bool lit, Kind kind, size_t index = 0, bool disabled = false,
                const Row* row = nullptr) {
        const RECT r{x, y, x + w, y + 30};
        const bool over = inside(r) && !disabled;
        if (lit && row && row->has_colour) box(r.left, r.top, r.right, r.bottom, row->r * 0.45f, row->g * 0.45f, row->b * 0.45f, 1.0f);
        else if (lit) box(r.left, r.top, r.right, r.bottom, 70, 140, 80, 1.0f);
        else box(r.left, r.top, r.right, r.bottom, over ? 74.0f : 52.0f, over ? 74.0f : 52.0f, over ? 84.0f : 60.0f, 1.0f);
        if (over) frame_box(r.left, r.top, r.right, r.bottom, 1, 200, 200, 210);
        float tr = 240, tg = 240, tb = 240;
        if (disabled) tr = tg = tb = 120;
        else if (!lit && row && row->has_colour) tr = row->r, tg = row->g, tb = row->b;
        text.draw(canvas, x + (w - text.width(label)) / 2, y + 5, label, tr, tg, tb);
        hits.push_back({r, kind, index, row && !row->tip.empty() ? &row->tip : nullptr});
    }
    void tile(const Entry& e, int x, int y, Kind kind, size_t index) {
        if (const std::vector<uint8_t>* pic = picture(e.id)) canvas.picture(pic->data(), kIcon, x + kIcon * 0.5f, y + kIcon * 0.5f, 1.0f);
        else box(x, y, x + kIcon, y + kIcon, 70, 70, 76, 1.0f);
        if (e.count > 0) {
            const std::wstring count = std::to_wstring(e.count);
            text.draw(canvas, x + kIcon - text.width(count) - 5, y + kIcon - 22, count, 255, 255, 255);
        }
        const RECT r{x, y, x + kIcon, y + kIcon};
        if (inside(r)) frame_box(x, y, x + kIcon, y + kIcon, 2, 235, 225, 205);
        if ((kind == kJunkItem && moved_junk.count(e.key)) || (kind == kBagItem && moved_bag.count(e.key)))
            frame_box(x - 3, y - 3, x + kIcon + 3, y + kIcon + 3, 3, 255, 200, 60);  // just moved here: a gold frame
        hits.push_back({r, kind, index});
    }
    void section(const std::wstring& heading, float r, float g, float b, const std::vector<Entry>& list, size_t& page, int rows_n, int head_y,
                 int top, Kind item, Kind prev, Kind next) {
        text.draw(canvas, kPad, head_y + 4, heading + L" (" + std::to_wstring(list.size()) + L")", r, g, b);
        const size_t n = pages(list.size(), rows_n), per = static_cast<size_t>(kCols * rows_n);
        page = std::min(page, n - 1);
        if (n > 1) pager(head_y, page, n, prev, next);
        if (list.empty()) text.draw(canvas, kPad, top + kIcon / 2 - 10, L"Empty", 150, 150, 160);
        for (size_t i = page * per; i < list.size() && i < (page + 1) * per; ++i) {
            const size_t k = i - page * per;
            tile(list[i], kPad + static_cast<int>(k % kCols) * (kIcon + kGap), top + static_cast<int>(k / kCols) * (kIcon + kGap), item, i);
        }
    }
    void pager(int y, size_t page, size_t n, Kind prev, Kind next) {  // "< 2/3 >" at the right
        const std::wstring where = std::to_wstring(page + 1) + L"/" + std::to_wstring(n);
        const int right = kW - kPad, ww = text.width(where) + 16;
        button(right - 30, y, 30, L">", false, next);
        text.draw(canvas, right - 30 - ww + 8, y + 5, where, 200, 200, 210);
        button(right - 30 - ww - 30, y, 30, L"<", false, prev);
    }

    // Lines of `s` that fit in `width` pixels (words kept whole where they can be).
    std::vector<std::wstring> wrap(const std::wstring& s, int width) {
        std::vector<std::wstring> out;
        size_t start = 0;
        while (start <= s.size()) {
            const size_t nl = s.find(L'\n', start);
            const std::wstring para = s.substr(start, nl == std::wstring::npos ? std::wstring::npos : nl - start);
            std::wstring line;
            size_t at = 0;
            while (at < para.size()) {
                size_t sp = para.find(L' ', at);
                if (sp == std::wstring::npos) sp = para.size();
                const std::wstring word = para.substr(at, sp - at);
                const std::wstring tryline = line.empty() ? word : line + L" " + word;
                if (!line.empty() && text.width(tryline) > width) {
                    out.push_back(line);
                    line = word;
                } else {
                    line = tryline;
                }
                at = sp + 1;
            }
            out.push_back(line);
            if (nl == std::wstring::npos) break;
            start = nl + 1;
        }
        return out;
    }

    // The rows of a generic tab: laid out top to bottom, buttons along a line while they fit (same_line), a new page
    // where the window ends. Draws the page shown.
    // A tab of rows (every feature's tab but the Auto Junk List and Windows): laid out top to bottom and scrolled
    // (mouse wheel, the scroll bar at the right: drag its thumb, or click above or below it). Rows outside the view are
    // cut off by draw() (clear_outside). The page control (pager, "< 1/2 >") stays for views that want pages.
    void draw_rows() {
        struct Placed {
            const Row* row;
            int x, y, w, h;
            std::vector<std::wstring> lines;
        };
        std::vector<Placed> placed;
        int content_h = 0;
        auto layout = [&](int right) {  // y from 0; the content's height into content_h
            placed.clear();
            const int left = kPad;
            int x = left, y = 10, line_h = 0;
            auto newline = [&] {
                if (line_h > 0) y += line_h + 6;
                x = left;
                line_h = 0;
            };
            for (const Row& r : rows) {
                if (r.kind == 'b' || r.kind == 'i') {  // buttons and item tiles run along the line and wrap
                    const bool tile_row = r.kind == 'i';
                    const int w = tile_row ? kIcon : std::max(34, text.width(r.text) + 22), h = tile_row ? kIcon : 30;
                    if (!(r.same && x > left && x + w <= right)) newline();
                    placed.push_back({&r, x, y, w, h, {}});
                    x += w + (tile_row ? kGap : 6);
                    line_h = std::max(line_h, h);
                } else {
                    newline();
                    if (r.kind == 's') {
                        placed.push_back({&r, left, y + 6, right - left, 1, {}});
                        y += 14;
                    } else {
                        std::vector<std::wstring> lines = wrap(r.text, right - left);
                        const int lh = r.kind == 'h' ? 26 : 22;
                        const int h = lh * static_cast<int>(lines.size()) + (r.kind == 'h' ? 4 : 0);
                        placed.push_back({&r, left, y + (r.kind == 'h' ? 4 : 0), right - left, h, std::move(lines)});
                        y += h + 2;
                    }
                }
            }
            newline();
            content_h = y + 10;
        };
        const int view = kViewBottom - kViewTop;
        layout(kW - kPad);
        const bool bar = content_h > view;
        if (bar) layout(kW - kPad - kBarW - 8);  // room for the scroll bar
        max_scroll = std::max(0, content_h - view);
        rows_scroll = std::clamp(rows_scroll, 0, max_scroll);
        const size_t first_hit = hits.size();
        for (const Placed& p : placed) {
            const int y = kViewTop + p.y - rows_scroll;
            if (y + p.h < kViewTop || y > kViewBottom) continue;  // out of view
            const Row& r = *p.row;
            if (r.kind == 'i') {  // an item tile: the same as the Auto Junk List's, with the same tooltip
                Entry e;
                e.id = r.item;
                e.count = r.count;
                e.name = r.text;
                tile(e, p.x, y, kRowItem, static_cast<size_t>(r.number));
                hits.back().row = &r;
                if (r.selected) frame_box(p.x - 3, y - 3, p.x + kIcon + 3, y + kIcon + 3, 3, 255, 200, 60);
            } else if (r.kind == 'b') {
                button(p.x, y, p.w, r.text, r.selected, kRowButton, static_cast<size_t>(r.number), r.disabled, &r);
            } else if (r.kind == 's') {
                box(p.x, y, p.x + p.w, y + 1, 90, 90, 100, 1.0f);
            } else {
                float cr = 220, cg = 220, cb = 225;
                if (r.kind == 'h') cr = 255, cg = 210, cb = 122;
                if (r.dim) cr = cg = cb = 150;
                if (r.has_colour) cr = r.r, cg = r.g, cb = r.b;
                int ly = y;
                for (const std::wstring& l : p.lines) {
                    text.draw(canvas, p.x, ly, l, cr, cg, cb);
                    ly += r.kind == 'h' ? 26 : 22;
                }
            }
        }
        for (size_t i = first_hit; i < hits.size();) {  // a button half out of view takes clicks only on its visible part
            const RECT v{0, kViewTop, kW, kViewBottom};
            if (!IntersectRect(&hits[i].r, &hits[i].r, &v)) hits.erase(hits.begin() + static_cast<std::ptrdiff_t>(i));
            else ++i;
        }
        if (bar) {  // the scroll bar: a track, and a thumb as tall as the part in view
            const int x0 = kW - kPad - kBarW, x1 = kW - kPad;
            const int track_h = view - 8, thumb_h = std::max(30, track_h * view / content_h);
            const int thumb_y = kViewTop + 4 + (max_scroll ? (track_h - thumb_h) * rows_scroll / max_scroll : 0);
            track_r = {x0, kViewTop + 4, x1, kViewTop + 4 + track_h};
            thumb_r = {x0, thumb_y, x1, thumb_y + thumb_h};
            box(track_r.left, track_r.top, track_r.right, track_r.bottom, 40, 42, 50, 1.0f);
            const bool over = thumb_drag || inside(thumb_r);
            box(thumb_r.left + 1, thumb_r.top, thumb_r.right - 1, thumb_r.bottom, over ? 150.0f : 110.0f, over ? 160.0f : 118.0f, over ? 185.0f : 135.0f, 1.0f);
            hits.push_back({track_r, kScrollTrack, 0});
            hits.push_back({thumb_r, kScrollThumb, 0});
        } else {
            track_r = thumb_r = RECT{};
        }
        if (rows.empty()) text.draw(canvas, kPad, kViewTop + 14, rows_of == current ? L"Nothing here" : L"...", 150, 150, 160);
    }

    // Everything drawn above and below the scrolled view goes: the background is drawn there again.
    void clear_outside() {
        for (int y = 0; y < kH; ++y) {
            if (y >= kViewTop && y < kViewBottom) continue;
            std::fill(pixels.begin() + static_cast<std::ptrdiff_t>(y) * kW, pixels.begin() + static_cast<std::ptrdiff_t>(y + 1) * kW, 0u);
        }
        box(0, 0, kW, kViewTop, 18, 18, 22, 0.94f);
        box(0, kViewBottom, kW, kH, 18, 18, 22, 0.94f);
    }

    void scroll_to(int to) {
        const int v = std::clamp(to, 0, max_scroll);
        if (v != rows_scroll) {
            rows_scroll = v;
            dirty = true;
        }
    }

    void wheel(int delta, int x, int y) override {
        if (current == "loot_filter" || current == "windows") return;
        scroll_to(rows_scroll - delta * 66 / WHEEL_DELTA);  // 3 lines a notch
    }

    // The Windows tab (this DLL's own): each pinned window with Show/Hide and Reset, and how to move them.
    void draw_windows() {
        int y = kTop + 14;
        text.draw(canvas, kPad, y, L"Pinned windows", 255, 210, 122);
        y += 34;
        for (size_t i = 0; i < g_pinned.size(); ++i) {
            PinnedLayer* p = g_pinned[i];
            const bool hidden = p->lay().hidden;
            text.draw(canvas, kPad, y + 5, p->title, 230, 230, 235);
            button(kPad + 200, y, 110, hidden ? L"Show" : L"Hide", !hidden, kPinShow, i);
            button(kPad + 320, y, 150, L"Reset place", false, kPinReset, i);
            y += 40;
        }
        text.draw(canvas, kPad, y + 5, L"FlameKit window", 230, 230, 235);
        button(kPad + 320, y, 150, L"Reset place", false, kPinReset, g_pinned.size());  // its place and size
        y += 40;
        y += 10;
        static const wchar_t* kHelp[] = {
            L"Hold the pointer key (Right Alt unless changed in Settings) to get",
            L"the pointer while you play. Then a pinned window can be dragged by",
            L"its title bar, resized from its lower right corner,",
            L"collapsed with \u2013 or hidden with \u00D7. Let go of the key to play on.",
        };
        for (const wchar_t* l : kHelp) {
            text.draw(canvas, kPad, y, l, 190, 195, 205);
            y += 24;
        }
    }

    void draw_junk() {
        const std::wstring drop_label = std::wstring(delete_junk ? L"Delete" : L"Drop") + L" ▾";
        const int drop_w = std::max(text.width(L"Delete ▾"), text.width(L"Drop ▾")) + 28;
        const int drop_x = kW - kPad - drop_w, by = kTop + 10;
        button(drop_x, by, drop_w, drop_label, false, kDrop);
        const int dump_w = text.width(L"Dump Junk") + 28, dump_x = drop_x - 8 - dump_w;
        button(dump_x, by, dump_w, L"Dump Junk", false, kDump);
        const int auto_w = text.width(L"Auto: OFF") + 28;
        button(dump_x - 8 - auto_w, by, auto_w, auto_on ? L"Auto: ON" : L"Auto: OFF", auto_on, kAuto);
        int ox = kPad;  // the feature's other settings
        for (size_t i = 0; i < opts.size(); ++i) {
            const int w = text.width(opts[i].label) + 22;
            button(ox, opts_y, w, opts[i].label, opts[i].lit, kOpt, i);
            if (!opts[i].tip.empty()) hits.back().tip = &opts[i].tip;
            ox += w + 8;
        }
        section(L"In your bag", 255, 210, 122, bag, bag_page, kBagRows, kBagHead, kBagTop, kBagItem, kBagPrev, kBagNext);
        section(L"Your junk list", 255, 74, 61, junk, junk_page, kJunkRows, kJunkHead, kJunkTop, kJunkItem, kJunkPrev, kJunkNext);
        if (drop_open) {  // the drop-down's options, over what is below
            box(drop_x - 1, by + 29, drop_x + drop_w + 1, by + 30 + 2 * 30 + 1, 200, 200, 210, 1.0f);
            button(drop_x, by + 30, drop_w, L"Drop", !delete_junk, kDropOption, 0);
            button(drop_x, by + 60, drop_w, L"Delete", delete_junk, kDropOption, 1);
        }
    }

    // Lays the window out at its size now: the tab rows (as many as the tabs need), where a tab's content starts, the
    // part a tab of rows scrolls in, and the Auto Junk List's grids (as many icons across and rows down as fit).
    void lay_out() {
        tab_r.clear();
        int total = 0;
        for (const Tab& t : tabs) total += text.width(t.title) + 32;
        const int pad = total <= kW - 2 * kPad ? 28 : 18;  // narrower tabs first, then a second row
        int tx = kPad, ty = kTitle + 6;
        for (const Tab& t : tabs) {
            const int w = text.width(t.title) + pad;
            if (tx > kPad && tx + w > kW - kPad) {
                tx = kPad;
                ty += 34;
            }
            tab_r.push_back({tx, ty, tx + w, ty + 30});
            tx += w + 4;
        }
        kTop = ty + 30 + 14;
        kCols = std::max(1, (kW - 2 * kPad + kGap) / (kIcon + kGap));
        const int grid_h = kH - kTop - 52 - 30 - kPad - 30 - kPad;
        const int grid_rows = std::max(2, (grid_h + 2 * kGap) / (kIcon + kGap));
        kBagRows = std::max(1, (grid_rows * 5 + 4) / 9);
        kJunkRows = std::max(1, grid_rows - kBagRows);
        {  // the Auto Junk List's option buttons: at the left of its top row when they fit, else a line under it
            int need = 0, right = 0;
            for (const Opt& o : opts) need += text.width(o.label) + 22 + 8;
            right = std::max(text.width(L"Delete \u25BE"), text.width(L"Drop \u25BE")) + 28 + 8 + text.width(L"Dump Junk") + 28 + 8 +
                    text.width(L"Auto: OFF") + 28 + 8;
            opts_y = kPad + need + right <= kW - kPad ? kTop + 10 : kTop + 48;
        }
        kBagHead = kTop + 52 + (opts_y > kTop + 10 ? 38 : 0);
        kBagTop = kBagHead + 30;
        kJunkHead = kBagTop + kBagRows * kIcon + (kBagRows - 1) * kGap + kPad;
        kJunkTop = kJunkHead + 30;
        kViewTop = kTop + 2 + (current == "changes" ? 44 : 0);  // What's New: the Check for updates button above
        kViewBottom = kH - kPad;
    }

    void draw() {
        if (!fonts) {
            fonts = true;
            text.ready(g_screen, 16);
        }
        resize(kW, kH);
        hits.clear();
        std::fill(pixels.begin(), pixels.end(), 0u);
        lay_out();
        box(0, 0, kW, kH, 18, 18, 22, 0.94f);
        const bool rows_tab = current != "loot_filter" && current != "windows";
        if (rows_tab) {  // first, so the title bar and the tabs are drawn over what is scrolled out at the top
            draw_rows();
            clear_outside();
        }
        // the title bar: FlameKit and its version, the x that closes the window; dragged to move the window
        box(0, 0, kW, kTitle, 30, 34, 44, 0.95f);
        text.draw(canvas, 12, 7, version.empty() ? std::wstring(L"FlameKit") : L"FlameKit v" + widen(version), 235, 225, 205);
        close_r = {kW - 32, 5, kW - 8, kTitle - 5};
        {
            const bool over = inside(close_r);
            box(close_r.left, close_r.top, close_r.right, close_r.bottom, over ? 170.0f : 50.0f, over ? 60.0f : 54.0f, over ? 60.0f : 64.0f, 1.0f);
            text.draw(canvas, close_r.left + (close_r.right - close_r.left - text.width(L"\u00D7")) / 2, close_r.top + 1, L"\u00D7", 235, 235, 240);
            hits.push_back({close_r, kClose, 0});
        }
        // the tab rows
        for (size_t i = 0; i < tabs.size() && i < tab_r.size(); ++i) {
            const RECT& r = tab_r[i];
            const bool on = tabs[i].id == current;
            const bool over = inside(r);
            box(r.left, r.top, r.right, r.bottom, on ? 46.0f : over ? 50.0f : 32.0f, on ? 92.0f : over ? 56.0f : 36.0f, on ? 150.0f : over ? 70.0f : 44.0f, 1.0f);
            text.draw(canvas, r.left + (r.right - r.left - text.width(tabs[i].title)) / 2, r.top + 5, tabs[i].title, on ? 235.0f : 170.0f,
                      on ? 240.0f : 190.0f, 255);
            hits.push_back({r, kTab, i});
        }
        box(kPad, kTop - 6, kW - kPad, kTop - 5, 70, 110, 170, 1.0f);
        if (current == "loot_filter") draw_junk();
        else if (current == "windows") draw_windows();
        if (current == "changes") {  // the updater's normal check, at once (web_update::g_check_now)
            const int cw = text.width(L"Check for updates") + 24;
            // how often the updater looks (web_update.hpp): every minute on the test channel, every 10 minutes for players
            const bool test = read_text(g_flamekit_dir + L"update_channel.txt", 16).rfind("test", 0) == 0;
            text.draw(canvas, kPad, kTop + 9, test ? L"FlameKit looks for updates every minute (test channel)." : L"FlameKit looks for updates every 10 minutes.",
                      150, 155, 165);
            button(kW - kPad - cw, kTop + 4, cw, L"Check for updates", false, kCheckUpdates);
        }
        // the frame, and the grip in the lower right corner that resizes the window
        frame_box(0, 0, kW, kH, 1, 120, 160, 220);
        for (int k = 0; k < kGrip; k += 3) box(kW - kGrip + k, kH - 2 - k / 3, kW - 2, kH - 1 - k / 3, 140, 170, 220, 0.9f);
        for (const Hit& h : hits) {  // under the pointer: an item's tooltip (the standard one), or a button's
            if (!inside(h.r)) continue;
            if ((h.kind == kBagItem && h.index < bag.size()) || (h.kind == kJunkItem && h.index < junk.size())) {
                const Entry& e = h.kind == kBagItem ? bag[h.index] : junk[h.index];
                ItemTip t;
                t.name = e.name;
                t.rarity = e.rarity;
                t.level = e.level;
                t.type = e.type;
                t.count = e.count;
                t.command = widen(e.key);
                t.hint = h.kind == kBagItem ? L"Click: put it on your junk list" : L"Click: take it off your junk list";
                draw_item_tip(canvas, text, mouse_x, mouse_y, kW, kH, t);
                break;
            }
            if (h.kind == kRowItem && h.row) {
                ItemTip t;
                t.name = h.row->text;
                t.rarity = h.row->rarity;
                t.level = h.row->level;
                t.type = h.row->type;
                t.count = h.row->count;
                t.command = h.row->command;
                t.hint = h.row->tip;
                draw_item_tip(canvas, text, mouse_x, mouse_y, kW, kH, t);
                break;
            }
            std::wstring tip;
            if (h.tip) tip = *h.tip;
            if (tip.empty()) continue;
            const std::vector<std::wstring> lines = wrap(tip, 420);
            int tw = 0;
            for (const std::wstring& l : lines) tw = std::max(tw, text.width(l));
            tw += 16;
            const int th = 22 * static_cast<int>(lines.size()) + 8;
            const int tx2 = std::clamp(mouse_x + 14, 0, std::max(0, kW - tw)), ty = std::clamp(mouse_y + 20, 0, std::max(0, kH - th));
            box(tx2, ty, tx2 + tw, ty + th, 30, 30, 36, 1.0f);
            frame_box(tx2, ty, tx2 + tw, ty + th, 1, 120, 120, 130);
            int ly = ty + 4;
            for (const std::wstring& l : lines) {
                text.draw(canvas, tx2 + 8, ly, l, 240, 240, 240);
                ly += 22;
            }
            break;
        }
        changed = true;
    }

    void close(const char* why) {
        open = close_asked = drop_open = false;
        moved_junk.clear();
        moved_bag.clear();
        show_junk.clear();
        show_bag.clear();
        mouse_x = mouse_y = -1;
        visible = false;
        changed = true;
        tell_view();
        FK_LOG(fklog::kInfo, "window: closed (%s)", why);
    }

    void update(const Frame& f) override {
        // the Lua part asks for the window on a tab (after an update: What's New; features/changes.lua): ui_open.dat
        // holds the tab's id; opened once, the file is deleted
        if (!open && f.now >= next_open_check) {
            next_open_check = f.now + 500;
            const std::wstring file = g_flamekit_dir + L"ui_open.dat";
            if (f.in_world && f.game_front && GetFileAttributesW(file.c_str()) != INVALID_FILE_ATTRIBUTES) {
                const std::string tab = read_text(file, 64);
                DeleteFileW(file.c_str());
                std::string id;
                for (char c : tab)
                    if (std::isalnum(static_cast<unsigned char>(c)) || c == '_') id += c;
                if (!id.empty()) current = id;
                g_ui_request = true;
                FK_LOG(fklog::kInfo, "window: opened by the Lua part on tab %s", current.c_str());
            }
        }
        if (g_ui_request.exchange(false)) {
            if (!open && f.game_front) {
                open = true;
                if (version.empty()) version = version_in(g_flamekit_dir + L"mod.json");
                list_stamp = tabs_stamp = 0;  // read at once
                dirty = true;
                FK_LOG(fklog::kInfo, "window: opened (F6), tab %s", current.c_str());
            } else if (!open) {
                FK_LOG(fklog::kInfo, "window: F6 ignored: the game's window is not the front window");
            }
        }
        if (open && (close_asked || !f.in_world)) close(close_asked ? "F6, Esc or its x" : "the world ended");
        if (!open) return;
        tell_view();
        const uint64_t ls = stamp_of(g_flamekit_dir + L"ui_list.dat"), ts = stamp_of(g_flamekit_dir + L"ui_tabs.dat");
        if (ls != list_stamp && read_list()) {
            list_stamp = ls;
            dirty = true;
            auto go_to = [&](std::string& key, const std::vector<Entry>& list, size_t& page, int rows_n) {
                for (size_t i = 0; i < list.size() && !key.empty(); ++i)
                    if (list[i].key == key) {
                        page = i / static_cast<size_t>(std::max(1, kCols * rows_n));
                        key.clear();
                    }
            };
            go_to(show_junk, junk, junk_page, kJunkRows);
            go_to(show_bag, bag, bag_page, kBagRows);
        }
        if (ts != tabs_stamp && read_tabs()) {
            tabs_stamp = ts;
            dirty = true;
            bool known = false;
            for (const Tab& t : tabs) known = known || t.id == current;
            if (!known && !tabs.empty()) {
                current = tabs[0].id;
                tell_view();
            }
        }
        LayoutEntry& e = g_layout.get("window");  // its size and place: the player's (ui_layout.txt), else the defaults
        const int w = std::clamp(e.w > 0 ? e.w : kDefW, kMinW, std::max(kMinW, f.gw));
        const int h = std::clamp(e.h > 0 ? e.h : kDefH, kMinH, std::max(kMinH, f.gh));
        if (w != kW || h != kH) {
            kW = w;
            kH = h;
            dirty = true;
        }
        if (dirty) {
            dirty = false;
            draw();
        }
        visible = true;
        const int x = e.x >= 0 ? e.x : (f.gw - kW) / 2, y = e.y >= 0 ? e.y : (f.gh - kH) / 2;
        place(std::clamp(x, 0, std::max(0, f.gw - kW)), std::clamp(y, 0, std::max(0, f.gh - kH)));
    }

    void end_win_drag() {
        win_drag = kStill;
        LayoutEntry& e = g_layout.get("window");
        e.x = rect.left;
        e.y = rect.top;
        e.w = kW;
        e.h = kH;
        g_layout.save();
        FK_LOG(fklog::kInfo, "window: placed at %d,%d, %dx%d", e.x, e.y, e.w, e.h);
    }

    bool wants_mouse() const override { return open; }
    bool wants_keys() const override { return open; }
    void key(WPARAM vk) override {
        const uint32_t wk = settings().window_vk;
        if (vk == VK_ESCAPE || (wk && vk == wk)) {
            close_asked = true;
            return;
        }
        // any other key: to the Lua part (a setting's Change takes it as the setting's key; else the shown tab's feature)
        if (current == "windows") return;
        std::string name = emf::keys::detail::key_name(static_cast<uint32_t>(vk));
        if (name.rfind("key ", 0) == 0) name = name.substr(4);  // "key 0xba": the setting is written "0xba"
        act("key", name);
    }
    // Another program took the front (a click on it, Alt+Tab): the window stays open (owner, 0.15.41), like the pinned
    // windows; it no longer gets the keys until it is clicked again (WM_MOUSEACTIVATE gives it the front back). F6, Esc
    // and its x close it.
    void lost_front() override {
        if (open) FK_LOG(fklog::kInfo, "window: another program took the front: the window stays open");
    }
    void mouse_left() override {
        mouse_x = mouse_y = -1;
        dirty = true;
    }
    void mouse(UINT msg, int x, int y) override {
        if (msg == WM_MOUSEMOVE) {
            if (win_drag == kMoving) {  // dragged by its title bar
                LayoutEntry& e = g_layout.get("window");
                e.x = rect.left + x - win_grab.x;
                e.y = rect.top + y - win_grab.y;
            } else if (win_drag == kSizing) {  // resized from its lower right corner
                LayoutEntry& e = g_layout.get("window");
                e.w = x + win_grab.x;
                e.h = y + win_grab.y;
            }
            if (thumb_drag) {  // the scroll bar's thumb follows the pointer
                const int track_h = track_r.bottom - track_r.top, thumb_h = thumb_r.bottom - thumb_r.top;
                if (track_h > thumb_h) scroll_to((y - thumb_grab - track_r.top) * max_scroll / (track_h - thumb_h));
            }
            if (x != mouse_x || y != mouse_y) {
                mouse_x = x;
                mouse_y = y;
                dirty = true;
            }
            return;
        }
        if (msg == WM_LBUTTONUP) {
            if (win_drag != kStill) end_win_drag();
            if (thumb_drag) {
                thumb_drag = false;
                dirty = true;
            }
            return;
        }
        if (msg != WM_LBUTTONDOWN) return;
        const bool was_open = drop_open;
        drop_open = false;
        dirty = true;
        for (auto it = hits.rbegin(); it != hits.rend(); ++it) {  // the last drawn is on top (the drop-down's options)
            const Hit& h = *it;
            if (x < h.r.left || y < h.r.top || x >= h.r.right || y >= h.r.bottom) continue;
            switch (h.kind) {
            case kTab:
                if (h.index < tabs.size() && tabs[h.index].id != current) {
                    current = tabs[h.index].id;
                    rows_page = 0;
                    rows_scroll = 0;
                    FK_LOG(fklog::kInfo, "window: tab %s", current.c_str());
                    tell_view();
                }
                break;
            case kPinShow:
                if (h.index < g_pinned.size()) {
                    LayoutEntry& e = g_pinned[h.index]->lay();
                    e.hidden = !e.hidden;
                    g_pinned[h.index]->dirty = true;
                    g_layout.save();
                    FK_LOG(fklog::kInfo, "window: pinned window %s %s", g_pinned[h.index]->id.c_str(), e.hidden ? "hidden" : "shown");
                }
                break;
            case kPinReset:
                if (h.index == g_pinned.size()) {  // FlameKit's window: the middle of the screen, its first size
                    g_layout.get("window") = LayoutEntry{};
                    g_layout.save();
                    FK_LOG(fklog::kInfo, "window: back to its first place and size");
                } else if (h.index < g_pinned.size()) {
                    g_pinned[h.index]->lay() = LayoutEntry{};
                    g_pinned[h.index]->dirty = true;
                    g_layout.save();
                    FK_LOG(fklog::kInfo, "window: pinned window %s back to its default place", g_pinned[h.index]->id.c_str());
                }
                break;
            case kClose:
                close_asked = true;
                break;
            case kOpt:
                if (h.index < opts.size()) act("opt", opts[h.index].key);
                break;
            case kScrollThumb:
                thumb_drag = true;
                thumb_grab = y - thumb_r.top;
                break;
            case kScrollTrack:  // above or below the thumb: a view's height up or down
                scroll_to(rows_scroll + (y < thumb_r.top ? -1 : 1) * (kViewBottom - kViewTop - 40));
                break;
            case kCheckUpdates:
                web_update::g_check_now = true;
                FK_LOG(fklog::kInfo, "window: Check for updates");
                break;
            case kRowButton:
            case kRowItem:
                if (h.kind == kRowItem && h.index == 0) break;  // an item tile without a click
                act("tab", rows_of + "/" + std::to_string(generation) + "/" + std::to_string(h.index));
                break;
            case kRowPrev: if (rows_page > 0) --rows_page; break;
            case kRowNext: ++rows_page; break;
            // A moved item gets a gold frame where it went. Moved straight back (the player changed their mind), it
            // gets none: it is back where it was.
            case kBagItem:
                if (h.index < bag.size()) {
                    const std::string& key = bag[h.index].key;
                    act("junk", key);
                    if (!moved_bag.erase(key)) moved_junk.insert(key);
                    show_junk = key;
                }
                break;
            case kJunkItem:
                if (h.index < junk.size()) {
                    const std::string& key = junk[h.index].key;
                    act("keep", key);
                    if (!moved_junk.erase(key)) moved_bag.insert(key);
                    show_bag = key;
                }
                break;
            case kAuto: act("auto", auto_on ? "0" : "1"); break;
            case kDump: act("dump", "-"); break;
            case kDrop: drop_open = !was_open; break;
            case kDropOption: act("action", h.index == 1 ? "delete" : "drop"); break;
            case kBagPrev: if (bag_page > 0) --bag_page; break;
            case kBagNext: ++bag_page; break;
            case kJunkPrev: if (junk_page > 0) --junk_page; break;
            case kJunkNext: ++junk_page; break;
            }
            return;
        }
        // nothing to click there: the lower right corner resizes the window, the title bar moves it
        if (x >= kW - kGrip && y >= kH - kGrip) {
            win_drag = kSizing;
            win_grab = {kW - x, kH - y};
        } else if (y < kTitle) {
            win_drag = kMoving;
            win_grab = {x, y};
            LayoutEntry& e = g_layout.get("window");
            e.x = rect.left;
            e.y = rect.top;
        }
    }
};

// ---- the backdrop: the whole game window takes the pointer while FlameKit's window is open ----
// Fully clear pixels of a layered window let the mouse through to the game, which hides its pointer over its own
// window. While FlameKit's window is open, this layer covers the game window with pixels that are as good as clear
// (alpha 1 of 255) so the pointer stays visible everywhere; a click outside FlameKit's window does nothing.
struct BackdropLayer : Layer {
    const char* name() const override { return "backdrop"; }
    const Layer* window = nullptr;
    void update(const Frame& f) override {
        const bool want = ((window && window->visible) || g_pointer_hold) && f.gw > 0 && f.gh > 0;
        if (want != visible) {
            visible = want;
            changed = true;
            FK_LOG(fklog::kDebug, "backdrop: %s", want ? "on (the pointer shows over the whole game window)" : "off");
        }
        if (!visible) return;
        if (canvas.w != f.gw || canvas.h != f.gh) {
            resize(f.gw, f.gh);
            std::fill(pixels.begin(), pixels.end(), 0x01000000u);
        }
        place(0, 0);
    }
    bool wants_mouse() const override { return visible; }
    // While Right Alt is held the overlay is the front window, so the game gets no mouse moves (it would turn the
    // camera) and its own pointer lock is let go; the game gets the front back when Right Alt is let go.
    bool wants_keys() const override { return visible && g_pointer_hold; }
};

// The game's own mouse pointer, so FlameKit's windows look like the game's: taken from Windows while the game shows its
// pointer (in its menus) the first time; until then (or if the game draws its pointer itself) Windows' arrow.
HCURSOR g_game_cursor = nullptr;
void look_for_game_cursor() {
    if (g_game_cursor) return;
    CURSORINFO ci{};
    ci.cbSize = sizeof(ci);
    if (!GetCursorInfo(&ci) || !(ci.flags & CURSOR_SHOWING) || !ci.hCursor) return;
    static const LPCSTR kSystem[] = {IDC_ARROW, IDC_IBEAM, IDC_WAIT, IDC_CROSS, IDC_UPARROW, IDC_SIZENWSE, IDC_SIZENESW, IDC_SIZEWE,
                                     IDC_SIZENS, IDC_SIZEALL, IDC_NO, IDC_HAND, IDC_APPSTARTING, IDC_HELP};
    for (LPCSTR id : kSystem)
        if (ci.hCursor == LoadCursorA(nullptr, id)) return;  // one of Windows' own: not the game's
    g_game_cursor = static_cast<HCURSOR>(CopyIcon(ci.hCursor));
    ICONINFO ii{};
    BITMAP bm{};
    if (g_game_cursor && GetIconInfo(g_game_cursor, &ii)) {
        GetObject(ii.hbmColor ? ii.hbmColor : ii.hbmMask, sizeof bm, &bm);
        if (ii.hbmColor) DeleteObject(ii.hbmColor);
        if (ii.hbmMask) DeleteObject(ii.hbmMask);
    }
    FK_LOG(fklog::kInfo, "cursor: the game's pointer is used for FlameKit's windows (%ldx%ld)", bm.bmWidth, bm.bmHeight);
}

// ---- the lower left corner: the status line, the FlameKit label, the update line, the debug level ----
// The label and the status line come from the Lua part in emf\mods\flamekit\ui_hud.dat (kit.lua describes it); the
// update line from update_status.txt, which this DLL's own updater writes (green: ready for a restart); the debug level line only while the level
// is not normal.
struct HudLayer : Layer {
    const char* name() const override { return "lower left lines"; }
    struct Line {
        std::wstring text;
        uint8_t r, g, b;
        bool operator==(const Line& o) const { return text == o.text && r == o.r && g == o.g && b == o.b; }
    };
    TextPainter text;
    bool font = false;
    std::vector<Line> shown;
    std::wstring label, status, notice, update_line;
    uint32_t status_rgb = 0xffb060, update_rgb = 0xffb060;
    uint64_t next_read = 0;

    void read_files(uint64_t now) {
        next_read = now + 500;
        if (FILE* fp = _wfsopen((g_flamekit_dir + L"ui_hud.dat").c_str(), L"rb", _SH_DENYNO)) {
            std::wstring new_label, new_status, new_notice;
            uint32_t rgb = 0xffb060;
            bool complete = false;
            char line[512];
            while (fgets(line, sizeof line, fp)) {
                line[std::strcspn(line, "\r\n")] = 0;
                if (std::strcmp(line, "end") == 0) {
                    complete = true;
                    break;
                }
                if (std::strncmp(line, "label ", 6) == 0) {
                    new_label = widen(line + 6);
                } else if (std::strncmp(line, "notice ", 7) == 0) {
                    new_notice = widen(line + 7);
                } else if (std::strncmp(line, "status ", 7) == 0 && std::strlen(line) > 14) {
                    rgb = static_cast<uint32_t>(std::strtoul(std::string(line + 7, 6).c_str(), nullptr, 16));
                    new_status = widen(line + 14);
                }
            }
            fclose(fp);
            if (complete) {
                label = new_label;
                status = new_status;
                notice = new_notice;
                status_rgb = rgb;
            }
        }
        update_line.clear();  // "<kind>|<text>" (web_update.hpp): ready green, ok pale green, failed red, busy orange
        if (FILE* fp = _wfsopen((g_flamekit_dir + L"update_status.txt").c_str(), L"rb", _SH_DENYNO)) {
            char line[256] = "";
            if (fgets(line, sizeof line, fp)) {
                line[std::strcspn(line, "\r\n")] = 0;
                const char* bar = std::strchr(line, '|');
                if (bar && bar[1]) {
                    update_line = widen(bar + 1);
                    update_rgb = std::strncmp(line, "ready", 5) == 0 ? 0x5adc6eu : std::strncmp(line, "failed", 6) == 0 ? 0xff5a50u
                               : std::strncmp(line, "ok", 2) == 0 ? 0xb4e6b4u : 0xffb060u;
                }
            }
            fclose(fp);
        }
    }

    void update(const Frame& f) override {
        if (f.now >= next_read) read_files(f.now);
        std::vector<Line> want;
        if (!status.empty()) want.push_back({status, static_cast<uint8_t>(status_rgb >> 16), static_cast<uint8_t>(status_rgb >> 8), static_cast<uint8_t>(status_rgb)});
        if (!label.empty()) want.push_back({label, 235, 225, 205});
        if (!notice.empty()) want.push_back({notice, 255, 150, 50});  // orange: e.g. the server does not run FlameKit
        if (!update_line.empty()) want.push_back({update_line, static_cast<uint8_t>(update_rgb >> 16), static_cast<uint8_t>(update_rgb >> 8), static_cast<uint8_t>(update_rgb)});
        const int mode = fklog::g_mode.load();
        if (mode != fklog::kNormal) want.push_back({std::wstring(L"FlameKit debug: ") + (mode == fklog::kOff ? L"off" : L"full"), 120, 200, 255});
        const bool vis = f.in_world && !want.empty();
        if (vis != visible) {
            visible = vis;
            changed = true;
            FK_LOG(fklog::kDebug, "lower left lines: %s", vis ? "shown" : "hidden");
        }
        if (!visible) return;
        if (want != shown) {
            shown = want;
            if (!font) {
                font = true;
                text.ready(g_screen, 18);
            }
            int w = 8;
            for (const Line& l : shown) w = std::max(w, text.width(l.text) + 8);
            resize(w, static_cast<int>(shown.size()) * 24 + 4);
            std::fill(pixels.begin(), pixels.end(), 0u);
            for (size_t i = 0; i < shown.size(); ++i) text.draw(canvas, 4, 2 + static_cast<int>(i) * 24, shown[i].text, shown[i].r, shown[i].g, shown[i].b);
            changed = true;
            FK_LOG(fklog::kDebug, "lower left lines: %d line(s), first '%ls'", static_cast<int>(shown.size()), shown.empty() ? L"" : shown[0].text.c_str());
        }
        place(f.gw * 12 / 1000, f.gh - f.gh * 20 / 1000 - canvas.h);
    }
};

// ---- the compositor: the layers into one surface ----
struct Compositor {
    std::vector<Layer*> layers;  // bottom first
    std::vector<RECT> was_rect;
    std::vector<bool> was_visible;

    static void unite(RECT& into, const RECT& r) {
        if (IsRectEmpty(&r)) return;
        if (IsRectEmpty(&into)) into = r;
        else UnionRect(&into, &into, &r);
    }

    // Puts what changed into `surface` (w x h); returns the part that changed (empty: nothing).
    RECT compose(uint32_t* surface, int w, int h, bool all) {
        if (was_rect.size() != layers.size()) {
            was_rect.assign(layers.size(), RECT{});
            was_visible.assign(layers.size(), false);
        }
        RECT dirty{};
        if (all) dirty = {0, 0, w, h};
        for (size_t i = 0; i < layers.size(); ++i) {
            Layer* l = layers[i];
            const bool moved = !EqualRect(&l->rect, &was_rect[i]);
            if (l->changed || moved || l->visible != was_visible[i]) {
                if (was_visible[i]) unite(dirty, was_rect[i]);
                if (l->visible) unite(dirty, l->rect);
            }
            l->changed = false;
            was_rect[i] = l->rect;
            was_visible[i] = l->visible;
        }
        const RECT screen{0, 0, w, h};
        IntersectRect(&dirty, &dirty, &screen);
        if (IsRectEmpty(&dirty)) return dirty;
        for (int y = dirty.top; y < dirty.bottom; ++y) std::fill(surface + static_cast<size_t>(y) * w + dirty.left, surface + static_cast<size_t>(y) * w + dirty.right, 0u);
        for (Layer* l : layers) {
            if (!l->visible || !l->canvas.px) continue;
            RECT part;
            if (!IntersectRect(&part, &l->rect, &dirty)) continue;
            for (int y = part.top; y < part.bottom; ++y) {
                const uint32_t* src = l->canvas.px + static_cast<size_t>(y - l->rect.top) * l->canvas.w + (part.left - l->rect.left);
                uint32_t* dst = surface + static_cast<size_t>(y) * w + part.left;
                for (int x = part.left; x < part.right; ++x, ++src, ++dst) {
                    const uint32_t s = *src, a = s >> 24;
                    if (a == 255 || *dst == 0) {
                        *dst = s;
                    } else if (a) {  // premultiplied "over"
                        const uint32_t d = *dst, inv = 255 - a;
                        auto ch = [&](int shift) { return std::min<uint32_t>(255, ((s >> shift) & 0xFF) + (((d >> shift) & 0xFF) * inv + 127) / 255) << shift; };
                        *dst = ch(24) | ch(16) | ch(8) | ch(0);
                    }
                }
            }
        }
        return dirty;
    }

    bool any_visible() const {
        for (const Layer* l : layers)
            if (l->visible) return true;
        return false;
    }
    Layer* keys_layer() const {
        for (auto it = layers.rbegin(); it != layers.rend(); ++it)
            if ((*it)->visible && (*it)->wants_keys()) return *it;
        return nullptr;
    }
    bool any_mouse() const {
        for (const Layer* l : layers)
            if (l->visible && l->wants_mouse()) return true;
        return false;
    }
    Layer* mouse_layer(int x, int y) const {  // the top layer that takes the mouse there
        const POINT p{x, y};
        for (auto it = layers.rbegin(); it != layers.rend(); ++it)
            if ((*it)->visible && (*it)->wants_mouse() && PtInRect(&(*it)->rect, p)) return *it;
        return nullptr;
    }
};

// ---- the presenter: a layered window over the game's window ----
// It covers the game window's client area exactly and lets every click through, except while a layer takes the mouse
// (then clicks on its fully clear pixels still go to the game: that is how layered windows work). Kept in front of the
// game: topmost while a window of the game's process is the front window, else just above the game's window, so other
// programs' windows cover it the way they cover the game. Windows tells this thread when the front window changes
// (SetWinEventHook), and the order is checked again every 0.5 s and by the watchdog.
struct WindowPresenter {
    HWND win = nullptr;
    HDC mem = nullptr;
    HBITMAP bitmap = nullptr;
    HGDIOBJ old = nullptr;
    uint32_t* bits = nullptr;
    int w = 0, h = 0;
    POINT at{};
    bool shown = false, interactive = false, topmost = false;

    bool resize(int nw, int nh) {
        if (nw == w && nh == h && bits) return false;
        if (bitmap) {
            SelectObject(mem, old);
            DeleteObject(bitmap);
            bitmap = nullptr;
            bits = nullptr;
        }
        BITMAPINFO bi{};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = nw;
        bi.bmiHeader.biHeight = -nh;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        void* p = nullptr;
        bitmap = CreateDIBSection(g_screen, &bi, DIB_RGB_COLORS, &p, nullptr, 0);
        if (!bitmap || !p) {
            FK_LOG(fklog::kError, "overlay: CreateDIBSection %dx%d failed (error %lu)", nw, nh, GetLastError());
            bitmap = nullptr;
            w = h = 0;
            return false;
        }
        old = SelectObject(mem, bitmap);
        bits = static_cast<uint32_t*>(p);
        w = nw;
        h = nh;
        std::fill(bits, bits + static_cast<size_t>(w) * h, 0u);
        FK_LOG(fklog::kInfo, "overlay: surface %dx%d", w, h);
        return true;
    }

    // Shows the changed part. moved: the window's place or size changed (then all of it).
    void present(const POINT& origin, const RECT& dirty, bool whole) {
        const bool moved = origin.x != at.x || origin.y != at.y;
        at = origin;
        SIZE size{w, h};
        POINT zero{0, 0};
        BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
        UPDATELAYEREDWINDOWINFO info{};
        info.cbSize = sizeof(info);
        info.hdcDst = g_screen;
        info.pptDst = &at;
        info.psize = &size;
        info.hdcSrc = mem;
        info.pptSrc = &zero;
        info.pblend = &blend;
        info.dwFlags = ULW_ALPHA;
        info.prcDirty = (whole || moved) ? nullptr : &dirty;
        if (!UpdateLayeredWindowIndirect(win, &info)) {
            static uint64_t said = 0;
            const uint64_t now = GetTickCount64();
            if (now - said > 5000) {
                said = now;
                FK_LOG(fklog::kError, "overlay: UpdateLayeredWindowIndirect failed (error %lu; surface %dx%d at %ld,%ld)", GetLastError(), w, h, at.x, at.y);
            }
        }
    }

    void set_interactive(bool mouse, bool keys) {
        const bool want = mouse || keys;
        LONG_PTR ex = GetWindowLongPtrW(win, GWL_EXSTYLE);
        LONG_PTR next = want ? (ex & ~static_cast<LONG_PTR>(WS_EX_TRANSPARENT)) : (ex | WS_EX_TRANSPARENT);
        next = keys ? (next & ~static_cast<LONG_PTR>(WS_EX_NOACTIVATE)) : (next | WS_EX_NOACTIVATE);
        if (next != ex) {
            SetWindowLongPtrW(win, GWL_EXSTYLE, next);
            FK_LOG(fklog::kInfo, "overlay: takes the mouse %s, the keyboard %s", want ? "yes" : "no", keys ? "yes" : "no");
        }
        interactive = want;
    }

    // In front of the game: topmost while the game's process has the front window, else right above the game's window.
    void order(HWND game, bool ours_front, const char* why) {
        if (!shown || !game) return;
        if (ours_front) {
            SetWindowPos(win, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        } else {
            SetWindowPos(win, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            HWND above = GetWindow(game, GW_HWNDPREV);  // the window just above the game's: go under it
            if (above && above != win) SetWindowPos(win, above, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
        if (topmost != ours_front) FK_LOG(fklog::kInfo, "overlay: %s (%s)", ours_front ? "topmost" : "just above the game's window", why);
        topmost = ours_front;
    }

    void show(bool on) {
        if (on == shown) return;
        shown = on;
        ShowWindow(win, on ? SW_SHOWNOACTIVATE : SW_HIDE);
        FK_LOG(fklog::kInfo, "overlay: %s", on ? "shown" : "hidden (nothing to show)");
    }
};

Compositor g_compositor;
WindowPresenter g_presenter;
Layer* g_mouse_capture = nullptr;  // the layer that got the button press: it gets the mouse until the release
Layer* g_mouse_over = nullptr;     // the layer under the pointer, for mouse_left
std::atomic<bool> g_reorder{true}; // the front window changed: put the overlay in order now

LRESULT CALLBACK overlay_proc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_MOUSEACTIVATE:
        return g_compositor.keys_layer() ? MA_ACTIVATE : MA_NOACTIVATE;
    case WM_SETCURSOR:
        if (g_presenter.interactive) {
            SetCursor(g_game_cursor ? g_game_cursor : LoadCursorA(nullptr, IDC_ARROW));
            return TRUE;
        }
        break;
    case WM_SYSKEYDOWN:  // Alt (Right Alt: the pointer for the pinned windows) and Alt+key: never Windows' window menu
    case WM_SYSKEYUP:
    case WM_SYSCHAR:
        if (msg == WM_SYSKEYDOWN && wp == VK_F4) {  // Alt+F4 over FlameKit: the game's own close, never the overlay's
            if (HWND g = game_window()) PostMessageW(g, WM_CLOSE, 0, 0);
            FK_LOG(fklog::kInfo, "overlay: Alt+F4 passed to the game's window");
        }
        return 0;
    case WM_CLOSE:  // only the game closes the overlay (with itself)
        return 0;
    case WM_SYSCOMMAND:
        if ((wp & 0xFFF0) == SC_KEYMENU) return 0;
        break;
    case WM_KEYDOWN:
        if (Layer* l = g_compositor.keys_layer()) {
            FK_LOG(fklog::kDebug, "overlay: key %llu to %s", static_cast<unsigned long long>(wp), l->name());
            l->key(wp);
        }
        return 0;
    case WM_ACTIVATE:
        FK_LOG(fklog::kDebug, "overlay: %s", LOWORD(wp) == WA_INACTIVE ? "lost the front" : "got the front");
        if (LOWORD(wp) == WA_INACTIVE)
            for (Layer* l : g_compositor.layers) l->lost_front();
        return 0;
    case WM_MOUSELEAVE:
        if (g_mouse_over) g_mouse_over->mouse_left();
        g_mouse_over = nullptr;
        return 0;
    case WM_MOUSEMOVE:
    case WM_LBUTTONDOWN:
    case WM_LBUTTONUP:
    case WM_RBUTTONDOWN: {
        const int x = static_cast<short>(LOWORD(lp)), y = static_cast<short>(HIWORD(lp));
        Layer* l = g_mouse_capture ? g_mouse_capture : g_compositor.mouse_layer(x, y);
        if (msg == WM_MOUSEMOVE && l != g_mouse_over) {
            if (g_mouse_over) g_mouse_over->mouse_left();
            g_mouse_over = l;
            TRACKMOUSEEVENT t{sizeof(TRACKMOUSEEVENT), TME_LEAVE, h, 0};
            TrackMouseEvent(&t);
        }
        if (!l) return 0;
        if (msg == WM_LBUTTONDOWN) {
            g_mouse_capture = l;
            SetCapture(h);
            FK_LOG(fklog::kDebug, "overlay: click at %d,%d to %s", x, y, l->name());
        }
        l->mouse(msg, x - l->rect.left, y - l->rect.top);
        if (msg == WM_LBUTTONUP && g_mouse_capture) {
            g_mouse_capture = nullptr;
            ReleaseCapture();
        }
        return 0;
    }
    case WM_MOUSEWHEEL: {  // the position comes in screen coordinates
        POINT pt{static_cast<short>(LOWORD(lp)), static_cast<short>(HIWORD(lp))};
        ScreenToClient(h, &pt);
        if (Layer* l = g_mouse_capture ? g_mouse_capture : g_compositor.mouse_layer(pt.x, pt.y))
            l->wheel(GET_WHEEL_DELTA_WPARAM(wp), pt.x - l->rect.left, pt.y - l->rect.top);
        return 0;
    }
    case WM_CAPTURECHANGED:
        if (g_mouse_capture) {
            g_mouse_capture->mouse(WM_LBUTTONUP, -1, -1);
            g_mouse_capture = nullptr;
        }
        return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

void CALLBACK on_foreground(HWINEVENTHOOK, DWORD, HWND h, LONG, LONG, DWORD, DWORD) {
    g_reorder = true;
    FK_LOG(fklog::kInfo, "windows: front window: %s", window_info(h).c_str());
}

// ---- the watchdog ----
// While a window of the game's process is the front window and the overlay has something to show, the overlay must be
// shown, topmost, above the game's window in Windows' window order, and over the game's client area. Checked 4 times a
// second; every failure is a warning in the log with the window that was in the way, and is repaired at once (and
// checked again). A summary every minute (normal level).
struct Watchdog {
    uint64_t next = 0, summary_at = 0;
    uint64_t checks = 0, failures = 0, repaired = 0;

    static bool above_game(HWND win, HWND game) {  // win comes before game in the window order (top first)
        int steps = 0;
        for (HWND w = GetWindow(win, GW_HWNDNEXT); w && steps < 4096; w = GetWindow(w, GW_HWNDNEXT), ++steps)
            if (w == game) return true;
        return false;
    }

    std::string problem(HWND win, HWND game, const POINT& origin, int gw, int gh) {
        std::string p;
        if (!IsWindowVisible(win)) p += "not shown; ";
        if (!(GetWindowLongPtrW(win, GWL_EXSTYLE) & WS_EX_TOPMOST)) p += "not topmost; ";
        if (!above_game(win, game)) p += "below the game's window; ";
        RECT r{};
        GetWindowRect(win, &r);
        if (r.left != origin.x || r.top != origin.y || r.right - r.left != gw || r.bottom - r.top != gh) {
            char s[160];
            snprintf(s, sizeof s, "at %ld,%ld %ldx%ld instead of %ld,%ld %dx%d; ", r.left, r.top, r.right - r.left, r.bottom - r.top, origin.x,
                     origin.y, gw, gh);
            p += s;
        }
        return p;
    }

    void tick(const Frame& f, bool should_show) {
        if (f.now < next) return;
        next = f.now + 250;
        if (f.now - summary_at >= 60000) {
            if (summary_at) FK_LOG(fklog::kInfo, "watchdog: last minute: %llu checks, %llu failures, %llu repaired", checks, failures, repaired);
            summary_at = f.now;
            checks = failures = repaired = 0;
        }
        if (!should_show || !f.ours_front || !f.game || IsIconic(f.game)) return;
        ++checks;
        const std::string p = problem(g_presenter.win, f.game, f.origin, f.gw, f.gh);
        if (p.empty()) {
            FK_LOG(fklog::kDebug, "watchdog: ok");
            return;
        }
        ++failures;
        POINT mid{f.origin.x + f.gw / 2, f.origin.y + f.gh / 2};
        HWND top = WindowFromPoint(mid);
        FK_LOG(fklog::kWarn, "watchdog: FAILED: overlay %s| front window: %s | top window at the game's centre: %s", p.c_str(),
               window_info(GetForegroundWindow()).c_str(), window_info(top).c_str());
        if (!IsWindowVisible(g_presenter.win)) {
            g_presenter.shown = false;
            g_presenter.show(true);
        }
        g_presenter.order(f.game, true, "watchdog repair");
        const std::string again = problem(g_presenter.win, f.game, f.origin, f.gw, f.gh);
        if (again.empty()) {
            ++repaired;
            FK_LOG(fklog::kWarn, "watchdog: repaired");
        } else {
            FK_LOG(fklog::kWarn, "watchdog: STILL FAILING after the repair: %s", again.c_str());
        }
    }
};

// ---- the UI thread ----
void ui_thread_body() {
    const HINSTANCE inst = GetModuleHandleW(nullptr);
    g_screen = GetDC(nullptr);
    g_presenter.mem = CreateCompatibleDC(g_screen);
    WNDCLASSW wc{};
    wc.lpfnWndProc = overlay_proc;
    wc.hInstance = inst;
    wc.lpszClassName = L"FlameKitOverlay";
    if (!RegisterClassW(&wc)) {
        FK_LOG(fklog::kError, "overlay: RegisterClass failed (error %lu): FlameKit shows nothing", GetLastError());
        return;
    }
    g_overlay = CreateWindowExW(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, wc.lpszClassName,
                                L"FlameKit", WS_POPUP, 0, 0, 16, 16, nullptr, nullptr, inst, nullptr);
    if (!g_overlay) {
        FK_LOG(fklog::kError, "overlay: CreateWindow failed (error %lu): FlameKit shows nothing", GetLastError());
        return;
    }
    g_presenter.win = g_overlay;
    const HWINEVENTHOOK hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr, on_foreground, 0, 0, WINEVENT_OUTOFCONTEXT);
    FK_LOG(hook ? fklog::kInfo : fklog::kError, "overlay: window %p created; front window notifications %s", static_cast<void*>(g_overlay),
           hook ? "on" : "FAILED (the order is still checked every 0.5 s)");

    MinimapLayer minimap;
    HudLayer hud;
    WindowLayer window;
    BackdropLayer backdrop;
    backdrop.window = &window;
    PartyLayer party;
    MessagesLayer messages;
    g_compositor.layers = {&hud, &backdrop, &minimap, &party, &messages, &window};  // bottom first (the minimap and the pinned windows over the backdrop: they take the mouse)
    Watchdog watchdog;
    HWND game = nullptr;
    uint64_t looked = 0, ordered = 0, stats_at = 0;
    bool said_game = false, keys_had = false, f12_was = false;
    POINT pointer_at{-1, -1};  // where the pointer was when it was last put away (game window coordinates; -1: never)
    int restore_rounds = 0;    // rounds left to put the pointer back there
    uint64_t frames = 0, frame_us = 0, frame_max_us = 0;

    for (;;) {
        MSG msg;
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        LARGE_INTEGER t0, t1, freq;
        QueryPerformanceCounter(&t0);
        Frame f;
        f.now = GetTickCount64();
        if ((!game || !IsWindow(game)) && f.now - looked > 1000) {
            looked = f.now;
            game = game_window();
            if (game) {
                RECT r{};
                GetClientRect(game, &r);
                const LONG_PTR style = GetWindowLongPtrW(game, GWL_STYLE), ex = GetWindowLongPtrW(game, GWL_EXSTYLE);
                FK_LOG(fklog::kInfo, "overlay: game window: %s, %ldx%ld, style %08llx ex %08llx (%s)", window_info(game).c_str(), r.right, r.bottom,
                       static_cast<unsigned long long>(style), static_cast<unsigned long long>(ex),
                       (style & WS_CAPTION) ? "a window with a frame" : "borderless");
                said_game = true;
            } else if (!said_game) {
                FK_LOG(fklog::kDebug, "overlay: no game window yet");
            }
        }
        f.game = game;
        if (game) {
            RECT client{};
            GetClientRect(game, &client);
            ClientToScreen(game, &f.origin);
            f.gw = client.right;
            f.gh = client.bottom;
        }
        const HWND front = GetForegroundWindow();
        DWORD front_pid = 0;
        GetWindowThreadProcessId(front, &front_pid);
        f.game_front = game && front == game;
        f.ours_front = front_pid == GetCurrentProcessId();
        f.in_world = f.now - g_seen.load() < 1500;

        // Ctrl+Shift+F12, while the game's process is in front: the next debug level
        const bool f12 = f.ours_front && (GetAsyncKeyState(VK_F12) & 0x8000) && (GetAsyncKeyState(VK_CONTROL) & 0x8000) &&
                         (GetAsyncKeyState(VK_SHIFT) & 0x8000);
        if (f12 && !f12_was) fklog::set_mode((fklog::g_mode.load() + 1) % 3);
        f12_was = f12;

        // The pointer key (setting pointer_key: Right Alt, Right Ctrl or Caps Lock) held while the game's process is in
        // front: the pointer is out for the pinned windows
        const int pointer_vk = settings().pointer_vk;
        const bool hold = f.ours_front && f.in_world && (GetAsyncKeyState(pointer_vk) & 0x8000) != 0;
        if (hold != g_pointer_hold) {
            g_pointer_hold = hold;
            FK_LOG(fklog::kInfo, "pointer: the pointer key (vk %02x) %s", pointer_vk, hold ? "held: the pinned windows take the mouse" : "let go");
        }
        // The pointer comes back where it was the last time the pointer was out (Right Alt or FlameKit's window), so it
        // does not jump around; the first time, in the middle of the game window. It is put there at once and on the
        // next 4 rounds (60 ms), because the game may still move it while it lets go of the mouse.
        {
            const bool mode = hold || window.open;
            if (mode && !g_pointer_mode) {
                restore_rounds = 5;
            } else if (!mode && g_pointer_mode) {
                POINT p{};
                if (GetCursorPos(&p) && f.gw > 0) {
                    pointer_at = {p.x - f.origin.x, p.y - f.origin.y};
                    FK_LOG(fklog::kDebug, "pointer: left at %ld,%ld in the game window", pointer_at.x, pointer_at.y);
                }
            }
            g_pointer_mode = mode;
            if (restore_rounds > 0 && g_pointer_mode && f.gw > 0 && f.gh > 0) {
                --restore_rounds;
                const LONG x = pointer_at.x >= 0 ? std::clamp<LONG>(pointer_at.x, 0, f.gw - 1) : f.gw / 2;
                const LONG y = pointer_at.y >= 0 ? std::clamp<LONG>(pointer_at.y, 0, f.gh - 1) : f.gh / 2;
                SetCursorPos(f.origin.x + x, f.origin.y + y);
                if (restore_rounds == 4) FK_LOG(fklog::kDebug, "pointer: put back at %ld,%ld in the game window", x, y);
            } else if (!g_pointer_mode) {
                restore_rounds = 0;
            }
        }

        // One of the game's menus is open (bag, map, skills, ...): the game's own window is in front and shows the
        // pointer (a pointer "showing" without a picture is hidden: the game hides it that way too). FlameKit's own
        // pointer is not a menu: then FlameKit's overlay is in front.
        if (f.game_front && !g_pointer_mode) {
            CURSORINFO ci{};
            ci.cbSize = sizeof(ci);
            f.in_menu = GetCursorInfo(&ci) && (ci.flags & CURSOR_SHOWING) != 0 && ci.hCursor != nullptr;
        }

        if (f.game_front) look_for_game_cursor();  // the game's pointer, while the game shows it in its menus
        for (Layer* l : g_compositor.layers) l->update(f);

        // the keyboard and the mouse: to the overlay while a layer takes them
        Layer* keys = g_compositor.keys_layer();
        g_presenter.set_interactive(g_compositor.any_mouse(), keys != nullptr);
        if (keys && !keys_had) {
            g_presenter.show(true);
            g_presenter.order(game, true, "a layer takes the keyboard");
            SetForegroundWindow(g_overlay);
            SetFocus(g_overlay);
            FK_LOG(fklog::kInfo, "overlay: took the front for %s: %s", keys->name(), GetForegroundWindow() == g_overlay ? "ok" : "REFUSED by Windows");
        } else if (!keys && keys_had) {
            if (game && IsWindow(game)) SetForegroundWindow(game);
            FK_LOG(fklog::kInfo, "overlay: gave the front back to the game");
        }
        keys_had = keys != nullptr;

        const bool should_show = game && f.gw > 0 && f.gh > 0 && !IsIconic(game) && g_compositor.any_visible();
        if (should_show) {
            const bool fresh = g_presenter.resize(f.gw, f.gh);
            if (g_presenter.bits) {
                const bool all = fresh || !g_presenter.shown;  // after being hidden the surface is out of date: all of it again
                const RECT dirty = g_compositor.compose(g_presenter.bits, g_presenter.w, g_presenter.h, all);
                const bool moved = f.origin.x != g_presenter.at.x || f.origin.y != g_presenter.at.y;
                if (!IsRectEmpty(&dirty) || moved || all) g_presenter.present(f.origin, dirty, all);
            }
            if (!g_presenter.shown) {
                g_presenter.show(true);
                g_reorder = true;
            }
        } else {
            g_compositor.compose(g_presenter.bits ? g_presenter.bits : nullptr, 0, 0, false);  // keeps the layers' "was" in step
            g_presenter.show(false);
        }
        if (g_presenter.shown && (g_reorder.exchange(false) || f.now - ordered > 500)) {
            ordered = f.now;
            g_presenter.order(game, f.ours_front, "front window or regular check");
        }
        watchdog.tick(f, should_show);

        QueryPerformanceCounter(&t1);
        QueryPerformanceFrequency(&freq);
        const uint64_t us = static_cast<uint64_t>((t1.QuadPart - t0.QuadPart) * 1000000 / freq.QuadPart);
        ++frames;
        frame_us += us;
        frame_max_us = std::max(frame_max_us, us);
        if (f.now - stats_at >= 10000) {
            if (stats_at)
                FK_LOG(fklog::kDebug, "overlay: %llu rounds in %.1f s, %.2f ms each on average, %.2f ms the longest; front %s; shown %d, topmost %d, "
                       "takes mouse %d", frames, (f.now - stats_at) / 1000.0, frames ? frame_us / 1000.0 / frames : 0.0, frame_max_us / 1000.0,
                       f.game_front ? "the game" : f.ours_front ? "FlameKit" : "another program", g_presenter.shown, g_presenter.topmost,
                       g_presenter.interactive);
            stats_at = f.now;
            frames = frame_us = frame_max_us = 0;
        }
        Sleep(15);
    }
}
void ui_thread() { fklog::guarded("ui", ui_thread_body); }


// ---- the monitor: what goes on around FlameKit, into FlameKit's log ----
// Once at the start: this DLL's build, the versions, Windows, the computer, the screens. Then: the debug level from
// debug.txt every 2 s; EMF's log (emf\emf_core.log, which also has the Lua part's lines: "[flamekit] ...") copied in
// line by line every second; the game process's memory, handles and CPU every minute (every 10 s at full).
std::string read_text(const std::wstring& path, size_t max = 4096) {
    std::string out;
    if (FILE* fp = _wfsopen(path.c_str(), L"rb", _SH_DENYNO)) {
        out.resize(max);
        out.resize(fread(out.data(), 1, max, fp));
        fclose(fp);
    }
    return out;
}

std::string version_in(const std::wstring& mod_json) {
    const std::string text = read_text(mod_json, 16384);
    const size_t at = text.find("\"version\"");
    if (at == std::string::npos) return "?";
    const size_t q1 = text.find('"', text.find(':', at) + 1), q2 = q1 == std::string::npos ? q1 : text.find('"', q1 + 1);
    return q2 == std::string::npos ? "?" : text.substr(q1 + 1, q2 - q1 - 1);
}

BOOL CALLBACK log_monitor(HMONITOR m, HDC, LPRECT, LPARAM) {
    MONITORINFOEXW mi{};
    mi.cbSize = sizeof(mi);
    if (GetMonitorInfoW(m, &mi))
        FK_LOG(fklog::kInfo, "system: screen %ls: %ldx%ld at %ld,%ld%s", mi.szDevice, mi.rcMonitor.right - mi.rcMonitor.left,
               mi.rcMonitor.bottom - mi.rcMonitor.top, mi.rcMonitor.left, mi.rcMonitor.top, (mi.dwFlags & MONITORINFOF_PRIMARY) ? " (main)" : "");
    return TRUE;
}

void log_start_info() {
    FK_LOG(fklog::kInfo, "start: FlameKit Native %s (FlameKit Lua part %s), built %s %s with MSVC %d; debug level %s; update channel %s",
           version_in(g_game_dir + L"emf\\mods\\flamekit_native\\mod.json").c_str(), version_in(g_flamekit_dir + L"mod.json").c_str(), __DATE__,
           __TIME__, _MSC_FULL_VER, fklog::mode_name(fklog::g_mode.load()),
           read_text(g_flamekit_dir + L"update_channel.txt", 16).rfind("test", 0) == 0 ? "test (dist-test)" : "players (dist)");
    using RtlGetVersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
    OSVERSIONINFOW os{};
    os.dwOSVersionInfoSize = sizeof(os);
    if (auto fn = reinterpret_cast<RtlGetVersionFn>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"))) fn(&os);
    SYSTEM_INFO si{};
    GetNativeSystemInfo(&si);
    MEMORYSTATUSEX mem{};
    mem.dwLength = sizeof(mem);
    GlobalMemoryStatusEx(&mem);
    FK_LOG(fklog::kInfo, "system: Windows %lu.%lu build %lu, %lu processors, %.1f GB memory (%.1f GB free), screen DPI %d",
           os.dwMajorVersion, os.dwMinorVersion, os.dwBuildNumber, si.dwNumberOfProcessors, mem.ullTotalPhys / 1073741824.0,
           mem.ullAvailPhys / 1073741824.0, GetDeviceCaps(g_screen ? g_screen : GetDC(nullptr), LOGPIXELSX));
    EnumDisplayMonitors(nullptr, nullptr, log_monitor, 0);
    wchar_t exe[MAX_PATH];
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    WIN32_FILE_ATTRIBUTE_DATA info{};
    GetFileAttributesExW(exe, GetFileExInfoStandard, &info);
    SYSTEMTIME t{};
    FileTimeToSystemTime(&info.ftLastWriteTime, &t);
    FK_LOG(fklog::kInfo, "system: game program %ls, %llu bytes, changed %04u-%02u-%02u", exe,
           (static_cast<unsigned long long>(info.nFileSizeHigh) << 32) | info.nFileSizeLow, t.wYear, t.wMonth, t.wDay);
}

void monitor_body() {
    log_start_info();
    const std::wstring emf_log = g_game_dir + L"emf\\emf_core.log";
    uint64_t emf_pos = 0, next_mode = 0, next_tail = 0, next_stats = 0, cpu_was = 0, cpu_at = 0;
    std::string partial;
    for (;;) {
        const uint64_t now = GetTickCount64();
        if (now >= next_mode) {
            next_mode = now + 2000;
            fklog::read_mode();
        }
        if (now >= next_tail) {  // EMF's log, the new lines
            next_tail = now + 1000;
            HANDLE h = CreateFileW(emf_log.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, 0, nullptr);
            if (h != INVALID_HANDLE_VALUE) {
                LARGE_INTEGER size{};
                GetFileSizeEx(h, &size);
                if (static_cast<uint64_t>(size.QuadPart) < emf_pos) {  // a new file: from its start
                    emf_pos = 0;
                    partial.clear();
                }
                if (static_cast<uint64_t>(size.QuadPart) > emf_pos) {
                    LARGE_INTEGER at{};
                    at.QuadPart = static_cast<LONGLONG>(emf_pos);
                    SetFilePointerEx(h, at, nullptr, FILE_BEGIN);
                    std::string chunk(static_cast<size_t>(std::min<uint64_t>(size.QuadPart - emf_pos, 1 << 20)), '\0');
                    DWORD got = 0;
                    ReadFile(h, chunk.data(), static_cast<DWORD>(chunk.size()), &got, nullptr);
                    chunk.resize(got);
                    emf_pos += got;
                    partial += chunk;
                    size_t start = 0;
                    for (size_t nl; (nl = partial.find('\n', start)) != std::string::npos; start = nl + 1) {
                        std::string line = partial.substr(start, nl - start);
                        while (!line.empty() && line.back() == '\r') line.pop_back();
                        if (line.empty()) continue;
                        const bool lua = line.find("[flamekit]") != std::string::npos;
                        const bool bad = line.find("error") != std::string::npos || line.find("ERROR") != std::string::npos ||
                                         line.find(" failed") != std::string::npos || line.find("FAILED") != std::string::npos;
                        FK_LOG(bad ? fklog::kWarn : fklog::kInfo, "%s %s", lua ? "lua|" : "emf|", line.c_str());
                    }
                    partial.erase(0, start);
                }
                CloseHandle(h);
            }
        }
        if (now >= next_stats) {  // the game process: memory, handles, CPU
            next_stats = now + (fklog::g_mode.load() == fklog::kFull ? 10000 : 60000);
            PROCESS_MEMORY_COUNTERS_EX pm{};
            pm.cb = sizeof(pm);
            GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&pm), sizeof(pm));
            DWORD handles = 0;
            GetProcessHandleCount(GetCurrentProcess(), &handles);
            FILETIME c, e, k, u;
            GetProcessTimes(GetCurrentProcess(), &c, &e, &k, &u);
            const uint64_t cpu = ((static_cast<uint64_t>(k.dwHighDateTime) << 32 | k.dwLowDateTime) + (static_cast<uint64_t>(u.dwHighDateTime) << 32 | u.dwLowDateTime)) / 10000;  // ms
            SYSTEM_INFO si{};
            GetNativeSystemInfo(&si);
            const double load = cpu_at && now > cpu_at ? 100.0 * (cpu - cpu_was) / (now - cpu_at) / si.dwNumberOfProcessors : 0.0;
            FK_LOG(fklog::kInfo, "process: memory %.0f MB in use (%.0f MB private), %lu handles, %lu GDI and %lu USER objects, CPU %.1f%% of the computer",
                   pm.WorkingSetSize / 1048576.0, pm.PrivateUsage / 1048576.0, handles, GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS),
                   GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS), load);
            cpu_was = cpu;
            cpu_at = now;
        }
        Sleep(500);
    }
}
void monitor_thread() { fklog::guarded("monitor", monitor_body); }

void updater_body() {
    web_update::Updater updater;
    updater.mods = g_game_dir + L"emf\\mods\\";
    updater.log = [](int level, const char* text) {
        FK_LOG(level == 2 ? fklog::kWarn : level == 1 ? fklog::kDebug : fklog::kInfo, "%s", text);
    };
    updater.run();
}
void updater_thread() { fklog::guarded("updater", updater_body); }
}  // namespace

extern "C" __declspec(dllexport) bool emf_mod_load(const EmfApi* api) {
    g_game_dir = game_dir_of_process();
    g_flamekit_dir = g_game_dir + L"emf\\mods\\flamekit\\";
    fklog::open(g_flamekit_dir);  // FlameKit's own log (fk_log.hpp): first, so everything after is in it
    // a new version's Lua part, held since the last session: in place now, so the Lua part and this DLL switch together
    web_update::install_pending(g_game_dir + L"emf\\mods\\", [](const char* text) {
        FK_LOG(std::strstr(text, "failed") || std::strstr(text, "does not match") ? fklog::kWarn : fklog::kInfo, "%s", text);
    });
    if (!emf::init(api)) return false;
    if (!emf::has_v13()) {
        EMF_LOG(kMod, "needs EMF API v13 or newer");
        FK_LOG(fklog::kError, "start: needs EMF API v13 or newer: FlameKit Native does not run");
        return false;
    }
    read_settings();
    emf::on_setting_changed(kKit, [](emf::World, const std::string&) { read_settings(); });
    emf::on_tick(on_world_tick);
    std::thread(updater_thread).detach();  // FlameKit's own updates, straight from its repository (web_update.hpp)
    // pings (and, to learn from, the places the game announces) arrive as events of the client world
    const bool events = emf::add_program("flamekit_native_events", EMF_WORLD_CLIENT, {"UiPingEvent", "UiCurrentLocationEvent"}, {},
                                         [](void* ctx) {
        emf::read<gen::UiPingEvent>(ctx, [](const gen::UiPingEvent& e) {
            static int said = 0;
            const float x = static_cast<float>(meters(e.position.x)), z = static_cast<float>(meters(e.position.z));
            if (said++ < 10) FK_LOG(fklog::kInfo, "events: ping from entity %u at x %.1f z %.1f", e.senderEntityId.id, x, z);
            std::lock_guard<std::mutex> l(g_shared.lock);
            if (g_shared.pings.size() < 32) g_shared.pings.push_back({x, z, GetTickCount64()});
        });
        emf::read<gen::UiCurrentLocationEvent>(ctx, [](const gen::UiCurrentLocationEvent& e) {
            static int said = 0;
            if (said++ < 40)
                FK_LOG(fklog::kInfo, "events: location event: id %08x, entity %u, new %d, player at x %.0f z %.0f", static_cast<unsigned>(e.location.value),
                        e.entityId.id, e.isNew ? 1 : 0, g_x.load(), g_z.load());
            std::lock_guard<std::mutex> l(g_shared.lock);
            if (g_shared.announced.size() >= 32) g_shared.announced.erase(g_shared.announced.begin());
            g_shared.announced.push_back(e.location.value);
        });
    });
    if (!events) FK_LOG(fklog::kWarn, "events: the events program was refused: no pings on the minimap");
    std::thread(ui_thread).detach();
    std::thread(monitor_thread).detach();
    FK_LOG(fklog::kInfo, "start: loaded (the native part of FlameKit)");
    return true;
}
