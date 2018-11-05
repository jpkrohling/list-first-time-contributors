#!/usr/bin/env ruby

require 'rest-client'
require 'json'

## configuration options
username = ENV['FTC_GITHUB_USERNAME'] || 'jpkrohling'
token = ENV['FTC_GITHUB_TOKEN']
organization = ENV['FTC_ORGANIZATION'] || 'jaegertracing'
month = ENV['FTC_MONTH'] || Time.now.month
year = ENV['FTC_YEAR'] || Time.now.year

baseUrl = "https://api.github.com"
month_range = (Time.gm(year, month, 1)..Time.gm(year, month.to_i+1, 1))
month_contributors = {}

num_requests = 0

if token.nil? then
    STDERR.puts "GitHub credentials missing. Export FTC_GITHUB_USERNAME and FTC_GITHUB_TOKEN."
    exit 1
end

## get all the repositories under the organization
RestClient::Request.execute method: :get, url: "#{baseUrl}/orgs/#{organization}/repos?per_page=100", user: username, password: token do | resp1 | 
    sleep(2) # make it easy on github, they allow only up to 30 requests per minute, or one every two seconds
    num_requests += 1
    repos = JSON.parse(resp1.body)
    repos.each do | repo | 
        ## get the first 100 most-recently closed PRs from this repository
        RestClient::Request.execute method: :get, url: "#{baseUrl}/repos/#{organization}/#{repo['name']}/pulls?state=closed&sort=created&direction=desc&per_page=100", user: username, password: token do | resp2 | 
            sleep(2)
            num_requests += 1
            prs = JSON.parse(resp2.body)
            oldest_merge = Time.now
            prs.each do | pr | 
                ## we are interested only in PRs that eventually got merged
                unless pr['merged_at'].nil? then
                    merged_at = Time.parse(pr['merged_at'])
                    oldest_merge = merged_at if merged_at < oldest_merge
                    ## if this merge happened this month, we have a contributor for the month
                    if month_range.cover?(merged_at) then
                        month_contributors[pr['user']['login']] = merged_at
                    end
                end
            end

            ## if our oldest_merge is within the range, we have two possible causes:
            ### 1) we have more than 100 merged PRs (so, we want to fix the code above to get next pages)
            ### 2) it's a new repository, so, it's OK
            ### iterate over pages (case 1) would make this script a bit more complicated and we are not near 100 merges per month
            ### even for the main repository, so, no need to complicate things in advance
            if month_range.cover?(oldest_merge) then
                puts "ATTENTION: the oldest merge for repo #{repo['name']} is within this month! Date: #{oldest_merge}"
            end
        end
    end
end

## at this point, we have a list of everyone who contributed this month
## we just need then to filter the ones who first contributed this month
puts "Users who first contributed this month (merged_at;user;URL)"
month_contributors.sort.uniq.each do | k, v | 
    q = "is:pr author:#{k} org:#{organization} is:merged"
    ## get the oldest merged PR from this user across all repositories in the organization
    RestClient::Request.execute method: :get, url: "#{baseUrl}/search/issues?sort=created&order=asc&per_page=1&q=#{URI.escape(q)}", user: username, password: token do | resp | 
        sleep(2)
        num_requests += 1
        prs = JSON.parse(resp.body)['items']
        if prs.nil? then
            puts "Expected to get some PRs for user #{k} but got none."
            STDERR.puts resp.body
            next
        end
        pr = prs.first
        closed_at = Time.parse(pr['closed_at'])
        ## if the oldest PR was merged this month, then we have a first time contributor
        if month_range.cover?(closed_at) then
            puts "#{closed_at};#{k};https://github.com/#{k};#{pr['html_url']}"
        end
    end
end

puts
puts "Number of requests in total: #{num_requests}"