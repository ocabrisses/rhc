module RHC
  class CommandRunner < Commander::Runner
    # regex fix from git - match on word boundries
    def valid_command_names_from *args
      arg_string = args.delete_if { |value| value =~ /^-/ }.join ' '
      commands.keys.find_all { |name| name if /^#{name}\b/.match arg_string }
    end

    # override so we can do our own error handling
    def run!
      trace = false
      require_program :version, :description
      trap('INT') { abort program(:int_message) } if program(:int_message)
      trap('INT') { program(:int_block).call } if program(:int_block)
      global_option('-h', '--help', 'Display help documentation') do
        args = @args - %w[-h --help]
        command(:help).run(*args)
        return
      end
      global_option('-v', '--version', 'Display version information') { say version; return }
      global_option('-t', '--trace', 'Display backtrace when an error occurs') { trace = true }
      parse_global_options
      remove_global_options options, @args

      unless trace
        begin
          run_active_command
        rescue InvalidCommandError => e
          say RHC::HelpFormatter.new(self).render_missing
          1
        rescue \
          ArgumentError,
          OptionParser::InvalidOption,
          OptionParser::InvalidArgument,
          OptionParser::MissingArgument => e

          help_bindings = CommandHelpBindings.new(active_command, commands, Commander::Runner.instance.options)
          usage = RHC::HelpFormatter.new(self).render_command(help_bindings)
          say "#{e}\n#{usage}"
          1
        rescue \
          RHC::Rest::Exception,
          RHC::Exception => e

          RHC::Helpers.error e.message
          e.code.nil? ? 128 : e.code
        end
      else
        run_active_command
      end
    end

    def provided_arguments
      @args[0, @args.find_index { |arg| arg.start_with?('-') } || @args.length]
    end

    def create_default_commands
      command :help do |c|
        c.syntax = 'rhc help <command>'
        c.description = 'Display global or <command> help documentation.'
        c.when_called do |args, options|
          if args.empty?
            say help_formatter.render
          else
            command = command args.join(' ')
            begin
              require_valid_command command
            rescue InvalidCommandError => e
              abort "#{e}"
            end

            help_bindings = CommandHelpBindings.new command, commands, Commander::Runner.instance.options
            say help_formatter.render_command help_bindings
          end
        end
      end
    end
  end

  class CommandHelpBindings
    def initialize(command, instance_commands, global_options)
      @command = command
      @actions = instance_commands.collect do |ic|
        m = /^#{command.name} ([^ ]+)/.match(ic[0])
        # if we have a match and it is not an alias then we can use it
        m and ic[0] == ic[1].name ? {:name => m[1], :summary => ic[1].summary || ""} : nil
      end
      @actions.compact!
      @global_options = global_options
    end
  end
end
