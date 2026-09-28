class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  before_action :redirect_signed_in_user
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Try again later." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    if registration_params[:password_confirmation].present? && @user.save
      start_new_session_for @user
      redirect_to root_path, notice: "Your account is ready."
    else
      if registration_params[:password_confirmation].blank?
        @user.valid?
        @user.errors.add(:password_confirmation, "can't be blank")
      end
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end

  def redirect_signed_in_user
    redirect_to root_path if authenticated?
  end
end
