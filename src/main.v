module main

import arrays
import flag
import log
import os
import io { Writer }
import term
import term.ui { Color }
import stbi
import rand
import rand.seed

@[footer: '\nExamples\n========\n\nim2ansi --log DEBUG --path image.jpg --format svg -s 30']
@[xdoc: 'Convert images into ANSI art']
@[name: 'im2ansi']
struct Config {
	log_level     string @[long: log; xdoc: 'Set the log level (possible values are DEBUG|INFO|WARN|ERROR|FATAL) (default: INFO)']
	path          string @[long: path; short: p; xdoc: 'The path to the image to convert']
	seed          u32    @[long: seed; xdoc: 'The seed to use for the randomizer']
	format        string @[long: format; short: f; xdoc: 'The format to use (possible values are ansi|svg) (default: ansi)']
	size          int    @[long: size; short: s; xdoc: 'Set the size of the ANSI art (default: 30)']
	character_set string @[short: c; xdoc: 'The character set to include in the ANSI art (default: 01)']
	show_help     bool   @[long: help; short: h; xdoc: 'Show help and exit']
}

struct Pixel {
	color     Color
	character rune
}

fn write_svg(mut buf Writer, pixels [][]Pixel) !int {
	x := 10
	y := 10
	font_size := 10
	dy := f64(font_size) * 1.2
	widest_line := arrays.max[int](pixels.map(fn (row []Pixel) int {
		return row.len
	}))!
	required_width := x + widest_line * f64(font_size) * 0.7
	required_height := y + pixels.len * dy

	buf.write('<svg width="${required_width}" height="${required_height}" xmlns="http://www.w3.org/2000/svg">'.bytes())!
	buf.write('<text x="${x}" y="${y}" font-family="monospace" font-size="${font_size}">'.bytes())!
	mut line := 0
	for row in pixels {
		mut first_of_row := true
		for pixel in row {
			attrs := if first_of_row && line != 0 { 'dy="${dy}" x="${x}"' } else { '' }
			buf.write('<tspan fill="${pixel.color.hex()}" ${attrs}>${if pixel.character == ` ` {
				'&#160;'
			} else {
				pixel.character.str()
			}}</tspan>'.bytes())!
			first_of_row = false
		}
		line += 1
	}
	buf.write('</text>'.bytes())!
	buf.write('</svg>'.bytes())!
	return 0
}

fn write_ansi(mut buf Writer, pixels [][]Pixel) !int {
	for row in pixels {
		for pixel in row {
			buf.write(term.format_rgb(pixel.color.r, pixel.color.g, pixel.color.b, pixel.character.str(),
				'38', '0').bytes())!
		}
		buf.write('\n'.bytes())!
	}
	return 0
}

fn main() {
	config, no_matches := flag.using[Config](Config{
		log_level:     'INFO'
		seed:          seed.time_seed_32()
		format:        'ansi'
		size:          30
		character_set: '01'
		show_help:     false
	}, os.args,
		skip:  1
		style: .v_flag_parser
		mode:  .strict
	)!

	if no_matches.len > 0 {
		log.error('Unknown flag(s): ${no_matches}')
		exit(0)
	}

	if config.show_help {
		documentation := flag.to_doc[Config]()!
		println(documentation)
		exit(0)
	}

	if config.path.len == 0 {
		panic('path to image must be set with `-p` or `--path`')
	}

	log.set_level(log.level_from_tag(config.log_level) or { panic('invalid log level') })

	image_path := config.path
	original_image := stbi.load(image_path, desired_channels: 0)!
	ratio := f64(config.size) / f64(original_image.height)
	resized_image := stbi.resize_uint8(original_image, int(original_image.width * ratio),
		config.size)!
	channels := resized_image.nr_channels
	if channels !in [3, 4] {
		panic('image must be RGB or RGBA')
	}

	// stbi.stbi_write_jpg("out.jpg", resized_image.width, resized_image.height, 3, resized_image.data, resized_image.width * 3)!

	log.debug('Image has ${resized_image.nr_channels} channels')
	log.debug('Output has a size of ${resized_image.width}x${resized_image.height}')

	rand.seed([config.seed, config.seed])

	mut pixels := [][]Pixel{}
	for y in 0 .. resized_image.height {
		pixels << [[]]
		for x in 0 .. resized_image.width {
			pixel_index := unsafe { (y * resized_image.width + x) * channels }
			r := unsafe { resized_image.data[pixel_index + 0] }
			g := unsafe { resized_image.data[pixel_index + 1] }
			b := unsafe { resized_image.data[pixel_index + 2] }
			a := if channels == 4 { unsafe { resized_image.data[pixel_index + 3] } } else { 255 }
			for _ in 0 .. 2 {
				// generate two because characters usually have a ratio of 1:2
				character := if a < 100 {
					` `
				} else {
					rand.string_from_set(config.character_set, 1).runes()[0]
				}
				pixel := Pixel{
					color:     Color{r, g, b}
					character: character
				}
				pixels[y] << pixel
			}
		}
	}

	mut buf := os.stdout()
	if config.format == 'ansi' {
		write_ansi(mut &buf, pixels)!
	} else if config.format == 'svg' {
		write_svg(mut &buf, pixels)!
	} else {
		panic('invalid format ${config.format}; possible values are `ansi` and `svg`')
	}
}
