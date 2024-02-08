# frozen_string_literal: true

task default: %i[pull write_layers_json]

require 'json'
require 'http'
require 'uri'
require 'debug'

CATALOG_URL = 'https://earthworks.stanford.edu/catalog'
INSTITUTION = 'Stanford'
BASE_DIR = 'metadata-1.0'
IGNORED_FIELDS = %w[timestamp layer_availability_score_f _version_ hashed_id_ssi].freeze

# Wrap a function with a timestamp file to avoid re-processing documents
# If the block returns a timestamp, update the timestamp file
# rubocop:disable Metrics/AbcSize
def with_timestamp(timestamp_file = './last_run')
  return unless block_given?

  start_timestamp = Time.now.utc

  # Check the timestamp file for the previous timestamp
  puts "Unable to find timestamp file #{timestamp_file}" unless File.exist? timestamp_file
  previous_timestamp = File.read(timestamp_file).strip
  puts previous_timestamp.empty? ? "No timestamp found in #{timestamp_file}" : "Last run: #{previous_timestamp}"

  # Call the provided block with the previous timestamp, receiving the most
  # recent document's timestamp as the result of the block
  last_timestamp = yield(previous_timestamp)
  return unless last_timestamp

  # If the most recent document is in the past (beyond any reasonable clock-skew)
  # go ahead and bump the timestamp so we don't repeat documents
  last_timestamp = (Time.parse(last_timestamp) + 1).utc.iso8601 if (Time.parse(last_timestamp) + 3600) < start_timestamp
  puts "Updating last run: #{last_timestamp}"
  File.open(timestamp_file, 'w') { |f| f.puts last_timestamp }
end
# rubocop:enable Metrics/AbcSize

# Solr parameters used to crawl the catalog for records
def catalog_search_params(timestamp)
  {
    'f[dct_provenance_s][]': INSTITUTION,
    format: 'json',
    q: "layer_modified_dt:[#{timestamp} TO *] AND -layer_geom_type_s:Image AND -dc_type_s:\"Interactive Resource\"",
    per_page: 100,
    sort: 'layer_modified_dt asc'
  }
end

# Make an HTTP request and return parsed JSON
def get_json(url, params: {}, index: nil)
  prefix = index.nil? ? '[GET] ' : "[GET ##{index}] "
  suffix = params.empty? ? '' : "?#{URI.encode_www_form(params)}"
  puts [prefix, url, suffix].join('')
  JSON.parse(HTTP.get(url, params:).body.to_s)
end

# Yield all documents from the catalog updated since the given timestamp
# Returns the result of calling the block on the last document
# rubocop:disable Metrics/AbcSize
def updated_docs_since(timestamp)
  i = 1
  response = get_json(CATALOG_URL, params: catalog_search_params(timestamp), index: i)

  # Traverse solr paginated responses, adding each document's URL to the list
  urls = []
  while response&.key?('data') && response['data'].any?
    # binding.break
    urls.concat(response['data'].map { |x| x['links']['self'] })
    next_url = response.dig('links', 'next')
    response = next_url ? get_json(next_url, index: i += 1) : nil
  end
  puts "== Received #{urls.length} updated documents =="

  # For each document URL, yield the parsed JSON
  urls.map { |url| yield get_json("#{url}/raw", params: { format: :json }) }.last
end
# rubocop:enable Metrics/AbcSize

# Write the document's metadata to a file in the appropriate directory
# Returns the document's timestamp
def write_doc_metadata(doc)
  # Find the nested directory structure for the document
  tree_dirs = doc['layer_slug_s'].match(/stanford-(..)(...)(..)(....)/).captures.join('/')
  return if tree_dirs.empty?

  # Create the directory structure if it doesn't exist
  tree = File.expand_path("#{BASE_DIR}/#{tree_dirs}")
  FileUtils.mkdir_p(tree)

  # Strip out ignored fields and write the document to the directory
  IGNORED_FIELDS.each { |field| doc.delete(field) }
  File.open("#{tree}/geoblacklight.json", 'w') { |f| f.puts JSON.pretty_generate(doc) }

  # Return the document's timestamp
  doc['layer_modified_dt']
end

# Update everything
task :pull do
  with_timestamp do |previous_timestamp|
    updated_docs_since(previous_timestamp) do |doc|
      write_doc_metadata(doc)
    end
  rescue StandardError => e
    puts "[ERROR] #{e}"
  end
end

# Write a JSON file that maps each layer to its directory
# See: https://opengeometadata.org/share-on-ogm/#naming-by-metadata-standard
task :write_layers_json do
  data = {}

  # Crawl the directory structure and get each druid with its directory
  Dir.glob('**/geoblacklight.json').sort.each do |file|
    druid = File.dirname(file).split(%r{/}).drop(1).join
    data["druid:#{druid}"] = File.dirname(file)
  end

  # Write the JSON to a file
  File.open('./layers.json', 'w') { |f| f.puts JSON.pretty_generate(data) }
end
