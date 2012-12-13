require 'digest/sha1'
class User < ActiveRecord::Base
  has_many :deployments, :dependent => :nullify, :order => 'created_at DESC'
  
  # Virtual attribute for the unencrypted password
  #attr_accessor :password
  
  attr_accessible :login, :email, :password, :password_confirmation, :time_zone, :tz

  validates_presence_of     :login, :email
  validates_presence_of     :password,                   :if => :password_required?
  validates_presence_of     :password_confirmation,      :if => :password_required?
  validates_length_of       :password, :within => 4..40, :if => :password_required?
  validates_confirmation_of :password,                   :if => :password_required?
  validates_length_of       :login,    :within => 3..40
  validates_length_of       :email,    :within => 3..100
  validates_uniqueness_of   :login, :email, :case_sensitive => false
  
  named_scope :enabled, :conditions => {:disabled => nil}
  named_scope :disabled, :conditions => "disabled IS NOT NULL"

  CROWD_APPLICATION_USERNAME = "webistrano"
  CROWD_APPLICATION_PASSWORD = "foobar"
  CROWD_REST_HOST = "localhost"
  CROWD_REST_AUTHENTICATION_URL = "http://#{CROWD_APPLICATION_USERNAME}:#{CROWD_APPLICATION_PASSWORD}@#{CROWD_REST_HOST}:8095/crowd/rest/usermanagement/1/authentication?username=__username__"
  CROWD_REST_AUTHENTICATION_REQUEST_BODY = %(<?xml version="1.0" encoding="UTF-8"?>
    <password>
      <value>__password__</value>
    </password>
  )
    
  def validate_on_update
    if User.find(self.id).admin? && !self.admin?
      errors.add('admin', 'status can no be revoked as there needs to be one admin left.') if User.admin_count == 1
    end
  end
  
  # Authenticates a user by their user name and unencrypted password.  Returns the user or nil.
  def self.authenticate(username, password)

    url = CROWD_REST_AUTHENTICATION_URL.gsub("__username__", username)
    body = CROWD_REST_AUTHENTICATION_REQUEST_BODY.gsub("__password__", password)

    begin
      RestClient.post(url, body, {:content_type => "application/xml"})
      u = find_by_login_and_disabled(username, nil)
    rescue RestClient::BadRequest
      return nil
    end
  end

  # Encrypts some data with the salt.
  def self.encrypt(password, salt)
    Digest::SHA1.hexdigest("--#{salt}--#{password}--")
  end

  # Encrypts the password with the user salt
  def encrypt(password)
    self.class.encrypt(password, salt)
  end

  def remember_token?
    remember_token_expires_at && Time.now < remember_token_expires_at
  end

  # These create and unset the fields required for remembering users between browser closes
  def remember_me
    remember_me_for 2.weeks
  end

  def remember_me_for(time)
    remember_me_until time.from_now.utc
  end

  def remember_me_until(time)
    self.remember_token_expires_at = time
    self.remember_token            = encrypt("#{email}--#{remember_token_expires_at}")
    save(false)
  end

  def forget_me
    self.remember_token_expires_at = nil
    self.remember_token            = nil
    save(false)
  end
  
  def admin?
    self.admin.to_i == 1
  end
  
  def revoke_admin!
    self.admin = 0
    self.save!
  end
  
  def make_admin!
    self.admin = 1
    self.save!
  end
  
  def self.admin_count
    count(:id, :conditions => ['admin = 1 AND disabled IS NULL'])
  end
  
  def recent_deployments(limit=3)
    self.deployments.find(:all, :limit => limit, :order => 'created_at DESC')
  end
  
  def disabled?
    !self.disabled.blank?
  end
  
  def disable
    self.update_attribute(:disabled, Time.now)
    self.forget_me
  end
  
  def enable
    self.update_attribute(:disabled, nil)
  end

  protected
    
    def password_required?
      WebistranoConfig[:authentication_method] != :cas
    end

    
end
