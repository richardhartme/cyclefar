module Settings
  class FtpMutation
    attr_reader :refresh_result

    def initialize(profile:)
      @profile = profile
      @user = profile.user
    end

    def call
      IntervalsIcu::Synchronization.with_owner_lock(@user) do
        profile = nil
        previous_ftp = nil
        result = @user.with_lock do
          profile = @profile.persisted? ? @profile.reload : (@user.rider_profile || @user.build_rider_profile)
          @user.association(:rider_profile).target = profile
          previous_ftp = profile.ftp_watts
          value = yield profile
          FtpHistory.new(profile: profile).refresh_current!(previous_ftp: previous_ftp) if profile.ftp_readings.exists?
          value
        end
        # Release the local transaction/row locks before HTTP, but keep the
        # owner advisory lock so sync/removal cannot interleave with this save.
        if previous_ftp != profile.ftp_watts
          @refresh_result = IntervalsIcu::RefreshSyncedWorkouts.new(profile: profile).call
        end
        result
      end
    end
  end
end
