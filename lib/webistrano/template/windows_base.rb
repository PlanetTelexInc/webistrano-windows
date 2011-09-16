module Webistrano
  module Template
    module WindowsBase
      
      CONFIG = Webistrano::Template::Base::CONFIG.dup.merge({
      }).freeze
      
      DESC = <<-'EOS'
        Windows Base template that the other templates use to inherit from.
        Defines basic Capistrano configuration parameters.
        Overrides Capistrano tasks to use mklink instead of ln -s.
      EOS
      
      TASKS =  <<-'EOS'
      
        # allocate a pty by default as some systems have problems without
        default_run_options[:pty] = true
      
        # set Net::SSH ssh options through normal variables
        # at the moment only one SSH key is supported as arrays are not
        # parsed correctly by Webistrano::Deployer.type_cast (they end up as strings)
        [:ssh_port, :ssh_keys].each do |ssh_opt|
          if exists? ssh_opt
            logger.important("SSH options: setting #{ssh_opt} to: #{fetch(ssh_opt)}")
            ssh_options[ssh_opt.to_s.gsub(/ssh_/, '').to_sym] = fetch(ssh_opt)
          end
        end
        
        namespace :deploy do
          desc <<-DESC
            Deploys your project. This calls both 'stop', 'update' and 'start'. Note that \
            this will generally only work for applications that have already been deployed \
            once. For a "cold" deploy, you'll want to take a look at the 'deploy:cold' \
            task, which handles the cold start specifically.
          DESC
          task :default do
            stop
            update
            start
          end
          
          desc <<-DESC
            [internal] Touches up the released code. This is called by update_code \
            after the basic deploy finishes. It assumes a Rails project was deployed, \
            so if you are deploying something else, you may want to override this \
            task with your own environment's requirements.
        
            This task will make the release group-writable (if the :group_writable \
            variable is set to true, which is the default).
          DESC
          task :finalize_update, :except => { :no_release => true } do       
            set :my_link, latest_release.gsub("/", "\\\\\\")
            set :my_target, shared_path.gsub("/", "\\\\\\")
        
            # mkdir -p is making sure that the directories are there for some SCM's that don't
            # save empty folders
            run "rm -rf #{latest_release}/log && cmd /c mklink /D #{my_link}\\\\log #{my_target}\\\\log"
          end
          
          desc <<-DESC
            Updates the symlink to the most recently deployed version. Capistrano works \
            by putting each new release of your application in its own directory. When \
            you deploy a new version, this task's job is to update the 'current' symlink \
            to point at the new version. You will rarely need to call this task \
            directly; instead, use the 'deploy' task (which performs a complete \
            deploy, including 'restart') or the 'update' task (which does everything \
            except 'restart').
          DESC
          task :symlink, :except => { :no_release => true } do
                    
            set :my_link, current_path.gsub("/", "\\\\\\")
  
            on_rollback do
              set :my_target, previous_release.gsub("/", "\\\\\\")
            
              if previous_release
                run "rm -f #{current_path}; cmd /c mklink /D #{my_link} #{my_target}; true"
              else
                logger.important "no previous release to rollback to, rollback of symlink skipped"
              end
            end
        
            set :my_target, latest_release.gsub("/", "\\\\\\")
        
            run "rm -f #{current_path} && cmd /c mklink /D #{my_link} #{my_target}"
          end
            
          namespace :rollback do
            desc <<-DESC
              [internal] Points the current symlink at the previous revision.
              This is called by the rollback sequence, and should rarely (if
              ever) need to be called directly.
            DESC
            task :revision, :except => { :no_release => true } do
              set :my_link, current_path.gsub("/", "\\\\\\")
              set :my_target, previous_release.gsub("/", "\\\\\\")
              
              if previous_release
                run "rm #{current_path}; cmd /c mklink /D #{my_link} #{my_target}"
              else
                abort "could not rollback the code because there is no prior release"
              end
            end
          end
        end
        
      EOS
    end
  end
end