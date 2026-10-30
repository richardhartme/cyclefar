# Builds small synthetic FIT files for decoder edge cases that the recorded
# fixtures in spec/fixtures/files/fit do not exercise.
class FitFileBuilder
  RECORD_FIELDS = [ [ 253, 4, 0x86 ], [ 3, 1, 0x02 ], [ 6, 2, 0x84 ], [ 7, 2, 0x84 ] ].freeze

  def initialize
    @data = "".b
  end

  def file_id(type: 4, local: 0)
    define(local: local, global: 0, fields: [ [ 0, 1, 0x00 ] ])
    message(local: local, payload: [ type ].pack("C"))
  end

  def define(local:, global:, fields:, big_endian: false, developer_sizes: [])
    header = 0x40 | local
    header |= 0x20 if developer_sizes.any?
    @data << [ header, 0, big_endian ? 1 : 0 ].pack("CCC")
    @data << [ global ].pack(big_endian ? "n" : "v") << [ fields.size ].pack("C")
    fields.each { |field| @data << field.pack("CCC") }
    if developer_sizes.any?
      @data << [ developer_sizes.size ].pack("C")
      developer_sizes.each_with_index { |size, index| @data << [ index, size, 0 ].pack("CCC") }
    end
    self
  end

  def message(local:, payload:)
    @data << [ local ].pack("C") << payload.b
    self
  end

  def compressed(local:, offset:, payload:)
    @data << [ 0x80 | (local << 5) | offset ].pack("C") << payload.b
    self
  end

  def build(signature: ".FIT")
    header = [ 14, 0x20, 2132, @data.bytesize ].pack("CCvV") << signature
    header << [ Fit::Reader.crc(header) ].pack("v")
    file = header + @data
    file << [ Fit::Reader.crc(file) ].pack("v")
  end
end
