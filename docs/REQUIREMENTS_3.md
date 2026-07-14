this builds on requirements files: 
- REQUIREMENTS.md
- REQUIREMENTS_2.md

# General Requirements

# Data Ingestion Pipeline

# Machine Learning Pipeline
- Our data analysis tells us there is common indices in the two sets we must add an additional step following the ML pipeline forming a join between the two clusters finding the common indices then use those indices to predict the change factor and compare that against the constituencies which change.
- This means when the ML pipeline completes do:
a. join between the two cluster to get the common indices of deprivation that most characterize the high change cluster.
b. for both elections
c. use the decline between the two preceding years deprivation data to indicate change factor.
d. add to the JSON schmea change_factor_deprivation_key_indices which will be populated from the above pipeline.

# APIs

# User Interface
- additional map showing the new change_factor_deprivation_key_indices.
- additional x/y chart showing for each constituency (y axis) whether it was predicated to change and if it changed with each being 1/0 so where the prediction was inline with the outcome the dots are ontop of one another both at value 1.
- additional pie chart showing percentage of correct outcomes.