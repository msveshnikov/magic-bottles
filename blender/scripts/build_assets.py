# Magic Bottles — procedural asset builder (Blender 5.x, headless)
#   blender -b --factory-startup -P blender/scripts/build_assets.py
# Writes assets/models/bottle_<type>.glb, shelf.glb, bottles.json (cavity profiles for the
# liquid shader / volume tables) and renders/blender/preview.png.
import bpy, bmesh, json, math, os
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models")
REN = os.path.join(ROOT, "renders", "blender")
os.makedirs(OUT, exist_ok=True)
os.makedirs(REN, exist_ok=True)
SEG = 56


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ---------------------------------------------------------------- profiles
def arc(cx, cy, rad, a0, a1, n):
    return [(cx + rad * math.cos(a0 + (a1 - a0) * i / n), cy + rad * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def ease(a, b, t):
    t = 0.5 - 0.5 * math.cos(math.pi * t)
    return a + (b - a) * t


def side(r_of_y, y0, y1, n):
    return [(r_of_y(y0 + (y1 - y0) * i / n), y0 + (y1 - y0) * i / n) for i in range(n + 1)]


def dedupe(pts):
    out = []
    for p in pts:
        if not out or abs(out[-1][0] - p[0]) > 1e-5 or abs(out[-1][1] - p[1]) > 1e-5:
            out.append((round(p[0], 5), round(p[1], 5)))
    return out


def bottle_profiles(kind):
    """Return (outer_closed_profile, inner_cavity_profile, meta). y up, r >= 0."""
    t = 0.032  # glass wall
    if kind == "flask":
        R, f, yb, ys, yn, yl, ytop, rn, rl = 0.42, 0.13, 1.70, 1.98, 2.20, 2.24, 2.33, 0.165, 0.215
        y_full = 1.64

        def r_out(y):
            if y <= yb:
                return R
            if y <= ys:
                return ease(R, rn, (y - yb) / (ys - yb))
            return rn
        outer = [(0, 0)] + arc(R - f, f, f, -math.pi / 2, 0, 10) + side(r_out, f, yn, 40)
        outer += [(rl - 0.02, yn + 0.005), (rl, yn + 0.03), (rl, ytop - 0.03), (rl - 0.02, ytop), (rn - t + 0.01, ytop)]
        ri = lambda y: r_out(y) - t
        inner_top = [(rn - t, ytop - 0.01)]
        inner = side(ri, yn, f, 40)  # downward
        inner += arc(R - f, f, f - t, 0, -math.pi / 2, 10)[1:]
        inner += [(0, t)]
        outer_closed = outer + inner_top + inner
        cavity = list(reversed(inner))
        meta = dict(y_full=y_full, y_top=ytop, neck_r=rn - t, lip_r=rl, body_r=R, height=ytop)
    elif kind == "tube":
        R, ytop, rl = 0.33, 2.30, 0.375
        y_full = 2.02
        outer = [(0, 0)] + arc(0, R, R, -math.pi / 2, 0, 16) + side(lambda y: R, R, ytop - 0.08, 30)
        outer += [(rl - 0.02, ytop - 0.07), (rl, ytop - 0.04), (rl, ytop - 0.015), (rl - 0.02, ytop), (R - t + 0.005, ytop)]
        inner = side(lambda y: R - t, ytop - 0.01, R, 30)
        inner += arc(0, R, R - t, 0, -math.pi / 2, 16)[1:]
        inner[-1] = (0, t)
        outer_closed = outer + inner
        cavity = list(reversed(inner))
        meta = dict(y_full=y_full, y_top=ytop, neck_r=R - t, lip_r=rl, body_r=R, height=ytop)
    else:  # "jar": wide potion jar, slight taper, short neck
        R0, R1, f, yb, ys, yn, ytop, rn, rl = 0.45, 0.41, 0.11, 1.52, 1.80, 2.04, 2.13, 0.19, 0.24
        y_full = 1.47

        def r_out(y):
            if y <= yb:
                return R0 + (R1 - R0) * (y / yb)
            if y <= ys:
                return ease(R1, rn, (y - yb) / (ys - yb))
            return rn
        outer = [(0, 0)] + arc(R0 - f, f, f, -math.pi / 2, 0, 10) + side(r_out, f, yn, 40)
        outer += [(rl - 0.02, yn + 0.005), (rl, yn + 0.03), (rl, ytop - 0.03), (rl - 0.02, ytop), (rn - t + 0.01, ytop)]
        ri = lambda y: r_out(y) - t
        inner = side(ri, yn, f, 40)
        inner += arc(R0 - f, f, f - t, 0, -math.pi / 2, 10)[1:]
        inner += [(0, t)]
        outer_closed = outer + [(rn - t, ytop - 0.01)] + inner
        cavity = list(reversed(inner))
        meta = dict(y_full=y_full, y_top=ytop, neck_r=rn - t, lip_r=rl, body_r=R0, height=ytop)
    return dedupe(outer_closed), dedupe(cavity), meta


# ---------------------------------------------------------------- mesh helpers
def lathe(name, prof, seg=SEG, close=True):
    bm = bmesh.new()
    rings = []
    for r, y in prof:
        if r < 1e-6:
            rings.append([bm.verts.new((0, 0, y))])
        else:
            rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / seg), r * math.sin(2 * math.pi * i / seg), y)) for i in range(seg)])
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(seg):
            j = (i + 1) % seg
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[i]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def uv_cylinder(ob, scale_v=1.0):
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            u = (math.atan2(v.y, v.x) / (2 * math.pi)) % 1.0
            uvl.data[li].uv = (u, v.z * scale_v)


def np_image(name, arr):
    h, w, _ = arr.shape
    img = bpy.data.images.new(name, w, h, alpha=True)
    rgba = np.ones((h, w, 4), np.float32)
    rgba[:, :, :3] = np.clip(arr, 0, 1)
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    return img


def noise(h, w, scale, seed):
    rng = np.random.default_rng(seed)
    g = rng.random((h // scale + 2, w // scale + 2))
    ys = np.linspace(0, h / scale, h, endpoint=False)
    xs = np.linspace(0, w / scale, w, endpoint=False)
    y0 = ys.astype(int); x0 = xs.astype(int)
    fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]; b = g[y0][:, x0 + 1]; c = g[y0 + 1][:, x0]; d = g[y0 + 1][:, x0 + 1]
    return a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy


def cork_texture():
    h = w = 256
    n = 0.5 * noise(h, w, 4, 1) + 0.3 * noise(h, w, 16, 2) + 0.2 * noise(h, w, 2, 3)
    rng = np.random.default_rng(7)
    speck = (rng.random((h, w)) > 0.93).astype(np.float32) * 0.35
    base = np.array([0.62, 0.42, 0.24])
    dark = np.array([0.33, 0.20, 0.10])
    k = np.clip(n - speck, 0, 1)[:, :, None]
    return np_image("cork_tex", dark + (base - dark) * k)


def wood_texture():
    h, w = 256, 512
    n = noise(h, w, 32, 11)
    yy = np.linspace(0, 1, h)[:, None]
    grain = np.sin((yy * 40 + n * 6) * math.pi) * 0.5 + 0.5
    fine = noise(h, w, 2, 12)
    k = np.clip(0.55 * grain + 0.25 * fine + 0.2 * noise(h, w, 8, 13), 0, 1)[:, :, None]
    base = np.array([0.45, 0.25, 0.12])
    dark = np.array([0.20, 0.10, 0.05])
    return np_image("wood_tex", dark + (base - dark) * k)


def mat(name, color, rough=0.5, metal=0.0, img=None, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
    if img is not None:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = img
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)


# ---------------------------------------------------------------- build
def build_bottle(kind, data):
    reset()
    outer, cavity, meta = bottle_profiles(kind)
    glass = lathe("Glass", outer)
    glass.data.materials.append(mat("glass", (0.85, 0.93, 1.0), 0.05, alpha=0.2))
    # cork: sits in the neck, top flares a little
    rn = meta["neck_r"]
    ytop = meta["y_top"]
    cork_prof = [(0, ytop - 0.12), (rn * 0.94, ytop - 0.12), (rn * 0.99, ytop - 0.02), (rn * 1.18, ytop + 0.01),
                 (rn * 1.24, ytop + 0.05), (rn * 1.26, ytop + 0.17), (rn * 1.20, ytop + 0.21), (0, ytop + 0.215)]
    cork = lathe("Cork", cork_prof, 40)
    uv_cylinder(cork, 2.0)
    cork.data.materials.append(mat("cork", (1, 1, 1), 0.9, img=cork_texture()))
    export(os.path.join(OUT, f"bottle_{kind}.glb"), [glass, cork])
    data[kind] = dict(meta, cavity=[list(p) for p in cavity], **volume_tables(cavity, meta))


def volume_tables(cavity, meta):
    """Liquid surface height (relative to the bottle origin, world-up) for a bottle tilted by
    angle a (degrees, lip side going down) holding volume fraction v of the cavity.
    Layers of immiscible liquid stack as horizontal slabs, so the boundary between layers is
    just the surface height for the cumulative volume below it."""
    cav = np.array(cavity)
    ys_c, rs_c = cav[:, 1], cav[:, 0]
    ytop_c = ys_c.max()
    rmax = rs_c.max()
    ny, nx = 420, 220
    y = (np.arange(ny) + 0.5) / ny * ytop_c
    r = np.interp(y, ys_c, rs_c)
    x = (np.arange(nx) + 0.5) / nx * 2 * rmax - rmax
    X, Y = np.meshgrid(x, y)
    R = np.broadcast_to(r[:, None], X.shape)
    W = np.where(np.abs(X) < R, 2 * np.sqrt(np.maximum(R ** 2 - X ** 2, 0)), 0.0)
    m = W > 0
    X, Y, W = X[m], Y[m], W[m]
    total = W.sum()
    vs = np.linspace(0, 1, 65)
    fine = np.arange(0, 180.01, 0.5)
    H_fine = []
    for a in fine:
        t = math.radians(a)
        H = -X * math.sin(t) + Y * math.cos(t)
        o = np.argsort(H)
        cw = np.cumsum(W[o]) / total
        H_fine.append(np.interp(vs, cw, H[o]))
    H_fine = np.array(H_fine)  # (angles, vs)
    lip_x, lip_y = meta["neck_r"], ytop_c
    lip_h = -lip_x * np.sin(np.radians(fine)) + lip_y * np.cos(np.radians(fine))
    pour = []
    for k in range(len(vs)):
        idx = np.nonzero(H_fine[:, k] >= lip_h - 1e-4)[0]
        pour.append(float(fine[idx[0]]) if len(idx) else 180.0)
    unit = float(W[Y <= meta["y_full"]].sum() / total / 4.0)
    coarse = H_fine[::4]  # every 2 degrees
    return dict(unit=round(unit, 5), angle_step=2.0, vsteps=64,
                table=[[round(float(h), 4) for h in row] for row in coarse],
                pour_angle=[round(p, 2) for p in pour], cavity_top=float(ytop_c))


def build_shelf():
    reset()
    wood = mat("wood", (1, 1, 1), 0.7, img=wood_texture())
    brass = mat("brass", (0.95, 0.68, 0.30), 0.3, metal=1.0)
    # middle segment: 1 unit long along X, top surface at y=0 (Blender z=0)
    bpy.ops.mesh.primitive_cube_add(size=1)
    mid = bpy.context.object
    mid.name = "ShelfMid"
    mid.scale = (1.0, 0.9, 0.16)
    mid.location = (0, 0, -0.08)
    bpy.ops.object.transform_apply(scale=True, location=True)
    bev = mid.modifiers.new("bev", "BEVEL"); bev.width = 0.03; bev.segments = 3
    bpy.ops.object.modifier_apply(modifier="bev")
    me = mid.data
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            n = poly.normal
            uvl.data[li].uv = (v.x + 0.5, (v.y if abs(n.z) > 0.5 else v.z) * 2 + 0.5)
    mid.data.materials.append(wood)
    # brass rail along the front edge
    bpy.ops.mesh.primitive_cylinder_add(radius=0.035, depth=1.0, vertices=16, rotation=(0, math.pi / 2, 0), location=(0, -0.45, -0.06))
    rail = bpy.context.object; rail.name = "RailMid"
    rail.data.materials.append(brass)
    for p in rail.data.polygons:
        p.use_smooth = True
    bpy.ops.object.select_all(action="DESELECT")
    mid.select_set(True); rail.select_set(True)
    bpy.context.view_layer.objects.active = mid
    bpy.ops.object.join()
    # end cap: brass scroll bracket (origin at shelf end, extends to +X)
    caps = []
    for side_name, sgn in (("ShelfCapR", 1), ("ShelfCapL", -1)):
        prof = [(0, -0.25), (0.11, -0.25), (0.14, -0.2), (0.14, 0.2), (0.11, 0.25), (0, 0.25)]
        cap = lathe(side_name, [(r, y) for r, y in prof], 32)
        cap.rotation_euler = (0, sgn * math.pi / 2, 0)
        cap.scale = (0.75, 1.0, 1.0)
        cap.location = (0, 0, -0.08)
        bpy.context.view_layer.objects.active = cap
        cap.select_set(True)
        bpy.ops.object.transform_apply(rotation=True, scale=True, location=True)
        cap.data.materials.append(brass)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.085, location=(sgn * 0.27, 0, -0.08), segments=24, ring_count=12)
        knob = bpy.context.object
        knob.data.materials.append(brass)
        for p in knob.data.polygons:
            p.use_smooth = True
        bpy.ops.object.select_all(action="DESELECT")
        cap.select_set(True); knob.select_set(True)
        bpy.context.view_layer.objects.active = cap
        bpy.ops.object.join()
        caps.append(cap)
    export(os.path.join(OUT, "shelf.glb"), [mid] + caps)


def preview():
    reset()
    scn = bpy.context.scene
    for i, kind in enumerate(("flask", "tube", "jar")):
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, f"bottle_{kind}.glb"))
        for o in bpy.context.selected_objects:
            o.location.x += (i - 1) * 1.2
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, "shelf.glb"))
    for o in bpy.context.selected_objects:
        if o.name.startswith("ShelfMid"):
            o.scale.x = 3.6
        elif o.name.startswith("ShelfCapR"):
            o.location.x = 1.8
        elif o.name.startswith("ShelfCapL"):
            o.location.x = -1.8
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scn.collection.objects.link(cam)
    cam.location = (0, -6.5, 2.2)
    cam.rotation_euler = (math.radians(84), 0, 0)
    scn.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scn.collection.objects.link(sun)
    world = bpy.data.worlds.new("w"); scn.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.15, 0.1, 0.25, 1)
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scn.render.engine = eng
            break
        except Exception:
            pass
    scn.render.resolution_x, scn.render.resolution_y = 900, 600
    scn.render.filepath = os.path.join(REN, "preview.png")
    bpy.ops.render.render(write_still=True)


data = {}
for k in ("flask", "tube", "jar"):
    build_bottle(k, data)
build_shelf()
with open(os.path.join(OUT, "bottles.json"), "w") as fp:
    json.dump(data, fp, indent=1)
preview()
print("BUILD_OK", list(data))
