let

PAT = "YOUR_PAT",
BaseUrl = "https://dev.azure.com",
Org = "YOUR_ORGANIZATION",
Project = "YOUR_ORGANIZATION_PROJECT",

WIQLQuery =
    "{""query"": ""SELECT [System.Id] FROM WorkItems
    WHERE [System.TeamProject] = 'TeamProject'
    AND [System.WorkItemType] = 'WorkItemType'
    AND [System.State] = 'State'
    AND [System.AreaPath] UNDER 'AreaPath'
    AND [System.Tags] CONTAINS 'Tags'""}",

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
                    #"$expand" = "relations",
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

ExpandFields = Table.ExpandRecordColumn(ExpandRoot, "fields", {"System.WorkItemType","System.State","System.Title","System.CreatedDate","System.AreaPath","System.Tags","System.AssignedTo"}, {"WorkItemType","State","Title","CreatedDate","AreaPath","Tags","AssignedTo"}),

ExpandAssignedTo = Table.TransformColumns(ExpandFields, {{"AssignedTo", each try Record.Field(_, "displayName") otherwise null}}),
WithUserName = Table.RenameColumns(ExpandAssignedTo, {{"AssignedTo","UserName"}}),

PBITable = Table.SelectColumns(WithUserName, {"WorkItemId","Title","WorkItemType","CreatedDate","State","UserName","AreaPath","relations"}),

RelationsSource = Table.SelectColumns(PBITable, {"WorkItemId","relations"}),
ExpandRelations = Table.ExpandListColumn(RelationsSource, "relations"),
ExpandRelationRec = Table.ExpandRecordColumn(ExpandRelations, "relations", {"rel","url","attributes"}, {"RelType","TargetUrl","Attributes"}),

ExtractRelationName = Table.AddColumn(ExpandRelationRec, "RelationName", each try [Attributes][name] otherwise null),
ExtractTargetId = Table.AddColumn(ExtractRelationName, "TargetWorkItemId", each try Number.FromText(Text.AfterDelimiter([TargetUrl], "/workItems/")) otherwise null, Int64.Type),

TestsRelations = Table.SelectRows(ExtractTargetId, each [TargetWorkItemId] <> null and Text.Contains([RelationName]?, "Tested By", Comparer.OrdinalIgnoreCase)),
RelationsClean = Table.SelectColumns(TestsRelations, {"WorkItemId","TargetWorkItemId","RelationName"}),

MergePBI_Rel = Table.NestedJoin(PBITable, {"WorkItemId"}, RelationsClean, {"WorkItemId"}, "Rel", JoinKind.LeftOuter),
ExpandMergedRel = Table.ExpandTableColumn(MergePBI_Rel, "Rel", {"TargetWorkItemId","RelationName"}, {"TargetWorkItemId","RelationName"}),

TargetIds = List.Distinct(List.RemoveNulls(ExpandMergedRel[TargetWorkItemId])),
TargetBatches = List.Split(TargetIds, 150),

FetchTCBatch = (batch as list) =>
    let
        Body = "{""ids"": [" & Text.Combine(List.Transform(batch, each Text.From(_)), ",") & "], ""fields"": [""System.WorkItemType"",""System.State"",""System.Title""]}",
        Response = Web.Contents(
            BaseUrl,
            [
                RelativePath = Org & "/" & Project & "/_apis/wit/workitemsbatch",
                Query = [#"api-version" = "7.0"],
                Headers = [
                    Authorization = "Basic " & Binary.ToText(
                        Text.ToBinary(":" & PAT),
                        BinaryEncoding.Base64
                    ),
                    #"Content-Type" = "application/json"
                ],
                Content = Text.ToBinary(Body)
            ]
        ),
        JsonOut = Json.Document(Response)[value]
    in
        JsonOut,

AllTCs = if List.Count(TargetIds) = 0 then {} else List.Combine(List.Transform(TargetBatches, each FetchTCBatch(_))),
TCTable = Table.FromList(AllTCs, Splitter.SplitByNothing(), {"Item"}, null, ExtraValues.Error),
ExpandTCRoot = Table.ExpandRecordColumn(TCTable, "Item", {"id","fields"}, {"TargetId","fields"}),

ExpandTCFields = Table.ExpandRecordColumn(ExpandTCRoot, "fields", {"System.WorkItemType","System.State","System.Title"}, {"TC_WorkItemType","TC_State","TC_Title"}),
OnlyTestCases = Table.SelectRows(ExpandTCFields, each [TC_WorkItemType] = "Test Case"),

MergePBI_TC = Table.NestedJoin(ExpandMergedRel, {"TargetWorkItemId"}, OnlyTestCases, {"TargetId"}, "TC", JoinKind.LeftOuter),
FinalExpand = Table.ExpandTableColumn(MergePBI_TC, "TC", {"TC_WorkItemType","TC_State","TC_Title"}, {"TC_WorkItemType","TC_State","TC_Title"})

in
    #"FinalExpand"