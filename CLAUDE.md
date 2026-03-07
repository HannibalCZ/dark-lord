# CLAUDE.md — Dark Lord MVP

## O hře
Tahová strategie kde hráč hraje za Temného pána ovládajícího svět skrze stínové organizace, agenty a temné rituály. Hráč nevládne otevřeně — operuje ze stínu. Síly dobra (AI frakce) reagují na Heat, Infamy a Awareness.

GDD: `dark_lord_gdd_v8.docx` (referenční dokument pro veškerý design)

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
| `EconomicManager` | Zdroje: zlato, mana, RP — příjem a výdej |
| `AIManager` | AI rozhodování per frakce per tah |
| `CombatManager` | Vyhodnocení bojů (MVP: porovnání čísel) |
| `DarkActionsManager` | Dark Actions — AP systém, validace, efekty |
| `BuildingManager` | Budovy v regionech |
| `SpellManager` | Kouzla a rituály |
| `LogManager` | Herní log — co se stalo v tahu |

### EventBus (`scripts/core/EventBus.gd`)
Centrální signálová sběrnice. Veškerá mezimanažerská komunikace jde přes signály na EventBusu — ne přímými voláními.

```gdscript
# správně
EventBus.emit_signal("region_corrupted", region_id)

# špatně
RegionManager.on_region_corrupted(region_id)
```

### EffectsSystem (`scripts/core/EffectsSystem.gd`)
Zpracovává efekty akcí (výsledky misí, Dark Actions, kouzla). Efekty jsou data-driven přes `EffectContext`.

### Command/Query pattern (`scripts/core/command/`, `scripts/core/query/`)
- `GameCommand` — mutace stavu (akce které mění hru)
- `GameQuery`, `RegionQuery`, `UnitQuery` — čtení stavu bez side effects

### Balance.gd (`scripts/Balance.gd`)
**Všechna čísla patří sem.** Success chances misí, heat thresholdy, ceny budov, síly jednotek — vše jako konstanty v Balance.gd. Nikdy natvrdo v logice manažerů.

---

## Herní smyčka (Game Loop)

```
1. RADA ZASVĚCENÝCH     ← eventy z minulého tahu (TODO)
2. PLÁNOVÁNÍ HRÁČE      ← pohyb agentů, mise, dark actions, stavba
3. AI FÁZE              ← AIManager vykoná akce všech frakcí
4. VYHODNOCENÍ          ← mise, boje, organizace, ekonomika
5. ZPĚTNÁ VAZBA         ← LogManager, UI update
```

Tah je **simultánní** — hráč plánuje, pak se vše vyhodnotí najednou s AI.

---

## Datové modely

### Region (`scripts/models/RegionData.gd`)
Pohyb je definován přes **sousedství** (`neighbors: Array[int]`), ne přes souřadnice.
MVP používá čtvercovou mřížku 4×3 (12 regionů), ale architektura musí být připravena na přechod na graf uzlů (Crusader Kings styl).

Typy regionů: `CITY`, `VILLAGE`, `WILDERNESS`, `MANA_SOURCE`, `RUIN`

### Unit (`scripts/models/UnitData.gd`)
Pokrývá agenty i armády. Typ určuje dostupné mise a schopnosti.

### Mission (`scripts/models/MissionData.gd`)
Data-driven. Každá mise má `success_chance`, `success_effects[]`, `fail_effects[]`.

---

## Stav implementace

### Hotovo (základně)
- [x] Mapa a regiony
- [x] Agenti a pohyb
- [x] Mise agentů
- [x] Game loop (tahy, fáze)
- [x] Zdroje (zlato, mana, RP)
- [x] Heat / Infamy / Awareness
- [x] UI / HUD základní struktura

### Zbývá implementovat
- [ ] Narativní eventy — Rada zasvěcených (GDD sekce 12)
- [ ] Stínové organizace + doktríny (GDD sekce 4.3–4.4)
- [ ] AI frakce — chování a triggery (GDD sekce 5)
- [ ] Mid-game krize — Zrada, RDL, Inkvizitorská kampaň (GDD sekce 14)
- [ ] Dark Lord progression strom (GDD sekce 15)
- [ ] Archetypy + vítězné podmínky (GDD sekce 13)
- [ ] Artefakty
- [ ] Combat bonusy (MVP základ existuje, bonusy chybí)

---

## Konvence

### Pojmenování
- Soubory a třídy: `PascalCase` (např. `RegionManager.gd`)
- Proměnné a funkce: `snake_case`
- Signály: `snake_case`, minulý čas (např. `region_corrupted`, `mission_completed`)
- Konstanty v Balance.gd: `SCREAMING_SNAKE_CASE`

### Nový systém — checklist
1. Datový model do `scripts/models/`
2. Logika do příslušného manažera v `managers/`
3. Číselné hodnoty do `Balance.gd`
4. Komunikace přes `EventBus`, ne přímá volání
5. UI komponenta do `scripts/ui/` jako samostatný tab nebo panel

### Co nedělat
- Nepiš čísla natvrdo do manažerů — vždy `Balance.KONSTANTA`
- Nevolej manažery přímo z jiných manažerů — vždy přes EventBus nebo EffectsSystem
- Nespoléhej na souřadnice regionů — vždy přes `neighbors[]`
- Nemazat `MapTab_old.gd` bez explicitního pokynu

---

## Poznámky pro Claude Code

- Před každou větší změnou se zeptej na aktuální stav relevantního manažera
- GDD je autoritativní zdroj pro design — pokud je něco nejasné, odkazuj se na konkrétní sekci
- MVP combat = porovnání čísel (CombatManager) — netvoř komplexnější systém bez pokynu
- `MapTab_old.gd` existuje záměrně jako reference — nemaž
