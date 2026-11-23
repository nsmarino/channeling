extends Node3D

## A layered one-shot effect: every GPUParticles3D child is set to one_shot and
## fires together on play(). Called duck-typed (e.g. by BounceFeedback), so any
## burst scene can use this script — add or remove layers as plain children.


## Fire every layer from the start, cutting off any run still in progress.
func play() -> void:
	for child: Node in get_children():
		var p: GPUParticles3D = child as GPUParticles3D
		if p:
			p.restart()
