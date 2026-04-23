# CLAUDE.md — Dark Lord MVP

## O hře
Tahová strategie kde hráč hraje za Temného pána ovládajícího svět skrze stínové organizace, agenty a temné rituály. Hráč nevládne otevřeně — operuje ze stínu. Síly dobra (AI frakce) reagují na Heat, Infamy a Awareness.

GDD: `dark_lord_gdd_v18.docx` (referenční dokument pro veškerý design)

## Stack
- Godot 4.x, GDScript
- Žádné externí pluginy

---

## Struktura projektu

```
managers/       # Singleton manažeři — každý vlastní jednu doménu
scripts/
  core/         # Infrastruktura: EventBus, EffectsSystem, Command/Query patterny
  models/       # Datové třídy (RegionData, UnitData, MissionData)
  ui/           # UI komponenty a taby
  Balance.gd    # VŠECHNY číselné konstanty patří sem, nikam jinam
  GameState.gd  # Centrální stav hry
  Faction.gd    # Model frakce
  Region.gd     # Model regionu
  Unit.gd       # Model agenta/jednotky
  Mission.gd    # Model mise
```

---

## Architektura — klíčové principy

### Manažeři (Singletons)
Každý manažer vlastní svou doménu. Nekomunikují přímo — používají `EventBus` nebo `EffectsSystem`.

| Manažer | Doména |
|---|---|
| `RegionManager` | Stav regionů, korupce, sousedství |
| `UnitManager` | Agenti a armády — pohyb, stav, sloty |
| `MissionManager` | Zadávání a vyhodnocení misí |
| `FactionManager` | AI frakce — chování, triggery, stav |
| `EconomicManager` | Zdroje: zlato, mana, RP |
| `AIManager` | AI rozhodování per frakce per tah |
| `CombatManager` | Vyhodnocení bojů |
| `DarkActionsManager` | Dark Actions — AP systém, validace |
| `OrgManager` | Stínové organizace — zakládání, doktríny |
| `EventsManager` | Narativní eventy — Rada zasvěcených |
| `ReputationManager` | Reputace AI frakcí — výpočet, fáze |
| `ProgressionManager` | Progression strom — odemykání uzlů |
| `BuildingManager` | Budovy v regionech (stub) |
| `SpellManager` | Kouzla a rituály (stub) |
| `LogManager` | Herní log |

### EventBus (`scripts/core/EventBus.gd`)
Centrální signálová sběrnice. Veškerá mezimanažerská komunikace jde přes signály na EventBusu — ne přímými voláními.

```gdscript
# správně
EventBus.emit_signal("region_corrupted", region_id)

# špatně
RegionManager.on_region_corrupted(region_id)
```

### EffectsSystem (`scripts/core/EffectsSystem.gd`)
Jediné místo kde se mění herní stav. Veškeré změny gold, mana,
heat, awareness, infamy jdou výhradně přes EffectsSystem.apply().

```gdscript
var ctx := EffectContext.make(game_state, null, faction_id)
effects_system.apply({"gold": amount}, ctx)
```

Výjimky s TODO komentářem v kódu:
- `dark_actions_left` — AP systém zatím mimo EffectsSystem
- `unit_limit` — strukturální limit zatím mimo EffectsSystem

### Ekonomické vs. neekonomické efekty organizací
OrgManager předává EffectsSystem pouze neekonomické efekty
(heat, awareness, infamy). Nikdy neaplikuj gold/mana org efektů
přes EffectsSystem — způsobí double-application.

Pozor: OrgManager předává EffectsSystem pouze neekonomické efekty
(heat, awareness, infamy). Gold/mana org efektů jdou přes
EconomicManager — nikdy přes EffectsSystem (double-application).

### Query pattern — pravidla čtení dat

Data se čtou VŽDY přes Query vrstvu:

```gdscript
# správně
game_state.query.units.get_by_id(id)
game_state.query.regions.regions_owned_by(faction_id)
game_state.query.orgs.get_visible_player_orgs()

# špatně — přímý přístup na interní Arrays
unit_manager.units        # NIKDY
region_manager.regions    # NIKDY
org_manager.orgs          # NIKDY
```

Query soubory: `UnitQuery`, `RegionQuery`, `OrgQuery`
(scripts/core/query/)

**Rebuild pravidlo:** Po každé mutaci která mění indexovaná data
musí proběhnout rebuild příslušného Query.

Tato API rebuild garantují automaticky — nevolej rebuild zvlášť:
```gdscript
unit_manager.kill_unit(id)            # rebuild uvnitř
unit_manager.set_busy(id)             # rebuild není potřeba
unit_manager.release_unit(id)         # rebuild není potřeba
region_manager.claim_region(id, f)    # rebuild uvnitř
org_manager.add_org(...)              # rebuild uvnitř
org_manager.remove_org(...)           # rebuild uvnitř
org_manager.boost_org_loyalty(id, n)  # OrgManager vlastní data
```

Pokud mutuješ data mimo tato API (výjimečně), volej rebuild ručně:
```gdscript
game_state.query.units.rebuild()
game_state.query.regions.rebuild()
game_state.query.orgs.rebuild()
```

### Command pattern — aktuální rozsah

GameCommand.gd validuje a deleguje na manažery. Commands existují
pouze pro subset akcí (pohyb agentů, mise, Dark Actions). Ostatní
akce volají manažerské API přímo bez Command wrapperu — to je
přijatelné pokud API garantuje rebuild a konzistentní stav.

Nový Command wrapper přidej pouze pokud akce potřebuje validaci,
undo nebo konzistentní návratový formát pro UI.

### Balance.gd
Všechna čísla patří sem. Nikdy nepište hodnoty natvrdo do logiky
manažerů.

---

## Herní smyčka (Game Loop)

```
1. RADA ZASVĚCENÝCH     <- eventy z minulého tahu
2. PLÁNOVÁNÍ HRÁČE      <- pohyb agentů, mise, dark actions, stavba
3. AI FÁZE              <- AIManager vykoná akce všech frakcí
4. VYHODNOCENÍ          <- mise, boje, organizace, ekonomika
5. ZPĚTNÁ VAZBA         <- LogManager, UI update
```

Tah je simultánní — hráč plánuje, pak se vše vyhodnotí najednou.

### Pořadí v advance_turn()
Heat decay → reputation_manager.update_all() →
_check_heat_thresholds() → process_ai_spawning() →
_try_spawn_explorer() → org efekty → loyalty decay →
_check_org_visibility() → ekonomika → eventy

---

## Datové modely

### Region
Pohyb přes sousedství (`neighbors: Array[int]`), ne souřadnice.
Mapa: `data/maps/mvp_map.json` (19 regionů, node-based)
Archiv: `data/maps/mvp_map_archive.json`

region_kind hodnoty: `"civilized"` (vítězný práh), `"wilderness"`
(lairy, tajemství) — nikdy "wild" ani "wildlands"

### Unit (`scripts/models/UnitData.gd`)
Pokrývá agenty i armády. Typ určuje dostupné mise a schopnosti.

### Mission (`scripts/models/MissionData.gd`)
Data-driven. Každá mise má `success_chance`, `success_effects[]`, `fail_effects[]`.

### Organizace (org Dictionary)
Klíče: org_id, org_type, owner, region_id, doctrine,
founded_turn, loyalty, is_rogue, visible

visible: false = inkvizitor org nevidí a nemůže cílit.
get_org_effects_scaled() je jediné místo kde se aplikuje
loyalty multiplikátor.

### Progression
TYP A: modifier_ klíče → faction.modifiers (accumulator,
nikdy neresetuj, pouze přičítej)
TYP B: one_time → EffectsSystem při odemčení uzlu

---

## Milestones

v0.02–v0.05 uzavřeny. Aktuální: v0.06 (zdraví projektu,
tech debt, testování).

Odloženo na v0.06+: systém stop, zrada organizace, efekty
progression uzlů T1–T5, autonomní org, save/load,
rivalitní Dark Lord.

---

## Konvence

- Soubory a třídy: `PascalCase`
- Proměnné a funkce: `snake_case`
- Signály: `snake_case`, minulý čas (`region_corrupted`)
- Konstanty v Balance.gd: `SCREAMING_SNAKE_CASE`

### Nový systém — checklist
1. Datový model do `scripts/`
2. Logika do manažera v `managers/`
3. Číselné hodnoty do `Balance.gd`
4. Query metody do příslušného Query souboru
5. Komunikace přes EventBus
6. UI do `scripts/ui/`

---

## Known technical debt

- AIManager: pipeline zobecnění přes `"pipeline"` klíč
  v Balance.AI_PROFILE — v0.06
- Balance.AI_SPAWN["elf"]: spawn_rate 99 workaround —
  nahradit one_shot systémem v0.06
- Balance.gd: DARK_ACTIONS vs MISSION cost struktura
  (flat vs nested) — příležitostný refactoring
- CombatManager: N-way combat (MVP předpokládá 2 frakce)
- DarkActionsManager: AP cost přes EffectsSystem
- BuildingManager: unit_limit přes EffectsSystem

---

## Poznámky pro Claude Code

**Architektura:**
- MapTab: MapCanvas (clip) → MapContent (scrolluje) → tiles
  + ConnectionLayer. Tiles patří do MapContent, ne MapCanvas.
- game_updated je signal na GameState — ne na EventBusu.
  Emituj jako `GameState.game_updated.emit()`
- Procedurální rozmístění používá separátní proc_rng —
  ne hlavní game_state.rng

**AI systém:**
- Scout profil má izolovanou větev v execute_ai_turn() —
  nikdy nevolej _ai_move_towards() pro scout jednotky
- Explorer spawn je v GameState._try_spawn_explorer() —
  oddělená od process_ai_spawning()
- ReputationManager volat update_all() před
  _check_heat_thresholds() — pořadí je kritické

**Organizace:**
- Balance.ORG: efekty inline pod klíčem doktríny,
  lookup přes Balance.get_org_effects()
- Organizace se zakládají přes Dark Action — ne misí
- EventsManager.reset() volat z load_scenario()

**Ostatní:**
- MapTab_old.gd existuje záměrně jako reference — nemaž
- MVP combat = porovnání čísel — netvoř komplexnější systém
  bez pokynu