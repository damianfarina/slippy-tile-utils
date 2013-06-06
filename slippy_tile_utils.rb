require 'optparse'
require 'fileutils'
require 'net/http'
require 'RMagick'

class SlippyTileUtils
	def initialize(options)
		@options = options
	end

	def download
		tiles = calculate_tiles
		tiles.each do |xvalue, ytiles|
			ytiles.each do |yvalue|
				next if File.exist? "#{@options[:out_dir]}/#{@options[:zoom]}/#{xvalue}/#{yvalue}.png.tile"
				Net::HTTP.start("tile.openstreetmap.org") do |http|
				  resp = http.get("/#{@options[:zoom]}/#{xvalue}/#{yvalue}.png")
				  FileUtils.mkpath "#{@options[:out_dir]}/#{@options[:zoom]}/#{xvalue}"
				  open("#{@options[:out_dir]}/#{@options[:zoom]}/#{xvalue}/#{yvalue}.png.tile", "wb") do |file|
				    file.write(resp.body)
				  end
				end
				puts "Got #{@options[:out_dir]}/#{@options[:zoom]}/#{xvalue}/#{yvalue}.png.tile"
			end
		end
	end

	def join
		tiles = calculate_tiles
		result	= Magick::ImageList.new
		tiles.reverse_each do |xvalue, ytiles|
			images = Magick::ImageList.new
			ytiles.each do |yvalue|
				path = File.exist?("#{@options[:out_dir]}/#{@options[:zoom]}/#{xvalue}/#{yvalue}.png.tile") ? "#{@options[:out_dir]}/#{@options[:zoom]}/#{xvalue}/#{yvalue}.png.tile" : @options[:empty]
				image = Magick::Image.read(path)
				images << image.first
				image = nil
			end
			images_appended = images.append(true)
			images_appended.write "#{@options[:out_dir]}/result_#{@options[:zoom]}_#{xvalue}.png"
			result << Magick::Image.read("#{@options[:out_dir]}/result_#{@options[:zoom]}_#{xvalue}.png").first
			images_appended = nil
			images = nil
			GC.start
			puts "Appended #{xvalue} grid"
		end
		result_appended = result.append(false)
		result_appended.write "#{@options[:out_dir]}/result_#{@options[:zoom]}.png"
		result_appended = nil
		result = nil
		GC.start
		tiles.each do |xvalue, ytiles|
			File.delete "#{@options[:out_dir]}/result_#{@options[:zoom]}_#{xvalue}.png"
		end
		puts "Done! your map is #{@options[:out_dir]}/result_#{@options[:zoom]}.png"
	end

	def generate
		zoom_offset = @options[:new_zoom] - @options[:zoom]
		tiles = calculate_tiles
		tiles.each do |x, ytiles|
			ytiles.each do |y|
				path = File.exist?("#{@options[:out_dir]}/#{@options[:zoom]}/#{x}/#{y}.png.tile") ? "#{@options[:out_dir]}/#{@options[:zoom]}/#{x}/#{y}.png.tile" : @options[:empty]
				puts "Exploding #{path} to #{@options[:new_zoom]} zoom level"
				image = Magick::Image.read(path).first
				generate_tile_for_zoom(image, 0, 0, 2*x, 2*y, 1)
				generate_tile_for_zoom(image, 0, image.columns/2, 2*x, 2*y + 1, 1)
				generate_tile_for_zoom(image, image.rows/2, 0, 2*x +1, 2*y, 1)
				generate_tile_for_zoom(image, image.rows/2, image.columns/2, 2*x + 1, 2*y + 1, 1)
			end
		end
	end

private

	def generate_tile_for_zoom(image, image_width_offset, image_height_offset, x, y, zoom_index)
		zoom_offset = @options[:new_zoom] - @options[:zoom]

		if zoom_index < zoom_offset
			generate_tile_for_zoom(image, image_width_offset, image_height_offset,
				(2*x), (2*y),	zoom_index + 1)
			generate_tile_for_zoom(image, image_width_offset, (image_height_offset + (image.columns/(2*(zoom_index + 1)))),
				(2*x), (2*y + 1), zoom_index + 1)
			generate_tile_for_zoom(image, (image_width_offset + (image.columns/(2*(zoom_index + 1)))), image_height_offset,
				(2*x + 1), (2*y), zoom_index + 1)
			generate_tile_for_zoom(image, (image_width_offset + (image.columns/(2*(zoom_index + 1)))), (image_height_offset + (image.columns/(2*(zoom_index + 1)))),
				(2*x + 1), (2*y + 1), zoom_index + 1)
		else
			FileUtils.mkpath "#{@options[:out_dir]}/#{@options[:new_zoom]}/#{x}"
			image.crop(
				image_width_offset,
				image_height_offset,
				image.columns / (2*zoom_offset),
				image.rows / (2*zoom_offset))
			.resize(256, 256)
			.write("#{@options[:out_dir]}/#{@options[:new_zoom]}/#{x}/#{y}.png.tile")
		end
	end

	def calculate_tiles
		tiles = {}
		lat_offset = 85.0511 / 2**(@options[:zoom] - 1)
		lon_offset = 180.0 / 2**(@options[:zoom] - 1)
		current_lon = @options[:start_lon]
		while current_lon > @options[:end_lon] do
			current_lat = @options[:start_lat]
			while current_lat > @options[:end_lat] do
				xtile = (((current_lon + 180) / 360) * (2**@options[:zoom])).floor
				ytile = ((1 - Math.log(Math.tan(deg2rad(current_lat)) + 1 /
					Math.cos(deg2rad(current_lat))) / Math::PI) /2 * (2**@options[:zoom])).floor
				
				tiles[xtile] ||= []
				tiles[xtile] << ytile

				current_lat -= lat_offset
			end
			tiles[xtile] = tiles[xtile].uniq
			current_lon -= lon_offset
		end
		tiles
	end

	def deg2rad(degrees)
		degrees.to_f / 180.0 * Math::PI
	end
end

options = {}
option_parser = OptionParser.new do |opts|
	opts.on("--start-lon LON") do |lon|
		options[:start_lon] = lon.to_f
	end
	opts.on("--end-lon LON") do |lon|
		options[:end_lon] = lon.to_f
	end
	opts.on("--start-lat LAT") do |lat|
		options[:start_lat] = lat.to_f
	end
	opts.on("--end-lat LAT") do |lat|
		options[:end_lat] = lat.to_f
	end
	opts.on("--zoom LON") do |zoom|
		options[:zoom] = zoom.to_i
	end
	opts.on("--image IMAGE") do |image|
		options[:image] = image
	end
	opts.on("--out-dir OUT") do |out|
		options[:out_dir] = out
	end
	opts.on("--action ACTION") do |action|
		options[:action] = action
	end
	opts.on("--empty-tile EMPTY") do |empty|
		options[:empty] = empty
	end
	opts.on("--new-zoom ZOOM") do |zoom|
		options[:new_zoom] = zoom.to_i
	end
end
option_parser.parse!

generator = SlippyTileUtils.new options
case options[:action]
when "generate"
	generator.generate
when "download"
	generator.download
when "join"
	generator.join
end
