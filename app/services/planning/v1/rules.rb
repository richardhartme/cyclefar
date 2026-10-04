require_relative "../../training/v1/rules"

module Planning
  module V1
    module Rules
      ENGINE_VERSION = Training::V1::Rules::ENGINE_VERSION
      PRESET_MONTHS = [ 1, 3, 6 ].freeze
      MINIMUM_CUSTOM_WEEKS = 4
      MINIMUM_EVENT_LEAD_DAYS = 28
      FTP_TEST_IDEAL_DAYS = 35
      FTP_TEST_MIN_GAP_DAYS = 28
      FTP_TEST_MAX_GAP_DAYS = 42
      FTP_TEST_EVENT_EXCLUSION_DAYS = 14
      HARD_WEEK_GROWTH_CAP = 0.08
      RECOVERY_MAXIMUM_LEVEL = 1
      RECOVERY_DURATION_FACTOR = 0.70
      TAPER_DURATION_FACTOR = 0.60
      TAPER_INTENSITY_DURATION_FACTOR = 0.70
      TAPER_WORK_FACTOR = 0.60
      LONG_TAPER_DURATION_FACTOR = 0.90
      LONG_TAPER_WORK_FACTOR = 0.75
      LONG_TAPER_LOAD_FACTOR = 0.75
      EVENT_WEEK_LOAD_FACTOR = 0.50
      LONG_TAPER_MINIMUM_DAYS = 10
      TAPER_FINAL_STAGE_DAYS = 7
      TAPER_NO_HARD_DAYS = 2
      MOVE_STRUCTURE_WINDOW_DAYS = 7

      PHASE_PROPORTIONS = {
        with_base: { base: 0.35, build: 0.40, speciality: 0.25 }.freeze,
        without_base: { build: 0.60, speciality: 0.40 }.freeze
      }.freeze
      PHASE_LEVELS = { base: (1..4), build: (3..6), speciality: (4..7), taper: (1..2) }.freeze

      INTERVAL_CYCLES = {
        base: {
          general_fitness: %i[sweet_spot tempo sweet_spot threshold],
          increase_ftp: %i[sweet_spot threshold sweet_spot threshold],
          improve_endurance: %i[tempo sweet_spot tempo sweet_spot],
          improve_climbing: %i[sweet_spot threshold tempo sweet_spot],
          event: %i[sweet_spot tempo threshold sweet_spot]
        },
        build: {
          general_fitness: %i[threshold vo2_max sweet_spot threshold],
          increase_ftp: %i[threshold vo2_max threshold sweet_spot],
          improve_endurance: %i[sweet_spot threshold tempo vo2_max],
          improve_climbing: %i[threshold vo2_max over_under threshold]
        },
        speciality: {
          general_fitness: %i[threshold vo2_max sweet_spot tempo],
          increase_ftp: %i[threshold vo2_max threshold over_under],
          improve_endurance: %i[sweet_spot tempo threshold sweet_spot],
          improve_climbing: %i[threshold vo2_max over_under threshold]
        }
      }.freeze
      EVENT_DISCIPLINE_CYCLES = {
        build: {
          road: %i[threshold vo2_max sweet_spot threshold],
          gravel: %i[sweet_spot threshold tempo vo2_max],
          mtb: %i[vo2_max threshold vo2_max sweet_spot],
          ultra_endurance: %i[sweet_spot threshold tempo sweet_spot]
        },
        speciality: {
          road: %i[threshold vo2_max over_under threshold],
          gravel: %i[sweet_spot threshold tempo over_under],
          mtb: %i[vo2_max over_under vo2_max threshold],
          ultra_endurance: %i[tempo sweet_spot threshold tempo]
        }
      }.freeze
    end
  end
end
