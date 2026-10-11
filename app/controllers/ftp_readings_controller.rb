class FtpReadingsController < ApplicationController
  include FtpRefreshMessage

  before_action :set_reading, only: %i[edit update destroy]

  def edit
  end

  def update
    mutation = history
    mutation.update!(reading_id: @reading.id, attributes: reading_params)
    redirect_to settings_path, **ftp_save_flash("FTP reading updated.", mutation.refresh_result), status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    @reading = error.record
    render :edit, status: :unprocessable_content
  end

  def destroy
    mutation = history
    mutation.destroy!(reading_id: @reading.id)
    redirect_to settings_path, **ftp_save_flash("FTP reading deleted.", mutation.refresh_result), status: :see_other
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
