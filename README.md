# edu.stanford.purl

This repository contains geospatial metadata from [EarthWorks](https://earthworks.stanford.edu), the Stanford University Libraries geoportal.

This metadata is provided under the [CC0 v1.0 License](LICENSE), which allows for free use and redistribution without restrictions.

> [!WARNING]  
> Geoblacklight v1 schema metadata in `metadata-1.0` is no longer updated and is provided for reference only. Links are likely to be broken.

## Metadata

Metadata for geospatial data are provided in the following formats:

- geoblacklight.json -- [GeoBlacklight metadata](https://github.com/geoblacklight/geoblacklight/blob/master/schema/geoblacklight-schema.md)

Records in the Stanford digital repository are identified by a Digital Resource Unique Identifier (DRUID) in the format `druid:bb058zh0946`. Each record gets a corresponding permanent URL (PURL) page in the format [https://purl.stanford.edu/bb058zh0946](https://purl.stanford.edu/bb058zh0946).

For objects that are available to download, this page hosts download links for the original data as well as metadata in various formats, like FGDC XML and ISO 19139 XML.

## Contribution and enhancement status

![Open for metadata contributions](https://upload.wikimedia.org/wikipedia/commons/archive/0/0e/20170421060213%21Location_dot_green.svg) *Open for metadata corrections and enhancements*

For issues with the metadata, open an issue in this repository to get started.

## Updating the metadata

To update the metadata locally, you need to be on Stanford VPN in order to crawl Earthworks. After cloning the repository, run the rake task to update all layers changed or deleted since the last run:

```bash
rake
```

After the run, the files in `metadata-aardvark` will be updated with the latest metadata from Earthworks, and the `layers.json` index file will be updated accordingly. The `last_run` file will also be updated with the date and time of the run.

You can target a different environment like staging:

```bash
BASE_DIR=metadata-aardvark-stage PURL_FETCHER_URL=https://purl-fetcher-stage.stanford.edu CATALOG_URL=https://earthworks-stage.stanford.edu/catalog rake
```

This will read records from earthworks-stage and output them to a new directory called `metadata-aardvark-stage`. This can be useful to do a much shorter run without crawling all of Earthworks, e.g. in order to test changes to the Rakefile.
