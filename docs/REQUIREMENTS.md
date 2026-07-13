# General Requirements
1. The system must use AWS and serverless components where possible.
2. The system must use s3, DynamoDB (pay per use), Lambda and API gateway wherever possible.
3. The system must use APIs secured with Cognito for interaction with the UI.
4. The system must wherever possible use lambda - lambda invocation in app to app communication.
5. Where large sets of data are passed between an microservices S3 shall be used.
6. For data output to be rendered in the UI Dynamo DB shall be used.
7. The system will have a data ingestion layer which will be triggered once via the AWS console.
8. The users will call outputs from the data ingestion layer.
9. Any tools created such as scripts used for uploading data, pre processing data etc must be placed into `/home/nwood/non-soc/personal/curia-augur/tools`.
10. The app must use the domain howfhowfhowf as it is alreayd registered, its details can be found in the reference howf project.
11. The system will compare data as follows:
- deprivation data between 2015 and 2019 how it impacted the local election results in 2022 with 2018 as the bench mark for change.
- deprivation data between 2019 and 2025 how it impacted the local election results in 2026 with 2022 as the bench mark for change.

# Data Ingestion Pipeline
1. There are 3 key sets of data
- geospatial data, this is for use in the UI only and we have it for 2025 and 2022 and it can be found `/home/nwood/non-soc/personal/curia-augur/data/geospatial_data/Local_Authority_Districts_DEC_2025_Boundaries_UK_BFC_5780731924739583250.geojson` and `/home/nwood/non-soc/personal/curia-augur/data/geospatial_data/Local_Authority_Districts_December_2022_UK_BFC_V2_-4534861255799681503.geojson`
- deprivation data for each of 2025, 2019 and 2015 which can be found here `/home/nwood/non-soc/personal/curia-augur/data/deprivation_data`, the year is in the file name.
- the local election data can be found here for each of 2018, 2022 and 2026 `/home/nwood/non-soc/personal/curia-augur/data/local_election_data` and also has the year in the file name.
2. All input data for the data pipeline must be placed into S3.
3. The data pipeline lambda shall take an input of
```json
{
    "deprivation_file_start":"some file name",
    "deprivation_file_end":"some file name",
    "local_election_start":"some file name",
    "local_election_end":"some file name"
}
```
4. The data pipeline should create a single file called `deprivation-election-data-<composite key of input data>.json` where composite key is d_<year> where d is deprevation and le_<year> is local election.
5. The file `deprivation-election-data-<composite key of input data>.json` should have the following schema:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Local Authority Deprivation and Election Results",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "Local Authority District name": {
        "type": "string"
      },
      "deprivation": {
        "type": "object",
        "properties": {
          "Index of Multiple Deprivation (IMD) Rank (where 1 is most deprived) delta": { "type": "integer" },
          "Index of Multiple Deprivation (IMD) Decile (where 1 is most deprived 10% of LSOAs) delta": { "type": "integer" },
          "Income Rank (where 1 is most deprived) delta": { "type": "integer" },
          "Income Decile (where 1 is most deprived 10% of LSOAs) delta": { "type": "integer" },
          "Employment Rank (where 1 is most deprived) delta": { "type": "integer" },
          "Employment Decile (where 1 is most deprived 10% of LSOAs) delta": { "type": "integer" },
          "Education, Skills and Training Rank (where 1 is most deprived) delta": { "type": "integer" },
          "Education, Skills and Training Decile (where 1 is most deprived 10% of LSOAs) delta": { "type": "integer" },
          "Health Deprivation and Disability Rank (where 1 is most deprived) delta": { "type": "integer" },
          "Health Deprivation and Disability Decile (where 1 is most deprived 10% of LSOAs) delta": { "type": "integer" },
          "Crime Rank (where 1 is most deprived) delta": { "type": "integer" },
          "Crime Decile (where 1 is most deprived 10% of LSOAs) delta": { "type": "integer" },
          "Barriers to Housing and Services Rank (where 1 is most deprived) delta": { "type": "integer" },
          "Barriers to Housing and Services Decile (where 1 is most deprived 10% of LSOAs) delta": { "type": "integer" },
          "Living Environment Rank (where 1 is most deprived) delta": { "type": "integer" },
          "Living Environment Decile (where 1 is most deprived 10% of LSOAs) delta": { "type": "integer" }
        },
        "required": [
          "Index of Multiple Deprivation (IMD) Rank (where 1 is most deprived) delta",
          "Index of Multiple Deprivation (IMD) Decile (where 1 is most deprived 10% of LSOAs) delta",
          "Income Rank (where 1 is most deprived) delta",
          "Income Decile (where 1 is most deprived 10% of LSOAs) delta",
          "Employment Rank (where 1 is most deprived) delta",
          "Employment Decile (where 1 is most deprived 10% of LSOAs) delta",
          "Education, Skills and Training Rank (where 1 is most deprived) delta",
          "Education, Skills and Training Decile (where 1 is most deprived 10% of LSOAs) delta",
          "Health Deprivation and Disability Rank (where 1 is most deprived) delta",
          "Health Deprivation and Disability Decile (where 1 is most deprived 10% of LSOAs) delta",
          "Crime Rank (where 1 is most deprived) delta",
          "Crime Decile (where 1 is most deprived 10% of LSOAs) delta",
          "Barriers to Housing and Services Rank (where 1 is most deprived) delta",
          "Barriers to Housing and Services Decile (where 1 is most deprived 10% of LSOAs) delta",
          "Living Environment Rank (where 1 is most deprived) delta",
          "Living Environment Decile (where 1 is most deprived 10% of LSOAs) delta"
        ],
        "additionalProperties": false
      },
      "local_election_results": {
        "type": "object",
        "properties": {
          "council": {
            "type": "string"
          },
          "change_factor": {
            "type": "integer"
          }
        },
        "required": ["council", "change_factor"],
        "additionalProperties": {
          "type": "integer",
          "description": "Seat change delta for a given party, keyed by party name (e.g. 'Conservative', 'Labour', 'Liberal Democrat', 'Green', 'Independent')"
        }
      }
    },
    "required": [
      "Local Authority District name",
      "deprivation",
      "local_election_results"
    ],
    "additionalProperties": false
  }
}
```
6. The output file `deprivation-election-data-<composite key of input data>.json` keys with 'delta' should contain the 'delta' of the two input years data for example if year_start has 5 and year_end has 3 the value would be year_start-year_end=2.
7. The data pipeline for deprivation data must also output `unused-deprivation-election-data-<composite key of input data>.log` which has the same composite key formatting, this file contains data which could not be used, for example it should contain log statements like "could not join key x with key y between 2019 and 2025 files as the semantic search did not find anything".
8. The data pipeline must validate all fields, any entries with invalid fields should be entered into the log entry
9. The data pipeline function should account for file types of .xlsx, .json and .csv.
10. The data pipeline function should for each of the provided election files, first for each 'Council' in the .csv calculate the sum of entries for each party EG 
```csv
2018,'Buckinghamshire','Conservatives',10
2018',Buckinghamshire','Labour',5
2022,'Buckinghamshire','Conservatives',15
2022',Buckinghamshire','Labour',0
```
then calculate the change_factor and populate the output json `deprivation-election-data-<composite key of input data>.json` as per the schema.
11. To join local election data with deprivation data the Council field in the local election data should be joined with 'Local Authority District name <some date pattern matching must be used>'.



