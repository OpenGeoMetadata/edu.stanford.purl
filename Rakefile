# frozen_string_literal: true

# Harvests OGM Aardvark metadata for Stanford's records by crawling EarthWorks'
# own Blacklight index: /catalog.json lists record ids a page at a time, and
# /catalog/:id/raw returns a record's Solr document.
#
# Each run reads the records Solr has written since the last run, then lists
# every record to find any EarthWorks has dropped or we have never held. Set
# FULL to read every record instead; that takes hours from off campus, so do it
# on the Stanford network.

require 'json'
require 'net/http'
require 'time'
require 'fileutils'
require 'progress_bar'

# progress_bar draws on stderr, which is never buffered; unbuffer stdout too so
# our own lines stay in order with the bars when output isn't a terminal (CI).
$stdout.sync = true

HOST = ENV.fetch('EARTHWORKS_HOST', 'https://earthworks.stanford.edu')
BASE_DIR = ENV.fetch('BASE_DIR', 'metadata-aardvark')

# Check up to 1hr before the last run date, to give room for clock skew and
# anything that got updated but hasn't been committed yet.
OVERLAP = 3600

# If there are this many changed records or more, bail out and request a full
# reindex on VPN, because it'll take too long otherwise.
MAX_DOCUMENTS = 8000

# How many records to read at once. Any higher than this off VPN will just get
# you more resets from the F5 firewall. On VPN, you can bump it up more.
THREADS = Integer(ENV.fetch('THREADS', '4'))

# Internal solr fields that aren't valid in Aardvark; we strip them out.
IGNORED_FIELDS = %w[timestamp layer_availability_score_f _version_ hashed_id_ssi
                    solr_bboxtype__minX solr_bboxtype__maxX solr_bboxtype__minY
                    solr_bboxtype__maxY].freeze

# Used to split a DRUID into the filesystem tree.
DRUID_REGEX = /\Astanford-([b-df-hjkmnp-tv-z]{2})([0-9]{3})([b-df-hjkmnp-tv-z]{2})([0-9]{4})\z/i

HEADERS = {
  # Earthworks checks for this and skips Cloudflare Turnstile if present.
  'sec-fetch-dest' => 'empty',
  # Anything with "bot" tells Blacklight not to keep a search session for each request.
  'User-Agent' => 'OpenGeoMetadata harvester (bot; +https://github.com/OpenGeoMetadata/edu.stanford.purl)'
}.freeze

# GET a path and parse the JSON, or return nil for a 404. Stanford's F5 resets
# connections from off campus when requests come quickly, so each request gets
# its own connection and a few retries.
def get_json(path, attempt = 1)
  response = Net::HTTP.get_response(URI("#{HOST}#{path}"), HEADERS)
  return if response.code == '404'
  raise "HTTP #{response.code}" unless response.code == '200'

  JSON.parse(response.body)
rescue StandardError => e
  raise "giving up on #{path}: #{e.message}" if attempt == 5

  sleep 2**attempt
  get_json(path, attempt + 1)
end

# Request URL for the list of records. Sorted by ID, so records getting updated
# during the reindex doesn't reset the ordering.
def search_path(page, since: nil)
  query = { 'per_page' => 100, 'page' => page, 'sort' => 'id asc', 'f[schema_provider_s][]' => 'Stanford' }
  query['q'] = "timestamp:[#{since.utc.iso8601} TO *]" if since
  "/catalog.json?#{URI.encode_www_form(query)}"
end

# Get every document ID, or only those changed since a timestamp
def document_ids(since: nil)
  first = get_json(search_path(1, since:))
  pages = first.dig('meta', 'pages', 'total_pages')
  bar = ProgressBar.new(pages)
  ids = (1..pages).flat_map do |page|
    body = page == 1 ? first : get_json(search_path(page, since:))
    bar.increment!
    body['data'].map { |document| document['id'] }
  end
  warn '' if pages.positive? # progress_bar doesn't end its line
  ids
end

# How many records changed since a timestamp, from the first page alone.
def modified_count(since)
  get_json(search_path(1, since:)).dig('meta', 'pages', 'total_count')
end

# Read each record at the given ID and write it out, THREADS at a time.
def read_documents(ids)
  queue = Queue.new(ids).close
  bar = ProgressBar.new(ids.size)
  lock = Mutex.new # progress_bar isn't thread-safe
  Array.new(THREADS) do
    Thread.new do
      while (id = queue.pop)
        document = get_json("/catalog/#{id}/raw")
        write_document(document) if document
        lock.synchronize { bar.increment! }
      end
    end
  end.each(&:join)
  warn '' unless ids.empty? # progress_bar doesn't end its line
end

# Write a document hash to a place in the tree based on its DRUID.
def write_document(document)
  tree = document['id'].match(DRUID_REGEX)&.captures&.join('/')
  return unless tree

  path = File.join(BASE_DIR, tree)
  FileUtils.mkdir_p(path)
  IGNORED_FIELDS.each { |field| document.delete(field) }
  File.write(File.join(path, 'geoblacklight.json'), "#{JSON.pretty_generate(document)}\n")
end

# Delete a document from the DRUID tree, given its ID.
def delete_document(id)
  tree = id.match(DRUID_REGEX)&.captures&.join('/')
  FileUtils.rm_rf(File.join(BASE_DIR, tree)) if tree
end

task default: :harvest

desc 'Harvest records changed since the last run, and remove any EarthWorks has dropped'
task :harvest do
  since = Time.parse(File.read('last_run')) - OVERLAP unless ENV['FULL']
  started = Time.now.utc

  # Check how many records modified since last timestamp; bail out if we need a
  # full reindex but we didn't request one. Skip this on a full run.
  modified_ids = []
  if since
    count = modified_count(since)
    puts "== #{count} records modified since #{since.utc.iso8601} =="
    abort "Over #{MAX_DOCUMENTS} records modified; run this with FULL=1 on VPN" if count >= MAX_DOCUMENTS

    modified_ids = document_ids(since:)
  end

  # Get IDs for everything currently in Earthworks, plus the IDs of everything
  # in this repo (via layers.json).
  current_ids = document_ids
  known_ids = JSON.parse(File.read('layers.json')).keys.map { |druid| druid.sub('druid:', 'stanford-') }
  newly_added_ids = (current_ids - known_ids)
  puts "== #{current_ids.size} records in EarthWorks, #{known_ids.size} here, #{newly_added_ids.size} newly added =="

  # Update everything that should be updated: modified records plus newly added
  # records. For a full reindex this is just the entire catalog.
  updated_ids = since ? (modified_ids + newly_added_ids).uniq : current_ids
  read_documents(updated_ids)
  puts "== Updated #{updated_ids.size} records =="

  # Delete everything that is in this repo but not in the current catalog.
  gone_ids = known_ids - current_ids
  gone_ids.each { |id| delete_document(id) }
  puts "== Removed #{gone_ids.size} records =="

  # Update layers.json and move the last run timestamp.
  Rake::Task[:write_layers_json].invoke
  File.write('last_run', "#{started.iso8601}\n")
end

desc 'Write layers.json mapping druids to their directories'
task :write_layers_json do
  layers = Dir.glob("#{BASE_DIR}/**/geoblacklight.json").to_h do |file|
    directory = File.dirname(file)
    ["druid:#{directory.split('/').drop(1).join}", directory]
  end
  File.write('layers.json', "#{JSON.pretty_generate(layers.sort.to_h)}\n")
  puts "== Wrote #{layers.size} layers to layers.json =="
end
