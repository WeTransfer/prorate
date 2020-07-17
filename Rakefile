require "bundler/gem_tasks"
require "rspec/core/rake_task"
require 'rubocop/rake_task'
require 'yard'

YARD::Rake::YardocTask.new(:doc) do |t|
  # The dash has to be between the two to "divide" the source files and
  # miscellaneous documentation files that contain no code
  t.files = ['lib/**/*.rb', '-', 'LICENSE.txt', 'CHANGELOG.md']
end

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.rspec_opts = ["-c", "--order=rand"]
  spec.pattern = FileList['spec/**/*_spec.rb']
end

RuboCop::RakeTask.new(:rubocop)
task default: [:spec, :rubocop]
