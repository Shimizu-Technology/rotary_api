class User < ApplicationRecord
  has_secure_password
  validates :email, presence: true, uniqueness: true
  belongs_to :restaurant, optional: true
  # optional: true => super_admin can have no restaurant
end
class User < ApplicationRecord
  belongs_to :restaurant, optional: true

  # Use has_secure_password for bcrypt-based password handling
  has_secure_password

  validates :email, presence: true, uniqueness: true
  validates :password_digest, presence: true

  def admin?
    role == 'admin'
  end
end
