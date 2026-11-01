extends RefCounted
## Shared daylight grading for Ground Zero: bright warm sun, cool soft shadows and
## lifted saturation, in the clean low-poly diorama style. Pure presentation; it
## only changes the scene's WorldEnvironment and sun, never gameplay state.
const SUN_COLOR := Color("ffe8c8")
const SUN_ENERGY := .78
const SUN_ROTATION := Vector3(-52,-38,0)
const SHADOW_OPACITY := .8
const AMBIENT_COLOR := Color("a9bdd8")
const AMBIENT_ENERGY := .36
const BACKGROUND := Color("a9c27a")

## Daylight values for the surface map.
static func apply_surface(environment: Environment, sun: DirectionalLight3D) -> void:
	if sun!=null:
		sun.light_color=SUN_COLOR
		sun.light_energy=SUN_ENERGY
		sun.rotation_degrees=SUN_ROTATION
		sun.shadow_enabled=true
		sun.shadow_opacity=SHADOW_OPACITY
		sun.shadow_blur=1.4
	if environment==null:return
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=BACKGROUND
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=AMBIENT_COLOR
	environment.ambient_light_energy=AMBIENT_ENERGY
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure=1.0
	environment.tonemap_white=4.5
	environment.adjustment_enabled=true
	environment.adjustment_brightness=1.0
	environment.adjustment_contrast=1.1
	environment.adjustment_saturation=1.15

## Restores the neutral grading used by the bunker and cave.
static func clear(environment: Environment, sun: DirectionalLight3D, rotation: Vector3, background: Color) -> void:
	if sun!=null:
		sun.rotation_degrees=rotation
		sun.shadow_opacity=1.0
		sun.shadow_blur=1.0
	if environment==null:return
	environment.background_color=background
	environment.adjustment_enabled=false
	environment.tonemap_exposure=1.0
	environment.tonemap_white=1.0
