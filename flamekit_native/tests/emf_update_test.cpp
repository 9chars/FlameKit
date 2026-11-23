// emf_update_test.cpp (0.15.454): tests EMF's own update (src/emf_update.hpp) in a folder of its own, never in a real
// game folder. build.cmd builds and runs it after every build of FlameKit Native; a failure fails the build.
// Usage: emf_update_test.exe <empty work folder> <EMF 0.6.6 package's game folder> <EMF 0.6.19 package's game folder>
// The "repository" is a folder on disk (the same layout as emf-dist-test in FlameKit's repository); its signature check
// takes "good" (the real check, with the release key, is web_update::signed_by_release_key and is used in the game).
#include "../src/web_update.hpp"

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <functional>
#include <string>
#include <vector>

namespace fs = std::filesystem;

static int g_fails = 0;
static void check(bool ok, const std::string& what) {
    std::printf("%s %s\n", ok ? "ok  " : "FAIL", what.c_str());
    if (!ok) ++g_fails;
}

static std::vector<uint8_t> bytes(const fs::path& p) {
    std::vector<uint8_t> out;
    web_update::read_file(p.wstring(), out);
    return out;
}
static void put(const fs::path& p, const std::string& text) {
    fs::create_directories(p.parent_path());
    web_update::write_file(p.wstring(), std::vector<uint8_t>(text.begin(), text.end()));
}
static void put(const fs::path& p, const std::vector<uint8_t>& data) {
    fs::create_directories(p.parent_path());
    web_update::write_file(p.wstring(), data);
}
static std::string text_of(const fs::path& p) {
    const auto b = bytes(p);
    return std::string(b.begin(), b.end());
}
static const char* kIni = "[flamekit]\nenabled=1\n";
static const char* kOther = "{\"id\":\"othermod\"}\n";
static const char* kKit = "{\"id\":\"flamekit\",\"version\":\"0.15.454\"}\n";
// Whether the player's setting and the two other mods are as make_game left them.
static bool untouched(const fs::path& game) {
    return text_of(game / "emf/config/flamekit.ini") == kIni && text_of(game / "emf/mods/othermod/mod.json") == kOther &&
           text_of(game / "emf/mods/flamekit/mod.json") == kKit;
}
static std::string ver(const fs::path& p) { return emf_update::version_string(p.wstring(), L"FileVersion"); }

// The files EMF's update brings from a package's game folder: dinput8.dll and emf\ without the example mods (only the
// Lua host of emf\mods), as make_emf_dist.py picks them.
static std::vector<std::string> package_files(const fs::path& game) {
    std::vector<std::string> out;
    for (const auto& e : fs::recursive_directory_iterator(game)) {
        if (!e.is_regular_file()) continue;
        std::string rel = fs::relative(e.path(), game).generic_string();
        if (rel != "dinput8.dll" && rel.rfind("emf/", 0) != 0) continue;
        if (rel.rfind("emf/mods", 0) == 0 && rel.rfind("emf/mods/lua/", 0) != 0) continue;  // also a renamed emf/mods.org
        out.push_back(rel);
    }
    std::sort(out.begin(), out.end());
    return out;
}

// A game folder with EMF from `pkg` (as EMF's installer leaves it, without the example mods), a setting of the player
// and two other mods that must never be touched.
static void make_game(const fs::path& dir, const fs::path& pkg) {
    fs::remove_all(dir);
    for (const std::string& rel : package_files(pkg)) put(dir / rel, bytes(pkg / rel));
    put(dir / "emf/config/flamekit.ini", std::string(kIni));
    put(dir / "emf/mods/othermod/mod.json", std::string(kOther));
    put(dir / "emf/mods/flamekit/mod.json", std::string(kKit));
}

// The repository's emf-dist-test folder for `version` with the files of `pkg`; `edit` may change the list's lines or
// a file before it is written (path -> data).
static void make_repo(const fs::path& repo, const std::string& version, const fs::path& pkg, const std::string& sig = "good",
                      const std::function<void(std::vector<std::string>& lines, std::vector<std::pair<std::string, std::vector<uint8_t>>>& files)>& edit = {}) {
    fs::remove_all(repo);
    std::vector<std::pair<std::string, std::vector<uint8_t>>> files;
    for (const std::string& rel : package_files(pkg)) files.push_back({rel, bytes(pkg / rel)});
    std::vector<std::string> lines;
    for (const auto& f : files) lines.push_back(std::to_string(f.second.size()) + " " + emf_update::sha256_hex(f.second) + " " + f.first);
    if (edit) edit(lines, files);
    std::string text = "emf " + version + "\n";
    for (const std::string& l : lines) text += l + "\n";
    put(repo / "emf-dist-test/emf.txt", text);
    put(repo / "emf-dist-test/emf.sig", sig);
    for (const auto& f : files) put(repo / "emf-dist-test/files" / f.first, f.second);
}

// Whether every file of `pkg` lies in `game` as it is in `pkg`.
static bool same_as(const fs::path& game, const fs::path& pkg) {
    for (const std::string& rel : package_files(pkg))
        if (bytes(game / rel) != bytes(pkg / rel)) {
            std::printf("     differs: %s\n", rel.c_str());
            return false;
        }
    return true;
}

// Files named *.emfnew below `dir`.
static int count_tail(const fs::path& dir, const std::string& tail) {
    int n = 0;
    for (const auto& e : fs::recursive_directory_iterator(dir))
        if (e.is_regular_file() && e.path().filename().string().size() > tail.size() &&
            e.path().filename().string().compare(e.path().filename().string().size() - tail.size(), tail.size(), tail) == 0)
            ++n;
    return n;
}

int main(int argc, char** argv) {
    if (argc != 4) {
        std::printf("usage: emf_update_test <work folder> <EMF 0.6.6 game folder> <EMF 0.6.19 game folder>\n");
        return 2;
    }
    const fs::path work = fs::absolute(argv[1]), old_pkg = fs::absolute(argv[2]), new_pkg = fs::absolute(argv[3]);
    const fs::path game = work / "game", repo = work / "repo";
    fs::create_directories(work);
    check(ver(old_pkg / "emf/emf_core.dll") == "0.6.6" && ver(new_pkg / "emf/emf_core.dll") == "0.6.19",
          "the two packages are EMF 0.6.6 and 0.6.19 (" + ver(old_pkg / "emf/emf_core.dll") + ", " + ver(new_pkg / "emf/emf_core.dll") + ")");
    check(emf_update::sha256_hex(std::vector<uint8_t>{'a', 'b', 'c'}) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
          "SHA-256 of \"abc\"");

    // the paths the update may write
    check(emf_update::allowed("dinput8.dll") && emf_update::allowed("emf/emf_core.dll") && emf_update::allowed("emf/mods/lua/lua.dll") &&
              emf_update::allowed("emf/ui/app.js"),
          "allowed: the loader, EMF's files, the Lua host");
    check(!emf_update::allowed("emf/config/flamekit.ini") && !emf_update::allowed("emf/mods/othermod/mod.json") &&
              !emf_update::allowed("emf/mods/flamekit/mod.json") && !emf_update::allowed("emf/flamekit_emf_backup/x") &&
              !emf_update::allowed("emf/flamekit_update/x") && !emf_update::allowed("../x.dll") && !emf_update::allowed("emf/../x") &&
              !emf_update::allowed("enshrouded.exe") && !emf_update::allowed("/emf/x") && !emf_update::allowed("emf/a b") &&
              !emf_update::allowed("emf/emf_core.dll.emfold") && !emf_update::allowed("EMF/CONFIG/x"),
          "refused: settings, other mods, FlameKit's folders, .., the game, odd names");

    emf_update::Emf e;
    e.game = game.wstring() + L"\\";
    e.get = [&](const std::wstring& path, std::vector<uint8_t>& out, std::string& why) {
        const std::wstring prefix = L"/9chars/FlameKit/c/";
        if (path.rfind(prefix, 0) != 0) {
            why = "not below the test root";
            return false;
        }
        const fs::path p = repo / path.substr(prefix.size());
        if (!web_update::read_file(p.wstring(), out)) {
            why = "HTTP 404";
            return false;
        }
        return true;
    };
    e.verify = [](const std::vector<uint8_t>&, const std::string& sig, std::string& why) {
        if (sig == "good") return true;
        why = "the signature does not match";
        return false;
    };
    std::vector<std::string> said;
    e.say = [&](int level, const std::string& text) {
        said.push_back(text);
        std::printf("     [%d] %s\n", level, text.c_str());
    };
    const std::wstring root = L"/9chars/FlameKit/c/emf-dist-test/";
    const auto reset = [&] {
        e.checked.clear();
        e.failed_list.clear();
        e.retry_at = 0;
        e.ready.clear();
        e.last_note.clear();
    };
    const fs::path core = game / "emf/emf_core.dll";

    // nothing in the repository
    make_game(game, old_pkg);
    fs::remove_all(repo);
    check(e.check(root) == 0 && ver(core) == "0.6.6", "no EMF list: nothing changes");

    // a list with a bad signature, a forbidden path, a wrong fingerprint
    make_repo(repo, "0.6.19", new_pkg, "bad");
    reset();
    check(e.check(root) == -1 && same_as(game, old_pkg), "a list with a bad signature: refused, nothing changes");
    for (const std::string bad : {"emf/config/flamekit.ini", "emf/mods/othermod/mod.json", "../evil.dll", "emf/flamekit_emf_backup/backup.txt"}) {
        make_repo(repo, "0.6.19", new_pkg, "good", [&](std::vector<std::string>& lines, auto& files) {
            const std::vector<uint8_t> evil{'x'};
            lines.push_back("1 " + emf_update::sha256_hex(evil) + " " + bad);
            if (bad.find("..") == std::string::npos) files.push_back({bad, evil});
        });
        reset();
        check(e.check(root) == -1 && same_as(game, old_pkg) && untouched(game),
              "a list naming " + bad + ": refused, nothing changes");
    }
    make_repo(repo, "0.6.19", new_pkg, "good", [](auto&, std::vector<std::pair<std::string, std::vector<uint8_t>>>& files) {
        for (auto& f : files)
            if (f.first == "emf/mods/lua/lua.dll") f.second.push_back(0);  // the file in the repository is not the listed one
    });
    reset();
    check(e.check(root) == -1 && same_as(game, old_pkg) && count_tail(game, ".emfnew") == 0, "a file that does not match its SHA-256: nothing changes");
    check(e.check(root) == 0 && same_as(game, old_pkg), "the same failed list right after: not tried again before 30 minutes");

    // an older list, a game whose dinput8.dll is another loader
    make_repo(repo, "0.6.5", old_pkg);
    reset();
    check(e.check(root) == 0 && same_as(game, old_pkg), "a list older than the installed EMF: nothing changes");
    make_repo(repo, "0.6.19", new_pkg);
    {
        wchar_t sys[MAX_PATH];
        GetSystemDirectoryW(sys, MAX_PATH);
        put(game / "dinput8.dll", bytes(fs::path(sys) / "version.dll"));  // a DLL that is not EMF's loader
        reset();
        check(e.check(root) == 0 && ver(core) == "0.6.6", "another loader as dinput8.dll: EMF is left alone");
        put(game / "dinput8.dll", bytes(old_pkg / "dinput8.dll"));
    }

    // a failure half-way: everything changed so far goes back (emf_core.dll in use, as in the game)
    const HMODULE in_use = LoadLibraryExW(core.wstring().c_str(), nullptr, LOAD_LIBRARY_AS_IMAGE_RESOURCE);
    check(in_use != nullptr, "emf_core.dll mapped like a loaded DLL (it cannot be deleted or overwritten now)");
    check(!DeleteFileW(core.wstring().c_str()), "emf_core.dll in use cannot be deleted");
    make_repo(repo, "0.6.19", new_pkg, "good", [](std::vector<std::string>& lines, auto& files) {
        const std::vector<uint8_t> x{'x'};
        lines.push_back("1 " + emf_update::sha256_hex(x) + " emf/zz_blocked/file.txt");
        files.push_back({"emf/zz_blocked/file.txt", x});
    });
    put(game / "emf/zz_blocked", "a file where the update needs a folder");
    reset();
    check(e.check(root) == -1 && same_as(game, old_pkg) && ver(core) == "0.6.6", "a failure half-way: every changed file put back, emf_core.dll too");
    check(count_tail(game, ".emfnew") == 0, "no .emfnew left after the failure");
    fs::remove(game / "emf/zz_blocked");

    // the update itself: 0.6.6 -> 0.6.19 while emf_core.dll is in use
    make_repo(repo, "0.6.19", new_pkg);
    reset();
    check(e.check(root) == 1, "EMF 0.6.6 -> 0.6.19: put in place");
    check(same_as(game, new_pkg) && ver(core) == "0.6.19", "every file is the 0.6.19 one");
    check(untouched(game), "the player's setting and the other mods are untouched");
    check(ver(game / "emf/flamekit_emf_backup/emf/emf_core.dll") == "0.6.6" && ver(game / "emf/flamekit_emf_backup/dinput8.dll") == "0.6.6",
          "the backup holds EMF 0.6.6");
    {
        const auto b = bytes(game / "emf/flamekit_emf_backup/backup.txt");
        check(std::string(b.begin(), b.end()).rfind("emf 0.6.6\n", 0) == 0, "backup.txt starts with emf 0.6.6");
    }
    check(fs::exists(game / "emf/emf_core.dll.emfold") && count_tail(game, ".emfnew") == 0, "the running core is emf_core.dll.emfold, no .emfnew left");
    check(e.ready == "0.6.19", "ready: 0.6.19 starts with the next game start");
    check(e.check(root) == 0 && same_as(game, new_pkg), "the same list again: nothing to do");

    // a newer list while the first waits: the core in use is the .emfold, the waiting new core is replaced in place
    make_repo(repo, "0.6.20", new_pkg, "good", [](std::vector<std::string>& lines, std::vector<std::pair<std::string, std::vector<uint8_t>>>& files) {
        for (size_t i = 0; i < files.size(); ++i)
            if (files[i].first == "emf/emf_core.dll") {
                files[i].second.push_back(0);  // a different core (still saying 0.6.19 inside: the list's version counts here)
                lines[i] = std::to_string(files[i].second.size()) + " " + emf_update::sha256_hex(files[i].second) + " emf/emf_core.dll";
            }
    });
    reset();
    const auto new_size = bytes(new_pkg / "emf/emf_core.dll").size();
    check(e.check(root) == 1 && bytes(core).size() == new_size + 1, "a newer list while one waits: the waiting core replaced in place");
    check(ver(game / "emf/flamekit_emf_backup/emf/emf_core.dll") == "0.6.19", "the backup now holds what was there before (0.6.19)");

    // the next game start: the old files go
    FreeLibrary(in_use);
    e.clean_up();
    check(count_tail(game, ".emfold") == 0 && count_tail(game, ".emfnew") == 0, "at the next start: the .emfold files are removed");
    check(untouched(game), "the player's setting and the other mods are still there");

    // no version readable: left alone
    make_repo(repo, "0.6.21", new_pkg);
    put(core, std::string("not a DLL"));
    reset();
    check(e.check(root) == 0 && bytes(core).size() == 9, "the installed EMF's version cannot be read: left alone");

    std::printf(g_fails == 0 ? "EMF UPDATE TESTS: ALL PASSED\n" : "EMF UPDATE TESTS: %d FAILED\n", g_fails);
    return g_fails == 0 ? 0 : 1;
}
