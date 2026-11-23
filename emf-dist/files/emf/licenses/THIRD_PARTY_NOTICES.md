# Third-party code in EMF

EMF itself is under the MIT licence (`LICENSE`). It includes, or links, the libraries below, each under its own
licence. Their full licence texts are next to their code in `third_party/`. The release zip carries them in
`licenses\`.

emf_content.dll is built from the Enshrouded Mod Loader and is under the GPL-3.0-or-later; the rest of EMF stays under
the MIT licence. Its source is in this repository (`src/content/` and `third_party/eml/`) and in the source archive of
each release.

| Library | Used for | Licence | Shipped in the release |
|---|---|---|---|
| [Dear ImGui](https://github.com/ocornut/imgui) (`third_party/imgui`) | the in-game console and Mods tab | MIT | yes, inside `emf_core.dll` |
| ProggyClean font by Tristan Grimmer (embedded in Dear ImGui's `imgui_draw.cpp`) | ImGui's built-in fallback font | MIT | yes, inside `emf_core.dll` |
| [stb](https://github.com/nothings/stb) by Sean Barrett: `imstb_truetype.h` 1.26, `imstb_rectpack.h`, `imstb_textedit.h` (bundled with Dear ImGui) | font rasterising, the font atlas, checking font files, text editing | MIT or public domain (your choice) | yes, inside `emf_core.dll` |
| [Lua 5.4](https://www.lua.org) (`third_party/lua`; a second copy comes with EML's `lua-src` crate) | Lua mods; EML mods' scripts in `emf_content.dll` | MIT | yes, inside the `lua` mod and inside `emf_content.dll` |
| [MinHook](https://github.com/TsudaKageyu/minhook) (`third_party/minhook`), with Hacker Disassembler Engine | function hooks | BSD 2-Clause | yes, inside `emf_core.dll` |
| [Kiln](https://github.com/frostdev-ops/kiln)'s signature database (`docs/modding/kiln_signatures.patterns`) | engine signatures for other loaders (data; EMF does not use it) | MIT (Kiln contributors; the notice is in the file's header) | yes, in `docs\modding\` |
| [Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) (`third_party/vulkan-headers`) | the overlay's Vulkan layer (headers only) | Apache-2.0 | headers compiled in |
| [Microsoft WebView2 SDK](https://www.nuget.org/packages/Microsoft.Web.WebView2) 1.0.4258.31 (`third_party/webview2`) | EMF.exe's window (static loader library) | BSD 3-Clause style (Microsoft) | yes, inside `EMF.exe` |
| [Alegreya](https://github.com/huertatipografica/Alegreya) 2.008 by The Alegreya Project Authors (Huerta Tipográfica), Regular and Bold (`third_party/fonts/alegreya`) | the serif of the on-screen text, the wheels and the console's tabs | SIL OFL 1.1 | yes, unmodified, in `emf\fonts\` |
| [Cascadia Mono](https://github.com/microsoft/cascadia-code) 2407.24 by Microsoft, Regular (`third_party/fonts/cascadia`) | the console's font where Windows' Consolas is missing | SIL OFL 1.1 | yes, unmodified, in `emf\fonts\` |
| [Enshrouded Mod Loader (EML)](https://github.com/Brabb3l/kfc-parser) by Brabb3l and contributors, v0.2.0 (`third_party/eml`) | building the game content of EML mods | GPL-3.0-or-later | yes, inside `emf_content.dll` |
| The Rust standard library | `emf_content.dll` | MIT or Apache-2.0 | yes, inside `emf_content.dll` |
| EML's Rust libraries from crates.io, each with its licence in `licenses/rust-crates.html` | `emf_content.dll` | MIT, Apache-2.0, BSD, Zlib and similar permissive licences | yes, inside `emf_content.dll` |
| [doctest](https://github.com/doctest/doctest) (`third_party/doctest`) | unit tests | MIT | no (tests only) |

`third_party/imgui_emf` holds EMF's own ImGui configuration (MIT, like EMF).

EMF uses Windows' own components at run time: WinHTTP, DPAPI, BCrypt, `tar.exe`, the Consolas font (the console's
default) and the WebView2 Runtime that Windows installs. It does not ship them.

## The game

Enshrouded is a game by Keen Games. EMF is an unofficial, fan-made framework and is not affiliated with or endorsed
by Keen Games. The repository contains no game files. The engine notes in `docs/` describe how the game's engine
works (names, offsets, byte patterns), as found by analysing a legally owned copy, to make mods interoperate with it.
