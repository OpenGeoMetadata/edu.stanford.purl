task default: [:pull, :write_layers_json]

require 'json'
require 'zip'
require 'http'
require 'uri'
require 'byebug'
require 'tempfile'

task :pull do
  timestamp = Time.now.utc.iso8601
  previous_timestamp = File.read('./last_run')
  next if previous_timestamp.empty?

  url = 'https://earthworks.stanford.edu/catalog'
  params = {
    'f[dct_provenance_s][]': 'Stanford',
    format: 'json',
    q: "-layer_geom_type_s:Image AND layer_modified_dt:[#{previous_timestamp} TO *]",
    per_page: 100
  }
  http_response = HTTP.get(url, params: params)
  response = JSON.parse(http_response.body.to_s)

  urls = []

  while response['data'].any?
    urls.concat response['data'].map { |x| x['links']['self'] }
    break if response['links']['next'].nil?
    http_response = HTTP.get(response['links']['next'])
    response = JSON.parse(http_response.body.to_s)
  end

  urls.each do |url|
    raw_doc = HTTP.get(url + '/raw', params: { format: :json })
    doc = JSON.parse(raw_doc.body.to_s)
    doc.delete('timestamp')
    doc.delete('layer_availability_score_f')
    doc.delete('_version_')
    doc.delete('hashed_id_ssi')

    tree = doc['layer_slug_s'].match(/stanford-(..)(...)(..)(....)/).captures.join('/')
    next if tree.empty?

    FileUtils.mkdir_p(tree)

    File.open("./#{tree}/geoblacklight.json", 'w') { |f| f.puts JSON.pretty_generate(doc) }

    references = JSON.parse(doc['dct_references_s'])
    mods_url = references['http://www.loc.gov/mods/v3']

    response = HTTP.follow.get(mods_url)
    mods = response.body.to_s
    File.open("./#{tree}/mods.xml", 'w') { |f| f.puts mods }

    data_zip_url = references['http://schema.org/downloadUrl']
    # TODO: figure out what to do with private data
    Tempfile.open('data_zip') do |f|
      response = HTTP.get(data_zip_url)
      f.write(response.body)
      f.rewind
      Zip::File.open(f.path) do |zip_file|
        iso19110 = zip_file.glob('*-iso19110.xml').first
        File.open("./#{tree}/iso19110.xml", 'w') { |f| f.puts iso19110.get_input_stream.read }
        iso19139 = zip_file.glob('*-iso19139.xml').first
        File.open("./#{tree}/iso19139.xml", 'w') { |f| f.puts iso19139.get_input_stream.read }
      end
    end
  end
  File.open('./last_run', 'w') { |f| f.puts timestamp }
end

task :write_layers_json do
  Dir.glob('**/geoblacklight.json').each do |file|
    druid = File.dirname(file).split(/\//).join
    data["druid:#{druid}"] = File.dirname(line)
  end
  File.open('./layers.json', 'w') { |f| f.puts JSON.pretty_generate(data) }
end
