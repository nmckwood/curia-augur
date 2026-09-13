this builds on requirements files: 
- REQUIREMENTS.md
- REQUIREMENTS_2.md
- REQUIREMENTS_3.md
- REQUIREMENTS_4.md

# General Requirements
User interface improvements

# Data Ingestion Pipeline
- no changes

# Machine Learning Pipeline
- no changes

# APIs
- no changes

# User Interface
- Remove the 'Per-year predictiveness' page.
- Have three discint widgets on the home page.
- widget 1
    - textual summary of both k means and linear regression
    - list of the indices which characterise the cluster 
- widget 2 dedicated to k means
    - row a:
        - map showing the actual elections results per LAD coloured if the change_factor is 0 or 1
        - map showing the LADS's coloured based on if change_factor_cluster is 0 or 1
        - 1 should always be the same colour accross both maps.
        - type hints and tool tips should explain what is being shown
    - row b
        - xy scatter plot showing PCA projection
        - xy scatter plot showing constituency on the x axis, y axis a new value cluster_correct which is green when change_factor+change_factor_cluster=2 otherwise red
-widget 3 dedicated to logistic regression
    - row a:
        - pie chart showing prediction accuracy
        - pie chart showing most common change factor
        - regression summary
- page must have a scroll bar on the right hand side
