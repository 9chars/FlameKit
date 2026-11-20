import csv, re, collections, sys
rows=[r for r in csv.DictReader(open("templates.csv")) if r["enemy_ai"]=="1"]
skip=re.compile(r"^(Base_|DEPRECATED|TEST|Z_|PLACEMENT|ProjectileSpawner|enemy_)|[Dd]ebug|_OLD|OLD_|WIP|AutomatedTesting|TESTING|_TEST|_test|VFX|lore|_hook|hookPtE|SummonStone|_sleep|SubEnemy|Tentacle|NoCombat|Night_Patrol|_Patrol|Dungeon|BonePile|Bonepile|_Guard|GuardTurn|GuardGroup|GuardParent|_add$|SpawnTube|_ShowCase|NOTFINISHED|NoEggs|NO_SPECIAL|Illusion|MainAppearance|VorgothFight|Calcified|start_cave|_Summon_|SpawnAnim|bossAdd|BossAdd|heavyAdd|HeavyAdd|Utility|_Pet_|Proto|Transformer|Companion|_Mini$|_summon|AfterDeath|_Leader|Trap_NoMovement|Suicider|Swarm|SpawnAdd|SpawnedSub|MudTeleport|huge_test|_Gen[12]|Organ|Spawner|Phase|_Tamed|Mushroom_Small|_BLIND|_Stare|DEPRECATED|_Flee|not_fleeing|Hover_Nest|_Nest_|_Elite_Unarmored|night_patrol|Deprecated|Mage_Summon")
fac={2:"Shroud",3:"Vukah",4:"Scavengers",5:"Animals",6:"Beasts",9:"Plants",10:"Undead",13:"Cyclops",14:"Drak",15:"Ancients"}
keep=[]
for r in rows:
    f=int(r["faction"]); n=r["name"]
    if f not in fac or skip.search(n): continue
    keep.append((fac[f], n, r["guid"], r["boss"]))
c=collections.Counter(k[0] for k in keep); print(len(keep), dict(c))
for k in sorted(keep): print(k[0], k[3], k[1])
open("monsters.tsv","w").write("\n".join("\t".join(k) for k in sorted(keep)))
