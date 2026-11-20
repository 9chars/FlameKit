# Game data tools

Python scripts that read the game's resource archive (`enshrouded.kfc` + `enshrouded.kfc_resources`; needs `zstd`).
Run them on the PC with the game folder as the first argument, e.g. `python3 seqs3.py "<game folder>"`.

- `kfc.py`: the reader the others load (resource keys, chunks, `resource_at(i)`).
- `find.py`, `look.py`, `list.py`, `list2.py`, `curate.py`: template lookups (`templates.csv`, `monsters.tsv` are
  their output, 2026-11-14).
- `tplcomp.py <game> <template guid> <component hash hex>`: dumps one component of a template (the hound's jump, 2026-11-17).
- `arsenal*.py`, `falldmg.py`: item and fall-damage lookups (2026-11-18).
- `seqs.py`, `seqs2.py`, `seqs3.py`: the action sequences (resource type 0x9fd4a561; a sequence's id is FNV-1a 32 of
  its GUID's 16 stored bytes). `seqs3.py` writes `seqnames.tsv`: every sequence's id, size and name (2026-11-19: the
  hound uses the wolf's sequences; Wolf Shout 0x89A1BC53 is the companion's heal cue).
