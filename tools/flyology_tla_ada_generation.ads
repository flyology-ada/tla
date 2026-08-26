package Flyology_TLA_Ada_Generation is

   procedure Generate
     (Module_Path         : String;
      Configuration_Path  : String;
      Type_Invariant      : String;
      Input_Type_Operator : String;
      Outcome_Type_Operator : String;
      Package_Name        : String;
      Output_Directory    : String;
      Java_Path           : String;
      TLC_Jar_Path        : String);

end Flyology_TLA_Ada_Generation;
