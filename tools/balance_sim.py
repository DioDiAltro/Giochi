#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================================
 SIMULATORE DI BILANCIAMENTO — Factory-Defense Incrementale a Nodi
=============================================================================
 Scopo: validare NUMERICAMENTE la spina dorsale matematica del gioco prima
 di scrivere una riga di GDScript. Ogni costante qui dentro e' la stessa che
 finisce in /data/*.json e quindi nell'engine.

 Uso:
     python3 tools/balance_sim.py            # stampa tutte le tabelle
     python3 tools/balance_sim.py --check    # esegue solo le invarianti
                                             # (exit 1 se il design e' rotto)

 Le "INVARIANTI DI DESIGN" in fondo al file sono il vero valore aggiunto:
 sono assert che falliscono se una modifica al bilanciamento rompe una delle
 regole strutturali del gioco (es. "raffinare deve sempre convenire").
=============================================================================
"""

import math
import sys

# =============================================================================
# SEZIONE 0 — COSTANTI GLOBALI DEL MODELLO
# =============================================================================

LAMBDA = 2.5        # base esponenziale del Valore Industriale per tier    VI ~ LAMBDA^R
BETA = 1.585        # esponente del moltiplicatore di danno munizioni      M ~ (R+1)^BETA
                    # 1.585 = log2(3): raddoppiare (R+1) triplica il danno
THETA_REF = 20.0    # VI/s di riferimento per la scala della minaccia
B0 = 150.0          # HP base dell'ondata 1 a Theta = 0
WAVE_GROWTH_A = 0.22   # coefficiente lineare interno della curva ondate
WAVE_GROWTH_P = 1.55   # esponente della curva ondate
THREAT_P = 0.80     # esponente industriale della minaccia (<1 = espandere conviene)

TICK_HZ = 20        # frequenza del tick logico della simulazione
SLOTS_PER_TILE = 3  # slot logici per cella di nastro

# Idle / offline
OFFLINE_ETA_BASE = 0.40   # rendimento produzione a gioco chiuso
OFFLINE_CAP_H_BASE = 8.0  # tetto ore accreditate

# Il timer delle ondate AVANZA anche a gioco chiuso. La base resta pero'
# invulnerabile: quando la difesa non ce la fa piu', il fronte si BLOCCA
# (la linea tiene ma non avanza) invece di essere sfondato.
OFFLINE_WAVES_ADVANCE = True
KAPPA_COMBAT_DATA = 0.20  # ricompensa in Dati per ondata respinta, espressa come
                          # frazione di cio' che la fabbrica produce in un intervallo
                          # d'ondata. Auto-scalante: non puo' MAI superare l'industria.
FRAG_AVG_TARGETS = 3.0    # bersagli medi colpiti dall'AoE (max 5, media prudenziale)

# =============================================================================
# SEZIONE 1 — MATERIALI E VALORE INDUSTRIALE (VI)
# =============================================================================
# VI(m) = base_value(m) * LAMBDA^R(m)
# Il VI e' la valuta universale del gioco: da esso derivano ALGORITMICAMENTE
#   1) i Dati/s generati conferendo il materiale al Core
#   2) la minaccia delle ondate (ancorata al VI/s che raggiunge il Core)
#   3) il costo-opportunita' di bruciare quel materiale come munizione

#            id                 nome                            R   base
MATERIALS = {
    "ore_iron":     ("Minerale di Ferro Grezzo",                0, 1.00),
    "ore_copper":   ("Minerale di Rame Grezzo",                 0, 1.20),
    "dust_iron":    ("Polvere di Ferro",                        1, 1.00),
    "dust_copper":  ("Polvere di Rame",                         1, 1.20),
    "pdust_iron":   ("Polvere di Ferro Purificata",             2, 1.00),
    "pdust_copper": ("Polvere di Rame Purificata",              2, 1.20),
    "ingot_iron":   ("Lingotto di Ferro",                       3, 1.00),
    "ingot_copper": ("Lingotto di Rame",                        3, 1.20),
    "alloy_cond":   ("Lingotto di Lega Conduttiva",             4, 1.50),
    "slag":         ("Fanghiglia (sottoprodotto)",              1, 0.35),
    "briquette":    ("Bricchetta di Scoria (combustibile)",     2, 0.35),
}


# Scarti e combustibili NON sono caricabili in torretta: il loro base_value basso
# li renderebbe la munizione piu' efficiente del gioco, svuotando di senso la
# raffinazione. Coerente con "valid_ammo": false in data/materials.json.
NON_AMMO = {"slag", "briquette"}


def tier(mid):
    return MATERIALS[mid][1]


def vi(mid):
    """Valore Industriale di un'unita' di materiale."""
    _, r, base = MATERIALS[mid]
    return base * (LAMBDA ** r)


def ammo_mult(r):
    """Moltiplicatore di danno di una munizione di tier R.
    Polinomiale (non esponenziale) PER SCELTA: la difesa deve crescere piu'
    lentamente dei Dati, cosi' il giocatore e' sempre spinto ad ampliare la
    logistica invece di limitarsi a salire di tier."""
    return (r + 1.0) ** BETA


# =============================================================================
# SEZIONE 2 — RICETTE E MACCHINARI
# =============================================================================
# Ogni ricetta: (macchina, input dict, output dict, secondi_ciclo, kW)
# I fluidi sono espressi in mB (millibucket).

RECIPES = {
    # --- STADIO 0: ESTRAZIONE ---------------------------------------------
    "drill_iron":    ("Trivella",      {},                                  {"ore_iron": 1},                    2.00,  6),
    "drill_copper":  ("Trivella",      {},                                  {"ore_copper": 1},                  2.00,  6),
    "pump_water":    ("Pompa Idrica",  {},                                  {"water_mb": 240},                  2.00,  8),

    # --- STADIO 1: TRITURAZIONE (resa x2) ---------------------------------
    "crush_iron":    ("Trituratore",   {"ore_iron": 1},                     {"dust_iron": 2},                   2.00, 12),
    "crush_copper":  ("Trituratore",   {"ore_copper": 1},                   {"dust_copper": 2},                 2.00, 12),

    # --- STADIO 2: LAVAGGIO (sottoprodotto Fanghiglia) --------------------
    "wash_iron":     ("Purificatore",  {"dust_iron": 2, "water_mb": 120},   {"pdust_iron": 2, "slag": 1},       2.00, 18),
    "wash_copper":   ("Purificatore",  {"dust_copper": 2, "water_mb": 120}, {"pdust_copper": 2, "slag": 1},     2.00, 18),

    # --- STADIO 3: FUSIONE ------------------------------------------------
    "smelt_iron":    ("Fornace",       {"pdust_iron": 1},                   {"ingot_iron": 1},                  3.00, 10),
    "smelt_copper":  ("Fornace",       {"pdust_copper": 1},                 {"ingot_copper": 1},                3.00, 10),
    # SCORCIATOIA deliberatamente penalizzata (resa 1x invece di 2x, ciclo lento)
    "smelt_direct_iron":   ("Fornace", {"ore_iron": 1},                     {"ingot_iron": 1},                  4.50, 10),
    "smelt_direct_copper": ("Fornace", {"ore_copper": 1},                   {"ingot_copper": 1},                4.50, 10),

    # --- CICLO SCORIE -> ENERGIA (loop chiuso) ----------------------------
    # NOTA BILANCIAMENTO: il tempo di combustione (5.0 s) NON e' arbitrario.
    # E' l'unico valore che rende il ciclo scorie->energia esattamente
    # autosufficiente per la base di riferimento (cfr. invariante #6).
    "compact_slag":  ("Compattatore",  {"slag": 2},                         {"briquette": 1},                   2.00, 14),
    "burn_briquette":("Generatore Termico", {"briquette": 1},               {"kW_s": 300},                      5.00,  0),

    # --- STADIO 4: MULTI-BLOCCO 2x2 ---------------------------------------
    "alloy_conductive": ("Fonderia a Induzione (2x2)",
                        {"ingot_copper": 2, "ingot_iron": 1, "water_mb": 200},
                        {"alloy_cond": 1}, 6.00, 90),

    # --- CONFERIMENTO AL CORE ---------------------------------------------
    # Il Server CONSUMA il materiale e lo converte in Dati. E' il sink finale.
    "server_upload": ("Server", {"<qualsiasi solido>": 2.0}, {"Dati": "2.0 * VI * eta"}, 1.00, 25),
}

# Throughput per macchina, derivato dalle ricette (unita'/s)
def machine_rate(recipe_id, key, side="out"):
    _, ins, outs, sec, _kw = RECIPES[recipe_id]
    d = outs if side == "out" else ins
    return d.get(key, 0) / sec


# =============================================================================
# SEZIONE 3 — TORRETTE E NEMICI
# =============================================================================
#            id            nome                    dmg/colpo  colpi/s  mun/colpo  range  aereo  kW_fuoco
TURRETS = {
    "kinetic":  ("Torretta Cinetica",              12.5,      2.0,     0.25,      8,     True,  15),
    "frag":     ("Torretta a Frammentazione",      22.0,      1.0,     0.50,      6,     False, 25),  # AoE, max 5 bersagli
}

#              id                nome              HP    vel(t/s) armatura  aereo
ENEMIES = {
    "swarm":    ("Drone Sciame",                    40,   1.80,    0,        False),
    "armored":  ("Cingolato Corazzato",            400,   0.70,   60,        False),
    "flyer":    ("Ricognitore Volante",             90,   2.60,   10,        True),
}
E_HP, E_SPEED, E_ARMOR, E_AIR = 1, 2, 3, 4     # indici nella tupla ENEMIES
T_DMG, T_RATE, T_AMMO, T_RANGE, T_AIR, T_KW = 1, 2, 3, 4, 5, 6   # indici in TURRETS

THERMAL_BURN_S = 5.0            # secondi per bruciare 1 bricchetta
CORRIDOR_TILES = 20.0           # celle di corridoio coperte da un cluster di torrette

# Composizione delle ondate per fascia (swarm, flyer, armored) — quota di HP budget
def wave_mix(n):
    if n < 5:    return {"swarm": 1.00, "flyer": 0.00, "armored": 0.00}
    if n < 13:   return {"swarm": 0.80, "flyer": 0.20, "armored": 0.00}
    if n < 26:   return {"swarm": 0.55, "flyer": 0.25, "armored": 0.20}
    return              {"swarm": 0.40, "flyer": 0.25, "armored": 0.35}


def wave_interval(n):
    """Secondi tra un'ondata e la successiva. Il ciclo e' CONTINUO, sia in
    sessione sia a gioco chiuso (vedi simulate_offline)."""
    return max(45.0, 120.0 - 1.5 * n)


def hp_budget(n, theta):
    """Budget HP totale dell'ondata n con throughput industriale theta (VI/s).

    Due fattori moltiplicativi:
      - CURVA ONDATE   (1 + a*n)^p       -> pressione temporale, polinomiale
      - CURVA INDUSTRIA (1 + theta/ref)^q -> pressione economica, q < 1

    q = 0.80 < 1 e' la scelta chiave: raddoppiare la produzione aumenta la
    minaccia solo di 2^0.8 = 1.74x. Espandere e' quindi SEMPRE net-positivo.
    """
    return B0 * ((1 + WAVE_GROWTH_A * n) ** WAVE_GROWTH_P) * ((1 + theta / THETA_REF) ** THREAT_P)


def effective_damage(raw, armor):
    """Armatura = riduzione piatta, con un pavimento del 15% per evitare
    l'immunita' totale. E' il meccanismo che OBBLIGA a raffinare: la polvere
    R1 e' quasi inutile contro i corazzati."""
    return max(raw * 0.15, raw - armor)


def loadout_dps_vs(turret_counts, ammo_tier, enemy_id, ballistics_levels=0, engagement=0.55):
    """DPS reale contro un archetipo specifico (armatura applicata per colpo)."""
    mult = ammo_mult(ammo_tier) * (1.0 + 0.06 * ballistics_levels)
    armor = ENEMIES[enemy_id][E_ARMOR]
    is_air = ENEMIES[enemy_id][E_AIR]
    total = 0.0
    for tid, count in turret_counts.items():
        t = TURRETS[tid]
        if is_air and not t[T_AIR]:
            continue  # questa torretta non colpisce i bersagli aerei
        total += count * effective_damage(t[T_DMG] * mult, armor) * t[T_RATE]
    return total * engagement


def wave_dps(turret_counts, ammo_tier, n, ballistics_levels=0, engagement=0.55):
    """DPS efficace pesato sulla composizione dell'ondata n."""
    mix = wave_mix(n)
    return sum(mix[e] * loadout_dps_vs(turret_counts, ammo_tier, e, ballistics_levels, engagement)
               for e in mix)


def engagement_window(n):
    """Secondi in cui l'ondata resta sotto il fuoco prima di toccare il Core.
    Pesata sulla velocita' media degli archetipi presenti nell'ondata."""
    mix = wave_mix(n)
    avg_speed = sum(mix[e] * ENEMIES[e][E_SPEED] for e in mix)
    return CORRIDOR_TILES / avg_speed


def damage_per_ammo(turret_counts, ammo_tier, ballistics_levels=0):
    """Danno totale erogato da UNA unita' di munizione, mediato sullo schieramento.
    Serve per sapere quante munizioni costa respingere un'ondata da X HP."""
    mult = ammo_mult(ammo_tier) * (1.0 + 0.06 * ballistics_levels)
    tot_dmg = 0.0
    tot_ammo = 0.0
    for tid, count in turret_counts.items():
        t = TURRETS[tid]
        shots_per_ammo = 1.0 / t[T_AMMO]
        aoe = FRAG_AVG_TARGETS if tid == "frag" else 1.0
        dmg = t[T_DMG] * mult * shots_per_ammo * aoe
        # peso = munizioni/s consumate da questo tipo di torretta
        w = count * t[T_AMMO] * t[T_RATE]
        tot_dmg += dmg * w
        tot_ammo += w
    return tot_dmg / tot_ammo if tot_ammo > 0 else 0.0


def combat_data_reward(theta, n):
    """Dati guadagnati respingendo l'ondata n.

    Definita come FRAZIONE della produzione industriale nel tempo di un'ondata,
    non come funzione degli HP nemici. E' la formulazione che rende impossibile
    per definizione che il combattimento superi la logistica come fonte di Dati:
    il rapporto e' fisso a kappa/(1+kappa) = 16.7% del totale a qualunque scala.
    """
    return KAPPA_COMBAT_DATA * theta * wave_interval(n)


def ammo_vi_cost_per_wave(turret_counts, ammo_tier, ballistics_levels, n, theta):
    """VI di munizioni bruciato per respingere l'ondata n."""
    hp = hp_budget(n, theta)
    dpa = damage_per_ammo(turret_counts, ammo_tier, ballistics_levels)
    ammo_units = hp / dpa
    examples = {0: "ore_iron", 1: "dust_iron", 2: "pdust_iron", 3: "ingot_iron", 4: "alloy_cond"}
    return ammo_units * vi(examples[ammo_tier]), ammo_units


def simulate_offline(dt_seconds, wave_index, turret_counts, ammo_tier,
                     ballistics_levels, theta, eta=OFFLINE_ETA_BASE,
                     cap_h=OFFLINE_CAP_H_BASE, ammo_supply_rate=None):
    """Risolve una sessione offline con il timer ondate ATTIVO.

    Regola invalicabile: la base non puo' essere distrutta. Quando la difesa
    non basta piu' (DPS insufficiente o munizioni esaurite) il fronte si BLOCCA
    e il timer si ferma su quell'ondata. Il tempo residuo produce solo risorse.
    """
    t_left = min(dt_seconds, cap_h * 3600.0)
    t_total = t_left
    n = wave_index
    cleared = 0
    data = 0.0
    ammo_spent_vi = 0.0
    stall = None
    theta_off = theta * eta
    if ammo_supply_rate is None:
        # per default le torrette sono alimentate dalla linea principale
        ammo_supply_rate = ammo_drain(turret_counts, duty_cycle=1.0)
    ammo_bank = 0.0

    while t_left > 0:
        dt_wave = wave_interval(n)
        if t_left < dt_wave:
            break
        # produzione durante l'intervallo
        ammo_bank += ammo_supply_rate * dt_wave * eta
        n_next = n + 1
        # ATTENZIONE: la minaccia offline si calcola sul Theta ONLINE (quello
        # dello snapshot di uscita), NON su theta_off. Se usassimo il Theta
        # ridotto, le ondate offline sarebbero piu' facili di quelle online e il
        # giocatore rientrerebbe a un'ondata che la sua difesa non regge da
        # sveglio: idle "sicuro" solo sulla carta. Con questa scelta il punto di
        # stallo offline COINCIDE con il tetto difensivo online.
        hp = hp_budget(n_next, theta)
        need_dps = hp / engagement_window(n_next)
        have_dps = wave_dps(turret_counts, ammo_tier, n_next, ballistics_levels)
        if have_dps < need_dps:
            stall = "dps"
            break
        need_ammo = hp / damage_per_ammo(turret_counts, ammo_tier, ballistics_levels)
        if ammo_bank < need_ammo:
            stall = "munizioni"
            break
        ammo_bank -= need_ammo
        examples = {0: "ore_iron", 1: "dust_iron", 2: "pdust_iron", 3: "ingot_iron", 4: "alloy_cond"}
        ammo_spent_vi += need_ammo * vi(examples[ammo_tier])
        data += combat_data_reward(theta_off, n_next)
        n = n_next
        cleared += 1
        t_left -= dt_wave

    # tutto il tempo (anche quello dopo lo stallo) produce Dati industriali,
    # al netto del VI bruciato in munizioni
    data += theta_off * t_total - ammo_spent_vi
    return {
        "waves_cleared": cleared,
        "wave_final": n,
        "stall": stall,
        "data": data,
        "ammo_vi": ammo_spent_vi,
        "capped": dt_seconds > cap_h * 3600.0,
    }


def ammo_drain(turret_counts, duty_cycle=0.40):
    """Munizioni/s consumate dallo schieramento. E' il costo-opportunita'
    diretto sui Dati: ogni munizione bruciata e' VI che NON arriva al Core."""
    return sum(TURRETS[t][T_AMMO] * TURRETS[t][T_RATE] * c
               for t, c in turret_counts.items()) * duty_cycle


# =============================================================================
# SEZIONE 4 — RICERCA
# =============================================================================
# Costo per livello di un upgrade ripetibile: C(L) = base * growth^L
RESEARCH_NODES = [
    # id, nome, costo, prereq, effetto
    ("log_belts_1",    "Nastri Rinforzati",         120,   [],                    "Nastri 6 -> 9 slot/s (+50%)"),
    ("mine_drills_1",  "Punte al Tungsteno",        150,   [],                    "Trivelle +25% velocita'"),
    ("proc_washing",   "Purificazione a Umido",     400,   ["mine_drills_1"],     "Sblocca Purificatore + Pompa Idrica"),
    ("pow_briquette",  "Recupero Scorie",           550,   ["proc_washing"],      "Sblocca Compattatore + Generatore Termico"),
    ("def_ballistics", "Calibratura Balistica",     300,   [],                    "+6%/liv danno torrette (10 liv, x1.35)"),
    ("data_servers_1", "Bus Dati Parallelo",        900,   ["proc_washing"],      "Server 2.0 -> 2.6 item/s"),
    ("proc_alloy",     "Metallurgia Induttiva",    2400,   ["pow_briquette", "data_servers_1"], "Sblocca Fonderia a Induzione 2x2"),
    ("def_turret_frag","Testate a Frammentazione", 1800,   ["def_ballistics"],    "Sblocca Torretta a Frammentazione"),
    ("idle_uplink_1",  "Uplink Autonomo",          3000,   ["data_servers_1"],    "Offline 40%->55%, cap 8h->12h"),
    ("pow_efficiency", "Isolamento Criogenico",    3500,   ["pow_briquette"],     "-20% consumo energetico"),
    ("act_overclock",  "Protocollo Overclock",     5000,   ["proc_alloy"],        "Abilita' Overclock x2.5 / 45s / CD 10min"),
    ("data_compress",  "Compressione Entropica",   9000,   ["idle_uplink_1", "proc_alloy"], "Dati per VI x1.5"),
]


def repeatable_cost(base, growth, level):
    return base * (growth ** level)


def cumulative_cost(base, growth, levels):
    return base * ((growth ** levels) - 1) / (growth - 1)


# =============================================================================
# SEZIONE 5 — BASE DI RIFERIMENTO MVP ("Reference Base")
# =============================================================================
# Questa e' la base che il giocatore dovrebbe avere alla fine del tutorial
# esteso. Tutti i numeri del gioco sono tarati su di essa.

REFERENCE_BASE = {
    "Trivella (ferro)":            4,
    "Trituratore":                 4,
    "Purificatore":                4,
    "Pompa Idrica":                2,
    "Fornace":                    12,
    "Compattatore":                2,
    "Generatore Termico":          5,
    "Server":                      2,
    "Torretta Cinetica":           4,
}

MACHINE_KW = {
    "Trivella (ferro)": 6, "Trituratore": 12, "Purificatore": 18, "Pompa Idrica": 8,
    "Fornace": 10, "Compattatore": 14, "Generatore Termico": 0, "Server": 25,
    "Torretta Cinetica": 15,
}

STARTER_GENERATOR_KW = 120
THERMAL_GENERATOR_KW = 60


# =============================================================================
# STAMPA TABELLE
# =============================================================================

def hr(title=""):
    print("\n" + "=" * 78)
    if title:
        print(" " + title)
        print("=" * 78)


def t_materials():
    hr("TABELLA 1 — MATERIALI E VALORE INDUSTRIALE (VI = base * 2.5^R)")
    print(f"{'ID':<14}{'Nome':<38}{'R':>2}{'base':>7}{'VI':>10}")
    print("-" * 78)
    for mid, (name, r, base) in MATERIALS.items():
        print(f"{mid:<14}{name:<38}{r:>2}{base:>7.2f}{vi(mid):>10.3f}")


def t_chain():
    hr("TABELLA 2 — CATENA COMPLETA vs SCORCIATOIA (per 1 Minerale Grezzo)")
    long_out = 2.0          # 1 ore -> 2 dust -> 2 pdust -> 2 ingot
    long_slag = 1.0         # + 1 fanghiglia ogni 2 polveri lavate
    short_out = 1.0
    v_long = long_out * vi("ingot_iron") + long_slag * vi("slag")
    v_short = short_out * vi("ingot_iron")
    print(f"  Catena lunga  (Trivella->Trituratore->Purificatore->Fornace)")
    print(f"     resa : {long_out:.1f} Lingotti + {long_slag:.1f} Fanghiglia")
    print(f"     VI   : {v_long:.3f}")
    print(f"     costo: 4 tipi di macchina, acqua, 46 kW per linea")
    print(f"  Scorciatoia   (Trivella->Fornace diretta)")
    print(f"     resa : {short_out:.1f} Lingotti")
    print(f"     VI   : {v_short:.3f}")
    print(f"     costo: 2 tipi di macchina, niente acqua, 16 kW per linea")
    print(f"  --> GUADAGNO DELLA CATENA LUNGA: x{v_long / v_short:.2f} in VI per minerale")
    print()
    print(f"  Conferire il MINERALE GREZZO al Core          : {vi('ore_iron'):>8.2f} VI")
    print(f"  Conferire il LINGOTTO da catena lunga (x2)    : {v_long:>8.2f} VI")
    print(f"  --> MOLTIPLICATORE DI RAFFINAZIONE            : x{v_long / vi('ore_iron'):.1f}")


def t_ratios():
    hr("TABELLA 3 — RAPPORTI DI MACCHINA (linea ferro, catena completa)")
    r_drill = machine_rate("drill_iron", "ore_iron")
    r_crush_in = machine_rate("crush_iron", "ore_iron", "in")
    r_crush_out = machine_rate("crush_iron", "dust_iron")
    r_wash_in = machine_rate("wash_iron", "dust_iron", "in")
    r_wash_out = machine_rate("wash_iron", "pdust_iron")
    r_wash_water = machine_rate("wash_iron", "water_mb", "in")
    r_smelt_in = machine_rate("smelt_iron", "pdust_iron", "in")
    r_pump = machine_rate("pump_water", "water_mb")

    print(f"  Trivella      : produce  {r_drill:.3f} minerale/s")
    print(f"  Trituratore   : consuma  {r_crush_in:.3f} minerale/s -> produce {r_crush_out:.3f} polvere/s")
    print(f"  Purificatore  : consuma  {r_wash_in:.3f} polvere/s   -> produce {r_wash_out:.3f} polvere pura/s  (+{machine_rate('wash_iron','slag'):.2f} fanghiglia/s, {r_wash_water:.0f} mB acqua/s)")
    print(f"  Fornace       : consuma  {r_smelt_in:.3f} pol.pura/s -> produce {machine_rate('smelt_iron','ingot_iron'):.3f} lingotti/s")
    print(f"  Pompa Idrica  : produce  {r_pump:.0f} mB acqua/s")
    print()
    n_drill = 4
    n_crush = n_drill * r_drill / r_crush_in
    n_wash = n_crush * r_crush_out / r_wash_in
    n_smelt = n_wash * r_wash_out / r_smelt_in
    n_pump = n_wash * r_wash_water / r_pump
    print(f"  RAPPORTO DI LINEA per {n_drill} trivelle:")
    print(f"     {n_drill:.0f} Trivella : {n_crush:.0f} Trituratore : {n_wash:.0f} Purificatore : {n_smelt:.0f} Fornace : {n_pump:.0f} Pompa")
    print(f"     ratio normalizzato  ->  1 : 1 : 1 : {n_smelt/n_crush:.0f} : {n_pump/n_wash:.1f}")
    print(f"  Output finale: {n_smelt * machine_rate('smelt_iron','ingot_iron'):.2f} lingotti/s")
    return n_smelt * machine_rate("smelt_iron", "ingot_iron")


def t_slag_loop():
    hr("TABELLA 4 — CICLO CHIUSO SCORIE -> ENERGIA")
    n_wash = 4
    slag_s = n_wash * machine_rate("wash_iron", "slag")
    comp_in = machine_rate("compact_slag", "slag", "in")
    comp_out = machine_rate("compact_slag", "briquette")
    n_comp = slag_s / comp_in
    briq_s = n_comp * comp_out
    gen_burn = 1.0 / THERMAL_BURN_S
    print(f"  {n_wash} Purificatori producono  : {slag_s:.2f} fanghiglia/s")
    print(f"  Servono                  : {n_comp:.0f} Compattatori  -> {briq_s:.2f} bricchette/s")
    print(f"  1 Generatore Termico brucia {gen_burn:.2f} bricchette/s per {THERMAL_GENERATOR_KW} kW")
    print(f"  Bricchette sostenibili   : {briq_s / gen_burn:.0f} generatori = {briq_s / gen_burn * THERMAL_GENERATOR_KW:.0f} kW")
    print(f"  --> il ciclo si CHIUDE: nessuna fanghiglia viene sprecata, nessun")
    print(f"      combustibile viene importato dall'esterno della fabbrica.")
    return briq_s, gen_burn


def t_power(briq_s, gen_burn):
    hr("TABELLA 5 — BILANCIO ENERGETICO DELLA BASE DI RIFERIMENTO")
    total = 0
    print(f"{'Edificio':<26}{'n':>4}{'kW cad':>9}{'kW tot':>10}")
    print("-" * 78)
    for name, count in REFERENCE_BASE.items():
        kw = MACHINE_KW[name]
        total += kw * count
        print(f"{name:<26}{count:>4}{kw:>9}{kw*count:>10}")
    print("-" * 78)
    print(f"{'DOMANDA TOTALE':<26}{'':>4}{'':>9}{total:>10} kW")
    n_gen = REFERENCE_BASE["Generatore Termico"]
    supply = STARTER_GENERATOR_KW + n_gen * THERMAL_GENERATOR_KW
    print(f"{'Generatore d Avvio':<26}{1:>4}{STARTER_GENERATOR_KW:>9}{STARTER_GENERATOR_KW:>10}")
    print(f"{'Generatore Termico':<26}{n_gen:>4}{THERMAL_GENERATOR_KW:>9}{n_gen*THERMAL_GENERATOR_KW:>10}")
    print(f"{'OFFERTA TOTALE':<26}{'':>4}{'':>9}{supply:>10} kW")
    sigma = min(1.0, supply / total)
    print(f"\n  Soddisfazione di rete  sigma = min(1, offerta/domanda) = {sigma:.3f}")
    print(f"  --> tutte le macchine girano al {sigma*100:.1f}% della velocita' nominale")
    burn_needed = n_gen * gen_burn
    print(f"  Bricchette richieste: {burn_needed:.2f}/s  |  prodotte: {briq_s:.2f}/s  |  margine: {briq_s-burn_needed:+.2f}/s")
    return total, supply, sigma


def t_data(ingot_s):
    hr("TABELLA 6 — GENERAZIONE DATI (motore incrementale)")
    eta = 1.0
    server_cap = 2.0
    print("  Formula:  D_dot = eta_server * SOMMA_i( rate_i [item/s] * VI_i )")
    print(f"  Cap per Server: {server_cap} item/s\n")
    scenarios = [
        ("Minerale grezzo al Core (nessuna raffinazione)", "ore_iron", 2.0),
        ("Polvere R1 al Core",                             "dust_iron", 4.0),
        ("Polvere pura R2 al Core",                        "pdust_iron", 4.0),
        ("Lingotti R3 al Core (base di riferimento)",      "ingot_iron", ingot_s),
        ("Lega Conduttiva R4 al Core",                     "alloy_cond", 0.667),
    ]
    print(f"{'Scenario':<48}{'item/s':>8}{'VI/s':>10}{'Dati/s':>10}")
    print("-" * 78)
    base_line = None
    for label, mid, rate in scenarios:
        theta = rate * vi(mid)
        d = eta * theta
        if base_line is None:
            base_line = d
        print(f"{label:<48}{rate:>8.2f}{theta:>10.2f}{d:>10.2f}")
    theta_ref_base = ingot_s * vi("ingot_iron")
    print(f"\n  --> La base di riferimento genera Theta = {theta_ref_base:.2f} VI/s = {theta_ref_base:.2f} Dati/s")
    print(f"  --> contro i {2.0*vi('ore_iron'):.2f} Dati/s del minerale grezzo: x{theta_ref_base/(2.0*vi('ore_iron')):.1f}")
    return theta_ref_base


def t_ammo_efficiency():
    hr("TABELLA 7 — EFFICIENZA MUNIZIONI: DANNO PER VI SPESO")
    print("  La decisione centrale del gioco: lo stesso materiale puo' andare")
    print("  al Core (Dati) o in torretta (sopravvivenza). Chi vince?\n")
    print(f"{'Tier':>5}{'Esempio':<32}{'VI':>9}{'Molt. danno':>13}{'Danno/VI':>11}{'vs corazzato':>14}")
    print("-" * 84)
    examples = {0: "ore_iron", 1: "dust_iron", 2: "pdust_iron", 3: "ingot_iron", 4: "alloy_cond"}
    rows = []
    for r in range(5):
        mid = examples[r]
        m = ammo_mult(r)
        v = vi(mid)
        raw = TURRETS["kinetic"][T_DMG] * m
        eff = effective_damage(raw, ENEMIES["armored"][E_ARMOR])
        rows.append((r, m, v, m / v, eff / v))
        print(f"{r:>5}  {MATERIALS[mid][0]:<30}{v:>9.2f}{m:>13.2f}{m/v:>11.3f}{eff/v:>14.3f}")
    print("\n  LETTURA: contro nemici SENZA armatura il tier basso (R1) e' il piu'")
    print("  efficiente per VI speso -> conviene sparare polvere e mandare i")
    print("  lingotti al Core. Contro i CORAZZATI l'armatura piatta ribalta la")
    print("  classifica -> serve munizione alto tier. E' la tensione voluta.")
    return rows


LOADOUTS = [
    ("L1  4 Cinetiche  / mun. R1 / balistica  0", {"kinetic": 4}, 1, 0),
    ("L2  4 Cinetiche  / mun. R3 / balistica  0", {"kinetic": 4}, 3, 0),
    ("L3  8 Cinetiche  / mun. R3 / balistica  5", {"kinetic": 8}, 3, 5),
    ("L4  8 Cin + 4 Frag / mun. R4 / balistica 10", {"kinetic": 8, "frag": 4}, 4, 10),
    ("L5 16 Cin + 8 Frag / mun. R4 / balistica 20", {"kinetic": 16, "frag": 8}, 4, 20),
]


def t_threat_curve(theta_base):
    hr("TABELLA 8 — CURVA MINACCIA vs CAPACITA' DIFENSIVA")
    print("  HP_ondata(n) = 150 * (1+0.22n)^1.55 * (1+Theta/20)^0.80")
    print(f"  Theta base di riferimento = {theta_base:.1f} VI/s")
    print(f"  Finestra di ingaggio: {CORRIDOR_TILES:.0f} celle di corridoio coperto\n")

    print("  DPS EFFICACE DEGLI SCHIERAMENTI (pesato sulla composizione ondata):")
    print(f"{'':>4}{'Schieramento':<46}{'ond.10':>9}{'ond.20':>9}{'ond.40':>9}{'mun/s':>8}")
    print("-" * 88)
    for name, tc, at, bl in LOADOUTS:
        print(f"{'':>4}{name:<46}{wave_dps(tc,at,10,bl):>9.0f}{wave_dps(tc,at,20,bl):>9.0f}"
              f"{wave_dps(tc,at,40,bl):>9.0f}{ammo_drain(tc):>8.2f}")

    for theta, label in [(theta_base, "base di riferimento"), (theta_base * 5, "base ampliata x5")]:
        print(f"\n  --- Theta = {theta:.1f} VI/s ({label}) ---")
        print(f"{'Ondata':>7}{'HP budget':>12}{'Finestra':>10}{'DPS rich.':>11}   Schieramenti sufficienti")
        print("-" * 88)
        for n in [1, 5, 10, 15, 20, 25, 30, 40, 50]:
            hpb = hp_budget(n, theta)
            window = engagement_window(n)
            need = hpb / window
            ok = [name.split()[0] for name, tc, at, bl in LOADOUTS
                  if wave_dps(tc, at, n, bl) >= need]
            mark = ", ".join(ok) if ok else "*** NESSUNO -- BASE PERSA ***"
            print(f"{n:>7}{hpb:>12.0f}{window:>9.1f}s{need:>11.0f}   {mark}")

    print("\n  ONDATA MASSIMA SOSTENIBILE (Theta base):")
    survival = {}
    for name, tc, at, bl in LOADOUTS:
        last = 0
        for n in range(1, 121):
            if wave_dps(tc, at, n, bl) >= hp_budget(n, theta_base) / engagement_window(n):
                last = n
            else:
                break
        survival[name] = last
        print(f"     {name:<46} -> ondata {last}")
    return survival


def t_feedback_loop(theta_base):
    hr("TABELLA 9 — IL LOOP DI RETROAZIONE NEGATIVA (auto-stabilizzazione)")
    print("  La minaccia e' ancorata a cio' che ARRIVA AL CORE, non a cio' che")
    print("  produci. Bruciare materiale in torretta abbassa quindi Theta e")
    print("  automaticamente le ondate future. Il sistema non puo' divergere.\n")
    tc = {"kinetic": 4}
    drain = ammo_drain(tc)
    print(f"  Schieramento: 4 Torrette Cinetiche, duty cycle 40%")
    print(f"  Consumo munizioni: {drain:.2f} item/s")
    print(f"{'Munizione':<22}{'VI sottratto/s':>16}{'Theta residuo':>16}{'HP ond.20':>12}{'delta':>9}")
    print("-" * 78)
    base_hp = hp_budget(20, theta_base)
    for mid in ["dust_iron", "pdust_iron", "ingot_iron"]:
        lost = drain * vi(mid)
        th = max(0.0, theta_base - lost)
        h = hp_budget(20, th)
        print(f"{MATERIALS[mid][0]:<22}{lost:>16.2f}{th:>16.2f}{h:>12.0f}{(h/base_hp-1)*100:>8.1f}%")
    print(f"\n  (riferimento senza consumo: Theta={theta_base:.2f}, HP ondata 20 = {base_hp:.0f})")


def t_research(theta_base):
    hr("TABELLA 10 — ALBERO DI RICERCA MVP (12 nodi) E TEMPI DI SBLOCCO")
    print("  Tempo stimato assumendo produzione crescente in 3 fasi:")
    print("    fase A (pre-lavaggio)  ~  5 Dati/s")
    print("    fase B (post-lavaggio) ~ 25 Dati/s")
    print("    fase C (base rif.)     ~ %.0f Dati/s\n" % theta_base)
    print(f"{'#':>3} {'Nodo':<28}{'Costo':>8}  {'Prereq':<34}{'~tempo':>9}")
    print("-" * 90)
    cum = 0
    for i, (nid, name, cost, prereq, _eff) in enumerate(RESEARCH_NODES, 1):
        cum += cost
        rate = 5.0 if cum < 700 else (25.0 if cum < 5000 else theta_base)
        t = cost / rate
        tstr = f"{t:.0f}s" if t < 120 else f"{t/60:.1f}min"
        print(f"{i:>3} {name:<28}{cost:>8}  {','.join(prereq) if prereq else '-':<34}{tstr:>9}")
    print(f"\n  Costo totale albero MVP: {cum} Dati")
    print(f"  Upgrade ripetibile 'Calibratura Balistica': C(L) = 300 * 1.35^L")
    for L in [0, 5, 10, 20, 30]:
        print(f"     livello {L:>2}: {repeatable_cost(300, 1.35, L):>12,.0f} Dati   (+{6*L}% danno)   cumulato {cumulative_cost(300,1.35,L):>14,.0f}")


def t_combat_reward(theta_base):
    hr("TABELLA 11 — RICOMPENSA DA COMBATTIMENTO (Dati per ondata respinta)")
    print("  D_ondata = kappa * Theta * intervallo(n),  kappa = %.2f" % KAPPA_COMBAT_DATA)
    print("  Definita come FRAZIONE dell'industria, non come funzione degli HP:")
    print("  cosi' il combattimento vale sempre il 16.7%% del totale, a ogni scala,")
    print("  e non puo' MAI diventare il motore trainante al posto della logistica.\n")
    print(f"{'Ondata':>7}{'interv.':>9}{'D industria':>14}{'D combatt.':>13}{'quota':>8}"
          f"{'mun. VI (R1)':>14}{'netto':>12}")
    print("-" * 82)
    tc, at, bl = {"kinetic": 8}, 1, 5
    for n in [5, 10, 20, 30, 40, 50, 60, 70]:
        iv = wave_interval(n)
        d_ind = theta_base * iv
        d_cmb = combat_data_reward(theta_base, n)
        cost, _units = ammo_vi_cost_per_wave(tc, at, bl, n, theta_base)
        print(f"{n:>7}{iv:>8.0f}s{d_ind:>14,.0f}{d_cmb:>13,.0f}"
              f"{d_cmb/(d_ind+d_cmb)*100:>7.1f}%{cost:>14,.0f}{d_cmb-cost:>+12,.0f}")
    print("\n  'netto' = Dati guadagnati meno il VI di munizioni bruciato.")
    print("  Resta positivo per tutto l'arco MVP e diventa un costo reale oltre")
    print("  l'ondata ~68: nel late game difendersi PESA, ed e' voluto.")


def t_offline(theta_base):
    hr("TABELLA 12 — PROGRESSIONE OFFLINE (timer ondate ATTIVO)")
    print("  Regole:")
    print("    - il timer ondate AVANZA a gioco chiuso e le ondate vengono risolte")
    print("    - la base resta INVULNERABILE: se la difesa non basta il fronte si")
    print("      BLOCCA su quell'ondata (la linea tiene ma non avanza)")
    print("    - le munizioni VENGONO consumate: difendersi offline costa davvero")
    print("    - la produzione gira a eta_offline, con tetto orario\n")

    print(f"{'Assenza':>9}{'ondate':>8}{'ondata':>8}{'stallo':>12}{'Dati':>14}{'mun. VI':>11}")
    print("-" * 68)
    for h in [0.25, 0.5, 1, 2, 4, 8, 12, 24]:
        r = simulate_offline(h * 3600, 20, {"kinetic": 8}, 3, 5, theta_base)
        print(f"{h:>8.2f}h{r['waves_cleared']:>8}{r['wave_final']:>8}"
              f"{(r['stall'] or '-'):>12}{r['data']:>14,.0f}{r['ammo_vi']:>11,.0f}")

    print("\n  Scenario: rientro dall'ondata 20 con 8 Cinetiche, munizione R3, balistica 5")
    print("  (schieramento L3, che regge fino all'ondata 35).")
    print("  --> il fronte si blocca da solo al limite naturale della difesa.")
    print("      Non puoi rientrare e trovarti all'ondata 300.")

    print("\n  CONFRONTO SCHIERAMENTI (8 h di assenza, partendo dall'ondata 20):")
    print(f"{'':>4}{'Schieramento':<46}{'ondate':>8}{'arriva a':>10}{'stallo':>12}")
    print("-" * 82)
    for name, tc, at, bl in LOADOUTS:
        r = simulate_offline(8 * 3600, 20, tc, at, bl, theta_base)
        print(f"{'':>4}{name:<46}{r['waves_cleared']:>8}{r['wave_final']:>10}"
              f"{(r['stall'] or '-'):>12}")
    print("\n  --> la progressione idle delle ondate e' LIMITATA DALLA DIFESA.")
    print("      Costruire torrette sblocca avanzamento offline: e' il collegamento")
    print("      che mancava fra il terzo genere (difesa) e lo strato incrementale.")

    print("\n  DATI TOTALI ACCUMULATI (industria + combattimento - munizioni):")
    print(f"{'Assenza':>9}{'eta=0.40 cap 8h':>20}{'eta=0.55 cap 12h':>20}")
    print("-" * 50)
    for h in [0.5, 2, 8, 12, 24]:
        a = simulate_offline(h*3600, 20, {"kinetic": 8}, 3, 5, theta_base, 0.40, 8.0)
        b = simulate_offline(h*3600, 20, {"kinetic": 8}, 3, 5, theta_base, 0.55, 12.0)
        print(f"{h:>8.1f}h{a['data']:>20,.0f}{b['data']:>20,.0f}")


def t_perf():
    hr("TABELLA 13 — BUDGET PRESTAZIONALE MOBILE (target: 60 fps su A12 / Snapdragon 730)")
    rows = [
        ("Tick logico",              f"{TICK_HZ} Hz", "5.0 ms/tick max = 10% CPU"),
        ("Edifici simulati",         "<= 2 000",      "aggiornati solo se 'attivi' (dirty set)"),
        ("Item su nastro",           "<= 6 000",      "NON sono nodi: array compressi per corsia"),
        ("Draw call item",           "1",             "MultiMeshInstance2D unico"),
        ("Nemici simultanei",        "<= 250",        "MultiMesh + flow field, 0 pathfinding per-nemico"),
        ("Ricalcolo flow field",     "<= 1 / 500 ms", "debounced, su thread separato"),
        ("Risoluzione grafo produz.","1 / 2 s",       "ordinamento topologico incrementale"),
        ("Save",                     "1 / 30 s",      "binario, su thread, < 8 ms"),
    ]
    print(f"{'Voce':<28}{'Budget':<16}{'Nota'}")
    print("-" * 78)
    for a, b, c in rows:
        print(f"{a:<28}{b:<16}{c}")


# =============================================================================
# INVARIANTI DI DESIGN — se una di queste fallisce, il gioco e' rotto
# =============================================================================

def check_invariants(verbose=True):
    fails = []

    def req(cond, msg):
        if not cond:
            fails.append(msg)
        elif verbose:
            print(f"  [OK]   {msg}")

    hr("INVARIANTI DI DESIGN")

    # 1. Raffinare deve SEMPRE convenire rispetto alla scorciatoia.
    v_long = 2.0 * vi("ingot_iron") + 1.0 * vi("slag")
    req(v_long >= 1.8 * vi("ingot_iron"),
        "La catena lunga rende almeno 1.8x la scorciatoia (attuale: %.2fx)" % (v_long / vi("ingot_iron")))

    # 2. Conferire materiale raffinato deve battere il grezzo di almeno 20x.
    req(v_long / vi("ore_iron") >= 20,
        "Raffinare batte il minerale grezzo di >=20x (attuale: %.1fx)" % (v_long / vi("ore_iron")))

    # 3. Espandere la produzione deve essere net-positivo (esponente minaccia < 1).
    req(THREAT_P < 1.0,
        "Esponente industriale della minaccia < 1 -> espandere conviene (%.2f)" % THREAT_P)

    # 4. Salire di tier NON deve da solo risolvere la difesa (serve anche scala).
    #    Confronto: guadagno di danno vs guadagno di minaccia, per tier.
    worst = None
    for r in range(1, 5):
        gain_dmg = ammo_mult(r) / ammo_mult(0)
        gain_threat = (LAMBDA ** r) ** THREAT_P
        ratio = gain_dmg / gain_threat
        if worst is None or ratio < worst[1]:
            worst = (r, ratio)
    req(worst[1] < 1.0,
        "Almeno un tier alto va in deficit difensivo -> obbliga a espandere (R%d: %.2f)" % worst)

    # 5. I Dati devono crescere piu' in fretta della minaccia (il giocatore vince).
    r = 4
    data_gain = LAMBDA ** r
    threat_gain = (LAMBDA ** r) ** THREAT_P
    req(data_gain / threat_gain > 1.5,
        "I Dati superano la minaccia salendo di tier (R4: x%.2f di vantaggio)" % (data_gain / threat_gain))

    # 6. Il ciclo scorie deve chiudersi (auto-sostenibile) senza sprechi.
    slag_s = 4 * machine_rate("wash_iron", "slag")
    briq_s = (slag_s / machine_rate("compact_slag", "slag", "in")) * machine_rate("compact_slag", "briquette")
    need = REFERENCE_BASE["Generatore Termico"] * (1.0 / THERMAL_BURN_S)
    req(briq_s >= need,
        "Il ciclo scorie->energia si autoalimenta (%.2f prodotte vs %.2f richieste bricchette/s)" % (briq_s, need))
    req(briq_s - need < 0.10,
        "Il ciclo scorie non produce surplus sprecato (margine %.3f bricchette/s)" % (briq_s - need))

    # 7. La rete elettrica della base di riferimento deve essere satura ma non in deficit.
    demand = sum(MACHINE_KW[k] * v for k, v in REFERENCE_BASE.items())
    supply = STARTER_GENERATOR_KW + REFERENCE_BASE["Generatore Termico"] * THERMAL_GENERATOR_KW
    req(supply >= demand,
        "Offerta energetica >= domanda nella base di riferimento (%d >= %d kW)" % (supply, demand))
    req(supply / demand <= 1.30,
        "Margine energetico <= 30%% -> l'energia resta un problema da ingegnerizzare (%.0f%%)" % ((supply/demand - 1) * 100))

    # 8. Munizione bassa piu' efficiente per VI contro non corazzati, alta contro corazzati.
    eff_low = ammo_mult(1) / vi("dust_iron")
    eff_high = ammo_mult(3) / vi("ingot_iron")
    req(eff_low > eff_high,
        "Munizione R1 piu' efficiente per VI di R3 contro bersagli nudi (%.3f > %.3f)" % (eff_low, eff_high))
    a_low = effective_damage(TURRETS["kinetic"][T_DMG] * ammo_mult(1), 60) / vi("dust_iron")
    a_high = effective_damage(TURRETS["kinetic"][T_DMG] * ammo_mult(3), 60) / vi("ingot_iron")
    req(a_high > a_low,
        "Contro i corazzati la classifica si ribalta (R3 %.3f > R1 %.3f)" % (a_high, a_low))

    # 9. Il primo nodo di ricerca deve arrivare entro 60 s dal primo Server.
    first = RESEARCH_NODES[0][2]
    req(first / 5.0 <= 60,
        "Primo nodo di ricerca raggiungibile in <=60s (%.0fs)" % (first / 5.0))

    # 10. Nessun rapporto di macchina deve essere frazionario nella linea base.
    n_smelt = (4 * machine_rate("drill_iron", "ore_iron") / machine_rate("crush_iron", "ore_iron", "in")) \
              * machine_rate("crush_iron", "dust_iron") / machine_rate("wash_iron", "dust_iron", "in") \
              * machine_rate("wash_iron", "pdust_iron") / machine_rate("smelt_iron", "pdust_iron", "in")
    req(abs(n_smelt - round(n_smelt)) < 1e-9,
        "I rapporti di linea sono numeri interi (Fornaci = %.4f)" % n_smelt)

    # 14. Il combattimento non deve MAI diventare la fonte primaria di Dati.
    #     (protegge "la logistica e la generazione di Dati sono il motore trainante")
    theta_r = 4.0 * vi("ingot_iron")
    worst_share = 0.0
    for n in range(1, 121):
        d_ind = theta_r * wave_interval(n)
        d_cmb = combat_data_reward(theta_r, n)
        worst_share = max(worst_share, d_cmb / (d_ind + d_cmb))
    req(worst_share <= 0.25,
        "I Dati da combattimento restano <=25%% del totale a ogni ondata (max %.1f%%)" % (worst_share * 100))

    # 15. Offline: il fronte deve BLOCCARSI, mai lasciar correre il timer all'infinito.
    r = simulate_offline(24 * 3600, 20, {"kinetic": 8}, 3, 5, theta_r)
    req(r["stall"] is not None,
        "Dopo 24h offline il fronte si blocca invece di correre (ondata %d, causa: %s)"
        % (r["wave_final"], r["stall"]))
    # 15b. Il punto di stallo offline NON deve superare il tetto difensivo online:
    #      altrimenti il giocatore rientra a un'ondata che non puo' vincere da sveglio.
    online_cap = 0
    for k in range(1, 200):
        if wave_dps({"kinetic": 8}, 3, k, 5) >= hp_budget(k, theta_r) / engagement_window(k):
            online_cap = k
        else:
            break
    req(r["wave_final"] <= online_cap,
        "Lo stallo offline non supera il tetto difensivo online (offline %d <= online %d)"
        % (r["wave_final"], online_cap))

    # 16. Offline: piu' difesa = piu' avanzamento. Deve essere monotono.
    prev = -1
    mono = True
    for _name, tc, at, bl in LOADOUTS:
        w = simulate_offline(8 * 3600, 20, tc, at, bl, theta_r)["waves_cleared"]
        if w < prev:
            mono = False
        prev = w
    req(mono, "Offline: uno schieramento migliore avanza sempre di piu' (monotonia)")

    # 17. Respingere un'ondata deve restare profittevole per tutto l'arco MVP.
    net50 = combat_data_reward(theta_r, 50) - ammo_vi_cost_per_wave({"kinetic": 8}, 1, 5, 50, theta_r)[0]
    req(net50 > 0,
        "Difendersi resta profittevole fino all'ondata 50 (netto %+.0f Dati)" % net50)

    print()
    if fails:
        print("  !!! %d INVARIANTI VIOLATE:" % len(fails))
        for f in fails:
            print("      - " + f)
        return False
    print("  Tutte le invarianti di design sono soddisfatte.")
    return True


def export_csv(path):
    """Esporta il foglio di calcolo di riferimento (apribile in Excel / Numbers /
    Google Sheets). Il GDD chiedeva un file di calcolo per mappare i processi:
    questo lo GENERA dai numeri veri invece di tenerlo a mano e desincronizzarlo."""
    import csv
    theta = 4.0 * vi("ingot_iron")
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)

        w.writerow(["# FOGLIO DI BILANCIAMENTO — generato da tools/balance_sim.py. NON modificare a mano."])
        w.writerow([])
        w.writerow(["=== MATERIALI ==="])
        w.writerow(["id", "nome", "tier_R", "base_value", "VI",
                    "munizione_valida", "danno_x", "danno_per_VI"])
        for mid, (name, r, base) in MATERIALS.items():
            ok = mid not in NON_AMMO
            w.writerow([mid, name, r, f"{base:.2f}", f"{vi(mid):.4f}",
                        "si" if ok else "NO",
                        f"{ammo_mult(r):.4f}" if ok else "-",
                        f"{ammo_mult(r)/vi(mid):.4f}" if ok else "-"])

        w.writerow([])
        w.writerow(["=== RICETTE ==="])
        w.writerow(["id", "macchina", "input", "output", "ciclo_s", "kW", "output_per_s"])
        for rid, (mach, ins, outs, sec, kw) in RECIPES.items():
            main_out = next(iter(outs.items())) if outs else ("", 0)
            rate = (main_out[1] / sec) if isinstance(main_out[1], (int, float)) else ""
            w.writerow([rid, mach,
                        "; ".join(f"{k}x{v}" for k, v in ins.items()) or "-",
                        "; ".join(f"{k}x{v}" for k, v in outs.items()) or "-",
                        f"{sec:.2f}", kw, f"{rate:.4f}" if rate != "" else ""])

        w.writerow([])
        w.writerow(["=== BASE DI RIFERIMENTO ==="])
        w.writerow(["edificio", "quantita", "kW_cad", "kW_tot"])
        tot = 0
        for name, count in REFERENCE_BASE.items():
            tot += MACHINE_KW[name] * count
            w.writerow([name, count, MACHINE_KW[name], MACHINE_KW[name] * count])
        w.writerow(["DOMANDA TOTALE", "", "", tot])
        w.writerow(["OFFERTA TOTALE", "", "",
                    STARTER_GENERATOR_KW + REFERENCE_BASE["Generatore Termico"] * THERMAL_GENERATOR_KW])

        w.writerow([])
        w.writerow(["=== CURVA ONDATE (Theta = %.1f) ===" % theta])
        w.writerow(["ondata", "HP_budget", "finestra_s", "DPS_richiesto", "intervallo_s"]
                   + [name.split()[0] for name, *_ in LOADOUTS])
        for n in range(1, 61):
            hpb = hp_budget(n, theta)
            win = engagement_window(n)
            row = [n, f"{hpb:.0f}", f"{win:.2f}", f"{hpb/win:.0f}", f"{wave_interval(n):.0f}"]
            for _name, tc, at, bl in LOADOUTS:
                row.append(f"{wave_dps(tc, at, n, bl):.0f}")
            w.writerow(row)

        w.writerow([])
        w.writerow(["=== ALBERO DI RICERCA ==="])
        w.writerow(["#", "id", "nome", "costo", "prereq", "effetto"])
        for i, (nid, name, cost, prereq, eff) in enumerate(RESEARCH_NODES, 1):
            w.writerow([i, nid, name, cost, "|".join(prereq), eff])

        w.writerow([])
        w.writerow(["=== CALIBRATURA BALISTICA (ripetibile) ==="])
        w.writerow(["livello", "costo_livello", "costo_cumulato", "bonus_danno"])
        for L in range(0, 31):
            w.writerow([L, f"{repeatable_cost(300,1.35,L):.0f}",
                        f"{cumulative_cost(300,1.35,L):.0f}", f"{6*L}%"])
    print(f"Foglio di calcolo scritto in: {path}")


def main():
    if "--csv" in sys.argv:
        i = sys.argv.index("--csv")
        path = sys.argv[i + 1] if len(sys.argv) > i + 1 else "data/balance_reference.csv"
        export_csv(path)
        return 0

    only_check = "--check" in sys.argv
    if not only_check:
        print("#" * 78)
        print("#  FACTORY-DEFENSE INCREMENTALE A NODI — REPORT DI BILANCIAMENTO")
        print("#  generato da tools/balance_sim.py")
        print("#" * 78)
        t_materials()
        t_chain()
        ingot_s = t_ratios()
        briq_s, gen_burn = t_slag_loop()
        t_power(briq_s, gen_burn)
        theta = t_data(ingot_s)
        t_ammo_efficiency()
        t_threat_curve(theta)
        t_feedback_loop(theta)
        t_research(theta)
        t_combat_reward(theta)
        t_offline(theta)
        t_perf()
    ok = check_invariants(verbose=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
