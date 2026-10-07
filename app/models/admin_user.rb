# Super admin, for the hidden stats section. Created only with `bin/rails admin:create`: there is
# no sign-up, and no password reset or confirmation by email.
class AdminUser
  include Mongoid::Document
  include Mongoid::Timestamps

  # lockable: 10 wrong passwords lock the account for an hour (see config/initializers/devise.rb).
  # timeoutable: signed out after 2 hours without using the admin.
  devise :database_authenticatable, :lockable, :timeoutable, :trackable, :validatable

  ## Database authenticatable
  field :email,              type: String, default: ""
  field :encrypted_password, type: String, default: ""

  ## Trackable
  field :sign_in_count,      type: Integer, default: 0
  field :current_sign_in_at, type: Time
  field :last_sign_in_at,    type: Time
  field :current_sign_in_ip, type: String
  field :last_sign_in_ip,    type: String

  ## Lockable
  field :failed_attempts, type: Integer, default: 0
  field :locked_at,       type: Time

  index({ email: 1 }, { unique: true })
end
