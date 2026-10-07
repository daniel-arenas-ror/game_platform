require "io/console"

namespace :admin do
  # In a terminal it asks for the password (hidden, twice). Without one (e.g. script/aws_run.sh),
  # it makes a strong password and prints it once. Re-running it for the same email sets a new
  # password and unlocks the account.
  desc "Create an admin, or reset an admin's password: bin/rails admin:create EMAIL=you@example.com"
  task create: :environment do
    email = ENV["EMAIL"].to_s.strip.downcase
    abort "Usage: bin/rails admin:create EMAIL=you@example.com" if email.blank?

    if $stdin.tty?
      password = $stdin.getpass("Password (#{Devise.password_length.min}+ characters): ")
      abort "The passwords don't match." unless password == $stdin.getpass("Again: ")
    else
      password = SecureRandom.base58(24)
      generated = true
    end

    admin = AdminUser.find_or_initialize_by(email: email)
    created = admin.new_record?
    admin.password = admin.password_confirmation = password
    admin.failed_attempts = 0
    admin.locked_at = nil
    abort admin.errors.full_messages.to_sentence unless admin.save

    puts "#{created ? 'Created' : 'Updated'} admin #{email}."
    puts "Password: #{password}\nSave it now, it isn't shown again." if generated
  end

  desc "List the admins"
  task list: :environment do
    AdminUser.order_by(email: :asc).each do |admin|
      puts [ admin.email, "#{admin.sign_in_count} sign-ins", ("LOCKED" if admin.access_locked?) ].compact.join(" · ")
    end
  end

  desc "Delete an admin: bin/rails admin:delete EMAIL=you@example.com"
  task delete: :environment do
    admin = AdminUser.where(email: ENV["EMAIL"].to_s.strip.downcase).first
    abort "No admin with that email." unless admin

    admin.destroy
    puts "Deleted admin #{admin.email}."
  end
end
