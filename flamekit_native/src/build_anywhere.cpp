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
// lets quadruple it"): the game's program upgrade_building_range (both worlds) writes an altar's TriggerShape (the
// build area's half widths, 20 or 80 m here) from its level; a hook after it multiplies rangeX/Y/Z by kAltarFactor,
// remembering what it wrote so a value is never multiplied twice. On for everyone while testing (local server only).
//
// Console: fkbuild stats | free on|off | altar on|off (debug master switches; both on at start).
// (0.15.416) an altar's change is logged once per altar and world (the server rewrites the range every step).
#include <windows.h>

#include <atomic>
#include <cmath>
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
constexpr uint32_t kOutsideZone = 0x8 | 0x2;  // bit 3 "needs a flame altar", bit 1 "needs building area"
constexpr float kAltarFactor = 4.0f;

struct ProgramContext {  // re_custom_programs.md 6: what an update function receives
    uint8_t* job;
    uint32_t entityIndex;
    uint32_t pad;
};
using CurrentEntityIdFn = uint32_t* (*)(ProgramContext*, uint32_t*);
CurrentEntityIdFn g_current = nullptr;

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

// what this hook last wrote per world kind and entity: an altar's range is multiplied only when the game wrote a new one
std::mutex g_altar_mx;
std::unordered_map<uint64_t, float> g_altar_written;

void altar_post(void* raw, void*) {
    if (!g_altar_on.load() || !g_current) return;
    auto* ctx = static_cast<ProgramContext*>(raw);
    if (!ctx || !ctx->job) return;
    const uint8_t* storage = *reinterpret_cast<uint8_t* const*>(ctx->job);
    if (!storage) return;
    const uint8_t kind = storage[8];  // 0 the server world
    emf::World w = kind == 0 ? emf::server_world() : emf::client_world();
    if (!w) return;
    const uint32_t n = ctx->entityIndex;
    if (n == 0 || n > 4096) return;
    for (uint32_t i = 1; i <= n; ++i) {
        ProgramContext c{ctx->job, i, 0};
        uint32_t buf[4] = {0, 0, 0, 0};
        const uint32_t* idp = g_current(&c, buf);
        if (!idp || !*idp) continue;
        auto* t = w.get<gen::ecs::TriggerShape>(*idp);
        if (!t || !(t->rangeX > 0.0f)) continue;
        const uint64_t key = (uint64_t(kind) << 32) | *idp;
        std::lock_guard<std::mutex> lk(g_altar_mx);
        auto it = g_altar_written.find(key);
        if (it != g_altar_written.end() && std::fabs(it->second - t->rangeX) < 0.001f) continue;  // ours already
        const float x0 = t->rangeX, z0 = t->rangeZ;
        t->rangeX *= kAltarFactor;
        t->rangeY *= kAltarFactor;
        t->rangeZ *= kAltarFactor;
        const bool first = g_altar_written.find(key) == g_altar_written.end();
        g_altar_written[key] = t->rangeX;
        g_altars.fetch_add(1);
        // (0.15.416) the game writes the range again every step on the server (0.15.415: ~4,500 log lines a second):
        // logged only the first time per altar and world
        if (first) EMF_LOG(kMod, "bigger altar areas (%s world): altar %u from %.0f x %.0f to %.0f x %.0f m (half widths)",
                kind == 0 ? "server" : "client", *idp, x0, z0, t->rangeX, t->rangeZ);
    }
}
}  // namespace

// called by flamekit_native's emf_mod_load in every process (a dedicated server, a player's game)
bool fk_build_anywhere_load(bool dedicated) {
    auto* a = emf::api();
    if (!a || !a->hook_program) {
        EMF_LOG(kMod, "free build: EMF has no hook_program: off");
        return false;
    }
    g_current = emf::resolve<CurrentEntityIdFn>("CurrentEntityId");
    bool c = false;
    if (!dedicated) c = a->hook_program("client_cursor", nullptr, client_post, nullptr);
    const bool s = a->hook_program("server_cursor_no_prediction", nullptr, server_post, nullptr);
    const bool al = g_current && a->hook_program("upgrade_building_range", nullptr, altar_post, nullptr);
    EMF_LOG(kMod, "free build: hook after client_cursor %s, after server_cursor_no_prediction %s; bigger altar areas (x%.0f, test): hook after upgrade_building_range %s",
            dedicated ? "(not here)" : (c ? "installed" : "NOT installed"), s ? "installed" : "NOT installed", kAltarFactor,
            al ? "installed" : "NOT installed");
    emf::on_tick([](emf::World w) {  // the lists of players, every 60 steps of each world
        static uint32_t steps_server = 0, steps_client = 0;
        if (w.is_server()) {
            if (steps_server++ % 60 == 0) read_list(L"free_build_server.txt", g_free_server, "server");
        } else if (w.is_client()) {
            if (steps_client++ % 60 == 0) read_list(L"free_build_client.txt", g_free_client, "this game");
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
        EMF_REPLY("free build %s (server list %zu, this game %zu; cleared: server %llu, this game %llu); bigger altar areas %s (%llu altar(s) made bigger)",
                  g_free_on.load() ? "on" : "off", ns, nc, (unsigned long long)g_server_cleared.load(),
                  (unsigned long long)g_client_cleared.load(), g_altar_on.load() ? "on" : "off", (unsigned long long)g_altars.load());
    });
    return c || s;
}
