// emf_update.hpp: FlameKit's updater also keeps EMF itself up to date (0.15.454; owner 2026-11-22 18:09 "expecting
// players to manually install a new version is mostly unacceptable", 18:14 "we need a pathway to support the latest
// version of EMF with our mod so we can stay on top of things", 18:26 "start building the updater for EMF").
//
// WHAT: the EMF version FlameKit was tested with lies in FlameKit's repository, in a channel folder of its own next to
// FlameKit's: emf-dist (players) and emf-dist-test (the developer's PC, update_channel.txt "test"), each with
//   emf.txt        "emf <version>" on the first line, then "<size> <sha256> <path>" per file, the path as it lies in the
//                  game folder (dinput8.dll, emf/emf_core.dll, emf/mods/lua/lua.dll)
//   emf.sig        the release key's signature of emf.txt's exact bytes (the same key and check as update.txt's)
//   files/<path>   the files themselves
// (flamekit_native/notes/make_emf_dist.py makes the folder from an EMF release package.) A list of its own on purpose:
// an older FlameKit refuses its whole update.txt when one line names a path outside its two folders, so EMF's files in
// update.txt would stop every older game from updating at all.
//
// WHEN: after each look at FlameKit's own list (every minute, web_update.hpp). EMF is changed only when the list's
// version is newer than the installed one (the FileVersion of emf\emf_core.dll): never to an older EMF, and a player who
// installed a newer EMF himself keeps it. Nothing is done when the installed version cannot be read, when the game's
// dinput8.dll is not EMF's own loader (a setup with another loader: EMF's installer handles those), or when the new EMF
// brings a Vulkan layer file that is not there yet (registering a layer is the installer's job).
//
// HOW: every file that differs is downloaded and checked (size and SHA-256) first; nothing changes before all of them
// are right. The files about to be replaced are copied to emf\flamekit_emf_backup\ with backup.txt (the version, then
// one path a line; "+<path>" for a file the update adds): the EMF from before the update, to go back by hand. Then file
// by file: the new one is written next to the old (<name>.emfnew), the old one renamed (<name>.emfold: a DLL or program
// in use can be renamed, not overwritten), and the new one put in its place. dinput8.dll goes last, as in EMF's own
// installer (a new core under the old loader works; the other way round may not). A failure puts every file changed so
// far back. The running game keeps the EMF it started with; the new one starts with the next game start, and the
// .emfold files are removed then. Never touched: emf\config (the player's settings), other mods in emf\mods (only EMF's
// Lua host, emf\mods\lua), FlameKit's own folders. A failed install is tried again 30 minutes later, not every minute.
// The dedicated server never runs the updater (flamekit_native.cpp): a server's EMF is updated by its admin.
//
// Included by web_update.hpp (it uses that file's helpers). Tested by flamekit_native/tests/emf_update_test.cpp, which
// build.cmd builds and runs after every build.
#pragma once

#include <algorithm>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace emf_update {

// SHA-256 of the bytes as 64 lowercase hex digits; empty when Windows' bcrypt cannot make it.
inline std::string sha256_hex(const std::vector<uint8_t>& data) {
    uint8_t digest[32];
    BCRYPT_ALG_HANDLE alg = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    const bool ok = BCRYPT_SUCCESS(BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0)) &&
                    BCRYPT_SUCCESS(BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0)) &&
                    BCRYPT_SUCCESS(BCryptHashData(hash, const_cast<PUCHAR>(data.data()), static_cast<ULONG>(data.size()), 0)) &&
                    BCRYPT_SUCCESS(BCryptFinishHash(hash, digest, sizeof digest, 0));
    if (hash) BCryptDestroyHash(hash);
    if (alg) BCryptCloseAlgorithmProvider(alg, 0);
    if (!ok) return {};
    static const char* hex = "0123456789abcdef";
    std::string out;
    for (uint8_t b : digest) {
        out += hex[b >> 4];
        out += hex[b & 15];
    }
    return out;
}

// A text of a file's version resource (key "FileVersion" or "ProductName") as the file on disk says it; empty when it has
// none. (0.15.456) Read from the file's bytes: Windows' GetFileVersionInfo answers for a DLL that is loaded (emf_core.dll
// in the game) with the loaded copy, so after an update it still named the running EMF, not the one on disk (seen in the
// game 18:54: "v0.6.6 here" with 0.6.19 already in place). The value follows its key's UTF-16 name and the padding to
// the next 4-byte boundary. Cached by size and modification time, so a check reads the file only when it changed.
inline std::string version_string(const std::wstring& path, const wchar_t* key) {
    WIN32_FILE_ATTRIBUTE_DATA fa{};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &fa)) return {};
    struct Cached {
        std::wstring path, key;
        uint64_t size = 0, time = 0;
        std::string value;
    };
    static std::mutex mx;
    static std::vector<Cached> cache;
    const uint64_t size = (uint64_t(fa.nFileSizeHigh) << 32) | fa.nFileSizeLow;
    const uint64_t time = (uint64_t(fa.ftLastWriteTime.dwHighDateTime) << 32) | fa.ftLastWriteTime.dwLowDateTime;
    {
        std::lock_guard<std::mutex> l(mx);
        for (const Cached& c : cache)
            if (c.path == path && c.key == key && c.size == size && c.time == time) return c.value;
    }
    std::string out;
    std::vector<uint8_t> data;
    if (size <= (64u << 20) && web_update::read_file(path, data)) {
        std::vector<uint8_t> name;
        for (const wchar_t* k = key; *k; ++k) {
            name.push_back(static_cast<uint8_t>(*k & 0xff));
            name.push_back(static_cast<uint8_t>(*k >> 8));
        }
        name.push_back(0);
        name.push_back(0);
        for (size_t at = 0; out.empty() && at + name.size() < data.size();) {
            const auto hit = std::search(data.begin() + at, data.end(), name.begin(), name.end());
            if (hit == data.end()) break;
            size_t v = static_cast<size_t>(hit - data.begin()) + name.size();
            at = v;
            while (v % 4) ++v;  // the value starts on a 4-byte boundary
            std::string text;
            for (; v + 1 < data.size() && text.size() < 128; v += 2) {
                const uint16_t c = static_cast<uint16_t>(data[v] | (data[v + 1] << 8));
                if (c == 0) break;
                text += c < 128 ? static_cast<char>(c) : '?';
            }
            while (!text.empty() && text.back() == ' ') text.pop_back();
            if (!text.empty()) out = text;
        }
    }
    std::lock_guard<std::mutex> l(mx);
    for (Cached& c : cache)
        if (c.path == path && c.key == key) {
            c.size = size, c.time = time, c.value = out;
            return out;
        }
    if (cache.size() < 16) cache.push_back({path, key, size, time, out});
    return out;
}

// What every file of EMF says it belongs to (its version resource's ProductName): EMF's loader and core say so.
inline constexpr const char* kEmfProduct = "EMF (Enshrouded Modding Framework)";

// Whether `p` (a path from emf.txt, below the game folder) may be written: only letters, digits, _ - . and /, no "..",
// and either the loader (dinput8.dll) or a file of EMF in emf/, but never the player's settings (emf/config), another
// mod (emf/mods/ except EMF's Lua host, emf/mods/lua) or FlameKit's own folders (emf/flamekit*).
inline bool allowed(const std::string& p) {
    if (p.empty() || p.size() > 180 || p.front() == '/' || p.back() == '/' || p.find("..") != std::string::npos || p.find("//") != std::string::npos)
        return false;
    for (char c : p)
        if (!(isalnum(static_cast<unsigned char>(c)) || c == '_' || c == '-' || c == '.' || c == '/')) return false;
    std::string low = p;
    for (char& c : low) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
    if (low == "dinput8.dll") return true;
    if (low.rfind("emf/", 0) != 0) return false;
    if (low.rfind("emf/config/", 0) == 0 || low.rfind("emf/flamekit", 0) == 0) return false;
    if (low.rfind("emf/mods/", 0) == 0) return low.rfind("emf/mods/lua/", 0) == 0;
    const size_t dot = low.find_last_of('.');
    if (dot != std::string::npos && (low.substr(dot) == ".emfold" || low.substr(dot) == ".emfnew")) return false;  // the update's own names
    return true;
}

// (0.15.455) The EMF version put in place in this session (waiting for the next start), for the About tab; empty when none.
inline std::mutex g_ready_mx;
inline std::string g_ready;
inline std::string ready_version() {
    std::lock_guard<std::mutex> l(g_ready_mx);
    return g_ready;
}

// One file of the list.
struct Entry {
    uint32_t size = 0;
    std::string sha;   // 64 lowercase hex digits
    std::string path;  // below the game folder, with /
    std::vector<uint8_t> data;
};

// Reads emf.txt: "emf <version>", then "<size> <sha256> <path>" per line (at most 128, each at most 16 MB, every path
// allowed and listed once, emf/emf_core.dll among them). False with `why` when anything in it is wrong.
inline bool parse(const std::string& text, std::string& version, std::vector<Entry>& out, std::string& why) {
    version.clear();
    out.clear();
    bool core = false;
    for (size_t at = 0; at < text.size();) {
        size_t end = text.find('\n', at);
        if (end == std::string::npos) end = text.size();
        std::string line = text.substr(at, end - at);
        at = end + 1;
        while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
        if (line.empty()) continue;
        if (version.empty()) {
            if (line.rfind("emf ", 0) != 0 || line.size() < 5 || line.size() > 27 || line.find_first_not_of("0123456789.", 4) != std::string::npos) {
                why = "the first line is not \"emf <version>\": " + line;
                return false;
            }
            version = line.substr(4);
            continue;
        }
        Entry e;
        char sha[80] = "", path[200] = "";
        if (sscanf(line.c_str(), "%u %79s %199s", &e.size, sha, path) != 3 || strlen(sha) != 64 ||
            std::string(sha).find_first_not_of("0123456789abcdef") != std::string::npos) {
            why = "a line is not \"<size> <sha256> <path>\": " + line;
            return false;
        }
        if (!allowed(path)) {
            why = std::string("a path that EMF's update may not write: ") + path;
            return false;
        }
        if (e.size > (16u << 20)) {
            why = std::string("a file over 16 MB: ") + path;
            return false;
        }
        e.sha = sha;
        e.path = path;
        for (const Entry& o : out)
            if (_stricmp(o.path.c_str(), e.path.c_str()) == 0) {
                why = "a path listed twice: " + e.path;
                return false;
            }
        if (_stricmp(path, "emf/emf_core.dll") == 0) core = true;
        out.push_back(std::move(e));
        if (out.size() > 128) {
            why = "more than 128 files";
            return false;
        }
    }
    if (version.empty()) why = "the list is empty";
    else if (!core) why = "emf/emf_core.dll is not in the list";
    return !version.empty() && core;
}

// Whether a file or folder is there.
inline bool exists(const std::wstring& path) { return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES; }

// EMF's own update: see the top of this file.
struct Emf {
    std::wstring game;  // the game folder (ends with a backslash)
    // a file of the repository: `path` below the host ("/9chars/FlameKit/<commit>/emf-dist/emf.txt"); false with `why`
    std::function<bool(const std::wstring& path, std::vector<uint8_t>& out, std::string& why)> get;
    // whether `sig` (128 hex digits) is the release key's signature of `data` (web_update::signed_by_release_key)
    std::function<bool(const std::vector<uint8_t>& data, const std::string& sig, std::string& why)> verify;
    std::function<void(int level, const std::string& text)> say;  // level: 0 what happens, 1 a detail, 2 a problem

    std::string ready;        // the EMF version put in place in this session, starting with the next game start
    std::string checked;      // emf.txt as last read with a good signature: the same list is not checked again
    std::string last_note;    // the last "nothing to do" line (said again only as a detail)
    std::string failed_list;  // the list whose install failed, and until when it is not tried again
    uint64_t retry_at = 0;

    void note(int level, const std::string& text) {
        if (say) say(level, text);
    }
    // A "nothing to do" line: a problem or news the first time, a detail when it repeats.
    void nothing(int level, const std::string& text) {
        note(text == last_note ? 1 : level, text);
        last_note = text;
    }
    std::wstring local(const std::string& path) const { return game + web_update::backslashes(web_update::wide(path)); }
    std::wstring backup_dir() const { return game + L"emf\\flamekit_emf_backup\\"; }

    // At the game start: removes what an earlier update left next to EMF's files (every <name>.emfold, the old files
    // the last game ran with, and any <name>.emfnew) in the game folder's dinput8.dll and in emf\ (not emf\config, not
    // the backup). Logs which EMF this game runs.
    void clean_up() {
        int removed = 0;
        for (const wchar_t* tail : {L".emfold", L".emfnew"})
            if (DeleteFileW((game + L"dinput8.dll" + tail).c_str())) ++removed;
        std::vector<std::wstring> dirs{game + L"emf\\"};
        for (size_t i = 0; i < dirs.size() && i < 2000; ++i) {
            WIN32_FIND_DATAW fd;
            const HANDLE find = FindFirstFileW((dirs[i] + L"*").c_str(), &fd);
            if (find == INVALID_HANDLE_VALUE) continue;
            do {
                const std::wstring name = fd.cFileName;
                if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                    if (name != L"." && name != L".." && !(i == 0 && (_wcsicmp(name.c_str(), L"config") == 0 || _wcsicmp(name.c_str(), L"flamekit_emf_backup") == 0)))
                        dirs.push_back(dirs[i] + name + L"\\");
                    continue;
                }
                const size_t n = name.size();
                if (n > 7 && (_wcsicmp(name.c_str() + n - 7, L".emfold") == 0 || _wcsicmp(name.c_str() + n - 7, L".emfnew") == 0) &&
                    DeleteFileW((dirs[i] + name).c_str()))
                    ++removed;
            } while (FindNextFileW(find, &fd));
            FindClose(find);
        }
        const std::string have = version_string(game + L"emf\\emf_core.dll", L"FileVersion");
        note(0, "update (EMF): this game runs EMF v" + (have.empty() ? std::string("?") : have) +
                    (removed ? " (" + std::to_string(removed) + " file(s) left by an EMF update removed)" : ""));
    }

    // One look at the EMF list below `root` ("/9chars/FlameKit/<commit>/emf-dist/"). 1: a new EMF was put in place (it
    // starts with the next game start); 0: nothing to do now; -1: the list was refused or the install failed.
    int check(const std::wstring& root) {
        std::vector<uint8_t> raw;
        std::string why;
        if (!get(root + L"emf.txt", raw, why)) {
            nothing(1, "update (EMF): no EMF list to read (" + why + "): EMF stays as it is");
            return 0;
        }
        const std::string text(raw.begin(), raw.end());
        if (text != checked) {  // a list not seen yet: its signature first
            std::vector<uint8_t> sig;
            if (!get(root + L"emf.sig", sig, why)) why = "there is no emf.sig (" + why + ")";
            else if (verify(raw, std::string(sig.begin(), sig.end()), why)) why.clear();
            if (!why.empty()) {
                nothing(2, "update (EMF): REFUSED: emf.txt is not signed by FlameKit's release key: " + why + ". Nothing was changed.");
                return -1;
            }
            checked = text;
        }
        std::string version;
        std::vector<Entry> files;
        if (!parse(text, version, files, why)) {
            nothing(2, "update (EMF): REFUSED: emf.txt: " + why + ". Nothing was changed.");
            return -1;
        }
        const std::string have = version_string(game + L"emf\\emf_core.dll", L"FileVersion");
        if (have.empty()) {
            nothing(2, "update (EMF): the installed EMF's version cannot be read (emf\\emf_core.dll): EMF is left alone");
            return 0;
        }
        if (!web_update::newer(version, have)) {
            nothing(0, "update (EMF): EMF v" + version + " in the list, v" + have + " here: nothing to do");
            return 0;
        }
        if (version_string(game + L"dinput8.dll", L"ProductName") != kEmfProduct) {
            nothing(0, "update (EMF): the game's dinput8.dll is not EMF's own loader (another loader starts EMF here): EMF v" + version +
                           " is not installed by FlameKit; EMF's own installer can do it");
            return 0;
        }
        for (const Entry& e : files) {
            std::string low = e.path;
            for (char& c : low) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
            if (low.rfind("emf/vk/", 0) == 0 && !exists(local(e.path))) {
                nothing(0, "update (EMF): EMF v" + version + " brings a new Vulkan layer (" + e.path + "), which only EMF's own installer can set up: not installed by FlameKit");
                return 0;
            }
        }
        if (text == failed_list && GetTickCount64() < retry_at) return 0;  // failed a moment ago: later again

        // what differs from what is here, downloaded and checked first
        std::vector<Entry*> want;
        uint64_t total = 0;
        for (Entry& e : files) {
            std::vector<uint8_t> here;
            if (web_update::read_file(local(e.path), here) && here.size() == e.size && sha256_hex(here) == e.sha) continue;
            want.push_back(&e);
            total += e.size;
        }
        if (want.empty()) {
            nothing(1, "update (EMF): EMF v" + version + " in the list, v" + have + " here, but every file is already the same: nothing to do");
            return 0;
        }
        note(0, "update (EMF): EMF v" + version + " is there (here: v" + have + "): " + std::to_string(want.size()) + " file(s), " +
                    std::to_string(total / 1024) + " KB");
        const auto fail = [&](const std::string& what) {
            note(2, "update (EMF): " + what);
            failed_list = text;
            retry_at = GetTickCount64() + 30ull * 60 * 1000;
            return -1;
        };
        for (Entry* e : want) {
            if (!get(root + L"files/" + web_update::wide(e->path), e->data, why))
                return fail("download failed: " + e->path + " (" + why + "): nothing was changed; tried again in 30 minutes");
            if (e->data.size() != e->size || sha256_hex(e->data) != e->sha)
                return fail("download failed: " + e->path + " did not arrive as listed (size or SHA-256): nothing was changed; tried again in 30 minutes");
        }

        // the files about to be replaced: copied to emf\flamekit_emf_backup\ (the backup before: its list first, then its files)
        const std::wstring bdir = backup_dir();
        {
            std::vector<uint8_t> old_list;
            if (web_update::read_file(bdir + L"backup.txt", old_list)) {
                DeleteFileW((bdir + L"backup.txt").c_str());
                const std::string t(old_list.begin(), old_list.end());
                for (size_t at = t.find('\n'); at != std::string::npos && at + 1 < t.size();) {
                    const size_t end = t.find('\n', at + 1);
                    std::string path = t.substr(at + 1, end == std::string::npos ? std::string::npos : end - at - 1);
                    at = end;
                    while (!path.empty() && (path.back() == '\r' || path.back() == ' ')) path.pop_back();
                    if (!path.empty() && path[0] != '+' && allowed(path)) DeleteFileW((bdir + web_update::backslashes(web_update::wide(path))).c_str());
                }
            }
        }
        std::string blist = "emf " + have + "\n";
        for (Entry* e : want) {
            std::vector<uint8_t> old;
            if (!exists(local(e->path))) {
                blist += "+" + e->path + "\n";
                continue;
            }
            const std::wstring copy = bdir + web_update::backslashes(web_update::wide(e->path));
            web_update::make_folders(game + L"emf", copy);
            if (!web_update::read_file(local(e->path), old) || !web_update::write_file(copy, old))
                return fail("could not copy " + e->path + " to emf\\flamekit_emf_backup (error " + std::to_string(GetLastError()) +
                            "): nothing was changed; tried again in 30 minutes");
            blist += e->path + "\n";
        }
        if (!web_update::write_file(bdir + L"backup.txt", std::vector<uint8_t>(blist.begin(), blist.end())))
            return fail("could not write emf\\flamekit_emf_backup\\backup.txt: nothing was changed; tried again in 30 minutes");

        // file by file, dinput8.dll last; a failure puts back what was changed
        std::vector<Entry*> order;
        for (Entry* e : want)
            if (_stricmp(e->path.c_str(), "dinput8.dll") != 0) order.push_back(e);
        for (Entry* e : want)
            if (_stricmp(e->path.c_str(), "dinput8.dll") == 0) order.push_back(e);
        struct Done {
            Entry* e;
            bool had;     // there was a file before
            bool direct;  // the file was replaced in place (the one the game runs is already <name>.emfold)
        };
        std::vector<Done> done;
        std::string error;
        for (Entry* e : order) {
            const std::wstring dst = local(e->path), tmp = dst + L".emfnew", old = dst + L".emfold";
            web_update::make_folders(game, dst);
            if (!web_update::write_file(tmp, e->data)) {
                error = "could not write " + e->path + ".emfnew (error " + std::to_string(GetLastError()) + ")";
                break;
            }
            const bool had = exists(dst);
            // an <name>.emfold that cannot be removed is in use: an update earlier in this game renamed the running file
            // there, so `dst` is only a waiting new file and is replaced in place
            const bool direct = had && exists(old) && !DeleteFileW(old.c_str());
            if (had && !direct && !MoveFileExW(dst.c_str(), old.c_str(), MOVEFILE_REPLACE_EXISTING)) {
                error = "could not rename " + e->path + " (error " + std::to_string(GetLastError()) + ")";
                DeleteFileW(tmp.c_str());
                break;
            }
            if (!MoveFileExW(tmp.c_str(), dst.c_str(), MOVEFILE_REPLACE_EXISTING)) {
                error = "could not put " + e->path + " in place (error " + std::to_string(GetLastError()) + ")";
                if (had && !direct) MoveFileExW(old.c_str(), dst.c_str(), MOVEFILE_REPLACE_EXISTING);
                DeleteFileW(tmp.c_str());
                break;
            }
            done.push_back({e, had, direct});
        }
        if (!error.empty()) {
            int back = 0;
            for (auto it = done.rbegin(); it != done.rend(); ++it) {
                const std::wstring dst = local(it->e->path), old = dst + L".emfold";
                bool ok;
                if (!it->had) ok = DeleteFileW(dst.c_str()) != 0;
                else if (!it->direct) ok = DeleteFileW(dst.c_str()) && MoveFileExW(old.c_str(), dst.c_str(), MOVEFILE_REPLACE_EXISTING);
                else {  // replaced in place: the copy in the backup is what was there
                    std::vector<uint8_t> was;
                    ok = web_update::read_file(bdir + web_update::backslashes(web_update::wide(it->e->path)), was) && web_update::write_file(dst, was);
                }
                if (ok) ++back;
                else note(2, "update (EMF): could NOT put back " + it->e->path + " (error " + std::to_string(GetLastError()) + "): emf\\flamekit_emf_backup has it");
            }
            return fail(error + ": EMF v" + version + " was not installed; " + std::to_string(back) + " of " + std::to_string(done.size()) +
                        " changed file(s) put back; tried again in 30 minutes");
        }
        ready = version;
        {
            std::lock_guard<std::mutex> l(g_ready_mx);
            g_ready = version;
        }
        failed_list.clear();
        last_note.clear();
        note(0, "update (EMF): EMF v" + version + " is in place (" + std::to_string(done.size()) + " file(s), " + std::to_string(total / 1024) +
                    " KB): it starts with the next game start. The EMF before it (v" + have + ") is kept in emf\\flamekit_emf_backup");
        return 1;
    }
};

}  // namespace emf_update
