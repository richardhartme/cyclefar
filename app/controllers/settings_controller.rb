class SettingsController < ApplicationController
  def show
    @profile = RiderProfile.current
  end

  def update
    @profile = Settings::Update.new(profile: RiderProfile.current, attributes: settings_params).call
    redirect_to settings_path, notice: "Settings saved.", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    @profile = error.record
    render :show, status: :unprocessable_content
  end

  private

  def settings_params
    params.expect(rider_profile: [ :ftp_watts, :intervals_icu_api_key, :clear_intervals_icu_api_key ])
  end
end
