require 'json'
require 'date'
require 'minitest/autorun'
require 'byebug'
require 'ruby-prof'
require 'benchmark'

class User
  attr_reader :attributes, :sessions

  def initialize(attributes:, sessions:)
    @attributes = attributes
    @sessions = sessions
  end
end

def parse_user(user)
  {
    id: user[1],
    full_name: "#{user[2]} #{user[3]}"
  }
end

def parse_session(session)
  {
    session_id: session[2],
    browser: session[3].upcase!,
    time: session[4].to_i,
    date: session[5]
  }
end

def collect_stats_from_users(report, users_objects)
  while users_objects.size.positive?
    user = users_objects.shift
    report[:usersStats][user.attributes[:full_name]] ||= {}
    report[:usersStats][user.attributes[:full_name]].merge!(yield(user))
  end
end

def work(file_path)
  users = []
  sessions = Hash.new { |hash, key| hash[key] = [] }
  sessions_count = 0

  File.foreach(file_path) do |line|
    line = line.split(',')
    users << parse_user(line) if line[0] == 'user'
    if line[0] == 'session'
      sessions[line[1]] << parse_session(line)
      sessions_count += 1
    end
  end

  report = {}
  report[:totalUsers] = users.count
  unique_browsers = sessions.values.flatten.map! { |session| session[:browser] }.uniq! || []
  report[:uniqueBrowsersCount] = unique_browsers.count
  report[:totalSessions] = sessions_count
  report[:allBrowsers] = unique_browsers.sort!.join(',')

  users.map! do |user|
    user_id = user[:id]
    user_sessions = sessions[user_id]
    User.new(attributes: user, sessions: user_sessions)
  end
  report[:usersStats] = {}

  collect_stats_from_users(report, users) do |user|
    users_times = user.sessions.map { |s| s[:time] }
    users_browsers = user.sessions.map { |s| s[:browser] }
    ie_count = 0
    chrome_count = 0
    users_browsers.each do |b|
      ie_count += 1 if /INTERNET EXPLORER/.match?(b)
      chrome_count += 1 if /CHROME/.match?(b)
    end

    {
      'sessionsCount' => user.sessions.count,
      'totalTime' => "#{users_times.sum} min.",
      'longestSession' => "#{users_times.max} min.",
      'browsers' => users_browsers.sort!.join(', '),
      'usedIE' => ie_count.positive?,
      'alwaysUsedChrome' => chrome_count == users_browsers.size,
      'dates' => user.sessions.map { |s| Date.parse(s[:date]).iso8601 }.sort!.reverse!
    }
  end

  File.write('result.json', "#{report.to_json}\n")
end

class TestMe < Minitest::Test
  def setup
    File.write('result.json', '')
    File.write('data.txt',
'user,0,Leida,Cira,0
session,0,0,Safari 29,87,2016-10-23
session,0,1,Firefox 12,118,2017-02-27
session,0,2,Internet Explorer 28,31,2017-03-28
session,0,3,Internet Explorer 28,109,2016-09-15
session,0,4,Safari 39,104,2017-09-27
session,0,5,Internet Explorer 35,6,2016-09-01
user,1,Palmer,Katrina,65
session,1,0,Safari 17,12,2016-10-21
session,1,1,Firefox 32,3,2016-12-20
session,1,2,Chrome 6,59,2016-11-11
session,1,3,Internet Explorer 10,28,2017-04-29
session,1,4,Chrome 13,116,2016-12-28
user,2,Gregory,Santos,86
session,2,0,Chrome 35,6,2018-09-21
session,2,1,Safari 49,85,2017-05-22
session,2,2,Firefox 47,17,2018-02-02
session,2,3,Chrome 20,84,2016-11-25
')
  end

  def test_result
    work('data.txt')
    expected_result = '{"totalUsers":3,"uniqueBrowsersCount":14,"totalSessions":15,"allBrowsers":"CHROME 13,CHROME 20,CHROME 35,CHROME 6,FIREFOX 12,FIREFOX 32,FIREFOX 47,INTERNET EXPLORER 10,INTERNET EXPLORER 28,INTERNET EXPLORER 35,SAFARI 17,SAFARI 29,SAFARI 39,SAFARI 49","usersStats":{"Leida Cira":{"sessionsCount":6,"totalTime":"455 min.","longestSession":"118 min.","browsers":"FIREFOX 12, INTERNET EXPLORER 28, INTERNET EXPLORER 28, INTERNET EXPLORER 35, SAFARI 29, SAFARI 39","usedIE":true,"alwaysUsedChrome":false,"dates":["2017-09-27","2017-03-28","2017-02-27","2016-10-23","2016-09-15","2016-09-01"]},"Palmer Katrina":{"sessionsCount":5,"totalTime":"218 min.","longestSession":"116 min.","browsers":"CHROME 13, CHROME 6, FIREFOX 32, INTERNET EXPLORER 10, SAFARI 17","usedIE":true,"alwaysUsedChrome":false,"dates":["2017-04-29","2016-12-28","2016-12-20","2016-11-11","2016-10-21"]},"Gregory Santos":{"sessionsCount":4,"totalTime":"192 min.","longestSession":"85 min.","browsers":"CHROME 20, CHROME 35, FIREFOX 47, SAFARI 49","usedIE":false,"alwaysUsedChrome":false,"dates":["2018-09-21","2018-02-02","2017-05-22","2016-11-25"]}}}' + "\n"
    assert_equal expected_result, File.read('result.json')
  end

  def test_regress
    time = Benchmark.realtime { work('data.txt') }
    assert time < 0.001, 'Test regress'
  end
end

def print_memory_usage
  '%d MB' % (`ps -o rss= -p #{Process.pid}`.to_i / 1024)
end

# RubyProf.measure_mode = RubyProf::MEMORY

puts 'Start'
result_profil = nil

time = Benchmark.realtime do
  puts "rss before: #{print_memory_usage}"
  # result_profil = RubyProf.profile do
    work('data_large.txt')
  # end
  puts "rss after: #{print_memory_usage}"
end

puts "Finish in #{time.round(2)}"

# printer = RubyProf::GraphHtmlPrinter.new(result_profil)
# printer.print(File.open('ruby_prof_graph_allocations_profile.html', 'w+'))
