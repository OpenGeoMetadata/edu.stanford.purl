# frozen_string_literal: true

task default: %i[update write_layers_json]

require 'json'
require 'faraday'
require 'faraday/net_http_persistent'
require 'faraday/retry'
require 'uri'
require 'debug'
require 'progress_bar'
require 'progress_bar/core_ext/enumerable_with_progress'

CATALOG_URL = ENV.fetch('CATALOG_URL', 'https://earthworks.stanford.edu/catalog')
INSTITUTION = 'Stanford'
BASE_DIR = 'metadata-1.0'
IGNORED_FIELDS = %w[timestamp layer_availability_score_f _version_ hashed_id_ssi].freeze
DOC_ID_REGEX = /\Astanford-([b-df-hjkmnp-tv-z]{2})([0-9]{3})([b-df-hjkmnp-tv-z]{2})([0-9]{4})\z/i

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
def catalog_search_params(modified_since: nil)
  q_modified = modified_since.nil? ? '' : "layer_modified_dt:[#{modified_since} TO *]"

  {
    'f[dct_provenance_s][]': INSTITUTION,
    format: 'json',
    q: "#{q_modified} AND -dc_type_s:\"Interactive Resource\"",
    per_page: 100,
    sort: 'layer_modified_dt asc'
  }
end

# Make a catalog request with given params and crawl through paginated results
# Returns an array of the results of calling the block on each data item
def crawl_catalog(params:, &block)
  # Track total requests made for the crawl and the results
  index = 1, results = []

  # While there are more pages, add the results of calling the block on each data item
  client = make_client
  response = get_json(CATALOG_URL, params:, client:)
  while response&.key?('data') && response['data'].any?
    results.concat(response['data'].map(&block))
    next_page = response.dig('links', 'next')
    response = next_page.nil? ? nil : get_json(next_page, params:, index: index += 1, client:)
  end

  # Return the collected results
  results
end

# Settings for retrying requests if the server rejects them
# See: https://github.com/lostisland/faraday-retry
def retry_options
  {
    max: 10,
    interval: 1,
    backoff_factor: 3,
    exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::TooManyRequestsError]
  }
end

# Persistent HTTP client with backoff used to make catalog requests
# pool_size controls parallelism
def make_client(pool_size: 1)
  Faraday.new(CATALOG_URL) do |conn|
    conn.request :retry, retry_options
    conn.adapter(:net_http_persistent, pool_size:)
    conn.response :raise_error
  end
end

# Make an HTTP request and return parsed JSON
def get_json(url, params: {}, client: make_client)
  JSON.parse(client.get(url, params).body.to_s)
end

# Check if a layer can be found in the catalog
def layer_exists?(doc_id, client: make_client)
  client.head("#{CATALOG_URL}/#{doc_id}", format: :json).success?
rescue Faraday::ResourceNotFound
  false
end

# Yield all documents from the catalog updated since the given timestamp
# Returns the result of calling the block on each document
def updated_docs_since(timestamp, &block)
  # Traverse solr paginated responses, adding each document's URL to the list
  urls = crawl_catalog(params: catalog_search_params(modified_since: timestamp)) { |doc| doc['links']['self'] }
  puts urls.empty? ? '== No updated layers found ==' : "== Found #{urls.length} updated layers =="

  # For each document URL, yield the parsed JSON
  client = make_client(pool_size: 4)
  urls.with_progress.map do |url|
    block.call(get_json("#{url}/raw", params: { format: :json }, client:))
  end
end

# Call block on all documents listed in layers.json that are no longer in the catalog
# Returns the result of calling the block on each document
def deleted_docs(&block)
  # Get the list of document ids and their Earthworks URLs from layers.json
  doc_ids = JSON.parse(File.read('layers.json')).keys.map { |x| x.sub('druid:', 'stanford-') }

  # For each document id, check if it's still in the catalog. If not, yield its id
  client = make_client(pool_size: 4)
  doc_ids.with_progress.map do |doc_id|
    block.call(doc_id) unless layer_exists?(doc_id, client:)
  end
end

# Write the document's metadata to a file in the appropriate directory
# Returns the document's timestamp
def write_doc_metadata(doc)
  # Find the nested directory structure for the document
  tree_dirs = doc['layer_slug_s'].match(DOC_ID_REGEX).captures.join('/')
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

# Delete a document and its containing directory
# Takes a document id like 'stanford-bb058zh0946'
def delete_doc(doc_id)
  # Find the nested directory structure for the document
  tree_dirs = doc_id.match(DOC_ID_REGEX).captures.join('/')
  return if tree_dirs.empty?

  # Delete the directory if it exists
  tree = File.expand_path("#{BASE_DIR}/#{tree_dirs}")
  FileUtils.rm_rf(tree) if File.exist?(tree)
end

# Update everything
task :update do
  puts '== Updating metadata for layers =='
  with_timestamp do |previous_timestamp|
    updated_docs_since(previous_timestamp) { |doc| write_doc_metadata(doc) }.last
  end

  puts '== Checking for deleted layers =='
  total_deleted = deleted_docs { |doc_id| delete_doc(doc_id) }.compact.length
  puts total_deleted.zero? ? '== No deleted layers found ==' : "== Deleted #{total_deleted} layers =="
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
  puts "== Wrote #{data.length} layers to layers.json =="
end
