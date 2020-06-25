task default: [:pull, :write_layers_json]

require 'json'
require 'zip'
require 'http'
require 'uri'
require 'byebug'
require 'tempfile'
require 'tmpdir'

task :pull do
  start_timestamp = Time.now.utc
  last_timestamp = nil
  previous_timestamp = File.read('./last_run')
  if !previous_timestamp || previous_timestamp.strip.empty?
    puts 'Unable to find ./last_run file'
    next
  end
  puts "Last run: #{previous_timestamp}"

  url = 'https://earthworks.stanford.edu/catalog'
  params = {
    'f[dct_provenance_s][]': 'Stanford',
    format: 'json',
    q: "-layer_geom_type_s:Image AND layer_modified_dt:[#{previous_timestamp.strip} TO *]",
    per_page: 100,
    sort: 'layer_modified_dt asc'
  }
  puts "[GET #0] #{url} #{params.inspect}"
  http_response = HTTP.get(url, params: params)
  response = JSON.parse(http_response.body.to_s)

  urls = []
  i = 1
  while response['data'].any?
    urls.concat response['data'].map { |x| x['links']['self'] }
    break if response['links']['next'].nil?
    puts "[GET ##{i}] #{response['links']['next']}"
    http_response = HTTP.get(response['links']['next'])
    response = JSON.parse(http_response.body.to_s)
    i += 1
  end

  puts "== Received #{urls.length} updated documents =="

  urls.each do |url|
    begin
      puts "[GET] #{url}"

      raw_doc = HTTP.get(url + '/raw', params: { format: :json })
      doc = JSON.parse(raw_doc.body.to_s)
      doc.delete('timestamp')
      doc.delete('layer_availability_score_f')
      doc.delete('_version_')
      doc.delete('hashed_id_ssi')

      tree_dirs = doc['layer_slug_s'].match(/stanford-(..)(...)(..)(....)/).captures.join('/')
      next if tree_dirs.empty?

      tree = File.expand_path(tree_dirs)

      FileUtils.mkdir_p(tree)

      Dir.mktmpdir do |dir|
        File.open("#{dir}/geoblacklight.json", 'w') { |f| f.puts JSON.pretty_generate(doc) }

        references = JSON.parse(doc['dct_references_s'])
        mods_url = references['http://www.loc.gov/mods/v3']

        puts "  [GET] #{mods_url}"
        response = HTTP.follow.get(mods_url)
        mods = response.body.to_s
        File.open("#{dir}/mods.xml", 'w') { |f| f.puts mods }

        data_zip_url = references['http://schema.org/downloadUrl']
        # TODO: figure out what to do with private data
        Tempfile.open('data_zip') do |f|
          puts "  [GET] #{data_zip_url}"
          response = if ENV['STACKS_TOKEN']
            HTTP.follow.auth("Bearer #{ENV['STACKS_TOKEN']}").get(data_zip_url)
          else
            HTTP.follow.get(data_zip_url)
          end

          if !response.status.ok?
            raise "Unable to fetch #{data_zip_url} (HTTP #{response.status})"
          end
          puts "  [GET] #{data_zip_url} [OK] (#{response.content_length} bytes)"

          f.write(response.body)
          f.rewind
          Zip::File.open(f.path) do |zip_file|
            iso19110 = zip_file.glob('*-iso19110.xml').first
            puts "  [ZIP] #{iso19110&.name.inspect}"
            File.open("#{dir}/iso19110.xml", 'w') { |f| f.puts iso19110.get_input_stream.read }
            iso19139 = zip_file.glob('*-iso19139.xml').first
            puts "  [ZIP] #{iso19139&.name.inspect}"
            File.open("#{dir}/iso19139.xml", 'w') { |f| f.puts iso19139.get_input_stream.read }
          end
        end
        FileUtils.cp_r Dir.glob("#{dir}/*"), tree
      end
      last_timestamp = doc['layer_modified_dt']
    rescue => e
      puts "[ERROR] #{e}"
    end
  end

  if last_timestamp
    # if the most recent document is in the past (beyond any reasonable clock-skew)
    # go ahead and bump the timestamp so we don't repeat documents
    if (Time.parse(last_timestamp) + 3600) < start_timestamp
      last_timestamp = (Time.parse(last_timestamp) + 1).utc.iso8601
    end

    puts "Updating last run: #{last_timestamp}"
    File.open('./last_run', 'w') { |f| f.puts last_timestamp }
  end
end

task :write_layers_json do
  data = {}
  Dir.glob('**/geoblacklight.json').sort.each do |file|
    druid = File.dirname(file).split(/\//).join
    data["druid:#{druid}"] = File.dirname(file)
  end
  File.open('./layers.json', 'w') { |f| f.puts JSON.pretty_generate(data) }
end
