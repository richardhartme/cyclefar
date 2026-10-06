module Settings
  # Explicit history mutations keep the current FTP cache and future metrics
  # in the same transaction. Settings saves share the owning-user lock.
  class FtpHistory
    def initialize(profile:)
      @profile = profile
    end

    def update!(reading_id:, attributes:)
      mutate do
        reading = @profile.ftp_readings.find(reading_id)
        reading.update!(attributes.to_h.symbolize_keys.slice(:ftp_watts, :effective_on))
        reading
      end
    end

    def destroy!(reading_id:)
      mutate do
        reading = @profile.ftp_readings.find(reading_id)
        if @profile.ftp_readings.count == 1
          reading.errors.add(:base, "Keep at least one FTP reading. Edit this reading or save a new FTP first.")
          raise ActiveRecord::RecordNotDestroyed.new("The final FTP reading cannot be deleted", reading)
        end
        reading.destroy!
      end
    end

    # Called within the owning-user transaction, also by Settings::Update.
    def refresh_current!(previous_ftp: @profile.ftp_watts)
      latest = @profile.ftp_readings.newest_first.first!
      @profile.update!(ftp_watts: latest.ftp_watts) if @profile.ftp_watts != latest.ftp_watts
      Planning::FtpRecalculator.new(profile: @profile).call if previous_ftp != latest.ftp_watts
    end

    private

    def mutate
      @profile.user.with_lock do
        @profile.reload
        result = yield
        refresh_current!
        result
      end
    end
  end
end
