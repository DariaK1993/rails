# frozen_string_literal: true

require "shellwords"

#
# Tests, setup, and teardown common to the application and plugin generator suites.
#
module SharedGeneratorTests
  def setup
    Rails.application = TestApp::Application
    super
    Rails::Generators::AppGenerator.instance_variable_set("@desc", nil)

    Kernel.silence_warnings do
      Thor::Base.shell.attr_accessor :always_force
      @shell = Thor::Base.shell.new
      @shell.always_force = true
    end
  end

  def teardown
    super
    Rails::Generators::AppGenerator.instance_variable_set("@desc", nil)
    Rails.application = TestApp::Application.instance
  end

  def application_path
    destination_root
  end

  def test_skeleton_is_created
    run_generator

    default_files.each { |path| assert_file path }
  end

  def test_plugin_new_generate_pretend
    run_generator ["testapp", "--pretend"]
    default_files.each { |path| assert_no_file File.join("testapp", path) }
  end

  def test_invalid_database_option_raises_an_error
    content = capture(:stderr) { run_generator([destination_root, "-d", "unknown"]) }
    assert_match(/Invalid value for --database option/, content)
  end

  def test_test_files_are_skipped_if_required
    run_generator [destination_root, "--skip-test"]
    assert_no_file "test"
  end

  def test_name_collision_raises_an_error
    reserved_words = %w[application destroy plugin runner test]
    reserved_words.each do |reserved|
      content = capture(:stderr) { run_generator [File.join(destination_root, reserved)] }
      assert_match(/Invalid \w+ name #{reserved}\. Please give a name which does not match one of the reserved rails words: application, destroy, plugin, runner, test\n/, content)
    end
  end

  def test_name_raises_an_error_if_name_already_used_constant
    %w{ String Hash Class Module Set Symbol }.each do |ruby_class|
      content = capture(:stderr) { run_generator [File.join(destination_root, ruby_class)] }
      assert_match(/Invalid \w+ name #{ruby_class}, constant #{ruby_class} is already in use\. Please choose another \w+ name\.\n/, content)
    end
  end

  def test_shebang_is_added_to_rails_file
    run_generator [destination_root, "--ruby", "foo/bar/baz", "--full"]
    assert_file "bin/rails", /#!foo\/bar\/baz/
  end

  def test_shebang_when_is_the_same_as_default_use_env
    run_generator [destination_root, "--ruby", Thor::Util.ruby_command, "--full"]
    assert_file "bin/rails", /#!\/usr\/bin\/env/
  end

  def test_template_raises_an_error_with_invalid_path
    quietly do
      content = capture(:stderr) { run_generator([destination_root, "-m", "non/existent/path"]) }

      assert_match(/The template \[.*\] could not be loaded/, content)
      assert_match(/non\/existent\/path/, content)
    end
  end

  def test_template_is_executed_when_supplied_an_https_path
    url = "https://gist.github.com/josevalim/103208/raw/"
    generator([destination_root], template: url)

    applied = nil
    apply_stub = -> (path, *) { applied = path }

    generator.stub(:apply, apply_stub) do
      run_generator_instance
    end

    assert_equal url, applied
  end

  def test_skip_git
    run_generator [destination_root, "--skip-git", "--full"]
    assert_no_file(".gitignore")
    assert_no_directory(".git")
  end

  def test_skip_keeps
    run_generator [destination_root, "--skip-keeps", "--full"]

    assert_file ".gitignore" do |content|
      assert_no_match(/\.keep/, content)
    end
    assert_directory("app/assets/images")
    assert_no_file("app/models/concerns/.keep")
  end

  def test_default_frameworks_are_required_when_others_are_removed
    run_generator [
      destination_root,
      "--skip-active-record",
      "--skip-active-storage",
      "--skip-action-mailer",
      "--skip-action-mailbox",
      "--skip-action-text",
      "--skip-action-cable"
    ]

    assert_file "#{application_path}/config/application.rb", /^require\s+["']rails["']/
    assert_file "#{application_path}/config/application.rb", /^require\s+["']active_model\/railtie["']/
    assert_file "#{application_path}/config/application.rb", /^require\s+["']active_job\/railtie["']/
    assert_file "#{application_path}/config/application.rb", /^# require\s+["']active_record\/railtie["']/
    assert_file "#{application_path}/config/application.rb", /^# require\s+["']active_storage\/engine["']/
    assert_file "#{application_path}/config/application.rb", /^require\s+["']action_controller\/railtie["']/
    assert_file "#{application_path}/config/application.rb", /^# require\s+["']action_mailer\/railtie["']/
    unless generator_class.name == "Rails::Generators::PluginGenerator"
      assert_file "#{application_path}/config/application.rb", /^# require\s+["']action_mailbox\/engine["']/
      assert_file "#{application_path}/config/application.rb", /^# require\s+["']action_text\/engine["']/
    end
    assert_file "#{application_path}/config/application.rb", /^require\s+["']action_view\/railtie["']/
    assert_file "#{application_path}/config/application.rb", /^# require\s+["']action_cable\/engine["']/
    assert_file "#{application_path}/config/application.rb", /^require\s+["']rails\/test_unit\/railtie["']/
  end

  def test_generator_without_skips
    run_generator
    assert_file "#{application_path}/config/application.rb", /\s+require\s+["']rails\/all["']/
    assert_file "#{application_path}/config/environments/development.rb" do |content|
      assert_match(/config\.action_mailer\.raise_delivery_errors = false/, content)
    end
    assert_file "#{application_path}/config/environments/test.rb" do |content|
      assert_match(/config\.action_mailer\.delivery_method = :test/, content)
    end
    assert_file "#{application_path}/config/environments/production.rb" do |content|
      assert_match(/# config\.action_mailer\.raise_delivery_errors = false/, content)
      assert_match(/^  # config\.require_master_key = true/, content)
    end
  end

  def test_gitignore_when_sqlite3
    run_generator

    assert_file ".gitignore" do |content|
      assert_match(/sqlite3/, content)
    end
  end

  def test_gitignore_when_non_sqlite3_db
    run_generator([destination_root, "-d", "mysql"])

    assert_file ".gitignore" do |content|
      assert_no_match(/sqlite/i, content)
    end
  end

  def test_generator_if_skip_active_record_is_given
    run_generator [destination_root, "--skip-active-record"]
    assert_no_directory "#{application_path}/db/"
    assert_no_file "#{application_path}/config/database.yml"
    assert_no_file "#{application_path}/app/models/application_record.rb"
    assert_file "#{application_path}/config/application.rb", /#\s+require\s+["']active_record\/railtie["']/
    assert_file "test/test_helper.rb" do |helper_content|
      assert_no_match(/fixtures :all/, helper_content)
    end
    assert_file "#{application_path}/bin/setup" do |setup_content|
      assert_no_match(/db:prepare/, setup_content)
    end
    assert_file ".gitignore" do |content|
      assert_no_match(/sqlite/i, content)
    end
  end

  def test_generator_for_active_storage
    run_generator([destination_root])

    assert_file "#{application_path}/config/environments/development.rb" do |content|
      assert_match(/config\.active_storage/, content)
    end

    assert_file "#{application_path}/config/environments/production.rb" do |content|
      assert_match(/config\.active_storage/, content)
    end

    assert_file "#{application_path}/config/environments/test.rb" do |content|
      assert_match(/config\.active_storage/, content)
    end

    assert_file "#{application_path}/config/storage.yml"
    assert_directory "#{application_path}/storage"
    assert_directory "#{application_path}/tmp/storage"

    assert_file ".gitignore" do |content|
      assert_match(/\/storage\//, content)
    end
  end

  def test_generator_if_skip_active_storage_is_given
    run_generator [destination_root, "--skip-active-storage"]

    assert_file "#{application_path}/config/application.rb", /#\s+require\s+["']active_storage\/engine["']/

    assert_file "#{application_path}/config/environments/development.rb" do |content|
      assert_no_match(/config\.active_storage/, content)
    end

    assert_file "#{application_path}/config/environments/production.rb" do |content|
      assert_no_match(/config\.active_storage/, content)
    end

    assert_file "#{application_path}/config/environments/test.rb" do |content|
      assert_no_match(/config\.active_storage/, content)
    end

    assert_no_file "#{application_path}/config/storage.yml"
    assert_no_directory "#{application_path}/storage"
    assert_no_directory "#{application_path}/tmp/storage"

    assert_file ".gitignore" do |content|
      assert_no_match(/\/storage\//, content)
    end
  end

  def test_generator_does_not_generate_active_storage_contents_if_skip_active_record_is_given
    run_generator [destination_root, "--skip-active-record"]

    assert_file "#{application_path}/config/application.rb", /#\s+require\s+["']active_storage\/engine["']/

    assert_file "#{application_path}/config/environments/development.rb" do |content|
      assert_no_match(/config\.active_storage/, content)
    end

    assert_file "#{application_path}/config/environments/production.rb" do |content|
      assert_no_match(/config\.active_storage/, content)
    end

    assert_file "#{application_path}/config/environments/test.rb" do |content|
      assert_no_match(/config\.active_storage/, content)
    end

    assert_no_file "#{application_path}/config/storage.yml"
    assert_no_directory "#{application_path}/storage"
    assert_no_directory "#{application_path}/tmp/storage"

    assert_file ".gitignore" do |content|
      assert_no_match(/\/storage\//, content)
    end
  end

  def test_generator_if_skip_action_mailer_is_given
    run_generator [destination_root, "--skip-action-mailer"]
    assert_file "#{application_path}/config/application.rb", /#\s+require\s+["']action_mailer\/railtie["']/
    assert_file "#{application_path}/config/environments/development.rb" do |content|
      assert_no_match(/config\.action_mailer/, content)
    end
    assert_file "#{application_path}/config/environments/test.rb" do |content|
      assert_no_match(/config\.action_mailer/, content)
    end
    assert_file "#{application_path}/config/environments/production.rb" do |content|
      assert_no_match(/config\.action_mailer/, content)
    end
    assert_no_directory "#{application_path}/app/mailers"
    assert_no_directory "#{application_path}/test/mailers"
  end

  def test_generator_if_skip_action_cable_is_given
    run_generator [destination_root, "--skip-action-cable", "--webpack"]
    assert_file "#{application_path}/config/application.rb", /#\s+require\s+["']action_cable\/engine["']/
    assert_no_file "#{application_path}/config/cable.yml"
    assert_no_file "#{application_path}/app/javascript/consumer.js"
    assert_no_directory "#{application_path}/app/javascript/channels"
    assert_no_directory "#{application_path}/app/channels"
    assert_file "Gemfile" do |content|
      assert_no_match(/"redis"/, content)
    end
  end

  def test_generator_when_sprockets_is_not_used
    run_generator [destination_root, "-a", "none"]

    assert_no_file "#{application_path}/config/initializers/assets.rb"
    assert_no_file "#{application_path}/app/assets/config/manifest.js"

    assert_file "Gemfile" do |content|
      assert_no_match(/sass-rails/, content)
    end

    assert_file "#{application_path}/config/environments/development.rb" do |content|
      assert_no_match(/config\.assets\.debug/, content)
    end

    assert_file "#{application_path}/config/environments/production.rb" do |content|
      assert_no_match(/config\.assets\.digest/, content)
      assert_no_match(/config\.assets\.css_compressor/, content)
      assert_no_match(/config\.assets\.compile/, content)
    end
  end

  def test_dev_option
    run_generator_using_prerelease [destination_root, "--dev"]
    rails_path = File.expand_path("../../..", Rails.root)
    assert_file "Gemfile", %r{^gem ["']rails["'], path: ["']#{Regexp.escape rails_path}["']$}
  end

  def test_edge_option
    Rails.stub(:gem_version, Gem::Version.new("2.1.0")) do
      run_generator_using_prerelease [destination_root, "--edge"]
    end
    assert_file "Gemfile", %r{^gem ["']rails["'], github: ["']rails/rails["'], branch: ["']2-1-stable["']$}
  end

  def test_edge_option_during_alpha
    Rails.stub(:gem_version, Gem::Version.new("2.1.0.alpha")) do
      run_generator_using_prerelease [destination_root, "--edge"]
    end
    assert_file "Gemfile", %r{^gem ["']rails["'], github: ["']rails/rails["'], branch: ["']main["']$}
  end

  def test_main_option
    run_generator_using_prerelease [destination_root, "--main"]
    assert_file "Gemfile", %r{^gem ["']rails["'], github: ["']rails/rails["'], branch: ["']main["']$}
  end

  def test_master_option
    run_generator_using_prerelease [destination_root, "--master"]
    assert_file "Gemfile", %r{^gem ["']rails["'], github: ["']rails/rails["'], branch: ["']main["']$}
  end

  def test_target_rails_prerelease_with_relative_app_path
    run_generator_using_prerelease ["myproject", "--main"]
    assert_file "myproject/Gemfile", %r{^gem ["']rails["'], github: ["']rails/rails["'], branch: ["']main["']$}
  end

  private
    def run_generator_instance
      @bundle_commands = []
      @bundle_command_stub ||= -> (command, *) { @bundle_commands << command }

      generator.stub(:bundle_command, @bundle_command_stub) do
        super
      end
    end

    def run_generator_using_prerelease(args)
      option_args, positional_args = args.partition { |arg| arg.start_with?("--") }
      project_path = File.expand_path(positional_args.first, destination_root)
      expected_args = [project_path, *positional_args.drop(1), *option_args]

      generator(positional_args, option_args)

      rails_gem_pattern = /^gem ["']rails["'], .+/
      bundle_command_rails_gems = []
      @bundle_command_stub = -> (command, *) do
        @bundle_commands << command
        assert_file File.expand_path("Gemfile", project_path) do |gemfile|
          bundle_command_rails_gems << gemfile[rails_gem_pattern]
        end
      end

      # run target_rails_prerelease on exit to mimic re-running generator
      generator.stub :exit, generator.method(:target_rails_prerelease) do
        run_generator_instance
      end

      assert_file File.expand_path("Gemfile", project_path) do |gemfile|
        assert_equal "install", @bundle_commands[0]
        assert_equal gemfile[rails_gem_pattern], bundle_command_rails_gems[0]

        assert_match %r"^exec rails (?:plugin )?new #{Regexp.escape Shellwords.join(expected_args)}", @bundle_commands[1]
        assert_equal gemfile[rails_gem_pattern], bundle_command_rails_gems[1]
      end
    end
end
