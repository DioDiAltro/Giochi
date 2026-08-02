extends MultiMeshInstance2D
## Disegna TUTTI gli item del mondo con UNA sola draw call.
##
## Un item non e' un nodo: e' un byte in world.belt_slots. Qui viene letto e
## trasformato in una istanza del MultiMesh. Con 6 000 item il costo di
## rendering resta una draw call, non 6 000.
##
## instance_count viene allocato UNA volta e mai piu': riallocare un MultiMesh
## a runtime provoca stutter garantito su mobile. Il numero effettivo di item
## disegnati si controlla con visible_instance_count.

const MAX_ITEMS := 6000
const ITEM_PX := 9.0

var _world: WorldState
var _slot_offsets: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_world = SimCore.world
	z_index = 10

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(ITEM_PX, ITEM_PX)
	mm.mesh = quad
	mm.instance_count = MAX_ITEMS
	mm.visible_instance_count = 0
	multimesh = mm

	# Il MultiMesh 2D modula il colore per istanza solo se c'e' una texture:
	# senza, tutti gli item uscirebbero bianchi.
	texture = _white_texture()

	# Offset dei 3 slot dentro una cella, per ciascuna delle 4 direzioni.
	# Precalcolati: sono 12 vettori costanti, ricalcolarli per ogni item
	# significherebbe farlo 6 000 volte per frame.
	var t := float(Database.tile_px)
	var step := t / 3.0
	_slot_offsets.resize(4 * 3)
	for dir in 4:
		var v := Vector2(WorldState.DIR_VEC[dir])
		for s in 3:
			# slot 0 = ingresso, slot 2 = uscita
			_slot_offsets[dir * 3 + s] = Vector2(t, t) * 0.5 + v * (float(s) - 1.0) * step


func _white_texture() -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	var mm := multimesh
	var t := float(Database.tile_px)
	var slots := _world.belt_slots
	var dirs := _world.belt_dir
	var w := _world.w
	var k := 0

	# Si itera sulle CORSIE, non su tutte le celle della mappa: cosi' il costo e'
	# proporzionale ai nastri costruiti, non ai 9 216 della griglia.
	for lane in SimCore.belts.lanes:
		# Frazione di avanzamento verso lo slot successivo, per l'interpolazione
		# a 60 fps di una logica che gira a 20 Hz.
		var sub := float(lane.accum) / float(BeltSystem.FP_ONE)
		var idx := lane.slot_idx
		var last := idx.size() - 1
		for i in idx.size():
			var gs := idx[i]
			var m := slots[gs]
			if m == 0:
				continue
			if k >= MAX_ITEMS:
				break

			var cell := gs / 3
			var slot := gs % 3
			var dir := dirs[cell]
			if dir == WorldState.NO_BELT:
				continue

			var pos := Vector2(float(cell % w), float(cell / w)) * t \
				+ _slot_offsets[dir * 3 + slot]

			# Si interpola SOLO se lo slot davanti e' libero, cioe' se l'item si
			# muovera' davvero. Interpolare anche gli item fermi in un ingorgo li
			# farebbe vibrare sul posto.
			if i < last and slots[idx[i + 1]] == 0:
				pos += Vector2(WorldState.DIR_VEC[dir]) * (t / 3.0) * sub

			mm.set_instance_transform_2d(k, Transform2D(0.0, pos))
			mm.set_instance_color(k, Database.color_from_index(m - 1))
			k += 1

	mm.visible_instance_count = k
