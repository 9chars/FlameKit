// test: icon_test <game dir/> <guid hex> <out.png> [size]
#include "item_icons.hpp"
static std::string g_dir;
int main(int argc, char** argv) {
    g_dir = argv[1];
    ItemIcons icons;
    icons.open = [](const char* name, void*) { return fopen((g_dir + name).c_str(), "rb"); };
    uint8_t guid[16];
    for (int i = 0; i < 16; ++i) { unsigned v; sscanf(argv[2] + i * 2, "%2x", &v); guid[i] = (uint8_t)v; }
    const int size = argc > 4 ? atoi(argv[4]) : 64;
    std::vector<uint8_t> rgba;
    if (!icons.icon(guid, size, rgba)) { printf("no icon (%s)\n", icons.note.c_str()); return 1; }
    const auto file = ItemIcons::png(rgba, size, size);
    FILE* f = fopen(argv[3], "wb"); fwrite(file.data(), 1, file.size(), f); fclose(f);
    printf("ok %zu bytes\n", file.size());
}
