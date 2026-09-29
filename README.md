# edu.stanford.purl

This repository contains geospatial metadata from [EarthWorks](https://earthworks.stanford.edu), the Stanford University Libraries geoportal.

This metadata is provided under the [CC0 v1.0 License](LICENSE), which allows for free use and redistribution without restrictions.

## Metadata

Metadata is provided in the [OGM Aardvark format](https://opengeometadata.org/ogm-aardvark/).

Records in the Stanford digital repository are identified by a Digital Resource Unique Identifier (DRUID) in the format `druid:bb058zh0946`.

Each record gets a corresponding permanent URL (PURL) page in the format [https://purl.stanford.edu/bb058zh0946](https://purl.stanford.edu/bb058zh0946).

## Contribution and enhancement status

![Open for metadata contributions](https://upload.wikimedia.org/wikipedia/commons/archive/0/0e/20170421060213%21Location_dot_green.svg) *Open for metadata corrections and enhancements*

For issues with the metadata, open an issue in this repository to get started.

## Updating the metadata

After cloning the repository, you can run the rake task to update all layers changed or deleted since the last run:

```bash
rake
```

After the run, the files in `metadata-aardvark` will be updated with the latest metadata from Earthworks, and the `layers.json` index file will be updated accordingly. The `last_run` file will also be updated with the date and time of the run.

Note that GitHub actions runs this process regularly and commits the results on its own.

### Full reindex

If the number of records that was recently changed is very high (see `MAX_DOCUMENTS` in the Rakefile), the incremental reindex will bail out. In these situations, it's faster to do a full reindex yourself manually.

To do this, make sure you're on VPN so that you can safely make more requests to Earthworks. Then you can set `FULL` to any value and `THREADS` to something higher, and invoke `rake`:

```bash
FULL=1 THREADS=8 rake
```

With this setup, you can accomplish a full reindex in around half an hour.

### Testing the harvest

You can target a different environment like staging:

```bash
BASE_DIR=metadata-aardvark-stage EARTHWORKS_HOST=https://earthworks-stage.stanford.edu rake
```

This will read records from earthworks-stage and output them to a new directory called `metadata-aardvark-stage`. This can be useful to do a much shorter run without crawling all of Earthworks, e.g. in order to test changes to the Rakefile.
