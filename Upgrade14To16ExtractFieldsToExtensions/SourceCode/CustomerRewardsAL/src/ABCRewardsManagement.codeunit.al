codeunit 50100 "ABC - Rewards Management"
{
    procedure ClaimReward(var Customer: record Customer): Boolean
    var
        TempABCRewardProvider: Record "ABC - Reward Provider" temporary;
        Success: boolean;
        PointsClaimed: Integer;
        ErrorMessage: Text;
    begin
        OnGetRewardProviders(TempABCRewardProvider, Customer);
        TempABCRewardProvider.Reset();
        OnExcludeRewardProviders(TempABCRewardProvider);
        IF NOT TempABCRewardProvider.FindFirst() then
            Error('There are no reward providers installed on the system');

        TempABCRewardProvider.SetFilter(Points, '<=%1', Customer."ABC - Reward Points");

        IF NOT TempABCRewardProvider.FindFirst() then
            Error('No reward providers are available for this customer');

        IF NOT (Page.RunModal(Page::"ABC - Select Reward", TempABCRewardProvider) in [Action::LookupOK, Action::OK]) then
            Exit(false);

        OnClaimReward(TempABCRewardProvider, Customer, PointsClaimed, Success, ErrorMessage);
        if not Success then
            Error(ErrorMessage);

        if (PointsClaimed < 0) then
            Error('Points claimend cannot be negative');

        if (PointsClaimed > Customer."ABC - Reward Points") then
            Error('Points claimed are greater than available points');

        Customer.Validate("ABC - Reward Points", Customer."ABC - Reward Points" - PointsClaimed);
        Customer.Modify(True);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnGetRewardProviders(var TempABCRewardProvider: Record "ABC - Reward Provider" temporary; Customer: Record Customer)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnClaimReward(var TempABCRewardProvider: Record "ABC - Reward Provider" temporary; var Customer: Record Customer; var PointsClaimed: Integer; var Success: Boolean; var ErrorMessage: text)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnExcludeRewardProviders(var TempABCRewardProvider: Record "ABC - Reward Provider" temporary)
    begin
    end;
}