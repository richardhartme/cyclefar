module LegacyOwnership
  class Backfill
    class UnsafeData < StandardError; end

    TABLES = %w[rider_profiles training_plans intervals_icu_syncs].freeze
    COUNTS = {
      users: "SELECT COUNT(*) FROM users",
      sessions: "SELECT COUNT(*) FROM sessions",
      rider_profiles: "SELECT COUNT(*) FROM rider_profiles",
      ftp_readings: "SELECT COUNT(*) FROM ftp_readings",
      training_plans: "SELECT COUNT(*) FROM training_plans",
      completed_workouts: "SELECT COUNT(*) FROM planned_workouts WHERE status = 'completed'",
      sync_linked: "SELECT COUNT(*) FROM intervals_icu_syncs WHERE planned_workout_id IS NOT NULL",
      sync_detached: "SELECT COUNT(*) FROM intervals_icu_syncs WHERE planned_workout_id IS NULL"
    }.freeze

    def initialize(connection:, owner_id:)
      @connection = connection
      @owner_id = owner_id
    end

    def report
      verify_auth_schema!
      { counts: counts, owner: owner_identity }
    end

    def counts
      verify_auth_schema!
      COUNTS.transform_values { |sql| connection.select_value(sql).to_i }
    end

    def preflight!
      inventory = report
      counts = inventory.fetch(:counts)
      errors = []
      errors << "An existing CYCLEFAR_LEGACY_OWNER_USER_ID is required for legacy training data" if training_data?(counts) && inventory[:owner].nil?
      errors << "More than one legacy rider profile exists" if counts[:rider_profiles] > 1
      errors << "FTP readings exist without a rider profile" if counts[:ftp_readings].positive? && counts[:rider_profiles].zero?
      errors << "Completed workouts exist without a training plan" if counts[:completed_workouts].positive? && counts[:training_plans].zero?
      errors << "An FTP reading references a missing profile" if count("SELECT COUNT(*) FROM ftp_readings f LEFT JOIN rider_profiles p ON p.id = f.rider_profile_id WHERE p.id IS NULL").positive?
      errors << "A workout references a missing plan" if count("SELECT COUNT(*) FROM planned_workouts w LEFT JOIN training_plans p ON p.id = w.training_plan_id WHERE p.id IS NULL").positive?
      errors << "A linked sync references a missing workout or plan" if count("SELECT COUNT(*) FROM intervals_icu_syncs s LEFT JOIN planned_workouts w ON w.id = s.planned_workout_id LEFT JOIN training_plans p ON p.id = w.training_plan_id WHERE s.planned_workout_id IS NOT NULL AND p.id IS NULL").positive?
      errors << "A sync external ID is outside the CycleFar namespace" if count("SELECT COUNT(*) FROM intervals_icu_syncs WHERE external_id NOT LIKE 'cyclefar-%'").positive?

      if inventory[:owner]
        TABLES.each do |table|
          next unless connection.column_exists?(table, :user_id)

          mismatch = count("SELECT COUNT(*) FROM #{table} WHERE user_id IS NOT NULL AND user_id != #{owner_id}")
          errors << "#{table} already contains a different owner" if mismatch.positive?
        end
      end

      raise UnsafeData, errors.join("; ") if errors.any?

      inventory
    end

    def backfill!
      connection.transaction do
        preflight!
        TABLES.each do |table|
          raise UnsafeData, "#{table}.user_id is missing" unless connection.column_exists?(table, :user_id)
        end
        next if owner_id.nil?

        TABLES.each do |table|
          connection.execute("UPDATE #{table} SET user_id = #{owner_id} WHERE user_id IS NULL")
        end
      end
    end

    private

    attr_reader :connection

    def owner_id
      return @parsed_owner_id if defined?(@parsed_owner_id)

      @parsed_owner_id = if @owner_id.present?
        Integer(@owner_id.to_s, 10).tap { |id| raise ArgumentError if id <= 0 }
      end
    rescue ArgumentError, TypeError
      raise UnsafeData, "CYCLEFAR_LEGACY_OWNER_USER_ID must be a positive integer"
    end

    def owner_identity
      return if owner_id.nil?

      row = connection.select_one("SELECT id, email_address FROM users WHERE id = #{owner_id}")
      raise UnsafeData, "Selected legacy owner does not exist" unless row

      row.slice("id", "email_address")
    end

    def training_data?(counts)
      counts.values_at(:rider_profiles, :ftp_readings, :training_plans, :completed_workouts, :sync_linked, :sync_detached).any?(&:positive?)
    end

    def count(sql)
      connection.select_value(sql).to_i
    end

    def verify_auth_schema!
      expected = { users: %w[id email_address password_digest], sessions: %w[id user_id] }
      expected.each do |table, columns|
        unless connection.data_source_exists?(table) && columns.all? { |column| connection.column_exists?(table, column) }
          raise UnsafeData, "#{table} does not match the generated authentication schema; repair it on a database copy before backfill"
        end
      end
      auth_migrations = %w[20260927123824 20260927123825]
      applied = connection.select_values("SELECT version FROM schema_migrations WHERE version IN ('20260927123824', '20260927123825')")
      unless (auth_migrations - applied).empty? &&
          connection.index_exists?(:users, :email_address, unique: true) &&
          connection.index_exists?(:sessions, :user_id) &&
          connection.foreign_key_exists?(:sessions, :users, column: :user_id)
        raise UnsafeData, "Generated authentication migrations, indexes or session foreign key are missing; repair them on a database copy before backfill"
      end
    end
  end
end
