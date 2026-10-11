module FtpRefreshMessage
  private

  def ftp_save_flash(notice, result)
    return { notice: notice } unless result
    return { notice: notice, alert: result.error } if result.error
    return { notice: notice } if result.refreshed_count.zero?

    count = result.refreshed_count
    { notice: "#{notice} Refreshed #{count} workout#{'s' unless count == 1} in Intervals.icu." }
  end
end
