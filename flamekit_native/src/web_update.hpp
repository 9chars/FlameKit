// web_update.hpp: FlameKit updates itself from its own repository on GitHub.
//
// A thread looks at the repository 15 seconds after the game starts and then every ten minutes (every minute on the
// test channel; and at once when the player asks, check_now). It first asks GitHub for the newest commit of main, through
// git's own address for that (https://github.com/9chars/FlameKit.git/info/refs, what every git clone uses: not cached),
// then reads https://raw.githubusercontent.com/9chars/FlameKit/<commit>/<channel>/update.txt and the files at that
// exact commit, which never change, so no cache can hand out an old copy. (Without the commit: main, as before.) The list has the version on its first line, then a line
// "<size> <hash> <path>" per file, the path as it lies under emf\mods (flamekit/core/bag.lua,
// flamekit_native/flamekit_native.dll). When the version is newer than what is installed, every file that differs is
// downloaded, checked against the list (size and FNV-1a hash), and only when all of them are right put in place. A new
// version changes nothing in the running game: everything switches together at the next game start.
//   this DLL (flamekit_native\): it is in use, so the old file is renamed and the new one takes over at the next start
//   the Lua part (flamekit\): held in emf\flamekit_update\ with a list (ready.txt); at the next start, before anything
//   else, this DLL checks the held files against the list and puts them in place (install_pending), mod.json last
// The channel is "dist", or "dist-test" where emf\mods\flamekit\update_channel.txt says "test" (the developer's PC).
// A game never takes an older version, and never writes outside emf\mods\flamekit and emf\mods\flamekit_native.
// What it is doing is written to emf\mods\flamekit\update_status.txt as "<kind>|<text>" (kind: busy, failed, ok or
// ready) for the lower left corner; empty while there is nothing to say.
#pragma once

#include <windows.h>
#include <winhttp.h>

#include <atomic>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace web_update {

inline uint32_t fnv(const std::vector<uint8_t>& data) {
    uint32_t h = 2166136261u;
    for (uint8_t b : data) h = (h ^ b) * 16777619u;
    return h;
}

inline bool read_file(const std::wstring& path, std::vector<uint8_t>& out) {
    out.clear();
    FILE* f = _wfsopen(path.c_str(), L"rb", _SH_DENYNO);
    if (!f) return false;
    uint8_t buf[65536];
    for (size_t got; (got = fread(buf, 1, sizeof buf, f)) > 0;) out.insert(out.end(), buf, buf + got);
    fclose(f);
    return true;
}

inline bool write_file(const std::wstring& path, const std::vector<uint8_t>& data) {
    const std::wstring tmp = path + L".upd";
    FILE* f = _wfsopen(tmp.c_str(), L"wb", _SH_DENYNO);
    if (!f) return false;
    const bool ok = data.empty() || fwrite(data.data(), 1, data.size(), f) == data.size();
    fclose(f);
    if (!ok || !MoveFileExW(tmp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING)) {
        DeleteFileW(tmp.c_str());
        return false;
    }
    return true;
}

// Makes every folder of `path` below `root` (both with backslashes).
inline void make_folders(const std::wstring& root, const std::wstring& path) {
    for (size_t i = root.size(); i < path.size(); ++i)
        if (path[i] == L'\\') CreateDirectoryW(path.substr(0, i).c_str(), nullptr);
}

inline std::wstring backslashes(std::wstring p) {
    for (wchar_t& c : p)
        if (c == L'/') c = L'\\';
    return p;
}

// "0.15.8" from a mod.json; empty when there is none.
inline std::string version_of(const std::wstring& mod_json) {
    std::vector<uint8_t> text;
    if (!read_file(mod_json, text)) return {};
    const std::string s(text.begin(), text.end());
    const size_t key = s.find("\"version\"");
    if (key == std::string::npos) return {};
    const size_t open = s.find('"', s.find(':', key));
    const size_t close = open == std::string::npos ? open : s.find('"', open + 1);
    if (close == std::string::npos) return {};
    return s.substr(open + 1, close - open - 1);
}

inline bool newer(const std::string& a, const std::string& b) {
    unsigned x[4] = {}, y[4] = {};
    if (sscanf(a.c_str(), "%u.%u.%u.%u", &x[0], &x[1], &x[2], &x[3]) < 1) return false;
    sscanf(b.c_str(), "%u.%u.%u.%u", &y[0], &y[1], &y[2], &y[3]);
    for (int i = 0; i < 4; ++i)
        if (x[i] != y[i]) return x[i] > y[i];
    return false;
}

// One file over HTTPS (from raw.githubusercontent.com unless `host` says otherwise); `got` counts the bytes as they arrive.
// Why the last fetch on this thread failed (for the log).
inline thread_local std::string g_fetch_error;

inline bool fetch(const std::wstring& path, std::vector<uint8_t>& out, std::atomic<uint64_t>* got, const wchar_t* host = L"raw.githubusercontent.com") {
    out.clear();
    bool ok = false;
    g_fetch_error = "no connection (WinHTTP error ";
    const HINTERNET session = WinHttpOpen(L"FlameKit", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session) return false;
    WinHttpSetTimeouts(session, 8000, 8000, 15000, 30000);
    const HINTERNET connect = WinHttpConnect(session, host, INTERNET_DEFAULT_HTTPS_PORT, 0);
    const HINTERNET request = connect ? WinHttpOpenRequest(connect, L"GET", path.c_str(), nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                                           WINHTTP_FLAG_SECURE | WINHTTP_FLAG_REFRESH)
                                      : nullptr;
    if (request && WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
        WinHttpReceiveResponse(request, nullptr)) {
        DWORD code = 0, len = sizeof code;
        WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &code, &len,
                            WINHTTP_NO_HEADER_INDEX);
        g_fetch_error = "the answer was HTTP " + std::to_string(code);
        if (code == 200) {
            ok = true;
            g_fetch_error = "the download broke off";
            for (;;) {
                DWORD avail = 0;
                if (!WinHttpQueryDataAvailable(request, &avail)) {
                    ok = false;
                    break;
                }
                if (avail == 0) break;
                const size_t at = out.size();
                if (at + avail > (16u << 20)) {  // no file of this mod is anywhere near 16 MB
                    ok = false;
                    break;
                }
                out.resize(at + avail);
                DWORD read = 0;
                if (!WinHttpReadData(request, out.data() + at, avail, &read)) {
                    ok = false;
                    break;
                }
                out.resize(at + read);
                if (got) got->fetch_add(read);
                if (read == 0) break;
            }
        }
    }
    if (g_fetch_error.rfind("no connection (WinHTTP error ", 0) == 0 && g_fetch_error.back() == ' ') g_fetch_error += std::to_string(GetLastError()) + ")";
    if (ok) g_fetch_error.clear();
    if (request) WinHttpCloseHandle(request);
    if (connect) WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    return ok;
}

struct File {
    uint32_t size = 0, hash = 0;
    std::string path;  // flamekit/core/bag.lua
    std::vector<uint8_t> data;
};

// Only letters, digits, _ - . and / , no "..", and inside one of the two folders.
inline bool safe(const std::string& p) {
    if (p.rfind("flamekit/", 0) != 0 && p.rfind("flamekit_native/", 0) != 0) return false;
    if (p.find("..") != std::string::npos || p.back() == '/') return false;
    for (char c : p)
        if (!(isalnum(static_cast<unsigned char>(c)) || c == '_' || c == '-' || c == '.' || c == '/')) return false;
    return true;
}

inline std::wstring wide(const std::string& s) { return std::wstring(s.begin(), s.end()); }

// emf\flamekit_update\ (next to emf\mods\): the Lua part of a new version, held until the next game start.
inline std::wstring pending_dir(const std::wstring& mods) {
    return mods.substr(0, mods.size() - 5) + L"flamekit_update\\";  // mods ends with "mods\\"
}

// At the game start, before anything else: the held Lua part of a new version, checked file by file against
// ready.txt and put in place (mod.json last). Anything that does not match is thrown away (it is downloaded again).
inline void install_pending(const std::wstring& mods, void (*log)(const char*)) {
    const std::wstring hold = pending_dir(mods);
    std::vector<uint8_t> raw;
    if (!read_file(hold + L"ready.txt", raw)) return;
    const std::string text(raw.begin(), raw.end());
    std::string version;
    struct Held {
        std::string path;
        std::vector<uint8_t> data;
    };
    std::vector<Held> files;
    bool good = true;
    size_t at = 0;
    for (size_t end; at < text.size(); at = end + 1) {
        end = text.find('\n', at);
        if (end == std::string::npos) end = text.size();
        const std::string line = text.substr(at, end - at);
        if (line.empty()) continue;
        if (version.empty()) {
            version = line;
            continue;
        }
        unsigned size = 0, hash = 0;
        char path[200] = "";
        if (sscanf(line.c_str(), "%u %x %199s", &size, &hash, path) != 3 || !safe(path)) {
            good = false;
            break;
        }
        Held h{path, {}};
        if (!read_file(backslashes(hold + wide(h.path)), h.data) || h.data.size() != size || fnv(h.data) != hash) {
            good = false;
            break;
        }
        files.push_back(std::move(h));
    }
    bool ok = good;
    for (int pass = 0; pass < 2 && ok; ++pass)  // mod.json last
        for (const Held& h : files)
            if (ok && (pass == 1) == (h.path == "flamekit/mod.json")) {
                const std::wstring local = backslashes(mods + wide(h.path));
                make_folders(mods, local);
                ok = write_file(local, h.data);
            }
    char msg[300];
    if (!good) snprintf(msg, sizeof msg, "update: the held v%s does not match its list: thrown away (it is downloaded again)", version.c_str());
    else if (!ok) snprintf(msg, sizeof msg, "update: install failed: v%s could not be put in place (error %lu): tried again at the next start", version.c_str(), GetLastError());
    else snprintf(msg, sizeof msg, "update: v%s put in place at the game start: %d file(s) of the Lua part", version.c_str(), static_cast<int>(files.size()));
    if (log) log(msg);
    if (ok || !good) {  // done, or useless: the held files go
        for (const Held& h : files) DeleteFileW(backslashes(hold + wide(h.path)).c_str());
        DeleteFileW((hold + L"ready.txt").c_str());
        WIN32_FIND_DATAW fd;  // the held folders, now empty (deepest first: a few passes)
        for (int pass = 0; pass < 8; ++pass) {
            std::vector<std::wstring> dirs{hold};
            for (size_t i = 0; i < dirs.size(); ++i) {
                HANDLE find = FindFirstFileW((dirs[i] + L"*").c_str(), &fd);
                if (find == INVALID_HANDLE_VALUE) continue;
                do
                    if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && wcscmp(fd.cFileName, L".") && wcscmp(fd.cFileName, L".."))
                        dirs.push_back(dirs[i] + fd.cFileName + L"\\");
                while (FindNextFileW(find, &fd));
                FindClose(find);
            }
            for (auto it = dirs.rbegin(); it != dirs.rend(); ++it) RemoveDirectoryW(it->c_str());
        }
    }
}

// The version held in emf\flamekit_update\ for the next start (ready.txt's first line); empty when none is held.
inline std::string held_version(const std::wstring& mods) {
    std::vector<uint8_t> raw;
    if (!read_file(pending_dir(mods) + L"ready.txt", raw)) return {};
    std::string v(raw.begin(), raw.end());
    v = v.substr(0, v.find('\n'));
    while (!v.empty() && (v.back() == '\r' || v.back() == ' ')) v.pop_back();
    return v;
}

// Throws the held Lua part away (its list first, so a half-cleared hold is never installed): before a newer version
// is held in its place.
inline void clear_pending(const std::wstring& mods) {
    const std::wstring hold = pending_dir(mods);
    std::vector<uint8_t> raw;
    if (!read_file(hold + L"ready.txt", raw)) return;
    DeleteFileW((hold + L"ready.txt").c_str());
    const std::string text(raw.begin(), raw.end());
    for (size_t at = text.find('\n'); at != std::string::npos && at + 1 < text.size();) {
        const size_t end = text.find('\n', at + 1);
        const std::string line = text.substr(at + 1, end == std::string::npos ? std::string::npos : end - at - 1);
        unsigned size = 0, hash = 0;
        char path[200] = "";
        if (sscanf(line.c_str(), "%u %x %199s", &size, &hash, path) == 3 && safe(path)) DeleteFileW(backslashes(hold + wide(path)).c_str());
        at = end;
    }
}

// The newest commit of main (40 hex digits), from git's reference list; empty when it could not be had.
inline std::string newest_commit() {
    std::vector<uint8_t> raw;
    if (!fetch(L"/9chars/FlameKit.git/info/refs?service=git-upload-pack", raw, nullptr, L"github.com")) return {};
    const std::string text(raw.begin(), raw.end());
    const size_t at = text.find(" refs/heads/main");
    if (at == std::string::npos || at < 40) return {};
    const std::string sha = text.substr(at - 40, 40);
    for (char c : sha)
        if (!std::isxdigit(static_cast<unsigned char>(c))) return {};
    return sha;
}

// Set by the "Check for updates" button: the updater looks at once.
inline std::atomic<bool> g_check_now{false};

struct Updater {
    std::wstring mods;     // ...\emf\mods\ (ends with a backslash)
    std::string last_status = "?";  // so the first status, even an empty one, is written: the file tells the panel this updater is here
    void (*log)(int level, const char* text) = nullptr;  // level: 0 what happens, 1 a detail, 2 a problem
    std::string last_seen;  // the version and commit of the last check (a repeated "up to date" is a detail)
    bool asked = false;     // this check was asked for with the button

    void status(const std::string& text) {
        if (text == last_status) return;
        last_status = text;
        write_file(mods + L"flamekit\\update_status.txt", std::vector<uint8_t>(text.begin(), text.end()));
    }
    void say(const std::string& text, int level = 0) {
        if (log) log(level, text.c_str());
    }

    // One look at the repository. Returns false when it could not be reached or the update failed.
    bool check() {
        std::vector<uint8_t> flag;
        const bool test = read_file(mods + L"flamekit\\update_channel.txt", flag) && flag.size() >= 4 && std::memcmp(flag.data(), "test", 4) == 0;
        const std::string commit = newest_commit();
        if (commit.empty()) say("update: the newest commit could not be read (" + g_fetch_error + "): main is used (may be a few minutes old)", 2);
        const std::wstring base = L"/9chars/FlameKit/" + (commit.empty() ? std::wstring(L"main") : wide(commit)) + (test ? L"/dist-test/" : L"/dist/");
        std::vector<uint8_t> raw;
        const std::string channel = test ? "dist-test" : "dist";
        if (!fetch(base + L"update.txt", raw, nullptr)) {
            say("update: check failed: could not read " + channel + "/update.txt from GitHub: " + g_fetch_error + " (tried again later)", 2);
            if (asked) status("failed|Could not reach GitHub: tried again later");
            return false;
        }
        const std::string text(raw.begin(), raw.end());
        const size_t eol = text.find('\n');
        if (eol == std::string::npos) {
            say("update: check failed: " + channel + "/update.txt has no version line", 2);
            return false;
        }
        std::string version = text.substr(0, eol);
        while (!version.empty() && (version.back() == '\r' || version.back() == ' ')) version.pop_back();
        const std::string have_lua = version_of(mods + L"flamekit\\mod.json"), have_map = version_of(mods + L"flamekit_native\\mod.json");
        const std::string held = held_version(mods);  // a version already downloaded, waiting for the next start
        if (!held.empty() && !newer(version, held)) {  // nothing newer than what waits
            say("update: checked " + channel + ": v" + version + " there, v" + held + " already waits for the next game start", last_seen == version ? 1 : 0);
            last_seen = version;
            status("ready|Update v" + held + " is ready: restart the game");
            return true;
        }
        if (held.empty() && !newer(version, have_lua) && !newer(version, have_map)) {  // up to date (or ahead of it)
            const std::string seen = version + " " + commit;
            say("update: checked " + channel + " at commit " + (commit.empty() ? std::string("main") : commit.substr(0, 7)) + ": v" + version +
                    " there, here v" + have_lua + " (Lua) and v" + have_map + " (native): up to date",
                seen == last_seen && !asked ? 1 : 0);
            last_seen = seen;
            if (asked) status("ok|FlameKit is up to date (v" + have_lua + ")");
            return true;
        }

        std::vector<File> files;
        for (size_t at = eol + 1; at < text.size();) {
            size_t end = text.find('\n', at);
            if (end == std::string::npos) end = text.size();
            std::string line = text.substr(at, end - at);
            at = end + 1;
            while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
            if (line.empty()) continue;
            File f;
            char path[200] = "";
            if (sscanf(line.c_str(), "%u %x %199s", &f.size, &f.hash, path) != 3 || !safe(path) || files.size() >= 200) {
                say("update: check failed: a line of " + channel + "/update.txt was refused: " + line, 2);
                return false;
            }
            f.path = path;
            files.push_back(std::move(f));
        }
        if (files.empty()) {
            say("update: check failed: " + channel + "/update.txt lists no files", 2);
            return false;
        }

        // only what differs from what is here (a file already held for an older waiting version is taken from the hold
        // when it is still the same, not downloaded again)
        std::vector<File*> want;
        uint64_t total = 0;
        for (File& f : files) {
            std::wstring local = mods + wide(f.path);
            for (wchar_t& c : local)
                if (c == L'/') c = L'\\';
            std::vector<uint8_t> here;
            if (read_file(local, here) && here.size() == f.size && fnv(here) == f.hash) continue;
            if (f.path.rfind("flamekit_native/", 0) != 0 && read_file(backslashes(pending_dir(mods) + wide(f.path)), here) && here.size() == f.size &&
                fnv(here) == f.hash) {
                f.data = std::move(here);  // already held, and the same
                want.push_back(&f);
                continue;
            }
            want.push_back(&f);
            total += f.size;
        }
        say("update: v" + version + " is there (here: v" + have_lua + " Lua, v" + have_map + " native): " + std::to_string(want.size()) +
            " file(s), " + std::to_string(total / 1024) + " KB");
        const DWORD started = GetTickCount();
        std::atomic<uint64_t> got{0};
        for (File* f : want) {
            if (!f->data.empty()) continue;  // taken from the hold
            status("busy|Downloading update v" + version + ": " + std::to_string(total ? got.load() * 100 / total : 100) + "%");
            if (!fetch(base + wide(f->path), f->data, &got) || f->data.size() != f->size || fnv(f->data) != f->hash) {
                say("update: download failed: " + f->path + " did not arrive as listed (" + (g_fetch_error.empty() ? std::string("wrong size or fingerprint") : g_fetch_error) + "): nothing was changed", 2);
                status("failed|Update v" + version + " failed: it is tried again later");
                return false;
            }
        }
        status("busy|Preparing update v" + version);

        // this DLL now (renamed aside, it is in use; used from the next start), the Lua part held for the next start
        const std::wstring hold = pending_dir(mods);
        if (!held.empty()) {
            say("update: v" + version + " replaces v" + held + ", which was waiting for the next game start");
            clear_pending(mods);
        }
        bool ok = true;
        std::string list = version + "\n";
        for (File* f : want) {
            if (!ok) break;
            const std::wstring local = backslashes(mods + wide(f->path));
            if (f->path.rfind("flamekit_native/", 0) == 0) {
                make_folders(mods, local);
                if (f->path == "flamekit_native/flamekit_native.dll") {
                    // The running DLL is either flamekit_native.dll (no update yet in this game) or, after an update
                    // in this game, flamekit_native.dll.old (in use, it cannot be deleted): then flamekit_native.dll is
                    // only a waiting new one and is simply replaced.
                    const bool old_runs = GetFileAttributesW((local + L".old").c_str()) != INVALID_FILE_ATTRIBUTES && !DeleteFileW((local + L".old").c_str());
                    if (old_runs) {
                        ok = write_file(local, f->data);
                        continue;
                    }
                    if (GetFileAttributesW(local.c_str()) != INVALID_FILE_ATTRIBUTES &&
                        !MoveFileExW(local.c_str(), (local + L".old").c_str(), MOVEFILE_REPLACE_EXISTING)) {
                        ok = false;
                        break;
                    }
                    if (!write_file(local, f->data)) {
                        MoveFileExW((local + L".old").c_str(), local.c_str(), MOVEFILE_REPLACE_EXISTING);
                        ok = false;
                    }
                } else {
                    ok = write_file(local, f->data);
                }
            } else {
                const std::wstring held = backslashes(hold + wide(f->path));
                make_folders(hold.substr(0, hold.size() - 1), held);
                ok = write_file(held, f->data);
                char line[260];
                snprintf(line, sizeof line, "%u %08x %s\n", f->size, f->hash, f->path.c_str());
                list += line;
            }
        }
        if (ok) ok = write_file(hold + L"ready.txt", std::vector<uint8_t>(list.begin(), list.end()));
        if (!ok) {
            say("update: install failed: a file could not be written (error " + std::to_string(GetLastError()) + ")", 2);
            status("failed|Update v" + version + " failed: it is tried again later");
            return false;
        }
        say("update: v" + version + " is ready, " + std::to_string(want.size()) + " file(s), " + std::to_string(total / 1024) + " KB in " +
            std::to_string((GetTickCount() - started) / 1000.0).substr(0, 4) + " s: it is used from the next game start");
        status("ready|Update v" + version + " is ready: restart the game");
        waiting_for_restart = true;
        return true;
    }

    bool waiting_for_restart = false;

    void run() {
        DeleteFileW((mods + L"flamekit_native\\flamekit_native.dll.old").c_str());  // the DLL an update replaced, now unused
        status("");
        Sleep(15000);
        uint64_t clear_at = 0;  // when a button answer ("up to date", "could not reach") goes away again
        for (;;) {
            asked = g_check_now.exchange(false);
            // Also while an update waits for the restart: a newer one then takes its place, so one restart always
            // brings the newest version (before 0.15.39 the updater stopped looking once one was waiting).
            if (asked) {
                say("update: check asked for with the button");
                status("busy|Checking for updates...");
            }
            check();
            if (asked && last_status.rfind("ready|", 0) != 0) clear_at = GetTickCount64() + 8000;
            // the next look: every minute on the test channel, every 10 minutes for players; the button cuts it short
            std::vector<uint8_t> flag;
            const bool test = read_file(mods + L"flamekit\\update_channel.txt", flag) && flag.size() >= 4 && std::memcmp(flag.data(), "test", 4) == 0;
            const uint64_t next = GetTickCount64() + (test ? 60ull : 600ull) * 1000;
            while (GetTickCount64() < next && !g_check_now.load()) {
                if (clear_at && GetTickCount64() >= clear_at) {
                    clear_at = 0;
                    if (last_status.rfind("ok|", 0) == 0 || last_status.rfind("failed|Could not reach", 0) == 0) status("");
                }
                Sleep(250);
            }
        }
    }
};

}  // namespace web_update
