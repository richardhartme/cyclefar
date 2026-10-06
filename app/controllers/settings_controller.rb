class SettingsController < ApplicationController
  before_action :load_ftp_history, only: :show
  def show
    @profile = Current.user.rider_profile || Current.user.build_rider_profile
  end

  def update
    @profile = Settings::Update.new(profile: Current.user.rider_profile || Current.user.build_rider_profile, attributes: settings_params).call
    redirect_to settings_path, notice: "Settings saved.", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    @profile = error.record
    load_ftp_history
    render :show, status: :unprocessable_content
  end

  private

  def load_ftp_history
    @ftp_readings = Current.user.rider_profile&.ftp_readings&.newest_first || []
  end

  def settings_params
    params.expect(rider_profile: [ :ftp_watts, :intervals_icu_api_key, :clear_intervals_icu_api_key ])
  end
end
