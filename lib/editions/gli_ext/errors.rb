module GLI
  module CustomErrorSupport
    def error_message ex
      if (ex.is_a? CommandException)
        qualified_message = '%s in %s command' % [ex.message, ex.command_in_context.name]
        '%s: %s' % [exe_name, (colorize qualified_message, :red)]
      else
        '%s: %s' % [exe_name, (colorize super.sub(/^error: (?:parse error: )?/, ''), :red)]
      end
    end
  end

  module App
    include CustomErrorSupport
  end

  class GLIOptionParser
    # monkeypatch GLI::GLIOptionParser::GlobalOptionParser to provide more sane error reporting
    class GlobalOptionParser
      def verify_required_options! flags, options
        missing = flags.values.
            select(&:required?).
            reject {|opt| !!options[opt.name] }
        unless missing.empty?
          summary = missing.map {|opt| %(    #{opt.all_forms} is required) } * "\n"
          # FIXME we don't have the context to report the command for which the argument is missing
          raise BadCommandLine, %(missing required option#{missing.size > 1 ? 's' : nil}\n#{summary})
        end
      end 
    end
  end
end
