require File.dirname(__FILE__) + '/../test_helper'

class UserTest < ActiveSupport::TestCase
  # Be sure to include AuthenticatedTestHelper in test/test_helper.rb instead.
  # Then, you can remove it from this and the functional test.
  include AuthenticatedTestHelper
  include RR::Adapters::TestUnit

  fixtures :users

  def setup()
    stub(CrowdUsersEndpoint).update_password(anything, anything) { Hash.new }
  end

  def test_should_create_user
    assert_difference 'User.count' do
      user = create_user
      assert !user.new_record?, "#{user.errors.full_messages.to_sentence}"
    end
  end

  def test_should_require_login
    assert_no_difference 'User.count' do
      u = create_user(:login => nil)
      assert u.errors.on(:login)
    end
  end

  def test_save_password_successful()

    user = create_user
    user.password = "foobar"
    user.password_confirmation = "foobar"

    stub(user).password_valid?() { true }

    stub(CrowdUsersEndpoint).update_password(user.login, user.password) { Hash.new }

    user.send(:save_password)
  end

  def test_save_password_unsuccessful()

    user = create_user
    user.password = "foobar"
    user.password_confirmation = "foobar"

    stub(user).password_valid?() { true }

    stub(CrowdUsersEndpoint).update_password(user.login, user.password) do
      raise "Could Not Save Password"
    end

    assert_raise(RuntimeError) do
      user.send(:save_password)
    end
    
  end  

  def test_should_authenticate_user
    expected_user = create_user
    expected_user.password = "foobar"
    expected_user.password_confirmation = "foobar"

    stub(CrowdUsersEndpoint).authenticate(expected_user.login, expected_user.password) { Hash.new }

    actual_user = User.authenticate(expected_user.login, expected_user.password)
    assert_equal(expected_user, actual_user)
  end

  def test_should_not_authenticate_if_disabled
    user = create_user
    user.disable
    user.save(false)
    user.password = "foobar"
    user.password_confirmation = "foobar"

    stub(CrowdUsersEndpoint).authenticate(user.login, user.password) { Hash.new }

    actual_user = User.authenticate(user.login, user.password)
    assert_nil(actual_user)
  end  

  def test_should_not_authenticate_user
    user = create_user
    user.password = "foobar"
    user.password_confirmation = "foobar"

    stub(CrowdUsersEndpoint).authenticate(user.login, user.password) { nil }

    actual_user = User.authenticate(user.login, user.password)
    assert_nil(actual_user)
  end

  def test_should_set_remember_token
    users(:quentin).remember_me
    assert_not_nil users(:quentin).remember_token
    assert_not_nil users(:quentin).remember_token_expires_at
  end

  def test_should_unset_remember_token
    users(:quentin).remember_me
    assert_not_nil users(:quentin).remember_token
    users(:quentin).forget_me
    assert_nil users(:quentin).remember_token
  end

  def test_should_remember_me_for_one_week
    before = 1.week.from_now.utc
    users(:quentin).remember_me_for 1.week
    after = 1.week.from_now.utc
    assert_not_nil users(:quentin).remember_token
    assert_not_nil users(:quentin).remember_token_expires_at
    assert users(:quentin).remember_token_expires_at.between?(before, after)
  end

  def test_should_remember_me_until_one_week
    time = 1.week.from_now.utc
    users(:quentin).remember_me_until time
    assert_not_nil users(:quentin).remember_token
    assert_not_nil users(:quentin).remember_token_expires_at
    assert_equal users(:quentin).remember_token_expires_at, time
  end

  def test_should_remember_me_default_two_weeks
    before = 2.weeks.from_now.utc
    users(:quentin).remember_me
    after = 2.weeks.from_now.utc
    assert_not_nil users(:quentin).remember_token
    assert_not_nil users(:quentin).remember_token_expires_at
    assert users(:quentin).remember_token_expires_at.between?(before, after)
  end
  
  def test_admin
    user = create_new_user
    assert !user.admin?
    
    user.admin = 1
    assert user.admin?
    
    user.revoke_admin!
    assert !user.admin?
    
    user.make_admin!
    assert user.admin?
  end
  
  def test_revert_admin_status_only_if_other_admins_left
    User.delete_all
    
    admin = create_new_user
    admin.make_admin!
    assert admin.admin?
    
    user = create_new_user
    assert !user.admin?
    
    # check that the admin status of admin cannot be taken
    admin.revoke_admin!
    admin = User.find(:first)
    assert admin.admin?
  end
  
  def test_recent_deployments
    user = create_new_user
    stage = create_new_stage
    role = create_new_role(:stage => stage)
    5.times do 
      deployment = create_new_deployment(:stage => stage, :user => user)
    end
    
    assert_equal 5, user.deployments.count
    assert_equal 3, user.recent_deployments.size
    assert_equal 2, user.recent_deployments(2).size
  end
  
  def test_disable
    user = create_new_user
    assert !user.disabled?
    
    user.disable
    
    assert user.disabled?
    
    user.enable
    
    assert !user.disabled?
  end
  
  def test_disable_resets_remember_me
    user = create_new_user
    user.remember_me
    
    assert_not_nil user.remember_token
    assert_not_nil user.remember_token_expires_at
    
    user.disable
    
    assert_nil user.remember_token
    assert_nil user.remember_token_expires_at
  end
  
  def test_enabled_named_scope
    User.destroy_all
    assert_equal [], User.enabled
    assert_equal [], User.disabled
    
    user = create_new_user
    
    assert_equal [user], User.enabled
    assert_equal [], User.disabled
    
    user.disable
    
    assert_equal [], User.enabled
    assert_equal [user], User.disabled
  end

  def test_create_from_crowd_user_admin

    user_json = JSON.parse(CROWD_USER_ADMIN_ACTIVE_JSON)

    User.create_or_update_from_crowd_user(user_json)

    created_user = User.find_by_email("zap@doop.net")
    assert_not_nil(created_user)
    assert_equal("zap", created_user.login)
    assert(created_user.admin?)
    assert(!created_user.disabled)
  end

  def test_create_from_crowd_user_non_admin

    user_json = JSON.parse(CROWD_USER_NONADMIN_DISABLED_JSON)

    User.create_or_update_from_crowd_user(user_json)

    created_user = User.find_by_email("fry@planetexpress.com")
    assert_not_nil(created_user)
    assert_equal("fry", created_user.login)
    assert(!created_user.admin?)
    assert(created_user.disabled?)
  end

  def test_update_from_crowd_user_admin
    user_json = JSON.parse(CROWD_USER_ADMIN_ACTIVE_JSON)

    seed_user = User.new(:login => "zap"); seed_user.save(false)

    User.create_or_update_from_crowd_user(user_json)

    updated_user = User.find_by_email("zap@doop.net")
    assert_not_nil(updated_user)
    assert_equal("zap", updated_user.login)
    assert(updated_user.admin?)
    assert(!updated_user.disabled?)  
  end

  def test_update_from_crowd_user_non_admin

    user_json = JSON.parse(CROWD_USER_NONADMIN_DISABLED_JSON)

    seed_user = User.new(:login => "fry"); seed_user.save(false)

    User.create_or_update_from_crowd_user(user_json)

    updated_user = User.find_by_email("fry@planetexpress.com")
    assert_not_nil(updated_user)
    assert_equal("fry", updated_user.login)
    assert(!updated_user.admin?)
    assert(updated_user.disabled?)    
  end

  def test_create_or_update_from_crowd_users

    mock(User).create_or_update_from_crowd_user("fry")
    mock(User).create_or_update_from_crowd_user("zap")
    stub(CrowdUsersEndpoint).get(anything) { | p | p }

    User.create_or_update_from_crowd_users(JSON.parse(CROWD_USERS_JSON))

  end

  CROWD_USERS_JSON = %({
    "expand" : "user",
    "users" : [
      {
        "link" : {
          "rel" : "self",
          "href" : "http://localhost:8095/crowd/rest/usermanagement/1/user?username=fry"
        },
        "name" : "fry"
      },
      {
        "link" : {
          "rel" : "self",
          "href" : "http://localhost:8095/crowd/rest/usermanagement/1/user?username=zap"
        },
        "name" : "zap"
      }
    ]
  })

  CROWD_USER_ADMIN_ACTIVE_JSON = %({
    "expand" : "attributes",
    "first-name" : "Zap",
    "last-name" : "Brannigan",
    "active" : true,
    "email" : "zap@doop.net",
    "attributes" : {
      "attributes" : [
        {
          "values" : [
            "false"
          ],
          "name" : "requiresPasswordChange"
        },
        {
          "values" : [
            "0"
          ],
          "name" : "invalidPasswordAttempts"
        },
        {
          "values" : [
            "1"
          ],
          "name" : "admin"
        },
        {
          "values" : [
            "1355946934385"
          ],
          "name" : "lastAuthenticated"
        },
        {
          "values" : [
            "1355863333318"
          ],
          "name" : "passwordLastChanged"
        }
      ]
    },
    "name" : "zap",
    "display-name" : "Zap Brannigan"
  })

  CROWD_USER_NONADMIN_DISABLED_JSON = %({
    "expand" : "attributes",
    "first-name" : "Philip",
    "last-name" : "Fry",
    "active" : false,
    "email" : "fry@planetexpress.com",
    "attributes" : {
      "attributes" : [
        {
          "values" : [
            "false"
          ],
          "name" : "requiresPasswordChange"
        },
        {
          "values" : [
            "0"
          ],
          "name" : "invalidPasswordAttempts"
        },
        {
          "values" : [
            "1355946934385"
          ],
          "name" : "lastAuthenticated"
        },
        {
          "values" : [
            "1355863333318"
          ],
          "name" : "passwordLastChanged"
        }
      ]
    },
    "name" : "fry",
    "display-name" : "Philip J. Fry"
  })

  protected
    def create_user(options = {})
      User.create({ :login => 'quire', :email => 'quire@example.com', :password => 'quire', :password_confirmation => 'quire' }.merge(options))
    end
  #end protected
end
