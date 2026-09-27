FactoryBot.define do
  factory :user do
    sequence(:email_address) { |number| "user#{number}@example.com" }
    password { "password" }
  end
end
