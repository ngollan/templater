module Templater
  
  module CLI
    
    class Generator

      def initialize(generator_name, destination_root, manifold, name, version)
        @destination_root, @manifold, @name, @version = destination_root, manifold, name, version
        @generator_name = generator_name
        @generator_class = @manifold.generator(@generator_name)
      end

      def version
        puts @version
        exit
      end

      # outputs a helpful message and quits
      def help
        puts "Usage: #{@name} #{@generator_name} [options] [args]"
        puts ''
        puts @generator_class.desc
        puts ''
        puts @options[:opts]
        puts ''
        exit
      end

      def run(arguments)
        generator_class = @generator_class # FIXME: closure wizardry, there has got to be a better way than this?
        @options = Templater::Parser.parse(arguments) do |opts, options|
          opts.separator "Options specific for this generator:"
          # the reason this is reversed is so that the 'main' generator will always have the last word
          # on the description of the option
          all_generators.reverse.each do |generator|
            # Loop through this generator's options and add them as valid command line options
            # so that they show up in help messages and such
            generator.options.each do |option|
              name = option[:name].to_s.gsub('_', '-')
              if option[:options][:as] == :boolean
                opts.on("--#{name}", option[:options][:desc]) do |s|
                  options[option[:name]] = s
                end                
              else
                opts.on("--#{name} OPTION", option[:options][:desc]) do |s|
                  options[option[:name]] = s.to_sym
                end
              end
            end
          end
        end

        self.help if @options[:help]
        self.help if arguments.first == 'help'
        self.version if @options[:version]

        # Try to instantiate a generator, if the arguments to it were incorrect: show a help message
        begin
          @generator = @generator_class.new(@destination_root, @options, *arguments)
        rescue Templater::ArgumentError
          self.help
        end

        if @options[:pretend] 
          puts "Generating with #{@generator_name} generator (just pretending):"
        else
          puts "Generating with #{@generator_name} generator:" 
        end
        step_through_templates
      end

      def step_through_templates
        all_templates.each do |template|
          if template.identical?
            say_status('identical', template, :blue)
          elsif template.exists?
            if @options[:force]
              say_status('forced', template, :yellow)
              template.invoke! unless @options[:pretend]
            elsif @options[:skip]
              say_status('skipped', template, :yellow)
            else
              say_status('conflict', template, :red)
              conflict_menu(template)
            end
          else
            say_status('added', template, :green)
            template.invoke! unless @options[:pretend]
          end
        end
      end

      protected

      def all_generators
        subgenerators(@generator_class)
      end

      def subgenerators(generator)
        generators = []
        generators.push(generator)
        generator.invocations.each do |invocation|
          generators.push(*subgenerators(invocation[:name]))
        end
        return generators
      end

      def all_templates
        subtemplates(@generator)
      end
      
      def subtemplates(generator)
        templates = []
        templates.push(*generator.templates)
        generator.invocations.each do |invocation|
          templates.push(*subtemplates(invocation))
        end
        return templates
      end

      def conflict_menu(template)
        choose do |menu|
          menu.prompt = "How do you wish to proceed with this file?"

          menu.choice(:skip) do
            say("Skipped file")
          end
          menu.choice(:overwrite) do
            say("Overwritten")
            template.invoke! unless @options[:pretend]
          end
          menu.choice(:render) do
            puts "Rendering " + template.relative_destination
            puts ""
            # outputs each line of the file with the row number prepended
            template.render.to_a.each_with_index do |line, i|
              puts((i+1).to_s.rjust(4) + ':  ' + line)
            end
            puts ""
            puts ""
            conflict_menu(template)
          end
          menu.choice(:diff) do
            puts "Showing differences for " + template.relative_destination
            puts ""

            diffs = Diff::LCS.diff(File.read(template.destination).to_s.to_a, template.render.to_a).first

            diffs.each do |diff|
              output_diff_line(diff)
            end

            puts ""
            puts ""
            conflict_menu(template)
          end
          menu.choice(:abort) do
            say("Aborted!")
            exit
          end
        end
      end

      def say_status(status, template, color = nil)
        status_flag = "[#{status.to_s.upcase}]".rjust(12)
        if color and not @options[:no_color]
          say "<%= color('#{status_flag}', :#{color}) %>  " + template.relative_destination
        else
          say "#{status_flag}  " + template.relative_destination
        end
      end

      def output_diff_line(diff)
        case diff.action
        when '-'
          say "<%= color('-  #{diff.element.chomp}', :red) %>"
        when '+'
          say "<%= color('+  #{diff.element.chomp}', :green) %>"
        else
          say "#{diff.action}  #{diff.element.chomp}"
        end
      end

    end
    
  end
  
end