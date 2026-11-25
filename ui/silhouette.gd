class_name Silhouette
extends RefCounted

## Solid-colour copies of textures that keep their alpha, for hit flashes: draw
## the copy over the original and fade it out. Cached per texture and colour,
## so every pip shares one copy.

static var _cache: Dictionary = {}


## A copy of `tex` filled with `color` (white by default), alpha kept.
static func of(tex: Texture2D, color: Color = Color.WHITE) -> Texture2D:
	if tex == null:
		return null
	var key: Array = [tex, color]
	if _cache.has(key):
		return _cache[key]
	var img: Image = tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			img.set_pixel(x, y, Color(color.r, color.g, color.b, img.get_pixel(x, y).a))
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_cache[key] = out
	return out
