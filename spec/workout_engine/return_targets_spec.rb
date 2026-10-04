require "engine_helper"

RSpec.describe "OFF-001 return-stage canonical power targets" do
  def generate(subtype, key, band)
    Workouts::Generator.new(
      subtype: subtype,
      duration_minutes: 60,
      variation_key: key,
      load_adjustments: { "return_target_band" => band }).call
  end

  { recovery: [ 45, 60 ], endurance: [ 55, 68 ], tempo: [ 78, 87 ] }.each do |subtype, band|
    Workouts::Variations.keys_for(subtype).each do |key|
      it "limits #{subtype} #{key} main sets and every warm-up/cool-down endpoint" do
        definition = generate(subtype, key, band)
        expect(definition.variation_key).to eq(key)
        expect(definition.steps.sum(&:duration_seconds)).to eq(3600)
        expect(definition.main_set_summary).to include("#{band.join('–')}% FTP")
        definition.steps.each do |step|
          targets = [ step.target_low_pct_ftp, step.target_high_pct_ftp, step.end_target_low_pct_ftp, step.end_target_high_pct_ftp ].compact
          expect(targets).to all(be <= band.last)
          expect(targets).to all(be >= band.first) if step.group_key == "main"
        end
        expect(generate(subtype, key, band)).to eq(definition)
      end
    end
  end

  it "leaves ordinary endurance targets unchanged" do
    normal = Workouts::Generator.new(subtype: :endurance, duration_minutes: 60, variation_key: "alternating").call
    expect(normal.steps.map(&:target_high_pct_ftp).max).to eq(74)
  end

  [ [ 68, 55 ], [ 0, 68 ], [ 55, 121 ], [ 55 ], [ Float::NAN, 68 ] ].each do |band|
    it "rejects invalid return band #{band.inspect}" do
      expect { generate(:endurance, "undulating", band) }.to raise_error(ArgumentError)
    end
  end
end
