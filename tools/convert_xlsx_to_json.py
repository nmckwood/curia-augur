import pandas as pd
import json

def xlsx_to_json(xlsx_path, json_path, sheet_name=0):
    df = pd.read_excel(xlsx_path, sheet_name=sheet_name)
    df.to_json(json_path, orient='records', indent=2)

if __name__ == "__main__":
    xlsx_to_json(
        "/home/nwood/non-soc/personal/curia-augur/data/deprivation_data/File_2_-_IoD2019_Domains_of_Deprivation.xlsx",
        "/home/nwood/non-soc/personal/curia-augur/data/deprivation_data/2019_dep.json",
        "IoD2019 Domains"
    )
    xlsx_to_json(
        "/home/nwood/non-soc/personal/curia-augur/data/deprivation_data/File_2_ID_2015_Domains_of_deprivation.xlsx",
        "/home/nwood/non-soc/personal/curia-augur/data/deprivation_data/2015_dep.json",
        "ID2015 Domains"
    )