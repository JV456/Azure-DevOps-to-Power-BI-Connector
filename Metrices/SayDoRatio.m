let

PAT = "YOUR_PAT",
BaseUrl = "https://dev.azure.com",
Org = "YOUR_ORGANIZATION",
Team = "YOUR_ORGANIZATION_TEAM",
Project = "YOUR_ORGANIZATION_PROJECT",


WIQLQuery =
    "{""query"": ""SELECT [System.Id] FROM WorkItems
    WHERE [System.TeamProject] = 'TeamProject'
    AND [System.WorkItemType] = 'WorkItemType'
    AND [State] <> 'Removed'
    AND [System.AreaPath] UNDER 'AreaPath'""}",

RawIdsResponse =
    Web.Contents(
        BaseUrl,
        [
            RelativePath = Org & "/" & Project & "/_apis/wit/wiql",
            Query = [#"api-version" = "7.0"],
            Headers = [
                Authorization = "Basic " & Binary.ToText(
                    Text.ToBinary(":" & PAT),
                    BinaryEncoding.Base64
                ),
                #"Content-Type" = "application/json"
            ],
            Content = Text.ToBinary(WIQLQuery)
        ]
    ),

RawIdsJson = Json.Document(RawIdsResponse),
AllIds     = List.Transform(RawIdsJson[workItems], each _[id]),
IdBatches  = List.Split(AllIds, 100),

FetchBatch = (batch as list) =>
    let
        IdText = Text.Combine(List.Transform(batch, each Text.From(_)), ","),
        Response = Web.Contents(
            BaseUrl,
            [
                RelativePath = Org & "/" & Project & "/_apis/wit/workitems",
                Query = [
                    ids = IdText,
                    #"$expand" = "all",
                    #"api-version" = "7.0"
                ],
                Headers = [
                    Authorization = "Basic " & Binary.ToText(
                        Text.ToBinary(":" & PAT),
                        BinaryEncoding.Base64
                    )
                ]
            ]
        ),
        JsonResponse = Json.Document(Response),
        Items = JsonResponse[value]
    in
        Items,

RawWorkItems = if List.Count(IdBatches) = 0 then {} else List.Combine(List.Transform(IdBatches, each FetchBatch(_))),
RawTable = Table.FromList(RawWorkItems, Splitter.SplitByNothing(), null, null, ExtraValues.Error),

ExpandRoot = Table.ExpandRecordColumn(RawTable, "Column1", {"id","fields","relations"}, {"WorkItemId","fields","relations"}),
WorkItems =
    Table.ExpandRecordColumn(
        ExpandRoot,
        "fields",
        {"System.IterationPath", "System.WorkItemType", "System.State", "System.Title", "System.AreaPath", "System.ChangedDate", "Microsoft.VSTS.Common.ActivatedDate", "Microsoft.VSTS.Common.ClosedDate", "System.AssignedTo"},
        {"IterationPath", "WorkItemType", "State","Title","AreaPath", "ChangedDate", "ActivatedDate", "ClosedDate", "AssignedTo"}
    ),

IterationsResponse =
    Web.Contents(
        BaseUrl,
        [
            RelativePath = Org & "/" & Project & "/" & Team & "/_apis/work/teamsettings/iterations",
            Query = [ includeDates = "true", #"api-version" = "7.0" ],
            Headers = [
                Authorization = "Basic " & Binary.ToText(
                    Text.ToBinary(":" & PAT),
                    BinaryEncoding.Base64
                ),
                #"Content-Type" = "application/json"
            ]
        ]
    ),
IterationsJson = Json.Document(IterationsResponse),
IterationsList = IterationsJson[value],
IterTable = Table.FromList(IterationsList, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
IterExpand = Table.ExpandRecordColumn(IterTable, "Column1", {"name","path","attributes"}, {"IterationName","IterationPathFull","attributes"}),
IterAttrs = Table.ExpandRecordColumn(IterExpand, "attributes", {"startDate","finishDate"}, {"IterationStartDate","IterationEndDate"}),

IterTypes1 = Table.TransformColumnTypes(IterAttrs, {{"IterationStartDate", type datetimezone}, {"IterationEndDate", type datetimezone}}),
IterTypes2 = Table.TransformColumnTypes(IterTypes1, {{"IterationStartDate", type date}, {"IterationEndDate", type date}}),

IterJoin =
    Table.NestedJoin(
        WorkItems,
        {"IterationPath"},
        IterTypes2,
        {"IterationPathFull"},
        "Iteration",
        JoinKind.LeftOuter
    ),
WithIterDates = Table.ExpandTableColumn(IterJoin, "Iteration", {"IterationStartDate","IterationEndDate"}, {"IterationStartDate","IterationEndDate"}),

#"Inserted Merged Column" = Table.AddColumn(#"Renamed Columns", "Merged", each Text.Combine({Text.From([WorkItemId], "en-US"), "-", [State]}), type text),
#"Renamed Columns1" = Table.RenameColumns(#"Inserted Merged Column",{{"ClosedDate", "Completed Date"}, {"AssignedTo.displayName", "AssignedTo"}}),
#"Filtered Rows" = Table.SelectRows(#"Renamed Columns1", each true)

in
    #"Filtered Rows"