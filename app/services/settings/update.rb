module Settings
  class Update
    def initialize(profile:, attributes:, effective_on: Date.current)
      @profile = profile
      @attributes = attributes.to_h.symbolize_keys.slice(:ftp_watts, :intervals_icu_api_key, :clear_intervals_icu_api_key)
      @effective_on = effective_on
    end

    def call
      RiderProfile.transaction do
        # Also serialize concurrent first saves, before the singleton row exists.
        RiderProfile.connection.execute("SELECT pg_advisory_xact_lock(731001)")
        current = RiderProfile.find_by(id: 1)
        @profile = current if current
        @profile.assign_attributes(profile_attributes)
        ftp_changed = @profile.new_record? || @profile.will_save_change_to_ftp_watts?
        @profile.save!
        if ftp_changed
          @profile.ftp_readings.create!(ftp_watts: @profile.ftp_watts, effective_on: @effective_on)
          Planning::FtpRecalculator.new(ftp_watts: @profile.ftp_watts, effective_on: @effective_on).call
        end
      end
      @profile
    end

    private

    def profile_attributes
      attributes = @attributes.except(:clear_intervals_icu_api_key)
      # A blank password field preserves the saved secret; clearing is explicit.
      attributes.delete(:intervals_icu_api_key) if attributes[:intervals_icu_api_key].blank?
      if ActiveModel::Type::Boolean.new.cast(@attributes[:clear_intervals_icu_api_key])
        attributes[:intervals_icu_api_key] = nil
      end
      attributes
    end
  end
end
