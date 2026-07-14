# Project Context
You are working on Curia Augur, a project to build a machine learning model which will predict the outcome of UK local elections using deprivation data from the UK government using SKlearn K-means. At the end of the project there will be a a user interface where users can select from different deprivation indicies to see if some local authority is likely to change how it votes based purely on the deprivation indicies available.

## Code Style
- always use snake case
- use python 3.11
- use flutter 3.32.0
- use dart 3.8.0
- use functional programming style for all backend work no OOP
- use OOP for front end dart work
- we will deploy the app using native 'cdk deploy' with env args passed in as arguments
- only a single env no dev/prod
- this will be a cdk app
- build to optimize cost
- no logging only debug logging to keep cost to a minimum
- all code EG for lambda functions, ECS tasks whatever must be written in such a way we can have a file in `/tools` which can import them to run the pipeline locally using the local files.
- there must be an env flag which is true for when running locall which reads files locally rather than from s3 for local running.

## Reference Code
- For examples see `/home/nwood/non-soc/personal/hof`

## Requirements
- Requirements docs are in `/home/nwood/non-soc/personal/curia-augur/docs/REQUIREMENTS.md`

# IMPORTANT
- You must log all prompts, questions, answers, plans etc truncated to max 200 characters in CLAUDE.log.
- You must pre fix all messages with what is is EG [PROMPT] etc like a log message in an app for example.
- You must append all info to CLAUDE.log in this dir.