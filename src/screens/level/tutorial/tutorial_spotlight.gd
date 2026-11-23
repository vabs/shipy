class_name TutorialSpotlight
extends ColorRect
## Soft full-screen dim with up to MAX_HOLES rounded-rect "windows" cut out of it (SDF in a canvas shader, so the
## edge is feathered at any size). Purely visual: it never takes mouse input, everything below stays clickable.
##
##   set_holes(rects: Array[Rect2], radii: Array[float])   screen-space rects (viewport px), per frame
##   dim: float      target darkness 0..1 (fades in/out)       tint: Color  (default deep navy)

const MAX_HOLES: int = 3
const CODE: String = """
shader_type canvas_item;
uniform vec4 holes[3];
uniform float radii[3];
uniform int hole_count = 0;
uniform vec4 tint : source_color = vec4(0.04, 0.07, 0.15, 1.0);
uniform float dim = 0.5;
uniform float feather = 26.0;
uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform float glow = 0.0;

float sd_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * view_size;
	float d = 100000.0;
	for (int i = 0; i < 3; i++) {
		if (i >= hole_count) { break; }
		vec2 hs = holes[i].zw * 0.5;
		d = min(d, sd_box(px - (holes[i].xy + hs), hs, min(radii[i], min(hs.x, hs.y))));
	}
	float edge = smoothstep(-2.0, feather, d);
	float a = dim * edge;
	// a faint warm halo just outside the window so the target reads as "lit"
	float halo = (1.0 - smoothstep(0.0, feather * 1.6, d)) * step(0.0, d) * glow;
	vec3 col = mix(tint.rgb, vec3(1.0, 0.85, 0.45), halo * 0.35);
	COLOR = vec4(col, clamp(a, 0.0, 1.0) * mix(1.0, 0.75, halo));
}
"""

static var _shader: Shader = null

var dim: float = 0.5
var glow: float = 1.0
var feather: float = 26.0
var _mat: ShaderMaterial
var _alpha: float = 0.0
var _holes: PackedVector4Array = PackedVector4Array()
var _radii: PackedFloat32Array = PackedFloat32Array()
var _n: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	material = _mat
	_holes.resize(MAX_HOLES)
	_radii.resize(MAX_HOLES)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func set_holes(rects: Array[Rect2], radii: Array[float]) -> void:
	_n = mini(rects.size(), MAX_HOLES)
	for i in MAX_HOLES:
		if i < _n:
			var r: Rect2 = rects[i]
			_holes[i] = Vector4(r.position.x, r.position.y, maxf(r.size.x, 2.0), maxf(r.size.y, 2.0))
			_radii[i] = radii[i] if i < radii.size() else 18.0
		else:
			_holes[i] = Vector4.ZERO
			_radii[i] = 0.0


func _process(delta: float) -> void:
	var target: float = dim if _n > 0 else 0.0
	_alpha = move_toward(_alpha, target, delta * 2.6)
	visible = _alpha > 0.005
	if not visible:
		return
	_mat.set_shader_parameter("holes", _holes)
	_mat.set_shader_parameter("radii", _radii)
	_mat.set_shader_parameter("hole_count", _n)
	_mat.set_shader_parameter("dim", _alpha)
	_mat.set_shader_parameter("feather", feather)
	_mat.set_shader_parameter("glow", glow)
	_mat.set_shader_parameter("view_size", size)
