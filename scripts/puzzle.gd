class_name Puzzle
extends RefCounted
## Water-sort rules, a weighted-A* solver (time-sliced, for hints) and the level generator.
## A state is an Array of bottles; a bottle is an Array[int] of colour ids (1..), bottom -> top.

const CAP := 4


static func run_len(b: Array) -> int:
	if b.is_empty():
		return 0
	var c: int = b[b.size() - 1]
	var n := 0
	for i in range(b.size() - 1, -1, -1):
		if b[i] == c:
			n += 1
		else:
			break
	return n


static func is_complete(b: Array) -> bool:
	return b.size() == CAP and run_len(b) == CAP


static func can_pour(s: Array, i: int, j: int) -> bool:
	if i == j or i < 0 or j < 0 or i >= s.size() or j >= s.size():
		return false
	var a: Array = s[i]
	var b: Array = s[j]
	if a.is_empty() or b.size() >= CAP or is_complete(a):
		return false
	return b.is_empty() or b[b.size() - 1] == a[a.size() - 1]


static func pour_amount(s: Array, i: int, j: int) -> int:
	return mini(run_len(s[i]), CAP - (s[j] as Array).size())


static func apply(s: Array, i: int, j: int) -> int:
	var n := pour_amount(s, i, j)
	var a: Array = s[i]
	var b: Array = s[j]
	for k in n:
		b.append(a.pop_back())
	return n


static func is_solved(s: Array) -> bool:
	for b in s:
		if not (b.is_empty() or is_complete(b)):
			return false
	return true


## Legal moves that can make progress (pouring a single-colour bottle into an empty one never helps).
static func useful_moves(s: Array) -> Array:
	var out: Array = []
	var first_empty := -1
	for j in s.size():
		if (s[j] as Array).is_empty():
			first_empty = j
			break
	for i in s.size():
		var a: Array = s[i]
		if a.is_empty() or is_complete(a):
			continue
		var single := run_len(a) == a.size()
		for j in s.size():
			if not can_pour(s, i, j):
				continue
			if (s[j] as Array).is_empty():
				if single or j != first_empty:
					continue
			out.append(Vector2i(i, j))
	return out


static func copy(s: Array) -> Array:
	var o: Array = []
	for b in s:
		o.append((b as Array).duplicate())
	return o


# ======================================================================= solver
# Bottles are packed into ints (4 bits per unit, bottom unit in the low nibble) for speed.

static func pack(s: Array) -> PackedInt32Array:
	var p := PackedInt32Array()
	for b in s:
		var code := 0
		for k in (b as Array).size():
			code |= int(b[k]) << (4 * k)
		p.append(code)
	return p


static func _size(c: int) -> int:
	var n := 0
	while n < CAP and ((c >> (4 * n)) & 15) != 0:
		n += 1
	return n


static func _top(c: int, n: int) -> int:
	return (c >> (4 * (n - 1))) & 15 if n > 0 else 0


static func _run(c: int, n: int) -> int:
	if n == 0:
		return 0
	var t := _top(c, n)
	var r := 0
	for k in range(n - 1, -1, -1):
		if ((c >> (4 * k)) & 15) == t:
			r += 1
		else:
			break
	return r


static func _segments(p: PackedInt32Array) -> int:
	var seg := 0
	for c in p:
		var last := 0
		for k in CAP:
			var u := (c >> (4 * k)) & 15
			if u == 0:
				break
			if u != last:
				seg += 1
				last = u
	return seg


static func _key(p: PackedInt32Array) -> int:
	var q := p.duplicate()
	q.sort()
	return hash(q)


class Solver:
	extends RefCounted
	var weight := 1.5
	var ncolors := 0
	var states: Array[PackedInt32Array] = []
	var parent := PackedInt32Array()
	var move := PackedInt32Array()
	var gcost := PackedInt32Array()
	var heap_f := PackedFloat32Array()
	var heap_n := PackedInt32Array()
	var seen := {}
	var expanded := 0
	var status := 0          # 0 running, 1 found, 2 failed
	var result: Array = []   # Vector2i moves
	var _goal := -1

	func _init(s: Array, w := 1.5) -> void:
		weight = w
		var cols := {}
		for b in s:
			for u in b:
				cols[u] = true
		ncolors = cols.size()
		var p := Puzzle.pack(s)
		_add(p, -1, -1, 0)
		seen[Puzzle._key(p)] = true

	func _h(p: PackedInt32Array) -> float:
		return float(Puzzle._segments(p) - ncolors)

	func _add(p: PackedInt32Array, par: int, mv: int, g: int) -> void:
		var idx := states.size()
		states.append(p)
		parent.append(par)
		move.append(mv)
		gcost.append(g)
		_push(g + weight * _h(p), idx)

	func _push(f: float, n: int) -> void:
		heap_f.append(f)
		heap_n.append(n)
		var i := heap_f.size() - 1
		while i > 0:
			var pi := (i - 1) >> 1
			if heap_f[pi] <= heap_f[i]:
				break
			var tf := heap_f[pi]; heap_f[pi] = heap_f[i]; heap_f[i] = tf
			var tn := heap_n[pi]; heap_n[pi] = heap_n[i]; heap_n[i] = tn
			i = pi

	func _pop() -> int:
		var top := heap_n[0]
		var last := heap_f.size() - 1
		heap_f[0] = heap_f[last]
		heap_n[0] = heap_n[last]
		heap_f.resize(last)
		heap_n.resize(last)
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < last and heap_f[l] < heap_f[m]:
				m = l
			if r < last and heap_f[r] < heap_f[m]:
				m = r
			if m == i:
				break
			var tf := heap_f[m]; heap_f[m] = heap_f[i]; heap_f[i] = tf
			var tn := heap_n[m]; heap_n[m] = heap_n[i]; heap_n[i] = tn
			i = m
		return top

	static func _solved(p: PackedInt32Array) -> bool:
		for c in p:
			var n := Puzzle._size(c)
			if n != 0 and (n != Puzzle.CAP or Puzzle._run(c, n) != Puzzle.CAP):
				return false
		return true

	## Expands up to max_nodes states. Returns status.
	func step(max_nodes: int) -> int:
		if status != 0:
			return status
		var budget := max_nodes
		while budget > 0:
			if heap_n.is_empty():
				status = 2
				return status
			budget -= 1
			expanded += 1
			var ni := _pop()
			var p := states[ni]
			if _solved(p):
				_goal = ni
				_build()
				status = 1
				return status
			var g := gcost[ni] + 1
			var nb := p.size()
			var empty_done := false
			for i in nb:
				var a := p[i]
				var na := Puzzle._size(a)
				if na == 0:
					continue
				var ra := Puzzle._run(a, na)
				if ra == Puzzle.CAP:
					continue
				var ta := Puzzle._top(a, na)
				empty_done = false
				for j in nb:
					if j == i:
						continue
					var b := p[j]
					var nbj := Puzzle._size(b)
					if nbj == Puzzle.CAP:
						continue
					if nbj == 0:
						if ra == na or empty_done:
							continue
						empty_done = true
					elif Puzzle._top(b, nbj) != ta:
						continue
					var amt := mini(ra, Puzzle.CAP - nbj)
					var q := p.duplicate()
					var na2 := na - amt
					var mask := 0
					for k in na2:
						mask |= 15 << (4 * k)
					q[i] = a & mask
					var bb := b
					for k in amt:
						bb |= ta << (4 * (nbj + k))
					q[j] = bb
					var key := Puzzle._key(q)
					if seen.has(key):
						continue
					seen[key] = true
					_add(q, ni, i * 64 + j, g)
		return status

	func _build() -> void:
		result.clear()
		var n := _goal
		while n > 0 and parent[n] >= 0:
			var m := move[n]
			result.push_front(Vector2i(m / 64, m % 64))
			n = parent[n]


static func solve(s: Array, budget := 40000, w := 1.5) -> Array:
	var sv := Solver.new(s, w)
	if sv.step(budget) == 1:
		return sv.result
	return []


# ==================================================================== generator

## Random deal of ncolors x CAP units into ncolors bottles plus nempty empty ones.
static func deal(colors: Array, nempty: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	for c in colors:
		for k in CAP:
			pool.append(c)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = pool[i]; pool[i] = pool[j]; pool[j] = t
	var s: Array = []
	for i in colors.size():
		s.append(pool.slice(i * CAP, (i + 1) * CAP))
	for i in nempty:
		s.append([])
	return s


static func deal_ok(s: Array) -> bool:
	for b in s:
		if (b as Array).size() == CAP and run_len(b) >= 3:
			return false
	return true
