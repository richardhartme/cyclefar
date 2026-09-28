class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail subject: "Set or reset your CycleFar password", to: user.email_address
  end
end
