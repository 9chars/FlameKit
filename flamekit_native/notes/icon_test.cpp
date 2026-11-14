// test: icon_test <game dir/> item <guid hex> | buff <type id hex> [size]
// Prints the icon as text (# opaque, + half, . faint) so it can be checked without a picture viewer.
#include "item_icons.hpp"
#include <cstdlib>
static std::string g_dir;
int main(int argc, char** argv) {
    if (argc < 4) return 2;
    g_dir = argv[1];
    ItemIcons icons;
    icons.open = [](const char* name, void*) { return fopen((g_dir + name).c_str(), "rb"); };
    const int size = argc > 4 ? atoi(argv[4]) : 24;
    std::vector<uint8_t> rgba;
    bool got;
    if (std::string(argv[2]) == "buff") {
        got = icons.buff_icon(static_cast<uint32_t>(strtoul(argv[3], nullptr, 16)), size, rgba);
        printf("buff registry: %d types, %zu with an icon\n", icons.buff_types, icons.buff_icon_guid.size());
    } else {
        uint8_t guid[16];
        for (int i = 0; i < 16; ++i) { unsigned v; sscanf(argv[3] + i * 2, "%2x", &v); guid[i] = (uint8_t)v; }
        got = icons.icon(guid, size, rgba);
    }
    if (!got) { printf("no icon (%s)\n", icons.note.c_str()); return 1; }
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) { const int a = rgba[(y * size + x) * 4 + 3]; putchar(a > 200 ? '#' : a > 90 ? '+' : a > 20 ? '.' : ' '); }
        putchar('\n');
    }
    printf("ok, middle pixel %d %d %d %d\n", rgba[(size / 2 * size + size / 2) * 4], rgba[(size / 2 * size + size / 2) * 4 + 1], rgba[(size / 2 * size + size / 2) * 4 + 2], rgba[(size / 2 * size + size / 2) * 4 + 3]);
}
