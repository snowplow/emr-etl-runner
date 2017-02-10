# Copyright (c) 2012-2017 Snowplow Analytics Ltd. All rights reserved.
#
# This program is licensed to you under the Apache License Version 2.0,
# and you may not use this file except in compliance with the Apache License Version 2.0.
# You may obtain a copy of the Apache License Version 2.0 at http://www.apache.org/licenses/LICENSE-2.0.
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the Apache License Version 2.0 is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the Apache License Version 2.0 for the specific language governing permissions and limitations there under.

# Author::    Alex Dean (mailto:support@snowplowanalytics.com)
# Copyright:: Copyright (c) 2012-2014 Snowplow Analytics Ltd
# License::   Apache License Version 2.0

require 'optparse'
require 'yaml'
require 'json'
require 'contracts'
require 'erb'

# To have a command's description
class OptionParser
  attr_accessor :description
end

module Snowplow
  module EmrEtlRunner
    module Cli

      include Contracts

      # Get our arguments, configuration,
      # enrichments and Iglu resolver.
      #
      # Source from parse_args (i.e. the CLI)
      # unless both are provided as arguments
      # to this function
      #
      # Parameters:
      # +config_file+:: the YAML file containing our
      #                 configuration options
      #
      # Returns a Hash containing our runtime
      # arguments and our configuration.
      Contract None => ArgsConfigEnrichmentsResolverTuple
      def self.get_args_config_enrichments_resolver

        # Defaults
        options = {
          :skip => [],
          :include => [],
          :debug => false
        }

        commands = {
          'run' => OptionParser.new do |opts|
            opts.banner = "Usage: run [options]"
            opts.description = "Run the Snowplow pipeline on EMR"
            opts.on('-c', '--config CONFIG', 'configuration file') { |config| options[:config_file] = config }
            opts.on('-n', '--enrichments ENRICHMENTS', 'enrichments directory') {|config| options[:enrichments_directory] = config }
            opts.on('-r', '--resolver RESOLVER', 'Iglu resolver file') {|config| options[:resolver_file] = config }
            opts.on('-t', '--targets TARGETS', 'targets directory') { |config| options[:targets_directory] = config }
            opts.on('-d', '--debug', 'enable EMR Job Flow debugging') { |config| options[:debug] = true }
            opts.on('-s', '--start YYYY-MM-DD', 'optional start date *') { |config| options[:start] = config }
            opts.on('-e', '--end YYYY-MM-DD', 'optional end date *') { |config| options[:end] = config }
            opts.on('-x', '--skip staging,s3distcp,emr{enrich,shred,elasticsearch,archive_raw,analyze,archive_enriched}', Array, 'skip work step(s)') { |config| options[:skip] = config }
            opts.on('-E', '--process-enrich LOCATION', 'run enrichment only on specified location. Implies --skip staging,shred,archive_raw,archive_enriched,analyze,rdb_load') { |config|
              options[:process_enrich_location] = config
              options[:skip] = %w(staging shred archive_raw archive_enriched analyze)
            }
            opts.on('-S', '--process-shred LOCATION', 'run shredding only on specified location. Implies --skip staging,enrich,archive_raw,archive_enriched,analyze,rdb_load') { |config|
              options[:process_shred_location] = config
              options[:skip] = %w(staging enrich archive_raw archive_enriched analyze)
            }
          end
        }

        global = OptionParser.new do |opts|
          opts.banner = "Usage %s [options] [command [options]]" % NAME
          opts.separator ""
          opts.separator "Available commands are:"
          commands.each_pair do |c, opt|
            desc = opt.description
            opts.separator "#{c}: #{desc}"
          end
          opts.separator ""
          opts.separator "Global options are:"
          opts.on("-v", "--version", "Show version") do
            puts "%s %s" % [NAME, VERSION]
            exit
          end
        end

        # Run OptionParser's structural validation
        begin
          global.order!
          cmd_name = ARGV.shift
          if cmd_name
            cmd = commands[cmd_name]
            if cmd
              cmd.order!
            else
              puts "Invalid command: #{cmd_name}"
              puts global
              exit 1
            end
          else
            puts "Empty command!"
            puts global
            exit 1
          end
          process_options(options, cmd)
        rescue OptionParser::InvalidOption, OptionParser::MissingArgument
          raise ConfigError, "#{$!.to_s}\n#{cmd}"
        end
      end

      def self.process_options(options, optparse)
        args = {
          :debug                   => options[:debug],
          :start                   => options[:start],
          :end                     => options[:end],
          :skip                    => options[:skip],
          :include                 => options[:include],
          :process_enrich_location => options[:process_enrich_location],
          :process_shred_location  => options[:process_shred_location]
        }

        summary = optparse.to_s
        config = load_config(options[:config_file], summary)
        enrichments = load_enrichments(options[:enrichments_directory], summary)
        resolver = load_resolver(options[:resolver_file], summary)
        targets = load_targets(options[:targets_directory])

        [args, config, enrichments, resolver, targets]
      end

    private

      # Convert all keys in arbitrary hash into symbols
      # Taken from http://stackoverflow.com/a/10721936/255627
      def self.recursive_symbolize_keys(h)
        case h
        when Hash
          Hash[
            h.map do |k, v|
              [ k.respond_to?(:to_sym) ? k.to_sym : k, recursive_symbolize_keys(v) ]
            end
          ]
        when Enumerable
          h.map { |v| recursive_symbolize_keys(v) }
        else
          h
        end
      end

      # Validate our args, load our config YAML, check config and args don't conflict
      Contract Maybe[String], String => ConfigHash
      def self.load_config(config_file, summary)

        # Check we have a config file argument and it exists
        if config_file.nil?
          raise ConfigError, "Missing option: config\n#{summary}"
        end

        # A single hyphen indicates that the config should be read from stdin
        if config_file == '-'
          config = $stdin.readlines.join
        elsif File.file?(config_file)
          config = File.new(config_file).read
        else
          raise ConfigError, "Configuration file '#{config_file}' does not exist, or is not a file\n#{summary}"
        end

        erb_config = ERB.new(config).result(binding)

        recursive_symbolize_keys(YAML.load(erb_config))
      end

      # Load the enrichments directory into an array
      Contract Maybe[String], String => ArrayOf[String]
      def self.load_enrichments(enrichments_dir, summary)
        return [] if enrichments_dir.nil?

        # Check the enrichments directory exists and is a directory
        unless Dir.exist?(enrichments_dir)
          raise ConfigError, "Enrichments directory '#{enrichments_dir}' does not exist, or is not a directory\n#{summary}"
        end

        json_glob = Sluice::Storage::trail_slash(enrichments_dir) + '*.json'

        Dir.glob(json_glob).map { |f|
          File.read(f)
        }
      end

      # Validate our args, load our Iglu resolver
      Contract Maybe[String], String => String
      def self.load_resolver(resolver_file, summary)

        # Check we have a resolver file argument and it exists
        if resolver_file.nil?
          raise ConfigError, "Missing option: resolver\n#{summary}"
        end

        unless File.file?(resolver_file)
          raise ConfigError, "Iglu resolver file '#{resolver_file}' does not exist, or is not a file\n#{summary}"
        end

        File.read(resolver_file)
      end

      # Load configuration from JSONs
      Contract Maybe[String] => ArrayOf[JsonFileHash]
      def self.load_targets(targets_path)
        if targets_path.nil?
          []
        else
          Dir.entries(targets_path).select do |f|
            f.end_with?('.json')
          end.map do |f|
            {:file => f, :json => JSON.parse(File.read(targets_path + '/' + f), {:symbolize_names => true}) }
          end
        end
      end

    end
  end
end
