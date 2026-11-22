// build_anywhere.cpp (0.15.413, owner 2026-11-21 18:12 "lets try to change the may I build here check", 18:19 "yes" to
// the test): the build hammer's "Needs a Flame Altar nearby".
//
// Learned (0.15.412 log, 18:16-18:18 at the altar 6298.8 5187.2, range 80): bit 3 (0x8) of the cursor's flag words is
// on exactly while the player is outside every altar's area: ClientCursor.primaryFlags and .secondaryFlags in the
// player's own game, ServerCursor.primaryFlags on the server. The game's cursor programs work them out each step:
// client_cursor (the player's game) and server_cursor_no_prediction (the server).
// Test: a hook after each of those programs (EMF hook_program, post) switches bit 3 off again in the players' cursors,
// so the cursor's check says "inside a build zone" everywhere. OPEN: whether placing then works (the building programs
// may check the zone again on the server).
// Console: fkbuild on|off|stats (on at start, debug).
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

#include "emf/generated/components.hpp"
#include "emf/emf.hpp"

namespace gen = emf::gen;

namespace {
constexpr const char* kMod = "flamekit build";
constexpr uint32_t kOutsideZone = 0x8;  // bit 3

std::atomic<bool> g_on{true};
std::atomic<uint64_t> g_client_calls{0}, g_server_calls{0}, g_client_cleared{0}, g_server_cleared{0}, g_client_missing{0};
std::atomic<int> g_said{0};

void client_post(void*, void*) {
    g_client_calls.fetch_add(1);
    if (!g_on.load()) return;
    const uint32_t me = emf::local_player();
    if (!me) return;
    emf::World w = emf::client_world();
    if (!w) return;
    auto* c = w.get<gen::ecs::ClientCursor>(me);
    if (!c) { g_client_missing.fetch_add(1); return; }
    if ((c->primaryFlags | c->secondaryFlags) & kOutsideZone) {
        c->primaryFlags &= ~kOutsideZone;
        c->secondaryFlags &= ~kOutsideZone;
        if (g_client_cleared.fetch_add(1) == 0 || g_said.fetch_add(1) < 10)
            EMF_LOG(kMod, "client: cursor of %u: \"outside every build zone\" switched off", me);
    }
}

void server_post(void*, void*) {
    g_server_calls.fetch_add(1);
    if (!g_on.load()) return;
    emf::World w = emf::server_world();
    if (!w) return;
    for (uint32_t id = 1; id <= 64; ++id) {  // players are entities 1..; the first 64 are enough for a test
        auto* c = w.get<gen::ecs::ServerCursor>(id);
        if (!c) continue;
        if ((c->primaryFlags | c->secondaryFlags) & kOutsideZone) {
            c->primaryFlags &= ~kOutsideZone;
            c->secondaryFlags &= ~kOutsideZone;
            if (g_server_cleared.fetch_add(1) == 0 || g_said.fetch_add(1) < 10)
                EMF_LOG(kMod, "server: cursor of %u: \"outside every build zone\" switched off", id);
        }
    }
}
}  // namespace

// called by flamekit_native's emf_mod_load in every process (a dedicated server, a player's game)
bool fk_build_anywhere_load(bool dedicated) {
    auto* a = emf::api();
    if (!a || !a->hook_program) {
        EMF_LOG(kMod, "build anywhere: EMF has no hook_program: off");
        return false;
    }
    bool c = false, s = false;
    if (!dedicated) c = a->hook_program("client_cursor", nullptr, client_post, nullptr);
    s = a->hook_program("server_cursor_no_prediction", nullptr, server_post, nullptr);
    EMF_LOG(kMod, "build anywhere (test): hook after client_cursor %s, after server_cursor_no_prediction %s",
            dedicated ? "(not here)" : (c ? "installed" : "NOT installed"), s ? "installed" : "NOT installed");
    emf::add_command("fkbuild", " on|off|stats: build anywhere test (the cursor's \"outside every build zone\" bit)",
                     [](emf::World, const std::vector<std::string>& args) {
        if (!args.empty() && args[0] == "on") g_on = true;
        if (!args.empty() && args[0] == "off") g_on = false;
        EMF_REPLY("build anywhere %s: client %llu call(s), %llu cleared, %llu without a cursor; server %llu call(s), %llu cleared",
                  g_on.load() ? "on" : "off", (unsigned long long)g_client_calls.load(), (unsigned long long)g_client_cleared.load(),
                  (unsigned long long)g_client_missing.load(), (unsigned long long)g_server_calls.load(),
                  (unsigned long long)g_server_cleared.load());
    });
    return c || s;
}
