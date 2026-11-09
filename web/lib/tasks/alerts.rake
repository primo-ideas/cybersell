namespace :alerts do
  desc "Email players whose followed products reached their target price"
  task deliver: :environment do
    count = TargetAlerts.deliver_all
    puts "#{count} #{"product".pluralize(count)} announced" if count.positive?
  end
end
