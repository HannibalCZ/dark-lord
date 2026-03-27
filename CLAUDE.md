# CLAUDE.md — Dark Lord MVP

## O hře
Tahová strategie kde hráč hraje za Temného pána ovládajícího svět skrze stínové organizace, agenty a temné rituály. Hráč nevládne otevřeně — operuje ze stínu. Síly dobra (AI frakce) reagují na Heat, Infamy a Awareness.

GDD: `dark_lord_gdd_v14.docx` (referenční dokument pro veškerý design)

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
| `OrgManager` | Stínové organizace — zakládání, doktríny, pasivní efekty |

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

### EffectsSystem je jediné místo kde se mění herní stav
Veškeré změny gold, mana, research, heat, doom, awareness, infamy
jdou výhradně přes EffectsSystem.apply(). Manažeři orchestrují
KDY a CO — nikdy nemění proměnné přímo.

Pro globální efekty bez regionu:
```gdscript
var ctx := EffectContext.make(game_state, null, faction_id)
effects_system.apply({"gold": amount}, ctx)
```

Výjimky s TODO komentářem v kódu:
- `dark_actions_left` — AP systém zatím mimo EffectsSystem
- `unit_limit` — strukturální limit zatím mimo EffectsSystem

### Ekonomické vs. neekonomické efekty organizací
EconomicManager vlastní gold/mana změny včetně org příjmů.
OrgManager předává EffectsSystem pouze neekonomické efekty
(heat, awareness, infamy). Nikdy neaplikuj gold/mana org efektů
přes EffectsSystem — způsobí double-application.

### Command/Query pattern (`scripts/core/command/`, `scripts/core/query/`)
- `GameCommand` — mutace stavu (akce které mění hru)
- `GameQuery`, `RegionQuery`, `UnitQuery` — čtení stavu bez side effects

### Balance.gd (`scripts/Balance.gd`)
**Všechna čísla patří sem.** Success chances misí, heat thresholdy, ceny budov, síly jednotek — vše jako konstanty v Balance.gd. Nikdy natvrdo v logice manažerů.

---

## Herní smyčka (Game Loop)

```
1. RADA ZASVĚCENÝCH     <- eventy z minulého tahu
2. PLÁNOVÁNÍ HRÁČE      <- pohyb agentů, mise, dark actions, stavba
3. AI FÁZE              <- AIManager vykoná akce všech frakcí
4. VYHODNOCENÍ          <- mise, boje, organizace, ekonomika
5. ZPĚTNÁ VAZBA         <- LogManager, UI update
```

Tah je **simultánní** — hráč plánuje, pak se vše vyhodnotí najednou s AI.

---

## Datové modely

### Region (`scripts/models/RegionData.gd`)
Pohyb je definován přes **sousedství** (`neighbors: Array[int]`), ne přes souřadnice.
MVP používá čtvercovou mřížku 4x3 (12 regionů), ale architektura musí být připravena na přechod na graf uzlů (Crusader Kings styl).

Typy regionů: `CITY`, `VILLAGE`, `WILDERNESS`, `MANA_SOURCE`, `RUIN`

### Unit (`scripts/models/UnitData.gd`)
Pokrývá agenty i armády. Typ určuje dostupné mise a schopnosti.

### Mission (`scripts/models/MissionData.gd`)
Data-driven. Každá mise má `success_chance`, `success_effects[]`, `fail_effects[]`.

---

## Stav implementace

### Hotovo
- [x] Mapa a regiony (12 regionů, neighbors-based pohyb)
- [x] Agenti a pohyb
- [x] Mise agentů (data-driven, EffectsSystem pipeline)
- [x] Game loop (tahy, fáze, advance_turn())
- [x] Zdroje (zlato, mana, RP, research)
- [x] Heat / Infamy / Awareness — všechny zobrazeny v TopBar
- [x] UI / HUD — TopBar se zdroji, ikonkami a progress bary,
      pravý panel se sekcemi (RegionSection, OrgSection,
      ActionsSection, MovementSection)
- [x] AI systém
      - AIManager.execute_ai_turn() — vstupní bod
      - Balance.AI_PROFILE — čtyři profily (defender, raider,
        lair_hunter, investigator)
      - Behavior enum na Faction (PASSIVE/PATROLLING/
        AGGRESSIVE/COORDINATED)
      - RegionQuery rozšířen o has_lair a highest_corruption
- [x] Narativní eventy — Rada zasvěcených
      - EventData model, EventsManager, CouncilPanel
      - Sbírá: pohyby AI, výsledky misí, změny Heat,
        výsledky bitev, zničení organizací
      - Závěrečné eventy při výhře/prohře
- [x] Stínové organizace
      - Balance.ORG — tři typy, šest doktrín
      - OrgManager — zakládání, pasivní efekty,
        set_doctrine(), get_org_display_data()
      - Zakládání přes Dark Action (agent jako cena)
      - Zničení přes purge misi nebo vojenské obsazení
      - OrgSection v pravém panelu MapTab
      - mission_bonus (Shadow Network) funkční
      - infamy generování (Kult) funkční
- [x] Vítězné a prohrané podmínky
      - Výhra: 2/3 civilizovaných regionů (region_kind ==
        "civilized") pod kontrolou (vojensky nebo korupce fáze >= 3)
      - Prohra: obsazení startovního regionu nepřítelem
      - Počítadlo v TopBar, blokování tlačítka po konci hry
      - Závěrečné eventy v Radě zasvěcených
- [x] Technický dluh
      - UnitManager odstraněny přímé reference na jiné manažery
      - Veškeré herní efekty přes EffectsSystem

### Zbývá implementovat (MVP scope)
- [ ] Dark Lord progression strom (GDD sekce 15)
- [ ] AI vylepšení — Inkvizice strategické chování
- [ ] Mid-game krize (GDD sekce 14) — odloženo
- [ ] Archetypy (GDD sekce 13) — odloženo
- [ ] Artefakty (GDD sekce 15.4) — odloženo

### Známé TODO v kódu
- DarkActionsManager: AP cost přes EffectsSystem (klíč "ap")
- BuildingManager: unit_limit přes EffectsSystem
- CombatManager: N-way combat (MVP předpokládá 2 frakce)
- MapTab: Region.display_name a get_corruption_percent() chybí

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
- GDD `dark_lord_gdd_v14.docx` je autoritativní zdroj pro design
- MVP combat = porovnání čísel (CombatManager) — netvoř komplexnější systém bez pokynu
- `MapTab_old.gd` existuje záměrně jako reference — nemaž
- Balance.ORG struktura: inline efekty pod klíčem doktríny, lookup přes Balance.get_org_effects()
- Organizace se zakládají přes Dark Action — ne misí
