module Training
  # Training engine constants: zones, targets, progressions, and workout structures.
  module Rules
    def self.deep_freeze(value)
      case value
      when Hash then value.each { |key, item| deep_freeze(key); deep_freeze(item) }
      when Array then value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end

    ENGINE_VERSION = "v1".freeze
    MINIMUM_DURATION_MINUTES = 30
    MINIMUM_STEP_SECONDS = 30
    PROGRESSION_LEVELS = (1..7).freeze
    PROGRESSION_BIAS_BOUNDS = [ -2, 2 ].freeze
    FEEDBACK_HORIZON_DAYS = 14
    NEARBY_HARD_SESSION_DAYS = 2
    RPE_BANDS = deep_freeze(
      "recovery" => 1..3,
      "endurance" => 2..4,
      "tempo" => 4..6,
      "sweet_spot" => 5..7,
      "threshold" => 7..9,
      "vo2_max" => 8..10,
      "over_under" => 7..9)
    COMPARABLE_FAMILIES = deep_freeze([ %w[tempo sweet_spot threshold], %w[vo2_max over_under] ])
    MAXIMUM_TARGET_PCT = 120
    INTENSITY_VARIATION_KEYS = %w[standard redistributed_recovery].freeze
    RECOVERY_VARIATION_KEYS = %w[steady gentle_ramp].freeze
    VARIATION_RECOVERY_SHIFT_SECONDS = 30
    SAME_TSS_TOLERANCE = 0.05
    SAME_IF_TOLERANCE = 0.03
    NP_WINDOW_SECONDS = 30

    ZONES = deep_freeze(recovery: 0..55, endurance: 56..75, tempo: 76..90, threshold: 91..105, vo2_max: 106..120)
    TARGETS = deep_freeze(
      recovery: [ 45, 55 ],
      endurance: [ 60, 72 ],
      tempo: [ 78, 87 ],
      sweet_spot: [ 88, 94 ],
      threshold: [ 95, 102 ],
      vo2_max: [ 108, 118 ],
      under: [ 88, 94 ],
      over: [ 102, 108 ],
      easy: [ 50, 60 ]
    )
    UPPER_THRESHOLD_LEVEL = 5
    UPPER_THRESHOLD_TARGET = [ 95, 100 ].freeze
    VO2_TARGETS = deep_freeze(120 => [ 112, 118 ], 180 => [ 110, 116 ], 240 => [ 108, 114 ], 300 => [ 106, 112 ])
    SUBTYPE_NAMES = deep_freeze(
      recovery: "Recovery",
      endurance: "Endurance",
      tempo: "Tempo",
      sweet_spot: "Sweet Spot",
      threshold: "Threshold",
      vo2_max: "VO2 Max",
      over_under: "Over-Unders"
    )
    PURPOSES = deep_freeze(
      recovery: "Easy riding to support recovery.",
      endurance: "Develops steady aerobic endurance.",
      tempo: "Builds sustained aerobic strength.",
      sweet_spot: "Builds sustainable time just below threshold.",
      threshold: "Develops sustained power near FTP.",
      vo2_max: "Develops repeated aerobic-power efforts.",
      over_under: "Practises sustained work with repeated changes around threshold."
    )
    PHASES = %w[base build speciality taper].map(&:freeze).freeze
    GOALS = %w[general_fitness increase_ftp improve_endurance improve_climbing event].map(&:freeze).freeze
    DISCIPLINES = %w[road gravel mtb ultra_endurance].map(&:freeze).freeze

    # Rows are repetitions, work minutes, recovery minutes (between work blocks).
    LADDERS = deep_freeze(
      tempo: [ [ 2, 10, 4 ], [ 2, 15, 4 ], [ 3, 12, 4 ], [ 2, 20, 5 ], [ 3, 15, 4 ], [ 2, 25, 5 ], [ 3, 20, 5 ] ],
      sweet_spot: [ [ 3, 8, 4 ], [ 3, 10, 4 ], [ 3, 12, 4 ], [ 2, 20, 5 ], [ 3, 15, 5 ], [ 2, 25, 5 ], [ 3, 20, 5 ] ],
      threshold: [ [ 4, 6, 4 ], [ 3, 8, 4 ], [ 4, 8, 4 ], [ 3, 10, 5 ], [ 3, 12, 5 ], [ 2, 20, 6 ], [ 3, 15, 5 ] ],
      vo2_max: [ [ 5, 2, 3 ], [ 6, 2, 3 ], [ 5, 3, 3 ], [ 6, 3, 3 ], [ 5, 4, 4 ], [ 4, 5, 5 ], [ 5, 5, 5 ] ],
      over_under: [ [ 2, 9, 5 ], [ 3, 9, 5 ], [ 2, 12, 5 ], [ 3, 12, 5 ], [ 2, 16, 6 ], [ 3, 15, 6 ], [ 2, 20, 7 ] ]
    )
    # The spec permits shorter variations when even level 1 cannot fit.
    # Preserve multiple work bouts and normal recovery, with >=5 min at each end.
    SHORT_MAIN_SETS = deep_freeze(
      tempo: [ 2, 8, 4 ],
      sweet_spot: [ 2, 8, 4 ],
      threshold: [ 2, 6, 4 ],
      vo2_max: [ 4, 2, 3 ],
      over_under: [ 2, 6, 5 ]
    )
    # Under/over minutes per cycle. Levels 5/7 continue the 3:1 pattern;
    # the 15-minute level 6 uses five 2:1 cycles, keeping all blocks exact.
    OVER_UNDER_CYCLES = deep_freeze([ [ 2, 1 ], [ 2, 1 ], [ 3, 1 ], [ 3, 1 ], [ 3, 1 ], [ 2, 1 ], [ 3, 1 ] ])

    WARM_UPS = deep_freeze(
      recovery: { ramp: 300, start: [ 40, 50 ], finish: [ 50, 55 ], primers: 0, settle: 0 },
      endurance: { ramp: 480, start: [ 45, 55 ], finish: [ 65, 70 ], primers: 0, settle: 0 },
      tempo: { ramp: 480, start: [ 45, 55 ], finish: [ 70, 75 ], primers: 2, primer_target: [ 90, 100 ], settle: 120 },
      sweet_spot: { ramp: 480, start: [ 45, 55 ], finish: [ 70, 75 ], primers: 2, primer_target: [ 90, 100 ], settle: 120 },
      threshold: { ramp: 600, start: [ 45, 55 ], finish: [ 75, 75 ], primers: 2, primer_target: [ 95, 105 ], settle: 180 },
      vo2_max: { ramp: 600, start: [ 45, 55 ], finish: [ 75, 75 ], primers: 3, primer_target: [ 105, 115 ], settle: 180 },
      over_under: { ramp: 600, start: [ 45, 55 ], finish: [ 75, 75 ], primers: 3, primer_target: [ 105, 115 ], settle: 180 }
    )
    COMPACT_WARM_UP_SECONDS = 300
    PRIMER_SECONDS = 30
    PRIMER_RECOVERY_SECONDS = 60
    COOL_DOWN_SECONDS = 300
    LONG_COOL_DOWN_SECONDS = 480
    LONG_SESSION_MINUTES = 90
    COOL_DOWN_START = [ 55, 60 ].freeze
    COOL_DOWN_END = [ 40, 50 ].freeze
    RECOVERY_COOL_DOWN_START = [ 50, 55 ].freeze
    RECOVERY_COOL_DOWN_END = [ 40, 45 ].freeze
    ENDURANCE_STEADY_TARGET = [ 65, 72 ].freeze
    ENDURANCE_VARIATION_KEYS = %w[sustained alternating undulating].freeze
    ENDURANCE_LOW_TARGET = [ 64, 68 ].freeze
    ENDURANCE_HIGH_TARGET = [ 70, 74 ].freeze
    ENDURANCE_BLOCK_SECONDS = 300
    ENDURANCE_BREAK_TARGET = [ 55, 60 ].freeze
    ENDURANCE_BREAK_SECONDS = 60
    RECOVERY_RAMP_START = [ 45, 50 ].freeze
    RECOVERY_RAMP_END = [ 50, 55 ].freeze

    private_class_method :deep_freeze
  end
end
