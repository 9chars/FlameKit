#pragma once
// fk_log.hpp: FlameKit's own log, for everything in the project (the DLL, the Lua part, EMF's log, Windows, the game
// data FlameKit reads, the updater, the UI and its watchdog).
//
// One file per game session in emf\mods\flamekit\logs\, named flamekit_<date>_<time>.log; the newest 10 are kept. A
// file stops taking ordinary lines at 50 MB (errors and warnings still go in).
//
// How much goes in is the debug level, in emf\mods\flamekit\debug.txt (one word: off, normal or full; normal when the
// file is missing). It is read again every few seconds, so it changes while the game runs; Ctrl+Shift+F12 in the game
// steps through the levels and writes the file. The levels:
//   off     errors and warnings only (warnings: the UI watchdog's failures and anything else that went wrong)
//   normal  also what happens: windows, updates, clicks, the game's front window, EMF's log, resource use
//   full    also the details: every check, game data as read, timings
// Errors and warnings are always written, whatever the level.
#include <windows.h>
#include <psapi.h>

#include <algorithm>
#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace fklog {

enum Level { kError = 0, kWarn = 1, kInfo = 2, kDebug = 3 };
enum Mode { kOff = 0, kNormal = 1, kFull = 2 };

inline std::atomic<int> g_mode{kNormal};

inline bool on(Level level) {
    const int mode = g_mode.load();
    return level <= kWarn || (level == kInfo && mode >= kNormal) || (level == kDebug && mode >= kFull);
}

inline const char* mode_name(int mode) { return mode == kOff ? "off" : mode == kFull ? "full" : "normal"; }

struct Log {
    std::mutex lock;
    FILE* file = nullptr;
    std::wstring dir;                 // ...\emf\mods\flamekit\ (ends with a backslash)
    std::vector<std::string> early;   // lines from before the file was opened
    uint64_t bytes = 0;
    bool capped = false;
    static constexpr uint64_t kCap = 50ull * 1024 * 1024;
    static constexpr int kKeep = 10;
};
inline Log g_log;

inline std::string stamp() {
    SYSTEMTIME t;
    GetLocalTime(&t);
    char s[48];
    snprintf(s, sizeof s, "%04u-%02u-%02u %02u:%02u:%02u.%03u", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond,
             t.wMilliseconds);
    return s;
}

inline void put(Level level, const std::string& text) {
    static const char* kNames[] = {"ERROR", "WARN ", "INFO ", "DEBUG"};
    char head[96];
    snprintf(head, sizeof head, "%s [t%05lu] %s ", stamp().c_str(), GetCurrentThreadId(), kNames[level]);
    std::string line = head + text;
    // the Windows user name never goes into the log (it is in many paths): "<user>" instead
    static const std::string user = [] {
        char name[128] = "";
        DWORD n = GetEnvironmentVariableA("USERNAME", name, sizeof name);
        return n >= 3 && n < sizeof name ? std::string(name, n) : std::string();
    }();
    if (!user.empty())
        for (size_t at = 0; (at = line.find(user, at)) != std::string::npos;) {
            line.replace(at, user.size(), "<user>");
            at += 6;
        }
    while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) line.pop_back();
    line += "\n";
    std::lock_guard<std::mutex> l(g_log.lock);
    if (!g_log.file) {
        if (g_log.early.size() < 2000) g_log.early.push_back(line);
        return;
    }
    if (g_log.capped && level > kWarn) return;
    fwrite(line.data(), 1, line.size(), g_log.file);
    fflush(g_log.file);
    g_log.bytes += line.size();
    if (!g_log.capped && g_log.bytes > Log::kCap) {
        g_log.capped = true;
        const char* note = "---- this file reached 50 MB: from here on only errors and warnings ----\n";
        fwrite(note, 1, std::strlen(note), g_log.file);
        fflush(g_log.file);
    }
}

inline void write(Level level, const char* fmt, ...) {
    char buf[2048];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof buf, fmt, args);
    va_end(args);
    put(level, buf);
}

// Reads debug.txt. Returns true when the level changed.
inline bool read_mode() {
    int mode = kNormal;
    if (FILE* f = _wfsopen((g_log.dir + L"debug.txt").c_str(), L"rb", _SH_DENYNO)) {
        char word[16] = "";
        if (fscanf(f, "%15s", word) == 1) {
            if (_stricmp(word, "off") == 0) mode = kOff;
            else if (_stricmp(word, "full") == 0) mode = kFull;
        }
        fclose(f);
    }
    const int was = g_mode.exchange(mode);
    if (was != mode) put(kWarn, std::string("log: debug level ") + mode_name(was) + " -> " + mode_name(mode) + " (debug.txt)");
    return was != mode;
}

// Sets the level and writes it into debug.txt (Ctrl+Shift+F12).
inline void set_mode(int mode) {
    const int was = g_mode.exchange(mode);
    if (FILE* f = _wfsopen((g_log.dir + L"debug.txt").c_str(), L"wb", _SH_DENYNO)) {
        fputs(mode_name(mode), f);
        fclose(f);
    }
    put(kWarn, std::string("log: debug level ") + mode_name(was) + " -> " + mode_name(mode) + " (Ctrl+Shift+F12)");
}

// Opens this session's file in `flamekit_dir` (...\emf\mods\flamekit\) and removes the oldest beyond 10.
inline void open(const std::wstring& flamekit_dir) {
    {
        std::lock_guard<std::mutex> l(g_log.lock);
        if (g_log.file) return;
        g_log.dir = flamekit_dir;
    }
    read_mode();
    const std::wstring logs = flamekit_dir + L"logs\\";
    CreateDirectoryW(logs.c_str(), nullptr);
    std::vector<std::wstring> old;
    WIN32_FIND_DATAW fd;
    HANDLE find = FindFirstFileW((logs + L"flamekit_*.log").c_str(), &fd);
    if (find != INVALID_HANDLE_VALUE) {
        do old.push_back(fd.cFileName);
        while (FindNextFileW(find, &fd));
        FindClose(find);
    }
    std::sort(old.begin(), old.end());  // the names are dates: oldest first
    while (old.size() >= static_cast<size_t>(Log::kKeep)) {
        DeleteFileW((logs + old.front()).c_str());
        old.erase(old.begin());
    }
    SYSTEMTIME t;
    GetLocalTime(&t);
    wchar_t name[64];
    swprintf(name, 64, L"flamekit_%04u-%02u-%02u_%02u-%02u-%02u.log", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond);
    FILE* f = _wfsopen((logs + name).c_str(), L"wb", _SH_DENYWR);
    std::lock_guard<std::mutex> l(g_log.lock);
    g_log.file = f;
    if (!f) return;
    for (const std::string& line : g_log.early) {
        fwrite(line.data(), 1, line.size(), f);
        g_log.bytes += line.size();
    }
    g_log.early.clear();
    fflush(f);
}

// A crash in one of FlameKit's own threads: the log gets the exception and where it happened, then Windows handles it
// as it would have (the game's own crash handling is not changed).
inline int crash_filter(const char* thread, EXCEPTION_POINTERS* ep) {
    void* at = ep->ExceptionRecord->ExceptionAddress;
    HMODULE module = nullptr;
    char name[MAX_PATH] = "?";
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           static_cast<LPCSTR>(at), &module))
        GetModuleFileNameA(module, name, MAX_PATH);
    const char* base = std::strrchr(name, '\\');
    write(kError, "crash: thread %s: exception %08lx at %s+0x%llx", thread, ep->ExceptionRecord->ExceptionCode, base ? base + 1 : name,
          static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(at) - reinterpret_cast<uintptr_t>(module)));
    return EXCEPTION_CONTINUE_SEARCH;
}

// Runs `fn` as a thread body with crash_filter around it.
inline void guarded(const char* thread, void (*fn)()) {
    __try {
        fn();
    } __except (crash_filter(thread, GetExceptionInformation())) {
    }
}

}  // namespace fklog

#define FK_LOG(level, ...)                                         \
    do {                                                           \
        if (fklog::on(level)) fklog::write(level, __VA_ARGS__);    \
    } while (0)
