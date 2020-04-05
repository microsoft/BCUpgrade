pageextension 50101 "ABC - RewardsCustomerExtension" extends "Customer Card"
{
    layout
    {
        addafter(TotalSales2)
        {
            field("ABC - Reward Points"; "ABC - Reward Points")
            {
                ApplicationArea = Basic, Suite;
            }

            field("ABC - Gold Customer"; "ABC - Gold Customer")
            {
                ApplicationArea = Basic, Suite;
            }
        }
    }

    actions
    {
        addafter(Invoices)
        {
            action("Claim Reward")
            {
                ApplicationArea = Basic, Suite;
                Caption = 'Claim Reward';
                Image = RegisterPutAway;
                Promoted = true;
                PromotedCategory = Category9;
                PromotedIsBig = true;
                trigger OnAction()
                var
                    RewardsManagement: Codeunit "ABC - Rewards Management";
                begin
                    RewardsManagement.ClaimReward(Rec);
                end;
            }
        }
    }
}