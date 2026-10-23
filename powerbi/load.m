// Power Query (M) queries for the dashboard.
// In Power BI Desktop: Home > Get data > Blank query > Advanced editor, paste one query each,
// and name them exactly "transactions" and "impact_sizing".
// Edit the two file paths to point at your copy of the project folder.

// ---------------------------------------------------------------- query: transactions
let
    Source = Csv.Document(
        File.Contents("C:\Users\YOU\payments-decline-analysis\data\transactions.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Typed = Table.TransformColumnTypes(
        Promoted,
        {
            {"transaction_id", type text}, {"created_at", type datetime}, {"user_id", Int64.Type},
            {"payment_method", type text}, {"currency", type text}, {"provider", type text},
            {"amount_eur", type number}, {"three_ds_required", Int64.Type},
            {"three_ds_outcome", type text}, {"status", type text}, {"decline_code", type text},
            {"retry_of", type text}, {"is_retry", Int64.Type}
        },
        "en-US"
    ),
    WithDate = Table.AddColumn(Typed, "date", each Date.From([created_at]), type date)
in
    WithDate

// ---------------------------------------------------------------- query: impact_sizing
let
    Source = Csv.Document(
        File.Contents("C:\Users\YOU\payments-decline-analysis\output\impact_sizing.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Typed = Table.TransformColumnTypes(
        Promoted,
        {
            {"recommendation", type text}, {"scenario", type text}, {"assumption", type text},
            {"addressable_value_eur", type number}, {"pct_of_declined_value", type number},
            {"pct_of_requested_value", type number}
        },
        "en-US"
    )
in
    Typed
