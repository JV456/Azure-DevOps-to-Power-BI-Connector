let

PAT = "YOUR_PAT",
BaseUrl = "https://dev.azure.com",
Org = "YOUR_ORGANIZATION",
Project = "YOUR_ORGANIZATION_PROJECT",

WIQLQuery =
    "{""query"": ""SELECT [System.Id] FROM WorkItems
    WHERE [System.TeamProject] = 'TeamProject'
    AND [System.WorkItemType] = 'WorkItemType'
    AND [System.State] <> 'State'
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
IdBatches  = List.Split(AllIds, 150),

FetchBatch = (batch as list) =>
    let
        IdText = Text.Combine(List.Transform(batch, each Text.From(_)), ","),
        Response = Web.Contents(
            BaseUrl,
            [
                RelativePath = Org & "/" & Project & "/_apis/wit/workitems",
                Query = [
                    ids = IdText,
                    #"$expand" = "All",
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
TCTable = Table.FromList(RawWorkItems, Splitter.SplitByNothing(), null, null, ExtraValues.Error)

in
    #"TCTable"