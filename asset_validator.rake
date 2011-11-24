require 'asset_validator'

namespace :validate do
  desc "validate image assets"
  task :assets, :format, :needs => :environment do |task, args|
    format = (args[:format] || 'simple').to_sym
    AssetValidator.new.run(format)
  end
end

