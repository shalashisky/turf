class_name Weapon
extends Resource
## Stats and look of a melee weapon. A citizen with nothing equipped swings
## its `fists` weapon instead.

enum SwingStyle {
	ARC,  ## Sweeps through arc_degrees, like a bat.
	JAB,  ## Thrusts straight out and back, like a punch.
	SHOOT,  ## Fires a projectile, like a pistol. Uses ammo.
}

@export var display_name := "Fists"
## Shown during the swing, drawn pointing right. Leave empty for no visible weapon.
@export var texture: Texture2D
@export var swing_style := SwingStyle.ARC
## Whether the weapon shows between attacks, or only while swinging.
@export var visible_when_idle := true
## For jabs: how far the weapon thrusts out at full extension, in meters.
@export var jab_distance := 0.45
## Pixels from the texture's left edge to where the hand holds it.
@export var grip_pixels := 2
## Health taken per hit.
@export var damage := 10
@export var reach := 1.4
@export var arc_degrees := 90.0
## Shove speed given to whoever gets hit, in m/s.
@export var knockback := 3.0
## Upward pop given to whoever gets hit, in m/s.
@export var knockback_lift := 1.5
## How long the swing animation takes.
@export var swing_time := 0.12
## Minimum time between swings.
@export var cooldown := 0.25
## Walking speed is multiplied by this while holding it: heavy weapons slow
## you down, light ones speed you up.
@export var move_speed_factor := 1.0

@export_group("Contact")
## Damage dealt just by bumping into someone while holding it, like a knife.
## 0 for none.
@export var contact_damage := 0
@export var contact_knockback := 2.5

@export_group("Shooting")
## Shots in a fresh gun. There's no reloading: when it's empty, the holder
## tosses it and goes back to their fists.
@export var max_ammo := 0
@export var projectile_speed := 32.0
## Random spread either side of where it's aimed, in degrees.
@export var spread_degrees := 3.0
