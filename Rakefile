# frozen_string_literal: true

task default: %i[update delete write_layers_json]

require 'json'
require 'faraday'
require 'faraday/net_http_persistent'
require 'faraday/retry'
require 'uri'
require 'debug'
require 'progress_bar'
require 'progress_bar/core_ext/enumerable_with_progress'
require 'time'

CATALOG_URL = ENV.fetch('CATALOG_URL', 'https://earthworks.stanford.edu/catalog')
PURL_FETCHER_URL = ENV.fetch('PURL_FETCHER_URL', 'https://purl-fetcher.stanford.edu')
INSTITUTION = 'Stanford'
BASE_DIR = 'metadata-aardvark'
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

# Yield all documents from the catalog updated since the given timestamp
# Returns the result of calling the block on each document
def updated_docs_since(timestamp, &block)
  # Query purl-fetcher for all released layers and filter to those updated since the timestamp
  released = get_json("#{PURL_FETCHER_URL}/released/Earthworks")
  updated = released.select { |layer| Time.parse(layer['updated_at']) > timestamp }
  puts updated.empty? ? '== No updated layers found ==' : "== Found #{updated.length} updated layers =="

  # For each druid, yield the parsed geoblacklight JSON from the catalog
  client = make_client(pool_size: 4)
  updated.map { |layer| layer['druid'].gsub('druid:', 'stanford-') }.with_progress.map do |doc_id|
    block.call(get_json("#{CATALOG_URL}/#{doc_id}/raw", params: { format: :json }, client:))
  rescue Faraday::ResourceNotFound
    # Released but not indexed (e.g. because of bad metadata); ignore
  end
end

# Call block on all documents listed in layers.json that are no longer released
# Returns the result of calling the block on each document
def deleted_docs(&block)
  # Query purl-fetcher for all released layers and compare to layers.json
  released = get_json("#{PURL_FETCHER_URL}/released/Earthworks").map { |layer| layer['druid'] }
  old = JSON.parse(File.read('layers.json')).keys
  deleted = old.to_set - released.to_set
  puts deleted.empty? ? '== No deleted layers found ==' : "== Found #{deleted.length} deleted layers =="

  # For each druid, call the block with its document ID
  deleted.map { |druid| druid.gsub('druid:', 'stanford-') }.with_progress.map do |doc_id|
    block.call(doc_id)
  end
end

# Write the document's metadata to a file in the appropriate directory
# Returns the document's timestamp
def write_doc_metadata(doc)
  # Find the nested directory structure for the document
  tree_dirs = doc['id'].match(DOC_ID_REGEX).captures.join('/')
  return if tree_dirs.empty?

  # Create the directory structure if it doesn't exist
  tree = File.expand_path("#{BASE_DIR}/#{tree_dirs}")
  FileUtils.mkdir_p(tree)

  # Strip out ignored fields and write the document to the directory
  IGNORED_FIELDS.each { |field| doc.delete(field) }
  File.open("#{tree}/geoblacklight.json", 'w') { |f| f.puts JSON.pretty_generate(doc) }

  # Return the document's timestamp
  doc['gbl_mdModified_dt']
end

# Delete a document and its containing directory
# Takes a document id like 'stanford-bb058zh0946'
def delete_doc(doc_id)
  # Find the nested directory structure for the document
  tree_dirs = doc_id.match(DOC_ID_REGEX).captures.join('/')
  return if tree_dirs.empty?

  # Delete the directory if it exists
  tree = File.expand_path("#{BASE_DIR}/#{tree_dirs}")
  FileUtils.rm_rf(tree)
end

# This is run first
desc 'Update metadata for layers'
task :update do
  puts '== Updating metadata for layers =='

  with_timestamp do |previous_timestamp|
    updated = updated_docs_since(Time.parse(previous_timestamp)) do |doc|
      write_doc_metadata(doc)
    end

    # Return the most recent timestamp from the updated documents
    updated.max_by { |timestamp| Time.parse(timestamp) }
  end
end

# This task is run after the update task
desc 'Delete metadata for layers no longer released'
task :delete do
  puts '== Deleting metadata for layers no longer released =='

  deleted_docs do |doc_id|
    delete_doc(doc_id)
  end
end

# See: https://opengeometadata.org/share-on-ogm/#naming-by-metadata-standard
# This task is run after the update and delete tasks
desc 'Write layers.json mapping layer IDs to file paths'
task :write_layers_json do
  data = {}

  # Crawl the directory structure and get each druid with its directory
  Dir.glob("#{BASE_DIR}/**/geoblacklight.json").each do |file|
    druid = File.dirname(file).split(%r{/}).drop(1).join
    data["druid:#{druid}"] = File.dirname(file)
  end

  # Write the JSON to a file
  File.open('./layers.json', 'w') { |f| f.puts JSON.pretty_generate(data) }
  puts "== Wrote #{data.length} layers to layers.json =="
end
