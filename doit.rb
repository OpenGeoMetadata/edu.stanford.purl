require 'json'
# ./bb/338/jh/0716/geoblacklight.json
data = {}
$stdin.readlines.each do |line|
  druid = File.dirname(line).split(/\//).join
  data["druid:#{druid}"] = File.dirname(line)
end
puts JSON.pretty_generate(data)
