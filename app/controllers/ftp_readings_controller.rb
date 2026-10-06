class FtpReadingsController < ApplicationController
  before_action :set_reading, only: %i[edit update destroy]

  def edit
  end

  def update
    history.update!(reading_id: @reading.id, attributes: reading_params)
    redirect_to settings_path, notice: "FTP reading updated.", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    @reading = error.record
    render :edit, status: :unprocessable_content
  end

  def destroy
    history.destroy!(reading_id: @reading.id)
    redirect_to settings_path, notice: "FTP reading deleted.", status: :see_other
  rescue ActiveRecord::RecordNotDestroyed => error
    redirect_to settings_path, alert: error.record.errors.full_messages.to_sentence, status: :see_other
  end

  private

  def set_reading
    @profile = Current.user.rider_profile
    raise ActiveRecord::RecordNotFound unless @profile

    @reading = @profile.ftp_readings.find(params[:id])
  end

  def history
    Settings::FtpHistory.new(profile: @profile)
  end

  def reading_params
    params.expect(ftp_reading: [ :ftp_watts, :effective_on ])
  end
end
