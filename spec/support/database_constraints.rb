module DatabaseConstraints
  def expect_database_rejection(error = ActiveRecord::StatementInvalid, &block)
    expect do
      ActiveRecord::Base.transaction(requires_new: true, &block)
    end.to raise_error(error)
  end
end

RSpec.configure do |config|
  config.include DatabaseConstraints
end
