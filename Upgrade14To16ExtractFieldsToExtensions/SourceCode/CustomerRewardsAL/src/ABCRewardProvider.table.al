table 50101 "ABC - Reward Provider"
{

    fields
    {
        field(1; "Provider ID"; Integer)
        {
            DataClassification = ToBeClassified;
        }
        field(2; Description; Text[250])
        {
            DataClassification = ToBeClassified;
        }
        field(3; Points; Integer)
        {
            DataClassification = ToBeClassified;
        }
    }

    keys
    {
        key(Key1; "Provider ID")
        {
            // Create a clustered index from this key.
            Clustered = true;
        }
    }

    trigger OnInsert()
    begin
        VerifyRecordIsCorrect(Rec);
    end;

    procedure VerifyRecordIsCorrect(var RewardProvider: Record 50101)
    begin
        if NOT RewardProvider.IsTemporary() then
            Error('Only Temporary records can be used');
    end;
}