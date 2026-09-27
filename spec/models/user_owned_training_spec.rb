require "rails_helper"

RSpec.describe "User-owned training", type: :model do
  uses_transaction "USR-002 enforces one profile during concurrent first creation",
    "USR-003 enforces one active plan during concurrent creation"

  def with_committed_user
    owner_id = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        User.create!(email_address: "concurrent-#{SecureRandom.hex(8)}@example.com", password: "password").id
      end
    end.value
    yield owner_id
  ensure
    if owner_id
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          RiderProfile.where(user_id: owner_id).delete_all
          TrainingPlan.where(user_id: owner_id).delete_all
          User.where(id: owner_id).delete_all
        end
      end.value
    end
  end

  def race_insert(&block)
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            ActiveRecord::Base.transaction(requires_new: true) { block.call }
            :created
          rescue ActiveRecord::RecordNotUnique
            :duplicate
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.map(&:value)
  end

  it "USR-002 enforces one profile during concurrent first creation" do
    with_committed_user do |owner_id|
      results = race_insert do
        RiderProfile.new(user_id: owner_id, ftp_watts: 260).save!(validate: false)
      end
      expect(results.sort).to eq(%i[created duplicate])
      expect(RiderProfile.where(user_id: owner_id).count).to eq(1)
    end
  end

  it "USR-003 enforces one active plan during concurrent creation" do
    with_committed_user do |owner_id|
      results = race_insert do
        plan = FactoryBot.build(:training_plan, user: User.find(owner_id))
        plan.save!(validate: false)
      end
      expect(results.sort).to eq(%i[created duplicate])
      expect(TrainingPlan.active.where(user_id: owner_id).count).to eq(1)
    end
  end

  it "USR-003 requires a real user for every plan in PostgreSQL" do
    plan = create(:training_plan, :archived)
    expect_database_rejection(ActiveRecord::NotNullViolation) { plan.update_columns(user_id: nil) }
    expect_database_rejection(ActiveRecord::InvalidForeignKey) { plan.update_columns(user_id: 999_999) }
  end
end
