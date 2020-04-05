page 50100 "ABC - Select Reward"
{
    PageType = List;
    SourceTable = "ABC - Reward Provider";

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field(Description; Description)
                {
                    ApplicationArea = Basic, Suite;
                }

                field(Points; Points)
                {
                    ApplicationArea = Basic, Suite;
                }
            }
        }
        area(factboxes)
        {

        }
    }

    actions
    {
        area(processing)
        {
            action(ActionName)
            {
                trigger OnAction();
                begin

                end;
            }
        }
    }
}