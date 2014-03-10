module GLI
  module CustomErrorSupport
    def error_message ex
      if ex.is_a? UnknownCommandArgument
        '%s: %s for %s command' % [exe_name, ex.message, ex.command_in_context.name]
      #elsif ex.is_a? UnknownGlobalArgument
      #  '%s: %s' % [exe_name, ex.message]
      else
        super
      end
    end
  end

  class GLIOptionParser
    # monkeypatch GLI::GLIOptionParser::GlobalOptionParser to provide more sane error reporting
    class GlobalOptionParser
      def verify_required_options! flags, options
        missing = flags.values.
            select(&:required?).
            reject {|opt| !!options[opt.name] }
        unless missing.empty?
          summary = missing.map {|opt| %(  #{opt.all_forms} is required) } * "\n"
          raise BadCommandLine, %(missing required option#{missing.size > 1 ? 's' : nil}:\n#{summary})
        end
      end 
    end
  end
end

GLI::App.include GLI::CustomErrorSupport
