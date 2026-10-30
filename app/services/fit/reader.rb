module Fit
  # Decodes the record samples of a FIT activity file. Only the fields ride
  # metrics need are read; other messages, fields and developer data are
  # skipped by size. See docs/adr/0001-ride-file-upload-for-completed-workouts.md.
  class Reader
    class InvalidFile < StandardError; end

    Sample = Data.define(:recorded_at, :power_watts, :heart_rate_bpm, :speed_mps)

    FIT_EPOCH = Time.utc(1989, 12, 31).to_i
    ACTIVITY_FILE_TYPE = 4
    FILE_ID = 0
    RECORD = 20
    TIMESTAMP_FIELD = 253
    FILE_TYPE_FIELD = 0
    HEART_RATE_FIELD = 3
    SPEED_FIELD = 6
    POWER_FIELD = 7
    ENHANCED_SPEED_FIELD = 73
    CRC_TABLE = [ 0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
                  0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400 ].freeze

    def self.crc(bytes)
      bytes.each_byte.reduce(0) do |crc, byte|
        [ byte & 0x0F, byte >> 4 ].reduce(crc) do |value, nibble|
          shifted = (value >> 4) & 0x0FFF
          shifted ^ CRC_TABLE[value & 0x0F] ^ CRC_TABLE[nibble]
        end
      end
    end

    def initialize(bytes)
      @bytes = bytes.b
    end

    def samples
      data_end = validate_framing!
      file_type = nil
      samples = []
      each_message(data_end) do |global, fields|
        file_type = fields[FILE_TYPE_FIELD] if global == FILE_ID
        next unless global == RECORD && fields[TIMESTAMP_FIELD]

        speed = fields[ENHANCED_SPEED_FIELD] || fields[SPEED_FIELD]
        samples << Sample.new(
          recorded_at: Time.at(FIT_EPOCH + fields[TIMESTAMP_FIELD]).utc,
          power_watts: fields[POWER_FIELD],
          heart_rate_bpm: fields[HEART_RATE_FIELD],
          speed_mps: speed && speed / 1000.0)
      end
      raise InvalidFile, "Not a FIT activity file" unless file_type == ACTIVITY_FILE_TYPE
      raise InvalidFile, "FIT file contains no ride data" if samples.empty?

      samples
    end

    private

    def validate_framing!
      header_size = @bytes.getbyte(0)
      raise InvalidFile, "Not a FIT file" unless [ 12, 14 ].include?(header_size) && @bytes.byteslice(8, 4) == ".FIT"

      data_end = header_size + @bytes.byteslice(4, 4).unpack1("V")
      raise InvalidFile, "FIT file is truncated" if @bytes.bytesize < data_end + 2
      raise InvalidFile, "FIT file is corrupt" unless self.class.crc(@bytes.byteslice(0, data_end + 2)).zero?

      data_end
    end

    def each_message(data_end)
      definitions = {}
      position = @bytes.getbyte(0)
      last_timestamp = nil
      while position < data_end
        header = @bytes.getbyte(position)
        position += 1
        if header & 0x80 != 0
          # Compressed timestamp header: a 5-bit offset from the last timestamp.
          definition = definitions.fetch((header >> 5) & 0x03) { raise InvalidFile, "FIT file is corrupt" }
          raise InvalidFile, "FIT file is corrupt" unless last_timestamp

          fields = decode(definition, position)
          last_timestamp += ((header & 0x1F) - (last_timestamp & 0x1F)) & 0x1F
          fields[TIMESTAMP_FIELD] = last_timestamp
        elsif header & 0x40 != 0
          definition, position = read_definition(header, position)
          raise InvalidFile, "FIT file is truncated" if position > data_end

          definitions[header & 0x0F] = definition
          next
        else
          definition = definitions.fetch(header & 0x0F) { raise InvalidFile, "FIT file is corrupt" }
          fields = decode(definition, position)
          last_timestamp = fields[TIMESTAMP_FIELD] if fields[TIMESTAMP_FIELD]
        end
        position += definition[:size]
        raise InvalidFile, "FIT file is truncated" if position > data_end

        yield definition[:global], fields
      end
    end

    def read_definition(header, position)
      big_endian = @bytes.getbyte(position + 1) == 1
      global = @bytes.byteslice(position + 2, 2).unpack1(big_endian ? "n" : "v")
      count = @bytes.getbyte(position + 4)
      position += 5
      fields = Array.new(count) { |index| @bytes.byteslice(position + index * 3, 2).bytes }
      position += count * 3
      size = fields.sum(&:last)
      if header & 0x20 != 0
        developer_count = @bytes.getbyte(position)
        size += Array.new(developer_count) { |index| @bytes.getbyte(position + 1 + index * 3 + 1) }.sum
        position += 1 + developer_count * 3
      end
      [ { global:, big_endian:, fields:, size: }, position ]
    rescue NoMethodError, TypeError
      raise InvalidFile, "FIT file is truncated"
    end

    # Reads unsigned 1, 2 and 4-byte fields; FIT's all-ones value means "no data".
    def decode(definition, position)
      definition[:fields].each_with_object({}) do |(number, size), fields|
        format = { 1 => "C", 2 => (definition[:big_endian] ? "n" : "v"), 4 => (definition[:big_endian] ? "N" : "V") }[size]
        value = format && @bytes.byteslice(position, size)&.unpack1(format)
        fields[number] = value unless value.nil? || value == (1 << (size * 8)) - 1
        position += size
      end
    end
  end
end
