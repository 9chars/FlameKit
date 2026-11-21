// loot_news.cpp (0.15.399, owner 2026-11-21 15:04 "I say implement the DLL fix for this. the constant scanning is just
// not a good solution"; 15:05 "eliminate any scanning for loot drops, monster body loot, chopping or axing... replace
// all that scanning with the DLL"): tells FlameKit's Lua part about each new loose item and each new container the
// moment the game makes it, on the server world, so the Lua part never walks the world's entities for loot.
//
// How: the game runs an init program on every entity it creates (flag 0x8, once per batch of new entities):
//   pickup_item_setup     (writes PickupItem, DestroyOnLoot)  every new loose item on the ground (trees, rocks, monsters)
//   inventory_setup_init  (reads Inventory, writes InventorySetup)  every new container (monster loot piles)
// A hook after each (EMF hook_program) reads that batch's entity ids (the game's own CurrentEntityId, resolved by EMF,
// for 1 .. the job's entity index, which the game's loop leaves at the batch's count) into a list. Only the server
// world's batches count (the job's storage kind 0).
// To the Lua part: loot_news.txt beside FlameKit's Lua part (emf\mods\flamekit), rewritten (a temporary file moved
// over it) after each server step that brought news: the newest kMostKept entries, one a line "<number> <p|c> <entity> <tick>"
// (p a loose item, c a container; tick: the server step that made it), the numbers counting up from 1 since this start. core/loot_news.lua reads it only
// while it waits for a drop or a loot pile (a few seconds after a kill or a chop), and takes the lines it has not seen.
// (15:15, first try: the events TestEvent1/2 to Lua's emf.on_event: EMF delivers no 4-byte event to Lua: "the queue
// layout of 4-byte events is not known yet")
// Debug: the first 20 ids of each kind are logged; "fkloot.stats" in the console gives the counts.
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <mutex>
#include <string>
#include <vector>

#include "emf/generated/components.hpp"
#include "emf/emf.hpp"

namespace {
constexpr const char* kMod = "flamekit loot";

struct ProgramContext {  // re_custom_programs.md 6: what an update function receives
    uint8_t* job;
    uint32_t entityIndex;
    uint32_t pad;
};
using CurrentEntityIdFn = uint32_t* (*)(ProgramContext*, uint32_t*);
CurrentEntityIdFn g_current = nullptr;

std::mutex g_mx;
std::vector<uint32_t> g_pickups, g_containers;
std::atomic<uint64_t> g_n_pickups{0}, g_n_containers{0}, g_n_sent{0}, g_n_dropped{0}, g_n_other_world{0}, g_n_writes{0};
struct Entry { uint64_t n; char kind; uint32_t id; uint64_t tick; };
std::deque<Entry> g_kept;  // the newest kMostKept, written to loot_news.txt (only the server step's thread)
uint64_t g_counter = 0;
constexpr size_t kMostKept = 512;

// loot_news.txt beside FlameKit's Lua part: <this DLL's folder>\..\flamekit\loot_news.txt
std::wstring news_file(const wchar_t* name) {
    HMODULE me = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&news_file), &me);
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(me, path, MAX_PATH);
    std::wstring s(path);
    s = s.substr(0, s.find_last_of(L"\\/"));  // ...\mods\flamekit_native
    s = s.substr(0, s.find_last_of(L"\\/"));  // ...\mods
    return s + L"\\flamekit\\" + name;
}

bool write_news() {
    static const std::wstring file = news_file(L"loot_news.txt"), tmp = news_file(L"loot_news.tmp");
    std::string out;
    out.reserve(g_kept.size() * 16);
    char line[48];
    for (const Entry& e : g_kept) {
        std::snprintf(line, sizeof line, "%llu %c %u %llu\n", (unsigned long long)e.n, e.kind, e.id, (unsigned long long)e.tick);
        out += line;
    }
    if (FILE* f = _wfopen(tmp.c_str(), L"wb")) {
        std::fwrite(out.data(), 1, out.size(), f);
        std::fclose(f);
        if (MoveFileExW(tmp.c_str(), file.c_str(), MOVEFILE_REPLACE_EXISTING)) { g_n_writes.fetch_add(1); return true; }
    }
    return false;  // (the Lua part may have it open this moment) written again after the next step
}
bool g_unwritten = false;
std::atomic<int> g_said_pickups{0}, g_said_containers{0};
constexpr size_t kMostWaiting = 4096;  // a bigger pile (nobody's Lua reading) is not kept

// The batch's entity ids, when it is the server world's (job+0 = the storage, storage+8 = its kind: 0 server)
void read_batch(void* raw, std::vector<uint32_t>& out, std::atomic<uint64_t>& count, std::atomic<int>& said, const char* what) {
    auto* ctx = static_cast<ProgramContext*>(raw);
    if (!ctx || !ctx->job || !g_current) return;
    const uint8_t* storage = *reinterpret_cast<uint8_t* const*>(ctx->job);
    if (!storage || storage[8] != 0) { g_n_other_world.fetch_add(ctx->entityIndex); return; }
    const uint32_t n = ctx->entityIndex;
    if (n == 0 || n > 100000) return;
    std::vector<uint32_t> ids;
    ids.reserve(n);
    for (uint32_t i = 1; i <= n; ++i) {
        ProgramContext c{ctx->job, i, 0};
        uint32_t buf[4] = {0, 0, 0, 0};
        const uint32_t* id = g_current(&c, buf);
        if (id && *id) ids.push_back(*id);
    }
    count.fetch_add(ids.size());
    for (uint32_t id : ids)
        if (said.fetch_add(1) < 20) EMF_LOG(kMod, "new %s: entity %u", what, id);
    std::lock_guard<std::mutex> lk(g_mx);
    if (out.size() + ids.size() > kMostWaiting) { g_n_dropped.fetch_add(ids.size()); return; }
    out.insert(out.end(), ids.begin(), ids.end());
}

void pickups_post(void* ctx, void*) { read_batch(ctx, g_pickups, g_n_pickups, g_said_pickups, "loose item"); }
void containers_post(void* ctx, void*) { read_batch(ctx, g_containers, g_n_containers, g_said_containers, "container"); }
}  // namespace

// called by flamekit_native's emf_mod_load once EMF is set up (emf::init), in every process (a dedicated server, a
// game that hosts: the server world's programs run there)
bool fk_loot_news_load() {
    g_current = emf::resolve<CurrentEntityIdFn>("CurrentEntityId");
    if (!g_current) {
        EMF_LOG(kMod, "CurrentEntityId is not resolved on this game build: no loot news (the Lua part gets none)");
        return false;
    }
    const bool a = emf::api()->hook_program && emf::api()->hook_program("pickup_item_setup", nullptr, pickups_post, nullptr);
    const bool b = emf::api()->hook_program && emf::api()->hook_program("inventory_setup_init", nullptr, containers_post, nullptr);
    emf::on_tick([](emf::World w) {  // after each server step: the news of that step into loot_news.txt
        if (!w.is_server()) return;
        std::vector<uint32_t> p, c;
        {
            std::lock_guard<std::mutex> lk(g_mx);
            if (g_pickups.empty() && g_containers.empty() && !g_unwritten) return;
            p.swap(g_pickups);
            c.swap(g_containers);
        }
        const uint64_t tick = w.tick();
        for (uint32_t id : p) g_kept.push_back({++g_counter, 'p', id, tick});
        for (uint32_t id : c) g_kept.push_back({++g_counter, 'c', id, tick});
        while (g_kept.size() > kMostKept) g_kept.pop_front();
        g_n_sent.fetch_add(p.size() + c.size());
        g_unwritten = !write_news();
    });
    const bool prog = true;
    EMF_LOG(kMod, "loot news: hook after pickup_item_setup %s, after inventory_setup_init %s, loot_news.txt writer %s",
            a ? "installed" : "NOT installed", b ? "installed" : "NOT installed", prog ? "on" : "NOT on");
    emf::add_command("fkloot.stats", ": loot news counts (new loose items, containers, file writes)", [](emf::World, const std::vector<std::string>&) {
        EMF_REPLY("loot news: %llu loose item(s), %llu container(s), %llu written in %llu file write(s), %llu dropped, %llu in other worlds",
                  (unsigned long long)g_n_pickups.load(), (unsigned long long)g_n_containers.load(), (unsigned long long)g_n_sent.load(),
                  (unsigned long long)g_n_writes.load(), (unsigned long long)g_n_dropped.load(), (unsigned long long)g_n_other_world.load());
    });
    return a && b && prog;
}
