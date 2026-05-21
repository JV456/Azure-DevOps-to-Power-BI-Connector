let

PAT = "YOUR_PAT",
BaseUrl = "https://dev.azure.com",
Org = "YOUR_ORGANIZATION",
Team = "YOUR_ORGANIZATION_TEAM",

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
        {"System.IterationPath", "System.WorkItemType", "System.State", "System.Title", "System.AreaPath", "System.TeamProject", "System.CreatedDate", "Microsoft.VSTS.Common.ActivatedDate", "Microsoft.VSTS.Common.StateChangeDate", "Microsoft.VSTS.Common.ClosedDate", "Microsoft.VSTS.Common.Severity", "System.AssignedTo"},
        {"IterationPath", "WorkItemType", "State","Title","AreaPath", "TeamProject", "CreatedDate", "ActivatedDate", "StateChangeDate", "ClosedDate", "Severity", "AssignedTo"}
    ),

StateCategoryMap = [
    #"New" = "Proposed",
    #"Active" = "InProgress",
    #"Resolved" = "Resolved",
    #"Closed" = "Completed",
    #"Removed" = "Removed",
    #"Approved" = "Proposed",
    #"Committed" = "InProgress",
    #"Done" = "Completed",
    #"Proposed" = "Proposed"
],

WithStateCategory = Table.AddColumn(
    WorkItems,
    "StateCategory",
    each Record.FieldOrDefault(StateCategoryMap, [State], "Unknown")
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
                )
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
        WithStateCategory,
        {"IterationPath"},
        IterTypes2,
        {"IterationPathFull"},
        "Iteration",
        JoinKind.LeftOuter
    ),
WithIterDates = Table.ExpandTableColumn(IterJoin, "Iteration", {"IterationStartDate","IterationEndDate"}, {"IterationStartDate","IterationEndDate"}),

#"Removed Columns" = Table.RemoveColumns(WithIterDates,{"relations"}),
#"Changed Type" = Table.TransformColumnTypes(#"Removed Columns",{{"ActivatedDate", type datetimezone}}),
#"Inserted Text After Delimiter" = Table.AddColumn(#"Changed Type", "Text After Delimiter", each Text.AfterDelimiter([IterationPath], "\"), type text),
#"Renamed Columns" = Table.RenameColumns(#"Inserted Text After Delimiter", {{"Text After Delimiter", "Sprint"}}),

#"Inserted Merged Column" = Table.AddColumn(
    #"Renamed Columns",
    "Work Item ID - State",
    each Text.Combine({Text.From([WorkItemId], "en-US"), "-", [State]}),
    type text
),
#"Reordered Columns" = Table.ReorderColumns(#"Inserted Merged Column",{"WorkItemId", "IterationPath", "WorkItemType", "State", "StateCategory", "Title", "AreaPath", "TeamProject", "CreatedDate", "ActivatedDate", "StateChangeDate", "ClosedDate", "Severity", "AssignedTo", "IterationStartDate", "IterationEndDate", "Sprint", "Work Item ID - State"}),
#"Changed Type1" = Table.TransformColumnTypes(#"Reordered Columns",{{"CreatedDate", type datetimezone}, {"ActivatedDate", type datetimezone}, {"StateChangeDate", type datetimezone}, {"ClosedDate", type datetimezone}}),
#"Changed Type2" = Table.TransformColumnTypes(#"Changed Type1",{{"CreatedDate", type date}, {"ActivatedDate", type date}, {"StateChangeDate", type date}, {"ClosedDate", type date}}),
#"Removed Duplicates" = Table.Distinct(#"Changed Type2", {"WorkItemId"}),
#"Replaced Value" = Table.ReplaceValue(#"Removed Duplicates","1 - ","d)",Replacer.ReplaceText,{"Severity"}),
#"Replaced Value1" = Table.ReplaceValue(#"Replaced Value","2 - ","c)",Replacer.ReplaceText,{"Severity"}),
#"Replaced Value2" = Table.ReplaceValue(#"Replaced Value1","3 - ","b)",Replacer.ReplaceText,{"Severity"}),
#"Replaced Value3" = Table.ReplaceValue(#"Replaced Value2","4 - ","a)",Replacer.ReplaceText,{"Severity"}),
#"Expanded AssignedTo" = Table.ExpandRecordColumn(#"Replaced Value3", "AssignedTo", {"displayName"}, {"AssignedTo.displayName"}),
#"Renamed Columns1" = Table.RenameColumns(#"Expanded AssignedTo",{{"AssignedTo.displayName", "AssignedTo"}, {"ClosedDate", "CompletedDate"}, {"StateCategory", "State Category"}})

in
    #"Renamed Columns1"