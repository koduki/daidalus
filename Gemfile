source 'https://rubygems.org'

gem 'sinatra', '~> 3.2'
gem 'sinatra-contrib', '~> 3.2'
gem 'puma', '~> 6.0'
gem 'json', '~> 2.6'
gem 'httparty', '~> 0.21'
gem 'dotenv', '~> 2.8'
gem 'rack-cors', '~> 2.0'

# Optional dependencies - only load if environment variables are set
gem 'google-cloud-firestore', '~> 2.7', require: false
gem 'octokit', '~> 6.0', require: false
gem 'line-bot-api', '~> 1.28', require: false

group :development, :test do
  gem 'rspec', '~> 3.12'
  gem 'rack-test', '~> 2.1'
  gem 'rubocop', '~> 1.50'
end
