module Activities
  # Recalculates a rider's unlinked rides whose FTP in force has changed with
  # their FTP history (FBK-004). Linked rides keep their workout's frozen
  # completion FTP and are never touched here.
  class FtpRefresh
    def initialize(user)
      @user = user
    end

    def call
      @user.activities.unlinked.cycling.joins(:ride_file_attachment).includes(:user).find_each do |activity|
        Linker.new(activity).recalculate! unless Figures.new(activity).current?
      end
    end
  end
end
