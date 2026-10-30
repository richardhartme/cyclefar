require "rails_helper"

RSpec.describe Fit::Reader do
  def fixture(name)
    file_fixture("fit/#{name}.fit").binread
  end

  def fit_time(time)
    time.to_i - described_class::FIT_EPOCH
  end

  let(:start) { Time.utc(2026, 10, 28, 11, 0, 0) }

  it "reads every record sample from a head-unit ride" do
    samples = described_class.new(fixture("outdoor_ride")).samples

    expect(samples.size).to eq(2935)
    expect(samples.first).to have_attributes(
      recorded_at: Time.utc(2026, 8, 25, 9, 30, 22), power_watts: 0, heart_rate_bpm: 100, speed_mps: 2.809)
    expect(samples.last.recorded_at - samples.first.recorded_at).to eq(2934)
  end

  it "skips developer fields in a trainer-app ride" do
    samples = described_class.new(fixture("indoor_ride")).samples

    expect(samples.size).to eq(2716)
    expect(samples.first).to have_attributes(power_watts: 115, heart_rate_bpm: 94)
  end

  it "returns nil power when the ride has no power data" do
    samples = described_class.new(fixture("outdoor_ride_without_power")).samples

    expect(samples.map(&:power_watts).uniq).to eq([ nil ])
    expect(samples.first.heart_rate_bpm).to eq(100)
  end

  it "applies compressed timestamp headers, including offset rollover" do
    # The base timestamp's low five bits are 30, so offset 2 rolls into the next 32s block.
    base = (fit_time(start) & ~0x1F) + 30
    file = FitFileBuilder.new.file_id
      .define(local: 1, global: 20, fields: FitFileBuilder::RECORD_FIELDS)
      .message(local: 1, payload: [ base, 120, 5000, 200 ].pack("VCvv"))
      .define(local: 2, global: 20, fields: FitFileBuilder::RECORD_FIELDS.drop(1))
      .compressed(local: 2, offset: 31, payload: [ 121, 5000, 210 ].pack("Cvv"))
      .compressed(local: 2, offset: 2, payload: [ 122, 5000, 220 ].pack("Cvv"))
      .build

    samples = described_class.new(file).samples

    expect(samples.map { |sample| fit_time(sample.recorded_at) - base }).to eq([ 0, 1, 4 ])
    expect(samples.map(&:power_watts)).to eq([ 200, 210, 220 ])
  end

  it "decodes big-endian definitions and skips developer data" do
    file = FitFileBuilder.new.file_id
      .define(local: 1, global: 20, fields: FitFileBuilder::RECORD_FIELDS, big_endian: true, developer_sizes: [ 3 ])
      .message(local: 1, payload: [ fit_time(start), 150, 8000, 300 ].pack("NCnn") + "abc")
      .message(local: 1, payload: [ fit_time(start) + 1, 0xFF, 0xFFFF, 0xFFFF ].pack("NCnn") + "def")
      .build

    samples = described_class.new(file).samples

    expect(samples.first).to have_attributes(recorded_at: start, heart_rate_bpm: 150, speed_mps: 8.0, power_watts: 300)
    expect(samples.last).to have_attributes(heart_rate_bpm: nil, speed_mps: nil, power_watts: nil)
  end

  it "prefers enhanced speed over speed" do
    fields = FitFileBuilder::RECORD_FIELDS + [ [ 73, 4, 0x86 ] ]
    file = FitFileBuilder.new.file_id
      .define(local: 1, global: 20, fields: fields)
      .message(local: 1, payload: [ fit_time(start), 140, 5000, 200, 7250 ].pack("VCvvV"))
      .build

    expect(described_class.new(file).samples.first.speed_mps).to eq(7.25)
  end

  describe "rejection" do
    def record_file(type: 4)
      FitFileBuilder.new.file_id(type: type)
        .define(local: 1, global: 20, fields: FitFileBuilder::RECORD_FIELDS)
        .message(local: 1, payload: [ fit_time(start), 140, 5000, 200 ].pack("VCvv"))
    end

    it "rejects files without the FIT signature" do
      expect { described_class.new("not a ride file").samples }.to raise_error(described_class::InvalidFile, "Not a FIT file")
      expect { described_class.new(record_file.build(signature: ".GPX")).samples }.to raise_error(described_class::InvalidFile, "Not a FIT file")
      expect { described_class.new("").samples }.to raise_error(described_class::InvalidFile)
    end

    it "rejects truncated files" do
      bytes = fixture("outdoor_ride")

      expect { described_class.new(bytes.byteslice(0, 10_000)).samples }.to raise_error(described_class::InvalidFile, "FIT file is truncated")
    end

    it "rejects files whose checksum does not match" do
      bytes = fixture("outdoor_ride").dup
      bytes.setbyte(5_000, bytes.getbyte(5_000) ^ 0xFF)

      expect { described_class.new(bytes).samples }.to raise_error(described_class::InvalidFile, "FIT file is corrupt")
    end

    it "rejects FIT files that are not activities" do
      expect { described_class.new(record_file(type: 5).build).samples }.to raise_error(described_class::InvalidFile, "Not a FIT activity file")
    end

    it "rejects activities without record samples" do
      expect { described_class.new(FitFileBuilder.new.file_id.build).samples }.to raise_error(described_class::InvalidFile, "FIT file contains no ride data")
    end

    it "rejects data messages that use an undefined local message type" do
      file = FitFileBuilder.new.file_id.message(local: 3, payload: "x").build

      expect { described_class.new(file).samples }.to raise_error(described_class::InvalidFile, "FIT file is corrupt")
    end

    it "rejects a compressed timestamp before any full timestamp" do
      file = FitFileBuilder.new.file_id
        .define(local: 1, global: 20, fields: FitFileBuilder::RECORD_FIELDS.drop(1))
        .compressed(local: 1, offset: 4, payload: [ 140, 5000, 200 ].pack("Cvv"))
        .build

      expect { described_class.new(file).samples }.to raise_error(described_class::InvalidFile, "FIT file is corrupt")
    end
  end
end
