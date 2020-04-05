codeunit 50101 "ABC - Bicycles Gold Cust"
{
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"ABC - Rewards Management", 'OnGetRewardProviders', '', true, true)]
    local procedure GetRewardProviders(var TempABCRewardProvider: Record "ABC - Reward Provider" temporary; Customer: Record Customer)
    var
        GeneralLedgerSetup: Record "General Ledger Setup";
    begin
        if NOT Customer."ABC - Gold Customer" then
            exit;

        CLEAR(TempABCRewardProvider);
        TempABCRewardProvider."Provider ID" := GetProviderId();
        TempABCRewardProvider.Points := GetPointsCost();
        if not GeneralLedgerSetup.Get then
            exit;

        TempABCRewardProvider.Description := StrSubstNo('Exclusive 1%1 Bicycles for gold customers.', GeneralLedgerSetup."Local Currency Symbol");
        TempABCRewardProvider.Insert(TRUE);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"ABC - Rewards Management", 'OnClaimReward', '', true, true)]
    local procedure ClaimReward(var TempABCRewardProvider: Record "ABC - Reward Provider" temporary; var Customer: Record Customer; var PointsClaimed: Integer; var Success: Boolean; var ErrorMessage: text)
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        JobQueueEntry: Record "Job Queue Entry";
        DocumentPost: Codeunit "Sales-Post";
        SucessNotification: Notification;
        PostImmediately: boolean;
    begin
        if TempABCRewardProvider."Provider ID" <> GetProviderId() then
            exit;

        if not Customer."ABC - Gold Customer" THEN begin
            ErrorMessage := 'Customer is not a gold customer';
            exit;
        end;

        if not (Customer."ABC - Reward Points" >= GetPointsCost()) then begin
            ErrorMessage := 'Not enough points for this action';
            exit;
        end;

        SalesHeader.Validate("Sell-to Customer No.", Customer."No.");
        SalesHeader.Validate("Document Type", SalesHeader."Document Type"::Invoice);
        IF NOT SalesHeader.Insert(true) then begin
            ErrorMessage := 'Could not insert Sales Header';
            exit;
        end;

        SalesLine.Validate("Document Type", SalesLine."Document Type"::Invoice);
        SalesLIne.Validate("Document No.", SalesHeader."No.");
        SalesLine.Validate("Line No.", 10000);
        SalesLine.Validate(Type, SalesLine.Type::Item);
        SalesLine.Validate("No.", '1000');
        SalesLine.Validate(Quantity, 1);
        salesLine.Validate("Line Amount", 1);

        IF NOT SalesLine.Insert(true) then begin
            ErrorMessage := 'Could not insert Sales Line';
            exit;
        end;

        Success := True;
        PointsClaimed := GetPointsCost();
        SucessNotification.Message('Gold Reward successfully claimed');
        SucessNotification.Send();
        commit;

        OnPostImmediately(PostImmediately);
        if PostImmediately then
            Codeunit.RUN(Codeunit::"Sales-Post", SalesHeader)
        else
            JobQueueEntry.ScheduleJobQueueEntry(CODEUNIT::"Sales Post via Job Queue", SalesHeader.RECORDID);
    end;

    local procedure GetPointsCost(): Integer
    begin
        exit(1000);
    end;

    local procedure GetProviderId(): Integer
    begin
        exit(Codeunit::"ABC - Bicycles Gold Cust");
    end;

    [IntegrationEvent(false, false)]
    local procedure OnPostImmediately(var PostImmediately: boolean)
    begin
    end;
}