"""Generates assets/levels/levels.json (same rules as scripts/puzzle.gd).
   python tools/gen_levels.py
Every level is a random deal that a weighted-A* solver proved solvable; 'par' is the solver's
move count (near-optimal), 'sol' its solution (replayed by the autotest), 'h' hidden-layer flags."""
import heapq, json, random, os, sys, time
from multiprocessing import Pool

CAP = 4
WORLD_COLORS = [(3, 6), (5, 7), (6, 8), (7, 9), (8, 10), (9, 12)]
HIDDEN = [0.0, 0.0, 0.0, 0.4, 0.3, 0.5]
PER_WORLD = 20
CANDIDATES = 5


def run_len(b):
    if not b:
        return 0
    c = b[-1]; n = 0
    for u in reversed(b):
        if u == c: n += 1
        else: break
    return n


def complete(b):
    return len(b) == CAP and run_len(b) == CAP


def segments(s):
    n = 0
    for b in s:
        last = 0
        for u in b:
            if u != last:
                n += 1; last = u
    return n


def solved(s):
    return all(not b or complete(b) for b in s)


def moves(s):
    first_empty_done = False
    for i, a in enumerate(s):
        if not a or complete(a):
            continue
        ra = run_len(a); ta = a[-1]
        empty_done = False
        for j, b in enumerate(s):
            if i == j or len(b) >= CAP:
                continue
            if not b:
                if ra == len(a) or empty_done:
                    continue
                empty_done = True
            elif b[-1] != ta:
                continue
            yield i, j, min(ra, CAP - len(b))


def solve(start, w=1.0, budget=200000):
    ncol = len({u for b in start for u in b})
    start = tuple(tuple(b) for b in start)
    seen = {tuple(sorted(start)): None}
    cnt = 0
    heap = [(w * (segments(start) - ncol), 0, cnt, start, None)]
    parents = {}
    exp = 0
    while heap and exp < budget:
        f, g, _, s, path = heapq.heappop(heap)
        exp += 1
        if solved(s):
            out = []
            while path is not None:
                out.append(path[0]); path = path[1]
            return out[::-1], exp
        for i, j, amt in moves(s):
            t = list(s)
            t[i] = s[i][:-amt]
            t[j] = s[j] + s[i][-amt:]
            t = tuple(t)
            k = tuple(sorted(t))
            if k in seen:
                continue
            seen[k] = None
            cnt += 1
            heapq.heappush(heap, (g + 1 + w * (segments(t) - ncol), g + 1, cnt, t, ((i, j), path)))
    return None, exp


def deal(cols, rng):
    pool = [c for c in cols for _ in range(CAP)]
    rng.shuffle(pool)
    s = [pool[i * CAP:(i + 1) * CAP] for i in range(len(cols))] + [[], []]
    return s


def deal_ok(s):
    return all(not (len(b) == CAP and run_len(b) >= 3) for b in s)


def make_level(idx):
    rng = random.Random(20261118 * 1000 + idx)
    w, k = divmod(idx, PER_WORLD)
    lo, hi = WORLD_COLORS[w]
    n = round(lo + (hi - lo) * k / (PER_WORLD - 1))
    if idx == 0: n = 2
    elif idx == 1: n = 3
    cands = []
    tries = 0
    while len(cands) < (1 if idx < 2 else CANDIDATES) and tries < 80:
        tries += 1
        cols = rng.sample(range(1, 13), n)
        s = deal(cols, rng)
        if not deal_ok(s):
            continue
        sol, exp = solve(s, 1.0, 60000 if n <= 9 else 25000)
        if sol is None:
            sol, exp = solve(s, 1.6, 150000)
        if sol is None:
            continue
        cands.append({"b": s, "sol": [list(m) for m in sol], "par": len(sol)})
    cands.sort(key=lambda c: c["par"])
    pick = cands[round((len(cands) - 1) * k / (PER_WORLD - 1))]
    lvl = {"b": pick["b"], "par": pick["par"], "sol": pick["sol"]}
    if HIDDEN[w] > 0 and (w != 4 or k % 2 == 1):
        lvl["h"] = [[1 if (u < len(b) - 1 and rng.random() < HIDDEN[w]) else 0 for u in range(len(b))] for b in pick["b"]]
    return idx, lvl, n


if __name__ == "__main__":
    t0 = time.time()
    total = len(WORLD_COLORS) * PER_WORLD
    out = [None] * total
    with Pool() as pool:
        for idx, lvl, n in pool.imap_unordered(make_level, range(total)):
            out[idx] = lvl
            print(f"level {idx + 1}: {n} colours, par {lvl['par']}  ({time.time() - t0:.0f}s)", flush=True)
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    with open(os.path.join(root, "assets", "levels", "levels.json"), "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print("GEN_OK", total)
