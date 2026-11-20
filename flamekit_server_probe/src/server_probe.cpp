// fk_server_probe (2026-11-17): FlameKit's companion drive, a TEST server mod on the owner's local server only (never
// published). Rebuilt at 17:09 (owner: everything old that did not work is gone: the player-body experiments, the
// template writes, the read-only dumps). What is left: the hook that moves a driven companion (see below).
#include <windows.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <string>
#include <vector>
#include <map>
#include <mutex>
#include <atomic>
#include <cmath>
#include "emf/generated/components.hpp"

#include "emf/emf.hpp"
#include "emf/query.hpp"

namespace {
constexpr const char* kMod = "fk_server_probe";

#pragma pack(push, 1)
struct WorldTransform {  // CurrentTransform (56 bytes): position in fixed point (1 m = 2^32), orientation, scale
    int64_t px, py, pz;
    float qx, qy, qz, qw;
    float sx, sy, sz;
    uint32_t pad;
};
#pragma pack(pop)
static_assert(sizeof(WorldTransform) == 56, "CurrentTransform is 56 bytes");

// (owner 2026-11-18 11:12) how close he follows the player: within this he stands (was 3 m); Lua DRIVE_STOP matches
constexpr double kFollowStop = 2.0;
constexpr double kCatchUp = 6.0;  // (owner 2026-11-19 16:37) sprint when he is this far behind
// ===== Option 2 (owner 15:58: "now that we've proven better bread crumbs work, get working on option 2") =========
// FlameKit's Lua picks where a driven NPC goes (his AI off): it writes the next breadcrumb into his AI data's
// movementTarget and the player's position into homeZonePosition (the AI is off, so nothing else uses them). The game's
// steering step writes "stand still" into his movement input every step, and Lua only runs after the step; so this hook
// runs right AFTER the steering step, inside the same step, and writes the movement input (direction, look, Walk/Run/
// Sprint), before his locomotion reads it. The game then moves and animates him like any monster.
// Driven = his AI off (enabled false), movementTargetIsValid true, faction 11 (PlayerAlly; 7 before 19:31). The list is refreshed every 30 ticks.
std::mutex g_drive_mx;
std::vector<uint32_t> g_driven;
std::atomic<uint64_t> g_drive_writes{0};
uint32_t g_drive_scan_tick = 0;

// ===== Bite test (owner 17:39-18:19): start one of his attack sequences the way the game's own code does it
// (server 0x1400369d0, "trigger an action sequence"): fill his movement input's trigger: sequence id (FNV-1a of the
// sequence GUID), the time, his entity, the call counter, and the fixed codes 0x18 / 0x38 (every attack call uses them).
// The skeleton hound: attack 0 = 0x63FE3237 (bite, 2 m), attack 1 = 0xC34733A8 (lunge, 4 m).
std::mutex g_bite_mx;
std::vector<std::pair<uint32_t, uint32_t>> g_bites;  // entity, sequence id: written once, at the next steering step

// (owner 18:38 "you gotta add code to keep the dog facing the monster its attacking") entity -> {target, until (ns)}:
// while it lasts, the look direction written at every steering step points at the target, moving or not. Without it
// the dog's look direction stays whatever it last was (the drive only writes it while he moves), so he attacks sideways.
struct FaceTarget { uint32_t target; int64_t until_ns; };
std::mutex g_face_mx;
std::map<uint32_t, FaceTarget> g_face;

// (owner 23:32 "lets try to finish the jump") two ways a jump may start, tried by fkprobe.jump <id> <mode> [type]:
//  mode 1: ActorInput.externalTriggerJumpType = type (JumpType: 1 Default, 5 Sprint), externalTriggerJumpTime = now
//  mode 2: the hound's jump sequence 0xe80706fc (PathWalker.jumpSequence) with triggerContext.jumpType = type,
//          strength 1 and directionOverride = his facing, else like the bite
struct JumpAsk { uint32_t id; int mode; uint8_t type; };
std::mutex g_jump_mx;
std::vector<JumpAsk> g_jumps;
void write_jumps(emf::World w) {
    std::vector<JumpAsk> todo;
    { std::lock_guard<std::mutex> lk(g_jump_mx); if (g_jumps.empty()) return; todo.swap(g_jumps); }
    for (auto& j : todo) {
        auto* ai = w.get<emf::gen::ecs::ActorInput>(j.id);
        auto* tr = static_cast<const WorldTransform*>(w.get_raw(0x027ac564u, j.id));
        if (!ai || !tr) { EMF_LOG(kMod, "jump: %u has no movement input", j.id); continue; }
        const int64_t now = w.ecs_time_ns();
        auto* raw = reinterpret_cast<uint8_t*>(ai);
        if (j.mode == 1) {
            raw[377] = j.type;
            std::memcpy(raw + 384, &now, 8);
            EMF_LOG(kMod, "jump: %u external jump type %u at %lld", j.id, j.type, (long long)now);
        } else {
            auto* tc = reinterpret_cast<uint8_t*>(&ai->triggerContext);
            std::memset(tc, 0, sizeof(ai->triggerContext));
            const uint32_t seq = 0xE80706FCu;
            const uint8_t call = ai->triggerCallCounter;
            std::memcpy(tc + 0, &seq, 4); std::memcpy(tc + 8, &now, 8); std::memcpy(tc + 16, &j.id, 4);
            tc[20] = call; const uint16_t trig = 0x18; std::memcpy(tc + 24, &trig, 2); tc[26] = 0x38;
            tc[88] = j.type;
            const double yaw = std::atan2(2.0 * (tr->qx * tr->qz + tr->qw * tr->qy), 1.0 - 2.0 * (tr->qx * tr->qx + tr->qy * tr->qy));
            const float dir[3] = {(float)std::sin(yaw), 0.0f, (float)std::cos(yaw)};
            std::memcpy(tc + 92, dir, 12);
            const float strength = 1.0f;
            std::memcpy(tc + 104, &strength, 4);
            EMF_LOG(kMod, "jump: %u sequence e80706fc, jumpType %u, direction %.2f %.2f", j.id, j.type, dir[0], dir[2]);
        }
    }
}

// one of his action sequences started, the way the game's own code does it (see the bite test above)
void start_sequence(emf::World w, uint32_t id, emf::gen::ecs::ActorInput* ai, uint32_t seq, const char* why) {
    auto* tc = reinterpret_cast<uint8_t*>(&ai->triggerContext);
    std::memset(tc, 0, sizeof(ai->triggerContext));
    const int64_t now = w.ecs_time_ns();
    const uint8_t call = ai->triggerCallCounter;
    std::memcpy(tc + 0, &seq, 4);
    std::memcpy(tc + 8, &now, 8);
    std::memcpy(tc + 16, &id, 4);
    tc[20] = call;
    const uint16_t trig = 0x18;
    std::memcpy(tc + 24, &trig, 2);
    tc[26] = 0x38;
    EMF_LOG(kMod, "%s: sequence %08x written into %u's trigger (call %u, time %lld)", why, seq, id, call, (long long)now);
}

// (owner 2026-11-19 09:03/09:17, the attack sequence) once per step per companion: the attack the Lua part asks for
// (combatData.selectedAttackIndex 0 = bite 0x63FE3237, 1 = lunge 0xC34733A8, the skeleton hound's; set back to 255 once
// started), and the ray to the monster he fights or checks (combatData.lastTargetId): from his shoulder (0.7 m up) to
// the monster's middle (0.5 m above its position), mask 7 (terrain and objects, not characters). Clear = nothing hit,
// or the hit within 1 m of the monster. Written into combatData.isTargetReachable (clear) and combatData
// .distanceToTarget (metres to the hit; the whole distance when clear) for the Lua part; logged when it changes. The
// hook runs several times per step on different threads: the per-step guard also ends the attack being started several
// times in one step (seen 2026-11-18 21:15).
struct FightStep { uint32_t tick = 0; uint32_t target = 0; int clear = -1; };
std::mutex g_fight_mx;
std::map<uint32_t, FightStep> g_fight;
void fight_step(emf::World w, void* ctx, uint32_t id, emf::gen::ecs::DynamicEnemy01BehaviorState* st,
                emf::gen::ecs::ActorInput* ai, const WorldTransform* tr);

void write_bites(emf::World w) {
    std::vector<std::pair<uint32_t, uint32_t>> todo;
    {
        std::lock_guard<std::mutex> lk(g_bite_mx);
        if (g_bites.empty()) return;
        todo.swap(g_bites);
    }
    for (auto& b : todo) {
        auto* ai = w.get<emf::gen::ecs::ActorInput>(b.first);
        if (!ai) { EMF_LOG(kMod, "bite: %u has no movement input", b.first); continue; }
        start_sequence(w, b.first, ai, b.second, "bite");
    }
}

// ---- (owner 20:55-20:59) the game's ray cast, for ground heights under the player's flight path ----
// Server function 0x1409300b0 (build of 2026-11-17, enshrouded_server.exe), used by the programs
// check_line_above_sensor (0x1400f0df0) and ray_cast_spawner (0x140107120):
//   rayCast(out, const float3* from, const float3* to, const Query* q)
//   out: +0 byte 0 = hit, +0x10 float3 = hit position (ray_cast_spawner reads them so).
//   Query (0x34 bytes, as check_line_above_sensor builds it): +0 byte = programContext->world->byte 0xbb,
//   +8 / +0x10 = the program's two system pointers (sys-read ecs::ColliderSystem, ecs::VoxelGrid; here from
//   emf singleton(), NOT CONFIRMED the same pointers), +0x18 0, +0x20 mask bits 0 and 3, +0x24 u16 0x100,
//   +0x28/+0x2c entity ids to ignore (0), +0x30 0, +0x33 byte 1. Test only: fkprobe.ground.
constexpr uintptr_t kRayCastRva = 0x9300b0;
const uint8_t kRayCastStart[] = {0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x08, 0x4C, 0x89, 0x40, 0x18, 0x48, 0x89, 0x50, 0x10};
using RayCastFn = void (*)(void* out, const float* from, const float* to, const void* query);

struct GroundAsk { double x, z, top, bottom; uint32_t mask; uint16_t flags; uint8_t b33; };
std::mutex g_ground_mx;
std::vector<GroundAsk> g_ground;

// Plain C function (no objects with destructors) so __try can guard it: a wrong guess faults here, not the server.
int ray_cast_guarded(RayCastFn fn, void* ctx, void* col, void* vox, const float* from, const float* to, float* hit,
                     uint32_t mask, uint16_t flags, uint8_t b33) {
    __try {
        alignas(16) uint8_t q[0x40] = {};
        alignas(16) uint8_t out[0x100] = {};
        q[0] = *(*(uint8_t**)ctx + 0xbb);
        *(void**)(q + 0x08) = col;
        *(void**)(q + 0x10) = vox;
        *(uint32_t*)(q + 0x20) = mask;
        *(uint16_t*)(q + 0x24) = flags;
        q[0x33] = b33;
        fn(out, from, to, q);
        hit[0] = *(float*)(out + 0x10); hit[1] = *(float*)(out + 0x14); hit[2] = *(float*)(out + 0x18);
        return out[0] == 0 ? 1 : 0;
    } __except (1) {
        return -1;
    }
}

void do_ground(emf::World w, void* ctx) {
    std::vector<GroundAsk> todo;
    { std::lock_guard<std::mutex> lk(g_ground_mx); if (g_ground.empty()) return; todo.swap(g_ground); }
    auto* base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto* fnp = base + kRayCastRva;
    if (std::memcmp(fnp, kRayCastStart, sizeof(kRayCastStart)) != 0) {
        EMF_LOG(kMod, "ground: the ray cast function is not at +0x%llx in this game build: not called", (unsigned long long)kRayCastRva);
        return;
    }
    void* col = w.singleton("ecs::ColliderSystem");
    void* vox = w.singleton("ecs::VoxelGrid");
    if (!col || !vox) { EMF_LOG(kMod, "ground: no ColliderSystem (%p) or VoxelGrid (%p)", col, vox); return; }
    for (auto& a : todo) {
        const float from[3] = {(float)a.x, (float)a.top, (float)a.z};
        const float to[3] = {(float)a.x, (float)a.bottom, (float)a.z};
        float hit[3] = {0, 0, 0};
        const int r = ray_cast_guarded(reinterpret_cast<RayCastFn>(fnp), ctx, col, vox, from, to, hit, a.mask, a.flags, a.b33);
        if (r < 0) EMF_LOG(kMod, "ground: %.1f %.1f: the ray cast FAULTED (caught); the query guess is wrong", a.x, a.z);
        else if (r == 0) EMF_LOG(kMod, "ground: %.1f %.1f: no hit between y %.1f and %.1f (mask %x flags %x b33 %u)", a.x, a.z, a.top, a.bottom, a.mask, a.flags, a.b33);
        else EMF_LOG(kMod, "ground: %.1f %.1f: hit at %.2f %.2f %.2f (ray from y %.1f; mask %x flags %x b33 %u)", a.x, a.z, hit[0], hit[1], hit[2], a.top, a.mask, a.flags, a.b33);
    }
}

// ---- (owner 21:39) the walkable-ground search (path grid), as the teleport program's ground search calls it ----
// Server 0x140175a20 (found from the teleport program 0x1400916a0, call at 0x140091a3a):
//   search(out, const float3* pos, bool isPlayer, PathGridSystem* pg, u8 worldFlag)   worldFlag = world byte 0xbb
//   out: +0 byte status (0 found; 1-3 not ready, ask again next tick; else nothing), +8 float3 the walkable spot.
// EMF re_teleport.md 1.4: snaps to the nearest walkable cell, about +-10 m vertically. Test only: fkprobe.walk.
constexpr uintptr_t kWalkSearchRva = 0x175a20;
const uint8_t kWalkSearchStart[] = {0x48, 0x89, 0x5C, 0x24, 0x08, 0x55, 0x48, 0x8B, 0xEC, 0x48, 0x83, 0xEC, 0x70, 0x33, 0xC0};
using WalkSearchFn = void* (*)(void* out, const float* pos, bool isPlayer, void* pg, uint8_t flag);
struct WalkAsk { float p[3]; int tries; int layer; int player; };
std::mutex g_walk_mx;
std::vector<WalkAsk> g_walk;

int walk_search_guarded(WalkSearchFn fn, void* ctx, void* pg, const float* pos, float* res, int layer, int player, int* used) {
    __try {
        alignas(16) uint8_t out[0x40] = {};
        const uint8_t flag = layer >= 0 ? (uint8_t)layer : *(*(uint8_t**)ctx + 0xbb);
        *used = flag;
        fn(out, pos, player != 0, pg, flag);
        res[0] = *(float*)(out + 8); res[1] = *(float*)(out + 0xc); res[2] = *(float*)(out + 0x10);
        return out[0];
    } __except (1) {
        return -1;
    }
}

void do_walk(emf::World w, void* ctx, void* pg_in = nullptr) {
    std::vector<WalkAsk> todo;
    { std::lock_guard<std::mutex> lk(g_walk_mx); if (g_walk.empty()) return; todo.swap(g_walk); }
    auto* base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto* fnp = base + kWalkSearchRva;
    if (std::memcmp(fnp, kWalkSearchStart, sizeof(kWalkSearchStart)) != 0) {
        EMF_LOG(kMod, "walk: the search function is not at +0x%llx in this game build: not called", (unsigned long long)kWalkSearchRva);
        return;
    }
    void* pg = pg_in ? pg_in : w.singleton("ecs::PathGridSystem");
    if (!pg) { EMF_LOG(kMod, "walk: no PathGridSystem"); return; }
    std::vector<WalkAsk> again;
    for (auto& a : todo) {
        float r[3] = {0, 0, 0};
        int used = -1;
        const int st = walk_search_guarded(reinterpret_cast<WalkSearchFn>(fnp), ctx, pg, a.p, r, a.layer, a.player, &used);
        if (st < 0) EMF_LOG(kMod, "walk: %.1f %.1f %.1f: FAULTED (caught)", a.p[0], a.p[1], a.p[2]);
        else if (st >= 1 && st <= 3 && a.tries < 120) { a.tries++; again.push_back(a); }
        else if (st == 0) EMF_LOG(kMod, "walk: %.1f %.1f %.1f: walkable at %.2f %.2f %.2f (after %d waits; layer %d player %d)", a.p[0], a.p[1], a.p[2], r[0], r[1], r[2], a.tries, used, a.player);
        else EMF_LOG(kMod, "walk: %.1f %.1f %.1f: nothing (status %d, after %d waits; layer %d player %d)", a.p[0], a.p[1], a.p[2], st, a.tries, used, a.player);
    }
    if (!again.empty()) { std::lock_guard<std::mutex> lk(g_walk_mx); g_walk.insert(g_walk.end(), again.begin(), again.end()); }
}

// (owner 22:28 "lets try it") ground check ahead of a driven companion, measuring only: every 15 steps, rays straight
// down 1, 2 and 3 m ahead along his movement (or facing) direction, from his height + 2 m to - 12 m, mask 7 (terrain
// and objects, not characters), ignoring himself. Logged; nothing about his movement changes. fkprobe.ahead on|off.
std::atomic<bool> g_ahead{false};
uint32_t g_ahead_tick = 0;
void log_ahead(emf::World w, void* ctx, uint32_t id, const emf::gen::ecs::ActorInput* ai, const WorldTransform* tr) {
    auto* base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto* fnp = base + kRayCastRva;
    if (std::memcmp(fnp, kRayCastStart, sizeof(kRayCastStart)) != 0) return;
    void* col = w.singleton("ecs::ColliderSystem");
    void* vox = w.singleton("ecs::VoxelGrid");
    if (!col || !vox) return;
    const double S = 4294967296.0;
    const double nx = tr->px / S, ny = tr->py / S, nz = tr->pz / S;
    double dx = ai->desiredWorldMoveInput.x, dz = ai->desiredWorldMoveInput.z;
    bool moving = true;
    if (dx * dx + dz * dz < 0.01) {  // standing: his facing (yaw from the orientation)
        moving = false;
        const double yaw = std::atan2(2.0 * (tr->qx * tr->qz + tr->qw * tr->qy), 1.0 - 2.0 * (tr->qx * tr->qx + tr->qy * tr->qy));
        dx = std::sin(yaw); dz = std::cos(yaw);
    }
    const double dl = std::sqrt(dx * dx + dz * dz);
    dx /= dl; dz /= dl;
    char buf[256]; int n = 0;
    n += std::snprintf(buf + n, sizeof(buf) - n, "ahead %u (%s, y %.2f):", id, moving ? "moving" : "standing", ny);
    for (int k = 1; k <= 3; k++) {
        const float from[3] = {(float)(nx + dx * k), (float)(ny + 2.0), (float)(nz + dz * k)};
        const float to[3] = {from[0], (float)(ny - 12.0), from[2]};
        float hit[3] = {0, 0, 0};
        const int r = ray_cast_guarded(reinterpret_cast<RayCastFn>(fnp), ctx, col, vox, from, to, hit, 0x7u, (uint16_t)0x100, (uint8_t)0);
        if (r < 0) n += std::snprintf(buf + n, sizeof(buf) - n, " %dm FAULT", k);
        else if (r == 0) n += std::snprintf(buf + n, sizeof(buf) - n, " %dm none", k);
        else n += std::snprintf(buf + n, sizeof(buf) - n, " %dm %+.2f", k, hit[1] - ny);
    }
    EMF_LOG(kMod, "%s", buf);
}

// (owner 22:37) edge stop: while a companion moves, one ray straight down 1.5 m ahead along his move direction (from his
// height + 2 m to - 12 m, mask 7: terrain and objects). No ground there, or ground more than 7.5 m lower (his fall
// damage starts at 8 m): he does not move this step. Worked out at most once per game step per companion (this hook
// runs several times per step on different worker threads; the result is cached for the step). Skipped while the Lua
// side marks him swimming (combatData.targetOfMyTarget = true; unused with his AI off).
struct EdgeState { uint32_t tick; bool blocked; bool was_blocked; };
std::mutex g_edge_mx;
std::map<uint32_t, EdgeState> g_edge;
std::atomic<uint32_t> g_edge_stops{0};
bool edge_blocked(emf::World w, void* ctx, uint32_t id, const WorldTransform* tr, double dx, double dz, bool drop_ok, uint8_t speed) {
    const uint32_t t = w.tick();
    {
        std::lock_guard<std::mutex> lk(g_edge_mx);
        auto it = g_edge.find(id);
        if (it != g_edge.end() && it->second.tick == t) return it->second.blocked;
    }
    bool blocked = false;
    auto* base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto* fnp = base + kRayCastRva;
    void* col = w.singleton("ecs::ColliderSystem");
    void* vox = w.singleton("ecs::VoxelGrid");
    float hy = 0;
    int r = -2;
    if (std::memcmp(fnp, kRayCastStart, sizeof(kRayCastStart)) == 0 && col && vox) {
        const double S = 4294967296.0;
        const double nx = tr->px / S, ny = tr->py / S, nz = tr->pz / S;
        // (22:48 test: he stopped at the edge, shifted a little, the ray 1.5 m ahead met the cliff face 7.25 m down,
        // under the 7.5 m limit: he stepped off and slid 27 m) a second ray 3 m ahead: a step down of more than 2.5 m
        // is only allowed when the ground beyond it is level (the 3 m point no more than 2.5 m lower than the 1.5 m
        // point, and within 7.5 m of him): a step he can drop down, not a cliff face that keeps going.
        auto ray_at = [&](double d, float* hit) {
            const float from[3] = {(float)(nx + dx * d), (float)(ny + 2.0), (float)(nz + dz * d)};
            const float to[3] = {from[0], (float)(ny - 12.0), from[2]};
            return ray_cast_guarded(reinterpret_cast<RayCastFn>(fnp), ctx, col, vox, from, to, hit, 0x7u, (uint16_t)0x100, (uint8_t)0);
        };
        float hit[3] = {0, 0, 0}, hit3[3] = {0, 0, 0};
        r = ray_at(1.5, hit);
        hy = hit[1];
        double d1 = ny - hit[1];
        if (r != 1) blocked = true;
        else if (d1 > 7.5) blocked = true;
        // (22:53 test: a rock or plant on the cliff face read as a ledge 7 m down, he fell 30 m) (owner 22:55) a drop
        // is allowed only when the Lua side says the player took it himself (his trail ahead goes down there:
        // combatData.isTargetInsideLeash = true, unused with the AI off); the 7.5 m limit still holds.
        // (23:08 test: he went down a ~58 degree slope at speed, stopped at the edge, and his speed carried him over)
        // (owner 23:11/23:12) without the player's way: no more than 30 degrees (0.87 m down within 1.5 m): the
        // hound's SlopeConfig slides on some ground materials from 30 degrees (slidingMaterialMinAngle 30).
        else if (d1 > 0.87) blocked = !drop_ok;
        // running or sprinting: a second look further ahead (2.5 / 3.5 m), same rules scaled, so he has room to stop
        if (!blocked && speed >= 3) {
            const double ahead2 = speed >= 4 ? 3.5 : 2.5;
            const int r2 = ray_at(ahead2, hit3);
            const double d2 = ny - hit3[1];
            if (r2 != 1 || d2 > 7.5 || (d2 > ahead2 * 0.577 && !drop_ok)) { blocked = true; d1 = d2; r = r2; }
        }
        bool was = false;
        {
            std::lock_guard<std::mutex> lk(g_edge_mx);
            auto& e = g_edge[id];
            was = e.was_blocked;
            e.tick = t; e.blocked = blocked; e.was_blocked = blocked;
        }
        if (blocked && !was) {
            g_edge_stops.fetch_add(1);
            EMF_LOG(kMod, "edge: %u stops at %.1f %.1f %.1f (ground 1.5 m ahead: %s, %.2f m down)", id, nx, ny, nz,
                    r != 1 ? "none within 12 m" : (d1 > 7.5 ? "more than 7.5 m lower" : "a drop the player did not take"), r == 1 ? d1 : -1.0);
        } else if (!blocked && was) {
            EMF_LOG(kMod, "edge: %u goes on (ground ahead %+.2f m)", id, (double)hy - ny);
        }
    }
    return blocked;
}

// (owner 23:36) jump log: per driven companion, every game step once: DynamicLocomotion.state 2 = in the air. Logs the
// takeoff spot, the highest point and the landing spot: distance and height of each jump.
struct JumpTrack { uint32_t tick; uint8_t state; double x, y, z, top; };
std::mutex g_jt_mx;
std::map<uint32_t, JumpTrack> g_jt;
void track_jump(emf::World w, uint32_t id, const WorldTransform* tr) {
    auto* loc = w.get<emf::gen::ecs::DynamicLocomotion>(id);
    if (!loc) return;
    const uint32_t t = w.tick();
    const double S = 4294967296.0;
    const double x = tr->px / S, y = tr->py / S, z = tr->pz / S;
    const uint8_t st = static_cast<uint8_t>(loc->state);
    std::lock_guard<std::mutex> lk(g_jt_mx);
    auto& j = g_jt[id];
    if (j.tick == t) return;
    j.tick = t;
    if (st == 2 && j.state != 2) {
        j.x = x; j.y = y; j.z = z; j.top = y;
        EMF_LOG(kMod, "jumplog: %u takes off at %.2f %.2f %.2f", id, x, y, z);
    } else if (st == 2) {
        if (y > j.top) j.top = y;
    } else if (j.state == 2) {
        EMF_LOG(kMod, "jumplog: %u lands at %.2f %.2f %.2f: %.2f m forward, highest %+.2f m, landed %+.2f m", id, x, y, z,
                std::sqrt((x - j.x) * (x - j.x) + (z - j.z) * (z - j.z)), j.top - j.y, y - j.y);
    }
    j.state = st;
}

// (owner 2026-11-18 18:35, FOLLOW_PLAN.md) the ray step jump (a ray from 5 m above him, 1.5 m ahead) and its jump boost
// are gone: steps up come from the player's trail now (npc_probe.lua drive_copy launches him). Under ceilings and
// overhangs the ray had read the overhang as a step.

// ---- (2026-11-20 13:05) pets: the drive's inputs from the Lua, in pet_drive.txt beside FlameKit: a line per pet
// "<entity> <target x y z> <player spot x y z> <code>" (code: pace 2/3/4, + 10 edge stop off, + 20 drops allowed; under
// 1.5 not driven). Read again whenever the file changes. (The first try kept them in the animal's own AnimalSaved /
// DynamicWildlife spawn positions: the game moved the dog by them, 20 m jumps.)
struct PetIn { double tx, ty, tz, hx, hy, hz; float code; int mode; };  // mode (9th field, 14:59): 1 = the game's pet action
std::mutex g_pet_mx;
std::map<uint32_t, PetIn> g_pets;
std::wstring flamekit_file(const wchar_t* name);
void read_pets() {
    static const std::wstring file = flamekit_file(L"pet_drive.txt");
    static FILETIME seen{};
    WIN32_FILE_ATTRIBUTE_DATA fa{};
    if (!GetFileAttributesExW(file.c_str(), GetFileExInfoStandard, &fa)) return;
    if (CompareFileTime(&fa.ftLastWriteTime, &seen) == 0) return;
    FILE* f = _wfopen(file.c_str(), L"rb");
    if (!f) return;
    std::map<uint32_t, PetIn> got;
    char line[256];
    while (std::fgets(line, sizeof line, f)) {
        unsigned id = 0;
        PetIn p{};
        if (std::sscanf(line, "%u %lf %lf %lf %lf %lf %lf %f %d", &id, &p.tx, &p.ty, &p.tz, &p.hx, &p.hy, &p.hz, &p.code, &p.mode) >= 8) got[id] = p;
    }
    std::fclose(f);
    seen = fa.ftLastWriteTime;
    std::lock_guard<std::mutex> lk(g_pet_mx);
    g_pets.swap(got);
}

// ---- (2026-11-20, owner 14:09 "yeah we need to remove the pick up and pet option, the pet option could be put in the
// wheel"; 14:22 "pick up is gone, but so is the E menu") a pet is a wild animal (a tame one has the game's Pick up,
// which comes with IsTame). The game's taming offer on a wild animal is off (runtime: sequences 0, isOffered false) and
// the game writes it again every step, so a write from the Lua after the step never reaches the client. Here, right
// before program interaction_offer copies the runtime offer into ClientInteractionOffer (what the client shows), each
// pet's runtime offer is set to EMF's touch sequence (no screen) with the word Talk; E then only fires
// InteractionAcceptedEvent, which the Lua turns into his wheel. After it: the client copy is checked (and logged).
constexpr uint32_t kTouchSeq = 0x3E5189BFu;   // EMF_SEQUENCE_TOUCH
constexpr uint32_t kTalkVerb = 0xD9861C4Bu;   // EMF_VERB_TALK
// (owner 14:59 "lets try it": "Pet" in a pet's wheel) while the Lua asks for it (mode 1): the game's own pet action, as
// a tame animal has it (petlog 14:11:55)
constexpr uint32_t kPetSeq = 0xB1EB4A70u;
constexpr uint32_t kPetVerb = 0x6D5B6297u;    // EMF_VERB_PET
constexpr uint32_t kCloseVerb = 0x3959A87Fu;  // (16:10) "Close", FlameKit's inv.CLOSE_VERB (the chest's onToOffVerb)
std::atomic<uint64_t> g_offer_log_at{0};
std::atomic<uint64_t> g_reset_log_at{0};
// where: 0 = before interaction_offer, 1 = after interaction_taming, 2 = before interaction_attempt (14:32: E on the
// Talk prompt fired no InteractionAcceptedEvent: the game's own offer was back by the time the press was checked),
// 3 = after interaction_offer (only checks and logs the client copy)
void pet_offers(int where) {
    emf::World w = emf::server_world();
    if (!w) return;
    std::vector<std::pair<uint32_t, int>> ids;
    {
        std::lock_guard<std::mutex> lk(g_pet_mx);
        for (auto& kv : g_pets) ids.push_back({kv.first, kv.second.mode});
    }
    const uint64_t now = GetTickCount64();
    const bool say = where == 3 && now >= g_offer_log_at.load();
    if (say) g_offer_log_at.store(now + 10000);
    for (auto [id, mode] : ids) {
        auto* o = w.get<emf::gen::ecs::InteractionOfferRuntime>(id);
        if (!o) continue;
        // mode 2 (owner 16:10): his chest is open: "Close" (FlameKit's inv.CLOSE_VERB, the touch sequence)
        const uint32_t seq = mode == 1 ? kPetSeq : kTouchSeq, verb = mode == 1 ? kPetVerb : (mode == 2 ? kCloseVerb : kTalkVerb);
        if (where != 3) {
            const bool ours = o->overrideSequence.value == seq && o->overrideVerbLocaId.value == verb &&
                              o->defaultSequence.value == seq && o->defaultVerbId.value == verb &&
                              o->isOffered && !o->isDisabled && o->offerId != 0;
            if (!ours && where == 2 && now >= g_reset_log_at.load()) {
                g_reset_log_at.store(now + 10000);
                EMF_LOG(kMod, "pet offer %u before interaction_attempt: the game's again (seq %08x/%08x verb %08x/%08x "
                        "offered %d disabled %d offerId %u): set back", id, o->defaultSequence.value, o->overrideSequence.value,
                        o->defaultVerbId.value, o->overrideVerbLocaId.value, (int)o->isOffered, (int)o->isDisabled, o->offerId);
            }
            // (14:37: before the press check the override was 0 again: a reset program clears the override, so with
            // the default at 0 the press had no sequence to play) the default is ours too
            o->defaultSequence.value = seq;
            o->defaultVerbId.value = verb;
            o->overrideSequence.value = seq;
            o->overrideVerbLocaId.value = verb;
            o->isOffered = true;
            o->isDisabled = false;
            // (14:43 petlog: the wild offer has offerId 0; the tame one, whose E worked at 14:07, had 1)
            if (o->offerId == 0) o->offerId = 1;
            continue;
        }
        auto* c = w.get<emf::gen::ecs::ClientInteractionOffer>(id);
        if (say)
            EMF_LOG(kMod, "pet offer %u after interaction_offer: runtime seq %08x/%08x verb %08x/%08x offered %d disabled %d; "
                    "client %s verb %08x offered %d", id, o->defaultSequence.value, o->overrideSequence.value,
                    o->defaultVerbId.value, o->overrideVerbLocaId.value, (int)o->isOffered, (int)o->isDisabled,
                    c ? "yes" : "NONE", c ? c->verbId.value : 0u, c ? (int)c->isOffered : -1);
    }
}
void pet_offers_pre(void*, void*) { pet_offers(0); }
void pet_offers_post(void*, void*) { pet_offers(3); }
void pet_offers_taming(void*, void*) { pet_offers(1); }
void pet_offers_attempt(void*, void*) { pet_offers(2); }

void drive_post(void* ctx, void*) {
    emf::World w = emf::server_world();
    if (!w) return;
    write_bites(w);
    write_jumps(w);
    if (ctx) do_ground(w, ctx);
    read_pets();

    std::vector<uint32_t> ids;
    {
        std::lock_guard<std::mutex> lk(g_drive_mx);
        ids = g_driven;
    }
    for (uint32_t id : ids) {
        auto* st = w.get<emf::gen::ecs::DynamicEnemy01BehaviorState>(id);
        auto* ai = w.get<emf::gen::ecs::ActorInput>(id);
        auto* tr = static_cast<const WorldTransform*>(w.get_raw(0x027ac564u, id));
        if (!ai || !tr) continue;
        // (2026-11-20 12:49, owner: pets "should just use what we made already") the same drive for a pet (an animal: no
        // monster AI); its inputs come from pet_drive.txt (read_pets above).
        double tx, tz, hx, hy, hz;
        float pace;
        bool edge_off, drop_ok;
        if (st) {
            if (st->enabled || !st->movementTargetIsValid) continue;
            tx = st->movementTarget.x, tz = st->movementTarget.z;
            hx = st->homeZonePosition.x, hy = st->homeZonePosition.y, hz = st->homeZonePosition.z;
            pace = st->combatData.prowlAngle;
            edge_off = st->combatData.targetOfMyTarget;
            drop_ok = st->combatData.isTargetInsideLeash;
        } else {
            PetIn p{};
            {
                std::lock_guard<std::mutex> lk(g_pet_mx);
                auto it = g_pets.find(id);
                if (it == g_pets.end()) continue;
                p = it->second;
            }
            if (p.code < 1.5f) continue;
            float code = p.code;
            drop_ok = code >= 20.0f;
            if (drop_ok) code -= 20.0f;
            edge_off = code >= 10.0f;
            if (edge_off) code -= 10.0f;
            pace = code;
            tx = p.tx, tz = p.tz;
            hx = p.hx, hy = p.hy, hz = p.hz;
        }
        track_jump(w, id, tr);
        // (the companion's fight) the attack asked for and the ray to his target, once per step (fight_step); combatData
        // .lastTargetId = the monster he fights: he faces it (below)
        if (st) fight_step(w, ctx, id, st, ai, tr);
        const double S = 4294967296.0;
        const double nx = tr->px / S, ny_here = tr->py / S, nz = tr->pz / S;
        const double dp = std::sqrt((hx - nx) * (hx - nx) + (hz - nz) * (hz - nz));
        double dx = tx - nx, dz = tz - nz;
        const double dl = std::sqrt(dx * dx + dz * dz);
        uint8_t speed = 0;  // LocomotionSpeedSelector: 0 Zero, 2 Walk, 3 Run, 4 Sprint
        // (owner 2026-11-18 11:10/11:12 "the follow distance needs to be 2 m": tight spots) he stops within kFollowStop
        // (2026-11-18 18:35) arrived = within kFollowStop across AND in height: a player straight below or above him
        // (a drop, a ledge) is not "here"
        const bool here = dp <= kFollowStop && std::fabs(hy - ny_here) <= kFollowStop;
        if (!here && dl > 0.05) {
            dx /= dl; dz /= dl;
            // (owner 2026-11-19 16:37 "I agree #2") his pace from the Lua (the player's at the crumb he heads for, in
            // combatData.prowlAngle: 2 walk, 3 run, 4 sprint; his AI is off so nothing else writes it); more than
            // kCatchUp from where he is headed (the player; in a fight the monster): sprint
            speed = dp > kCatchUp ? 4 : pace >= 3.5f ? 4 : pace >= 2.5f ? 3 : 2;
            // (2026-11-20 13:23, pets) the dog shot 10-30 m in half a second whenever he was given sprint (4): an animal's
            // locomotion has no sprint; run (3) and walk (2) moved him normally. Pets run at most.
            if (!st && speed > 3) speed = 3;
            // (23:41 test) no edge check while he is in the air (DynamicLocomotion.state 2): it measured from his raised
            // height and stopped his legs mid-jump
            auto* loc_now = w.get<emf::gen::ecs::DynamicLocomotion>(id);
            const bool airborne = loc_now && static_cast<uint8_t>(loc_now->state) == 2;
            if (ctx && !airborne && !edge_off && edge_blocked(w, ctx, id, tr, dx, dz, drop_ok, speed)) {
                speed = 0;  // edge: stand, still looking that way
                ai->desiredWorldLookDirection.x = (float)dx; ai->desiredWorldLookDirection.y = 0; ai->desiredWorldLookDirection.z = (float)dz;
                dx = dz = 0;
            }
        } else {
            dx = dz = 0;
        }
        ai->desiredWorldMoveInput.x = (float)dx; ai->desiredWorldMoveInput.y = 0; ai->desiredWorldMoveInput.z = (float)dz;
        if (speed) { ai->desiredWorldLookDirection.x = (float)dx; ai->desiredWorldLookDirection.y = 0; ai->desiredWorldLookDirection.z = (float)dz; }
        ai->locomotionSpeed = static_cast<decltype(ai->locomotionSpeed)>(speed);
        g_drive_writes.fetch_add(1, std::memory_order_relaxed);
        if (g_ahead.load() && ctx && w.tick() % 15 == 0 && w.tick() != g_ahead_tick) log_ahead(w, ctx, id, ai, tr);
        FaceTarget ft{0, 0};
        {
            std::lock_guard<std::mutex> lk(g_face_mx);
            auto it = g_face.find(id);
            if (it != g_face.end()) {
                if (it->second.until_ns < w.ecs_time_ns()) g_face.erase(it); else ft = it->second;
            }
        }
        if (!ft.target && st && st->combatData.lastTargetId.id != 0) ft.target = st->combatData.lastTargetId.id;  // the fight
        if (ft.target) {
            auto* tt = static_cast<const WorldTransform*>(w.get_raw(0x027ac564u, ft.target));
            if (tt) {
                double fx = tt->px / S - nx, fz = tt->pz / S - nz;
                const double fl = std::sqrt(fx * fx + fz * fz);
                if (fl > 0.05) {
                    ai->desiredWorldLookDirection.x = (float)(fx / fl);
                    ai->desiredWorldLookDirection.y = 0;
                    ai->desiredWorldLookDirection.z = (float)(fz / fl);
                }
            }
        }
    }
}

void fight_step(emf::World w, void* ctx, uint32_t id, emf::gen::ecs::DynamicEnemy01BehaviorState* st,
                emf::gen::ecs::ActorInput* ai, const WorldTransform* tr) {
    const uint32_t t = w.tick();
    FightStep prev;
    {
        std::lock_guard<std::mutex> lk(g_fight_mx);
        auto& e = g_fight[id];
        if (e.tick == t) return;
        e.tick = t;
        prev = e;
    }
    const uint8_t ask = st->combatData.selectedAttackIndex;
    // 0 bite, 1 lunge (the wolf's attacks), 2 the heal cue: Wolf Shout 0x89A1BC53 (owner 2026-11-19 20:59/21:01 "I want
    // Wolf Shout", "every heal would be a good queue that its happening")
    if (ask == 0 || ask == 1 || ask == 2) {
        static const uint32_t kSeq[3] = { 0x63FE3237u, 0xC34733A8u, 0x89A1BC53u };
        static const char* kWhy[3] = { "fight bite", "fight lunge", "heal shout" };
        start_sequence(w, id, ai, kSeq[ask], kWhy[ask]);
        st->combatData.selectedAttackIndex = 255;
    }
    const uint32_t target = st->combatData.lastTargetId.id;
    if (!target || !ctx) return;
    auto* tt = static_cast<const WorldTransform*>(w.get_raw(0x027ac564u, target));
    if (!tt) return;
    auto* base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto* fnp = base + kRayCastRva;
    void* col = w.singleton("ecs::ColliderSystem");
    void* vox = w.singleton("ecs::VoxelGrid");
    if (std::memcmp(fnp, kRayCastStart, sizeof(kRayCastStart)) != 0 || !col || !vox) return;
    const double S = 4294967296.0;
    const float from[3] = {(float)(tr->px / S), (float)(tr->py / S + 0.7), (float)(tr->pz / S)};
    const float to[3] = {(float)(tt->px / S), (float)(tt->py / S + 0.5), (float)(tt->pz / S)};
    const double total = std::sqrt((double)(to[0] - from[0]) * (to[0] - from[0]) + (double)(to[1] - from[1]) * (to[1] - from[1]) +
                                   (double)(to[2] - from[2]) * (to[2] - from[2]));
    float hit[3] = {0, 0, 0};
    const int r = ray_cast_guarded(reinterpret_cast<RayCastFn>(fnp), ctx, col, vox, from, to, hit, 0x7u, (uint16_t)0x100, (uint8_t)0);
    double hitd = total;
    bool clear = true;
    if (r == 1) {
        hitd = std::sqrt((double)(hit[0] - from[0]) * (hit[0] - from[0]) + (double)(hit[1] - from[1]) * (hit[1] - from[1]) +
                         (double)(hit[2] - from[2]) * (hit[2] - from[2]));
        const double left = std::sqrt((double)(to[0] - hit[0]) * (to[0] - hit[0]) + (double)(to[1] - hit[1]) * (to[1] - hit[1]) +
                                      (double)(to[2] - hit[2]) * (to[2] - hit[2]));
        clear = left <= 1.0;
    }
    st->combatData.isTargetReachable = clear;
    st->combatData.distanceToTarget = (float)(clear ? total : hitd);
    if (target != prev.target || (clear ? 1 : 0) != prev.clear) {
        {
            std::lock_guard<std::mutex> lk(g_fight_mx);
            auto& e = g_fight[id];
            e.target = target;
            e.clear = clear ? 1 : 0;
        }
        if (r < 0) EMF_LOG(kMod, "fight ray: %u -> %u: the ray FAULTED (taken as clear)", id, target);
        else EMF_LOG(kMod, "fight ray: %u -> %u: %s (%.1f m; hit at %.1f m, %.1f %.1f %.1f)", id, target, clear ? "clear" : "BLOCKED", total,
                     hitd, r == 1 ? hit[0] : 0.0f, r == 1 ? hit[1] : 0.0f, r == 1 ? hit[2] : 0.0f);
    }
}

void drive_scan(emf::World w) {
    if (!w.is_server()) return;
    const uint32_t t = w.tick();
    if (t - g_drive_scan_tick < 30) return;
    g_drive_scan_tick = t;
    std::vector<uint32_t> found;
    w.for_each_entity([&](uint32_t id) {
        auto* f = static_cast<const uint8_t*>(w.get_raw(0xa1f30f21u, id));
        auto* st = w.get<emf::gen::ecs::DynamicEnemy01BehaviorState>(id);
        if (!st) {  // (2026-11-20) a pet: an animal of ours that the Lua drives (pet_drive.txt, see drive_post)
            if (!f || *f != 11 || !w.get<emf::gen::ecs::DynamicWildlife>(id)) return;
            std::lock_guard<std::mutex> lk(g_pet_mx);
            auto it = g_pets.find(id);
            if (it != g_pets.end() && it->second.code >= 1.5f) found.push_back(id);
            return;
        }
        if (st->enabled || !st->movementTargetIsValid) return;
        if (!f || (*f != 11 && *f != 7)) return;  // (owner 19:31) companions are PlayerAlly 11; 7 = bodies from before
        found.push_back(id);
    });
    size_t before;
    {
        std::lock_guard<std::mutex> lk(g_drive_mx);
        before = g_driven.size();
        g_driven = found;
    }
    if (found.size() != before)
        EMF_LOG(kMod, "drive: %zu driven NPC(s) (movement input written %llu times so far)", found.size(),
                (unsigned long long)g_drive_writes.load());
}
// ---- (owner 2026-11-20 08:51 "when the chest spawns and opens I just want it to have the companions name on it")
// The game's floating names (CustomPlayerString.stringId on a chest or altar) are looked up in the server singleton
// "CustomPlayerStringsSystem". Found in enshrouded_server.exe (sha256 f0d824be7fcd48eb..., 2026-11-20):
//   0x140915b80 setString(out, sys, u64 oldKey, const {char* p; u64 n}* text): the server's own rename (used by the
//     CustomPlayerStringClientMessage handler at 0x1407bde90): key = FNV-1a 64 of the text (checked: "Private Stash"
//     = 0x2E2B803BEE877B55, the key on the owner's chest); takes a reference on the text's entry (making it when new,
//     refcount at entry +0x138) and drops one on oldKey's; out +0 byte 0 = done, out +8 the key.
//   Its hash map: sys +0x198 bit set (u64 words), +0x1a0 slot count (power of 2), +0x1b8 keys, +0x1d0 entries,
//     +0x1e4 count; slot = low 32 bits of the key & (count - 1), linear probing (lookup 0x140953040, which ALSO takes a
//     reference: not used here).
//   custom_player_string_init (0x1400c1970) sets an entity's key to 0 when the key is not in the map at spawn, so the
//     name has to be there BEFORE the chest is spawned.
// FlameKit (Lua) writes the names in emf\mods\flamekit\custom_names.txt, one per line; each new one is registered here
// once per server run (that reference is ours and is never dropped, so a destroyed chest cannot free the name).
constexpr uintptr_t kSetStringRva = 0x915b80;
const uint8_t kSetStringStart[] = {0x48, 0x89, 0x5C, 0x24, 0x10, 0x55, 0x56, 0x57, 0x41, 0x54, 0x41, 0x57, 0x48, 0x83,
                                   0xEC, 0x30, 0x4D, 0x8B, 0x59, 0x08, 0x45, 0x33, 0xE4, 0x49, 0x8B, 0x39, 0x4D, 0x8B,
                                   0xF9, 0x48, 0x8B, 0xEA, 0x48, 0x8B, 0xF1, 0x48, 0xBB, 0x25, 0x23, 0x22, 0x84, 0xE4,
                                   0x9C, 0xF2, 0xCB};
using SetStringFn = void (*)(void* out, void* sys, uint64_t old_key, const void* text);
struct TextRef { const char* p; uint64_t n; };
std::map<std::string, uint64_t> g_names_done;  // world thread only
int64_t g_names_tick = -1000;
FILETIME g_names_seen{};

uint64_t fnv1a64(const std::string& s) {
    uint64_t h = 0xcbf29ce484222325ull;
    for (unsigned char c : s) { h ^= c; h *= 0x100000001b3ull; }
    return h;
}

// -1 = the map does not look like one (or faulted), 0 = not there, 1 = there. Reads only.
int name_known(void* sys, uint64_t key) {
    __try {
        auto* b = static_cast<uint8_t*>(sys);
        const uint64_t n = *(uint64_t*)(b + 0x1a0);
        const uint64_t* bits = *(uint64_t**)(b + 0x198);
        const uint64_t* keys = *(uint64_t**)(b + 0x1b8);
        const uint32_t count = *(uint32_t*)(b + 0x1e4);
        if (n == 0 || (n & (n - 1)) != 0 || n > 0x100000 || count > n || !bits || !keys) return -1;
        if (count == 0) return 0;
        uint64_t i = (uint32_t)key & (n - 1);
        for (uint64_t steps = 0; steps < n && ((bits[i >> 6] >> (i & 63)) & 1); ++steps) {
            if (keys[i] == key) return 1;
            i = (i + 1 < n) ? i + 1 : 0;
        }
        return 0;
    } __except (1) {
        return -1;
    }
}

int set_string_guarded(SetStringFn fn, void* sys, const char* p, uint64_t n, uint64_t* key) {
    __try {
        alignas(16) uint8_t out[0x20] = {};
        TextRef t{p, n};
        fn(out, sys, 0, &t);
        *key = *(uint64_t*)(out + 8);
        return out[0] == 0 ? 1 : 0;
    } __except (1) {
        return -1;
    }
}

std::wstring flamekit_file(const wchar_t* name);
std::wstring names_file() { return flamekit_file(L"custom_names.txt"); }
std::wstring flamekit_file(const wchar_t* name) {
    HMODULE me = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&fnv1a64), &me);
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(me, path, MAX_PATH);
    std::wstring s(path);
    s = s.substr(0, s.find_last_of(L"\\/"));  // ...\mods\fk_server_probe
    s = s.substr(0, s.find_last_of(L"\\/"));  // ...\mods
    return s + L"\\flamekit\\" + name;
}

void names_tick(emf::World w) {
    const int64_t t = (int64_t)w.tick();
    if (t - g_names_tick < 30) return;
    g_names_tick = t;
    // (owner 14:49 "it wasn't labeling the inventory chest with the pets name": N2's key was 0 on its chest 2 min
    // after "registered ... now there") every 30 ticks: is each registered name still in the server's table?
    if (void* sysw = w.singleton("CustomPlayerStringsSystem")) {
        static std::map<std::string, int> last;
        for (const auto& kv : g_names_done) {
            if (!kv.second) continue;
            const int k = name_known(sysw, kv.second);
            auto it = last.find(kv.first);
            if (it == last.end() || it->second != k) {
                EMF_LOG(kMod, "names: '%s' (0x%016llX) %s in the server's table (%u names)", kv.first.c_str(),
                        (unsigned long long)kv.second, k > 0 ? "is" : (k < 0 ? "?? (table unreadable)" : "is NO LONGER"),
                        *(uint32_t*)(static_cast<uint8_t*>(sysw) + 0x1e4));
                last[kv.first] = k;
            }
        }
    }
    static const std::wstring file = names_file();
    WIN32_FILE_ATTRIBUTE_DATA fa{};
    if (!GetFileAttributesExW(file.c_str(), GetFileExInfoStandard, &fa)) return;
    if (CompareFileTime(&fa.ftLastWriteTime, &g_names_seen) == 0) return;
    FILE* f = _wfopen(file.c_str(), L"rb");
    if (!f) return;
    std::vector<std::string> names;
    char line[512];
    while (std::fgets(line, sizeof line, f)) {
        std::string s(line);
        while (!s.empty() && (s.back() == '\n' || s.back() == '\r')) s.pop_back();
        if (!s.empty() && s.size() <= 0xff) names.push_back(s);
    }
    std::fclose(f);
    g_names_seen = fa.ftLastWriteTime;
    auto* base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto* fnp = base + kSetStringRva;
    void* sys = w.singleton("CustomPlayerStringsSystem");
    static bool said_build = false;
    if (std::memcmp(fnp, kSetStringStart, sizeof(kSetStringStart)) != 0) {
        if (!said_build) EMF_LOG(kMod, "names: setString is not at +0x%llx in this game build: no names", (unsigned long long)kSetStringRva);
        said_build = true;
        return;
    }
    if (!sys) { EMF_LOG(kMod, "names: no CustomPlayerStringsSystem"); return; }
    for (const auto& n : names) {
        if (g_names_done.count(n)) continue;
        const uint64_t want = fnv1a64(n);
        const int before = name_known(sys, want);
        if (before < 0) {
            EMF_LOG(kMod, "names: the server's name table does not look as expected (%p): '%s' not registered", sys, n.c_str());
            g_names_done[n] = 0;
            continue;
        }
        uint64_t key = 0;
        const int r = set_string_guarded(reinterpret_cast<SetStringFn>(fnp), sys, n.data(), n.size(), &key);
        g_names_done[n] = key;
        EMF_LOG(kMod, "names: '%s' %s (key 0x%016llX, expected 0x%016llX, was %s, now %s, %u names)", n.c_str(),
                r > 0 ? "registered" : (r < 0 ? "FAULTED (caught)" : "refused"), (unsigned long long)key,
                (unsigned long long)want, before ? "there" : "new", name_known(sys, want) > 0 ? "there" : "MISSING",
                *(uint32_t*)(static_cast<uint8_t*>(sys) + 0x1e4));
    }
}
// ---- (owner 2026-11-20 12:12 "N1's chest spawned in the air... can you make that stay on the ground..?") ----
// FlameKit (Lua) asks for the ground under the places its companion chest could go: chest_ground.request, a line
// "<key> <x> <y> <z>" each (metres); from the step's program (the ray needs its context) each is one ray straight down
// from y + 1.5 to y - 8 (do_ground's settings: mask 0x9, flags 0x100, byte 1, as fkprobe.ground and the walk test) and
// the answer goes to chest_ground.answer: "<key> <hit y>" or "<key> none". The request file is removed once answered.
void do_chest_ground(emf::World w, void* ctx) {
    if (w.tick() % 3 != 0) return;
    static const std::wstring req = flamekit_file(L"chest_ground.request");
    static const std::wstring ans = flamekit_file(L"chest_ground.answer");
    FILE* f = _wfopen(req.c_str(), L"rb");
    if (!f) return;
    struct Ask { std::string key; double x, y, z; };
    std::vector<Ask> asks;
    char line[256];
    while (std::fgets(line, sizeof line, f)) {
        char key[64] = {};
        double x, y, z;
        if (std::sscanf(line, "%63s %lf %lf %lf", key, &x, &y, &z) == 4) asks.push_back({key, x, y, z});
    }
    std::fclose(f);
    DeleteFileW(req.c_str());
    auto* base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto* fnp = base + kRayCastRva;
    void* col = w.singleton("ecs::ColliderSystem");
    void* vox = w.singleton("ecs::VoxelGrid");
    const bool can = std::memcmp(fnp, kRayCastStart, sizeof(kRayCastStart)) == 0 && col && vox;
    std::string out;
    for (const Ask& a : asks) {
        float hit[3] = {0, 0, 0};
        int r = -2;
        if (can) {
            const float from[3] = {(float)a.x, (float)(a.y + 1.5), (float)a.z};
            const float to[3] = {(float)a.x, (float)(a.y - 8.0), (float)a.z};
            r = ray_cast_guarded(reinterpret_cast<RayCastFn>(fnp), ctx, col, vox, from, to, hit, 0x9u, 0x100, 1);
        }
        char buf[128];
        if (r > 0) std::snprintf(buf, sizeof buf, "%s %.3f\n", a.key.c_str(), hit[1]);
        else std::snprintf(buf, sizeof buf, "%s none\n", a.key.c_str());
        out += buf;
        EMF_LOG(kMod, "chest ground: %s at %.1f %.1f %.1f: %s", a.key.c_str(), a.x, a.y, a.z,
                r > 0 ? (std::string("ground at ") + std::to_string(hit[1])).c_str() : r == -2 ? "no ray cast in this build" : r < 0 ? "ray FAULTED" : "no ground");
    }
    const std::wstring tmp = ans + L".tmp";
    if (FILE* o = _wfopen(tmp.c_str(), L"wb")) {
        std::fwrite(out.data(), 1, out.size(), o);
        std::fclose(o);
        MoveFileExW(tmp.c_str(), ans.c_str(), MOVEFILE_REPLACE_EXISTING);
    }
}
}  // namespace

extern "C" __declspec(dllexport) bool emf_mod_load(const EmfApi* api) {
    if (!emf::init(api)) return false;
    // option 2: the hook after the steering step, and the driven list refreshed after each server step
    const bool hooked = emf::api()->hook_program && emf::api()->hook_program("steering_locomotion", nullptr, drive_post, nullptr);
    EMF_LOG(kMod, "drive: hook after steering_locomotion %s", hooked ? "installed" : "NOT installed");
    // (2026-11-20 14:22) pets' E: their offer set right before interaction_offer, checked after it (pet_offers)
    const bool offers = emf::api()->hook_program("interaction_offer", pet_offers_pre, pet_offers_post, nullptr);
    EMF_LOG(kMod, "pets: hook on interaction_offer %s", offers ? "installed" : "NOT installed");
    // (14:32) and wherever the game may put its own back before a press is checked
    const bool taming = emf::api()->hook_program("interaction_taming", nullptr, pet_offers_taming, nullptr);
    const bool attempt = emf::api()->hook_program("interaction_attempt", pet_offers_attempt, nullptr, nullptr);
    EMF_LOG(kMod, "pets: hook after interaction_taming %s, before interaction_attempt %s", taming ? "installed" : "NOT installed",
            attempt ? "installed" : "NOT installed");
    emf::on_tick([](emf::World w) { drive_scan(w); });
    emf::on_tick([](emf::World w) { if (w.is_server()) names_tick(w); });  // (2026-11-20) companion chest names
    emf::add_command("fkprobe.drive", ": option 2 drive status", [](emf::World w, const std::vector<std::string>&) {
        size_t n;
        { std::lock_guard<std::mutex> lk(g_drive_mx); n = g_driven.size(); }
        EMF_LOG(kMod, "drive: %zu driven, %llu writes", n, (unsigned long long)g_drive_writes.load());
        EMF_REPLY("drive: %zu driven, %llu writes", n, (unsigned long long)g_drive_writes.load());
    });
    emf::add_command("fkprobe.bite", "<entity> [sequence id hex, default 63fe3237]: start one attack sequence (test)",
                     [](emf::World w, const std::vector<std::string>& args) {
                         if (args.size() < 2) { EMF_REPLY("usage: fkprobe.bite <entity> [sequence hex]"); return; }
                         const uint32_t id = (uint32_t)std::strtoul(args[1].c_str(), nullptr, 0);
                         const uint32_t seq = args.size() > 2 ? (uint32_t)std::strtoul(args[2].c_str(), nullptr, 16) : 0x63FE3237u;
                         { std::lock_guard<std::mutex> lk(g_bite_mx); g_bites.emplace_back(id, seq); }
                         EMF_REPLY("bite %u: %08x queued", id, seq);
                     });
    emf::add_command("fkprobe.face", "<entity> <target> [seconds, default 5]: the entity looks at the target (attack test)",
                     [](emf::World w, const std::vector<std::string>& args) {
                         if (args.size() < 3) { EMF_REPLY("usage: fkprobe.face <entity> <target> [seconds]"); return; }
                         const uint32_t id = (uint32_t)std::strtoul(args[1].c_str(), nullptr, 0);
                         const uint32_t tg = (uint32_t)std::strtoul(args[2].c_str(), nullptr, 0);
                         const double sec = args.size() > 3 ? std::strtod(args[3].c_str(), nullptr) : 5.0;
                         const int64_t until = w.ecs_time_ns() + (int64_t)(sec * 1e9);
                         { std::lock_guard<std::mutex> lk(g_face_mx); g_face[id] = FaceTarget{tg, until}; }
                         EMF_LOG(kMod, "face: %u looks at %u for %.1f s", id, tg, sec);
                         EMF_REPLY("face %u -> %u for %.1f s", id, tg, sec);
                     });
    emf::add_command("fkprobe.ground", "<x> <z> <y top> <y bottom> [mask hex] [flags hex] [byte33]: one ray cast straight down, logs the ground hit (test)",
                     [](emf::World, const std::vector<std::string>& args) {
                         if (args.size() < 5) { EMF_REPLY("usage: fkprobe.ground <x> <z> <y top> <y bottom>"); return; }
                         GroundAsk a{std::strtod(args[1].c_str(), nullptr), std::strtod(args[2].c_str(), nullptr),
                                     std::strtod(args[3].c_str(), nullptr), std::strtod(args[4].c_str(), nullptr),
                                     args.size() > 5 ? (uint32_t)std::strtoul(args[5].c_str(), nullptr, 16) : 0x9u,
                                     args.size() > 6 ? (uint16_t)std::strtoul(args[6].c_str(), nullptr, 16) : (uint16_t)0x100,
                                     args.size() > 7 ? (uint8_t)std::strtoul(args[7].c_str(), nullptr, 10) : (uint8_t)1};
                         { std::lock_guard<std::mutex> lk(g_ground_mx); g_ground.push_back(a); }
                         EMF_REPLY("ground %.1f %.1f queued", a.x, a.z);
                     });
    // (21:57) our own step in the game loop, registered with the walkable-ground map (and the collision and terrain
    // grids): the walkable search answered "not ready" forever when called from the steering hook.
    const bool prog = emf::add_program("fk_ground_probe", EMF_WORLD_SERVER, {}, {},
        {"ecs::PathGridSystem", "ecs::ColliderSystem", "ecs::VoxelGrid"}, {}, [](void* ctx) {
            emf::World w = emf::server_world();
            if (!w) return;
            void* pg = emf::program_singleton(ctx, "ecs::PathGridSystem");
            static bool once = false;
            if (!once) {
                once = true;
                EMF_LOG(kMod, "ground program: PathGridSystem %p (world %p), ColliderSystem %p (world %p), VoxelGrid %p (world %p)",
                        pg, w.singleton("ecs::PathGridSystem"), emf::program_singleton(ctx, "ecs::ColliderSystem"),
                        w.singleton("ecs::ColliderSystem"), emf::program_singleton(ctx, "ecs::VoxelGrid"), w.singleton("ecs::VoxelGrid"));
            }
            if (pg) do_walk(w, ctx, pg);
            do_chest_ground(w, ctx);  // (2026-11-20 12:12) the companion chest on the ground
        });
    EMF_LOG(kMod, "ground program %s", prog ? "registered" : "NOT registered");
    emf::add_command("fkprobe.ahead", "on|off: log the ground 1, 2, 3 m ahead of each driven companion (measuring)",
                     [](emf::World, const std::vector<std::string>& args) {
                         g_ahead = args.size() > 1 && args[1] == "on";
                         EMF_REPLY("ahead %s", g_ahead.load() ? "on" : "off");
                     });
    emf::add_command("fkprobe.jump", "<entity> <mode 1 external | 2 sequence> [jump type, default 1]: jump test",
                     [](emf::World, const std::vector<std::string>& args) {
                         if (args.size() < 3) { EMF_REPLY("usage: fkprobe.jump <entity> <1|2> [type]"); return; }
                         JumpAsk j{(uint32_t)std::strtoul(args[1].c_str(), nullptr, 0), (int)std::strtol(args[2].c_str(), nullptr, 10),
                                   (uint8_t)(args.size() > 3 ? std::strtoul(args[3].c_str(), nullptr, 10) : 1)};
                         { std::lock_guard<std::mutex> lk(g_jump_mx); g_jumps.push_back(j); }
                         EMF_REPLY("jump %u mode %d type %u queued", j.id, j.mode, j.type);
                     });
    emf::add_command("fkprobe.walk", "<x> <y> <z> [layer, -1 = the world's] [player 0/1]: the game's walkable-ground search near that point (test)",
                     [](emf::World, const std::vector<std::string>& args) {
                         if (args.size() < 4) { EMF_REPLY("usage: fkprobe.walk <x> <y> <z>"); return; }
                         WalkAsk a{{(float)std::strtod(args[1].c_str(), nullptr), (float)std::strtod(args[2].c_str(), nullptr),
                                    (float)std::strtod(args[3].c_str(), nullptr)}, 0,
                                   args.size() > 4 ? (int)std::strtol(args[4].c_str(), nullptr, 10) : -1,
                                   args.size() > 5 ? (int)std::strtol(args[5].c_str(), nullptr, 10) : 0};
                         { std::lock_guard<std::mutex> lk(g_walk_mx); g_walk.push_back(a); }
                         EMF_REPLY("walk %.1f %.1f %.1f queued", a.p[0], a.p[1], a.p[2]);
                     });
    EMF_LOG(kMod, "loaded (drive, bite, facing, ground ray and walkable search tests, chest names; commands: fkprobe.drive, fkprobe.bite, fkprobe.face, fkprobe.ground, fkprobe.walk)");
    return true;
}
