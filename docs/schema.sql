Table OpenCouncilData {
  Council string
  WardName string
  CouncillorName string
  NextElection string
  PartyName string
  ElectoralCommissionPartyCode string
}

Table DeprivationData {
  Lsoacode20xx String
  Lsoaname20xx String
  LocalAuthorityDistrictcode20xx String
  LocalAuthorityDistrictname20xx String
  IndexofMultipleDeprivationIMDRankwhere1ismostdeprived Integer
  IndexofMultipleDeprivationIMDDecilewhere1ismostdeprived10ofLSOAs Integer
  IncomeRankwhere1ismostdeprived Integer
  IncomeDecilewhere1ismostdeprived10ofLSOAs Integer
  EmploymentRankwhere1ismostdeprived Integer
  EmploymentDecilewhere1ismostdeprived10ofLSOAs Integer
  EducationSkillsandTrainingRankwhere1ismostdeprived Integer
  EducationSkillsandTrainingDecilewhere1ismostdeprived10ofLSOAs Integer
  HealthDeprivationandDisabilityRankwhere1ismostdeprived Integer
  HealthDeprivationandDisabilityDecilewhere1ismostdeprived10ofLSOAs Integer
  CrimeRankwhere1ismostdeprived Integer
  CrimeDecilewhere1ismostdeprived10ofLSOAs Integer
  BarrierstoHousingandServicesRankwhere1ismostdeprived Integer
  BarrierstoHousingandServicesDecilewhere1ismostdeprived10ofLSOAs Integer
  LivingEnvironmentRankwhere1ismostdeprived Integer
  LivingEnvironmentDecilewhere1ismostdeprived10ofLSOAs Integer
}

Table GeoSpatialData {
  LAD20xxCD String
  LAD20xxNM String
  Name String
  Type String
  LAD20xxNMW String
  BNGE Float
  BNGN Float
  LONG Float
  LAT Float
  ShapeArea Float
  ShapeLength Float
}

Ref: OpenCouncilData.Council > DeprivationData.Lsoaname20xx
Ref: OpenCouncilData.Council > GeoSpatialData.LAD20xxNM
