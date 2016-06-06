class BMP
  class Read
    PIXEL_ARRAY_OFFSET = 54
    BITS_PER_PIXEL     = 24
    DIB_HEADER_SIZE    = 40

    def initialize(bmp_filename) 
      File.open(bmp_filename, "rb") do |file|
        read_bmp_header(file)
        read_dib_header(file)
        read_pixels(file)
      end
    end
    def [](x,y)
      @pixels[y][x]
    end

    attr_reader :width, :height

    def read_pixels(file)
      @pixels = Array.new(@height) { Array.new(@width) }

      (@height-1).downto(0) do |y|
        0.upto(@width - 1) do |x|
          @pixels[y][x] = file.read(3).unpack("H6").first
        end
        advance_to_next_row(file)
      end
    end
    def advance_to_next_row(file)
      padding_bytes = @width % 4
      return if padding_bytes == 0

      file.pos += padding_bytes
    end
    def read_bmp_header(file)
      header = file.read(14)
      magic_number, file_size, reserved1,
      reserved2, array_location = header.unpack("A2Vv2V")
      
      fail "Not a bitmap file!" unless magic_number == "BM"

      unless file.size == file_size
        fail "Corrupted bitmap: File size is not as expected" 
      end

      unless array_location == PIXEL_ARRAY_OFFSET
        fail "Unsupported bitmap: pixel array does not start where expected"
      end
    end
    def read_dib_header(file)
      header = file.read(40)

      header_size, width, height, planes, bits_per_pixel, 
      compression_method, image_size, hres, 
      vres, n_colors, i_colors = header.unpack("Vl<2v2V2l<2V2") 

      unless header_size == DIB_HEADER_SIZE
        fail "Corrupted bitmap: DIB header does not match expected size"
      end

      unless planes == 1
        fail "Corrupted bitmap: Expected 1 plane, got #{planes}"
      end

      unless bits_per_pixel == BITS_PER_PIXEL
        fail "#{bits_per_pixel} bits per pixel bitmaps are not supported"
      end

      unless compression_method == 0
        fail "Bitmap compression not supported"
      end

      unless image_size + PIXEL_ARRAY_OFFSET == file.size
        fail "Corrupted bitmap: pixel array size isn't as expected"
      end

      @width, @height = width, height
    end
  end
  class Write
    PIXEL_ARRAY_OFFSET = 54
    BITS_PER_PIXEL     = 24
    DIB_HEADER_SIZE    = 40
    PIXELS_PER_METER   = 2835

    def initialize(width, height)
      @width, @height = width, height

      @pixels = Array.new(@height) { Array.new(@width) { "000000" } }
    end
    def [](x,y)
      @pixels[y][x]
    end
    def []=(x,y,value)
      @pixels[y][x] = value
    end

    attr_reader :width, :height

    def save_as(filename)
      File.open(filename, "wb") do |file|
        write_bmp_file_header(file)
        write_dib_header(file)
        write_pixel_array(file)
      end
    end

    private

    def write_bmp_file_header(file)
      file << ["BM", file_size, 0, 0, PIXEL_ARRAY_OFFSET].pack("A2Vv2V")
    end
    def file_size
      PIXEL_ARRAY_OFFSET + pixel_array_size 
    end
    def pixel_array_size
      ((BITS_PER_PIXEL*@width)/32.0).ceil*4*@height
    end
    def write_dib_header(file)
      file << [DIB_HEADER_SIZE, @width, @height, 1, BITS_PER_PIXEL,
               0, pixel_array_size, PIXELS_PER_METER, PIXELS_PER_METER, 
               0, 0].pack("Vl<2v2V2l<2V2")
    end
    def write_pixel_array(file)
      @pixels.reverse_each do |row|
        row.each do |color|
          file << pixel_binstring(color)
        end

        file << row_padding
      end
    end
    def pixel_binstring(rgb_string)
      raise ArgumentError unless rgb_string =~ /\A\h{6}\z/
      [rgb_string].pack("H6")
    end
    def row_padding
      "\x0" * (@width % 4)
    end
  end
  class Encrypt
	def initialize(filename)
		@file = filename
		parse_file
		encrypt_file
		create_key
	end
	def parse_file
		@original = Read.new(@file)
		@matrix = Array.new(@original.height,Array.new(@original.width,""))
		@final = Write.new(@original.width,@original.height)
		
		@rows = Array.new
		continue = false
		next_row = rand(0...@original.height)
		while continue == false
			if @rows.include? next_row
				next_row = rand(0...@original.height)
			else
				@rows.push(next_row)
			end
			if @rows.length == @original.height
				continue = true
			end
		end

		@columns = Array.new
		continue = false
		next_column = rand(0...@original.width)
		while continue == false
			if @columns.include? next_column
				next_column = rand(0...@original.width)
			else
				@columns.push(next_column)
			end
			if @columns.length == @original.width
				continue = true
			end
		end
	end
	def encrypt_file
		y = 0
		@matrix.each do |grid|
			x = 0
			grid.each do |point|
				@final[@columns[x],@rows[y]] = @original[x,y].reverse
				x += 1
			end
			y += 1
		end
	end	
	def create_key
		filename = @file[0...@file.length-4]
		File.open("#{filename}_key.bmp","wb") do |file|
			x = 0
			@rows.each do |num|
				if x != @rows.length-1
					file << @rows[x]
					file << '|'
					x += 1
				else
					file << @rows[x]
					file << ']'
				end
			end
			x = 0
			@columns.each do |num|
				if x != @columns.length-1
					file << @columns[x]
					file << '|'
					x += 1
				else
					file << @columns[x]
					file << ']'
				end
			end
		end
	end
	def export
		return @final
	end
  end 
  class Decrypt
	def initialize(filename)
		@file = filename
		parse_file
		decrypt_file
	end	
	def parse_file
		@original = Read.new(@file)
		@matrix = Array.new(@original.height,Array.new(@original.width,""))
		@final = Write.new(@original.width,@original.height)
		filename = @file[0...@file.length-4]
		File.open("#{filename}_key.bmp","rb") do |file|
			num = ""
			@rows = Array.new
			while true
				char = file.read(1)
				if char == '|'
					@rows.push(num.to_i)
					num = char = ""
				elsif char == ']'
					@rows.push(num.to_i)
					break
				end
				num = num + char
			end
			num = ""
			@columns = Array.new
			while true
				char = file.read(1)
				if char == '|'
					@columns.push(num.to_i)
					num = char = ""
				elsif char == ']'
					@columns.push(num.to_i)
					break
				end
				num = num + char
			end
		end
	end
	def decrypt_file
		y = 0
		@matrix.each do |grid|
			x = 0
			grid.each do |point|
				@final[x,y] = @original[@columns[x],@rows[y]].reverse
				x += 1
			end
			y += 1
		end
	end
	def export
		return @final
	end
  end
end
