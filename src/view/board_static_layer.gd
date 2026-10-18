class_name BoardStaticLayer
extends Node2D

## Draws the board's static layer - backdrop, plate and sockets - into a SubViewport on
## behalf of BoardView, so it can be baked into one texture and blitted per frame.
##
## The painter is a Callable rather than a reference to BoardView: this node exists only to
## give the viewport something that can draw, and it must not grow its own copy of the board
## geometry.

var painter: Callable


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
