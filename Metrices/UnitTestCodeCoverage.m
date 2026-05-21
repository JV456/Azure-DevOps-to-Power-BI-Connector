let

PAT = "YOUR_PAT",
BaseUrl = "https://dev.azure.com",
Org = "YOUR_ORGANIZATION",
Project = "YOUR_ORGANIZATION_PROJECT",
PipelineId = "YOUR_AZURE_BUILD_PIPELINE_ID",


BuildsResponse = Web.Contents(
    BaseUrl,
    [
        RelativePath = Org & "/" & Project & "/_apis/build/builds",
        Query = [
            definitions = Text.From(PipelineId),
            queryOrder = "finishTimeDescending", // latest first
            top = "10", // get multiple builds
            #"api-version" = "7.1"
        ],
        Headers = [
            Authorization = "Basic " & Binary.ToText(
                Text.ToBinary(":" & PAT),
                BinaryEncoding.Base64
            )
        ]
    ]
),

BuildsJson = Json.Document(BuildsResponse),
BuildsTable = Table.FromList(BuildsJson[value], Splitter.SplitByNothing(), null, null, ExtraValues.Error),
BuildsExpanded = Table.ExpandRecordColumn(BuildsTable, "Column1", {"id", "status", "result"}, {"id", "status", "result"}),

SuccessfulBuilds = Table.SelectRows(BuildsExpanded, each [result] = "succeeded"),
LatestSucceededBuildId = if Table.IsEmpty(SuccessfulBuilds) then null else SuccessfulBuilds{0}[id],
BuildStatus = if Table.IsEmpty(SuccessfulBuilds) then null else SuccessfulBuilds{0}[status],
BuildResult = if Table.IsEmpty(SuccessfulBuilds) then null else SuccessfulBuilds{0}[result],

CoverageJson = if LatestSucceededBuildId <> null then
    let
        CoverageResponse = Web.Contents(
            BaseUrl,
            [
                RelativePath = Org & "/" & Project & "/_apis/test/codecoverage",
                Query = [
                    buildId = Number.ToText(LatestSucceededBuildId),
                    #"api-version" = "7.1"
                ],
                Headers = [
                    Authorization = "Basic " & Binary.ToText(
                        Text.ToBinary(":" & PAT),
                        BinaryEncoding.Base64
                    )
                ]
            ]
        )
    in
        Json.Document(CoverageResponse)
else
    null,

#"Converted to Table" = if CoverageJson <> null then Table.FromRecords({CoverageJson}) else #table({}, {}),
#"Expanded coverageData" = Table.ExpandListColumn(#"Converted to Table", "coverageData"),
#"Expanded coverageData1" = Table.ExpandRecordColumn(#"Expanded coverageData", "coverageData", {"coverageStats", "buildPlatform", "buildFlavor"}, {"coverageData.coverageStats", "coverageData.buildPlatform", "coverageData.buildFlavor"}),
#"Expanded coverageData.coverageStats" = Table.ExpandListColumn(#"Expanded coverageData1", "coverageData.coverageStats"),
#"Expanded coverageData.coverageStats1" = Table.ExpandRecordColumn(#"Expanded coverageData.coverageStats", "coverageData.coverageStats", {"label", "position", "total", "covered", "isDeltaAvailable", "delta"}, {"coverageData.coverageStats.label", "coverageData.coverageStats.position", "coverageData.coverageStats.total", "coverageData.coverageStats.covered", "coverageData.coverageStats.isDeltaAvailable", "coverageData.coverageStats.delta"}),
#"Expanded build" = Table.ExpandRecordColumn(#"Expanded coverageData.coverageStats1", "build", {"id", "url"}, {"build.id", "build.url"}),

#"Changed Type" = Table.TransformColumnTypes(#"Expanded build",{
    {"coverageData.coverageStats.label", type text},
    {"coverageData.coverageStats.position", Int64.Type},
    {"coverageData.coverageStats.total", Int64.Type},
    {"coverageData.coverageStats.covered", Int64.Type},
    {"coverageData.coverageStats.isDeltaAvailable", type logical},
    {"coverageData.coverageStats.delta", Int64.Type},
    {"coverageData.buildPlatform", type text},
    {"coverageData.buildFlavor", type text},
    {"build.id", Int64.Type},
    {"build.url", type text},
    {"deltaBuild", type any}
}),

#"Added Product Column" = Table.AddColumn(#"Changed Type", "Product", each "KoolProg"),
#"Changed Type1" = Table.TransformColumnTypes(#"Added Product Column",{{"Product", type text}}),
#"Added Status Column" = Table.AddColumn(#"Changed Type1", "BuildStatus", each BuildStatus),
#"Added Result Column" = Table.AddColumn(#"Added Status Column", "BuildResult", each BuildResult)

in
    #"Added Result Column"