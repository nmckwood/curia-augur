this builds on requirements files: 
- REQUIREMENTS.md
- REQUIREMENTS_2.md
- REQUIREMENTS_3.md

# General Requirements
The results output is not correct, we are missing the final stage of analysis to compare the clusters against if it did change. So the clusters create groups using k-means based on deprivation data then we use those groups to compare against the standard. We should be using the output, so in the analysis output file we have for each cluster whether it is 'is_high_change_cluster' and for each council whether it actually changed 'change_factor' and which council the cluter it maps to 'cluster_id' therfor each cluster should be ranked for accuracy. Each clusters accuracy is represented as the percentage of councils it predicted would or would not change vs their actual performance. Additionally the UI is misleading with the map projections, more on this below.

# Data Ingestion Pipeline
- no changes

# Machine Learning Pipeline
- Add change_factor_cluster to each constituency in the output, set to 1 if the constituency cluster_id is the cluster flagged as is_high_change_cluster, else 0.

# APIs
- no changes

# User Interface
- we should show two map projections, where the election result changed and another showing green where the change_factor_cluster is 1 red otherwise.
- the prediction accuracy pie chart should be updated to use the change_factor_cluster also.
- the xy chart should also change to change_factor_cluster
- the table should also use change_factor_cluster